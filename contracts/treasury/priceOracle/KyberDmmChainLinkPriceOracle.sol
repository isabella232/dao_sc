// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

import {ILiquidationPriceOracleBase} from '../../interfaces/liquidation/ILiquidationPriceOracleBase.sol';
import {IChainLinkAggregatorProxy} from '../../interfaces/liquidation/thirdParty/IChainLinkAggregatorProxy.sol';
import {IDMMPool} from '../../interfaces/liquidation/thirdParty/IDMMPool.sol';
import {PermissionAdmin} from '@kyber.network/utils-sc/contracts/PermissionAdmin.sol';
import {Utils} from '@kyber.network/utils-sc/contracts/Utils.sol';
import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/EnumerableSet.sol';


/**
* @dev Contract to calculate expected return amounts for a liquidation call
*   Also work with Kyber Dmm LP tokens
*   Can use hint to:
*     1. Remove liquidity given LP tokens
*     2. Calculate price of LP tokens to a dest token
*     3. Calculate price of normal tokens to a dest token
*/
contract KyberDmmChainLinkPriceOracle is ILiquidationPriceOracleBase, PermissionAdmin, Utils {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  // REMOVE_LIQUIDITY: take a single LP token and remove to 2 tokens in the poool
  // LIQUIDATE_TOKENS: liquidate list of tokens to a single token
  // LIQUIDATE_LP: liquidate list of LP tokens to a single token
  enum OracleHintType { REMOVE_LIQUIDITY, LIQUIDATE_TOKENS, LIQUIDATE_LP }

  struct AggregatorProxyData {
    address quoteEthProxy;
    uint8 quoteEthProxyDecimals;
    address quoteUsdProxy;
    uint8 quoteUsdProxyDecimals;
  }

  mapping (address => AggregatorProxyData) internal _tokenData;

  uint256 internal _defaultPremiumBps;
  mapping (address => uint256) internal _groupPremiumBps;

  // list of tokens that can be liquidate to
  EnumerableSet.AddressSet private _whitelistedTokens;

  event DefaultPremiumBpsSet(uint256 indexed premiumBps);
  event UpdateGroupPremiumBps(address indexed liquidator, uint256 indexed premiumBps);
  event WhitelistedTokenUpdated(address indexed token, bool indexed isAdd);

  constructor(
    address admin,
    address[] memory whitelistedTokens
  ) PermissionAdmin(admin) {
    _updateWhitelistedToken(whitelistedTokens, true);
  }

  /**
  * @dev Update list of aggregator proxies for tokens
  *   Need to check the data carefully, Aggregator contract doesn't have function to
  *     get the supported token or base, so can not do any safe check here
  */
  function updateAggregatorProxyData(
    address[] calldata tokens,
    address[] calldata quoteEthProxies,
    address[] calldata quoteUsdProxies
  ) external onlyAdmin {

    require(
      tokens.length == quoteEthProxies.length &&
      tokens.length == quoteUsdProxies.length,
      'invalid length data'
    );

    uint8 quoteEthProxyDecimals;
    uint8 quoteUsdProxyDecimals;

    for(uint256 i = 0; i < tokens.length; i++) {
      quoteEthProxyDecimals = quoteEthProxies[i] == address(0) ? 0 :
        IChainLinkAggregatorProxy(quoteEthProxies[i]).decimals();
      quoteUsdProxyDecimals = quoteUsdProxies[i] == address(0) ? 0 :
        IChainLinkAggregatorProxy(quoteUsdProxies[i]).decimals();

      _tokenData[tokens[i]] = AggregatorProxyData({
        quoteEthProxy: quoteEthProxies[i],
        quoteUsdProxy: quoteUsdProxies[i],
        quoteEthProxyDecimals: quoteEthProxyDecimals,
        quoteUsdProxyDecimals: quoteUsdProxyDecimals
      });
    }
  }

  function updatePremiumBps(address[] calldata liquidators, uint256[] calldata premiumBps)
    external override onlyAdmin
  {
    require(liquidators.length == premiumBps.length, 'invalid length');
    for(uint256 i = 0; i < liquidators.length; i++) {
      _setGroupPremiumBps(liquidators[i], premiumBps[i]);
    }
  }

  function updateWhitelistedTokens(address[] calldata tokens, bool isAdd)
    external onlyAdmin
  {
    _updateWhitelistedToken(tokens, isAdd);
  }

  /**
   * @dev Return list of min amounts that expected to get in return
   *  when liquidating corresponding list of src tokens
   * @param liquidator address of the liquidator
   * @param tokenIns list of src tokens
   * @param amountIns list of src amounts
   * @param tokenOuts list of return tokens
   * @param hint hint for getting conversion rates
   * @return minAmountOuts min expected amount for each token out
   */
  function getExpectedReturns(
    address liquidator,
    IERC20Ext[] calldata tokenIns,
    uint256[] calldata amountIns,
    IERC20Ext[] calldata tokenOuts,
    bytes calldata hint
  )
    external override view
    returns (uint256[] memory minAmountOuts)
  {
    require(tokenIns.length == amountIns.length, 'invalid length');
    minAmountOuts = new uint256[](tokenOuts.length);

    (OracleHintType hintType) = abi.decode(hint, (OracleHintType));

    if (hintType == OracleHintType.REMOVE_LIQUIDITY) {
      // Only Remove Liquidity given a LP token
      require(tokenIns.length == 1, 'invalid number token in');
      require(tokenOuts.length == 2, 'invalid number token out');
      (IERC20Ext[2] memory tokens, uint256[4] memory amounts) = getExpectedTokensFromLp(
        address(tokenIns[0]), amountIns[0]
      );
      if (tokens[0] == tokenOuts[0]) {
        (minAmountOuts[0], minAmountOuts[1]) = (amounts[2], amounts[3]);
      } else {
        (minAmountOuts[0], minAmountOuts[1]) = (amounts[3], amounts[2]);
      }
      return _applyPremiumFor(liquidator, minAmountOuts);
    }

    require(tokenOuts.length == 1, 'invalid number token out');
    require(isWhitelistedToken(address(tokenOuts[0])), 'token out must be whitelisted');

    if (hintType == OracleHintType.LIQUIDATE_TOKENS) {
      // Liquidate list of tokens to a single dest token
      for(uint256 i = 0; i < tokenIns.length; i++) {
        require(!isWhitelistedToken(address(tokenIns[i])), 'token in can not be a whitelisted token');
        uint256 rate = conversionRate(address(tokenIns[i]), address(tokenOuts[0]), amountIns[i]);
        require(rate > 0, 'invalid conversion rate');
        minAmountOuts[0] = minAmountOuts[0].add(
          calcDestAmount(tokenIns[i], tokenOuts[0], amountIns[i], rate)
        );
      }
      return _applyPremiumFor(liquidator, minAmountOuts);
    }

    // Liquidate list of LP tokens to a single dest token
    for(uint256 i = 0; i < tokenIns.length; i++) {
      (IERC20Ext[2] memory tokens, uint256[4] memory amounts) = getExpectedTokensFromLp(
        address(tokenIns[i]), amountIns[i]
      );
      // calc equivalent (tokens[0], amounts[2]) -> tokenOuts[0]
      uint256 rate = conversionRate(address(tokens[0]), address(tokenOuts[0]), amounts[2]);
      require(rate > 0, 'invalid conversion rate 0');
      minAmountOuts[0] = minAmountOuts[0].add(
        calcDestAmount(tokens[0], tokenOuts[0], amounts[2], rate)
      );
      // calc equivalent (tokens[1], amounts[3]) -> tokenOuts[0]
      rate = conversionRate(address(tokens[1]), address(tokenOuts[0]), amounts[3]);
      require(rate > 0, 'invalid conversion rate 1');
      minAmountOuts[0] = minAmountOuts[0].add(
        calcDestAmount(tokens[1], tokenOuts[0], amounts[3], rate)
      );
    }
    minAmountOuts = _applyPremiumFor(liquidator, minAmountOuts);
  }

  // Whitelisted tokens
  function getWhitelistedTokensLength() external view returns (uint256) {
    return _whitelistedTokens.length();
  }

  function getWhitelistedTokenAt(uint256 index) external view returns (address) {
    return _whitelistedTokens.at(index);
  }

  function getAllWhitelistedTokens()
    external view returns (address[] memory tokens)
  {
    uint256 length = _whitelistedTokens.length();
    tokens = new address[](length);
    for(uint256 i = 0; i < length; i++) {
      tokens[i] = _whitelistedTokens.at(i);
    }
  }

  /**
   * @dev Return expect amounts given pool and number of lp tokens
   *  TODO: should have a solution for token with fees, or just another contract to support
   * @return tokens [token0, token1]
   * @return amounts [amount0, amount1, expectedAmount0, expectedAmount1s]
   */
  function getExpectedTokensFromLp(
    address pool,
    uint256 lpAmount
  )
    public view
    returns (
      IERC20Ext[2] memory tokens,
      uint256[4] memory amounts
    )
  {
    uint256 totalSupply = IERC20Ext(pool).totalSupply();
    (tokens[0], tokens[1]) = (IDMMPool(pool).token0(), IDMMPool(pool).token1());
    (amounts[0], amounts[1]) = IDMMPool(pool).getReserves();

    (amounts[2], amounts[3]) = (
      amounts[0].mul(lpAmount) / totalSupply,
      amounts[1].mul(lpAmount) / totalSupply
    );
  }

  /**
  *  @dev Get conversion rate from src to dest token given amount
  *   For chainlink, amount is not needed
  *   Fetch rates using both eth and usd as quote, then take the average
  */
  function conversionRate(
    address src,
    address dest,
    uint256 /* amount */
  )
    public view returns(uint256 rate)
  {
    if (src == dest) return PRECISION;
    if (dest == address(ETH_TOKEN_ADDRESS)) {
      return getRateOverEth(src);
    }

    if (src == address(ETH_TOKEN_ADDRESS)) {
      rate = getRateOverEth(dest);
      if (rate > 0) rate = PRECISION.mul(PRECISION).div(rate);
      return rate;
    }

    uint256 srcRate;
    uint256 destRate;

    uint256 rateQuoteEth;
    uint256 rateQuoteUsd;

    // get rate from eth quote
    srcRate = getRateOverEth(src);
    if (srcRate > 0) {
      destRate = getRateOverEth(dest);
      if (destRate > 0) {
        rateQuoteEth = PRECISION.mul(srcRate).div(destRate);
      }
    }

    // get rate from usd quote
    srcRate = getRateOverUsd(src);
    if (srcRate > 0) {
      destRate = getRateOverUsd(dest);
      if (destRate > 0) {
        // update new rate if it is higher
        rateQuoteUsd = PRECISION.mul(srcRate).div(destRate);
      }
    }

    if (rateQuoteEth == 0) {
      rate = rateQuoteUsd;
    } else if (rateQuoteUsd == 0) {
      rate = rateQuoteEth;
    } else {
      // average rate over eth and usd
      rate = rateQuoteEth.add(rateQuoteUsd).div(2);
    }
  }

  function getTokenAggregatorProxyData(address token)
    external view returns (
      address quoteEthProxy,
      address quoteUsdProxy
    )
  {
    (quoteEthProxy, quoteUsdProxy) = (_tokenData[token].quoteEthProxy, _tokenData[token].quoteUsdProxy);
  }

  /**
  *   @dev Get token rate over eth with units of PRECISION
  */
  function getRateOverEth(address token) public view returns (uint256 rate) {
    int256 answer;
    IChainLinkAggregatorProxy proxy = IChainLinkAggregatorProxy(_tokenData[token].quoteEthProxy);
    if (proxy != IChainLinkAggregatorProxy(0)) {
      (, answer, , ,) = proxy.latestRoundData();
    }
    if (answer < 0) return 0; // safe check in case ChainLink returns invalid data
    rate = uint256(answer);
    uint256 decimals = uint256(_tokenData[token].quoteEthProxyDecimals);
    rate = (decimals < MAX_DECIMALS) ? rate.mul(10 ** (MAX_DECIMALS - decimals)) :
      rate.div(10 ** (decimals - MAX_DECIMALS));
  }

  /**
  *   @dev Get token rate over usd with units of PRECISION
  */
  function getRateOverUsd(address token) public view returns (uint256 rate) {
    int256 answer;
    IChainLinkAggregatorProxy proxy = IChainLinkAggregatorProxy(_tokenData[token].quoteUsdProxy);
    if (proxy != IChainLinkAggregatorProxy(0)) {
      (, answer, , ,) = proxy.latestRoundData();
    }
    if (answer < 0) return 0; // safe check in case ChainLink returns invalid data
    rate = uint256(answer);
    uint256 decimals = uint256(_tokenData[token].quoteUsdProxyDecimals);
    rate = (decimals < MAX_DECIMALS) ? rate.mul(10 ** (MAX_DECIMALS - decimals)) :
      rate.div(10 ** (decimals - MAX_DECIMALS));
  }

  function isWhitelistedToken(address token)
    public view returns (bool)
  {
    return _whitelistedTokens.contains(token);
  }

  function getPremiumBps(address liquidator) public override view returns (uint256) {
    uint256 premiumBps = _groupPremiumBps[liquidator];
    return premiumBps > 0 ? premiumBps : _defaultPremiumBps;
  }

  function _updateWhitelistedToken(address[] memory _tokens, bool _isAdd) internal {
    for(uint256 i = 0; i < _tokens.length; i++) {
      if (_isAdd) {
        _whitelistedTokens.add(_tokens[i]);
      } else {
        _whitelistedTokens.remove(_tokens[i]);
      }
      emit WhitelistedTokenUpdated(_tokens[i], _isAdd);
    }
  }

  function _applyPremiumFor(address liquidator, uint256[] memory amounts)
    internal view
    returns (uint256[] memory finalAmounts)
  {
    finalAmounts = amounts;
    uint256 premiumBps = getPremiumBps(liquidator);
    for(uint256 i = 0; i < finalAmounts.length; i++) {
      finalAmounts[i] -= premiumBps.mul(finalAmounts[i]) / BPS;
    }
  }

  function _setDefaultPremium(uint256 _premiumBps) internal {
    require(_premiumBps < BPS, 'invalid premium bps');
    _defaultPremiumBps = _premiumBps;
    emit DefaultPremiumBpsSet(_premiumBps);
  }

  function _setGroupPremiumBps(address _liquidator, uint256 _premiumBps) internal {
    require(_premiumBps < BPS, 'invalid premium bps');
    _groupPremiumBps[_liquidator] = _premiumBps;
    emit UpdateGroupPremiumBps(_liquidator, _premiumBps);
  }
}
