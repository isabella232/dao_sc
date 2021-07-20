// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

import {ILiquidationPriceOracleBase} from '../../interfaces/liquidation/ILiquidationPriceOracleBase.sol';
import {IChainLinkAggregatorProxy} from '../../interfaces/liquidation/thirdParty/IChainLinkAggregatorProxy.sol';
import {IDMMPool} from '../../interfaces/liquidation/thirdParty/IDMMPool.sol';
import {PermissionAdmin, PermissionOperators} from '@kyber.network/utils-sc/contracts/PermissionOperators.sol';
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
*   It may not work for LPs of token with fees
*/
contract KyberDmmChainLinkPriceOracle is ILiquidationPriceOracleBase, PermissionOperators, Utils {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  // REMOVE_LIQUIDITY: take a single LP token and remove to 2 tokens in the pool
  // LIQUIDATE_LP: liquidate list of LP tokens to a single token
  // LIQUIDATE_TOKENS: liquidate list of tokens to a single token
  enum OracleHintType { REMOVE_LIQUIDITY, LIQUIDATE_LP, LIQUIDATE_TOKENS }

  struct AggregatorProxyData {
    address quoteEthProxy;
    uint8 quoteEthProxyDecimals;
    address quoteUsdProxy;
    uint8 quoteUsdProxyDecimals;
  }

  mapping (address => AggregatorProxyData) internal _tokenData;

  struct PremiumData {
    uint64 removeLiquidityBps;
    uint64 liquidateLpBps;
    uint64 liquidateTokensBps;
  }

  address public immutable weth;
  PremiumData internal _defaultPremiumData;
  mapping (address => PremiumData) internal _groupPremiumData;

  // list of tokens that can be liquidate to
  EnumerableSet.AddressSet private _whitelistedTokens;

  event DefaultPremiumDataSet(
    uint64 indexed removeLiquidityBps,
    uint64 indexed liquidateLpBps,
    uint64 indexed liquidateTokensBps
  );
  event UpdateGroupPremiumData(
    address indexed liquidator,
    uint64 indexed removeLiquidityBps,
    uint64 indexed liquidateLpBps,
    uint64 liquidateTokensBps
  );
  event UpdateAggregatorProxyData(
    address indexed token,
    address indexed quoteEthProxy,
    address indexed quoteUsdProxy
  );
  event WhitelistedTokenUpdated(address indexed token, bool indexed isAdd);

  constructor(
    address admin,
    address wethAddress,
    address[] memory whitelistedTokens
  ) PermissionAdmin(admin) {
    weth = wethAddress;
    _updateWhitelistedToken(whitelistedTokens, true);
  }

  /**
  * @dev Update list of aggregator proxies for tokens
  *   Need to check the data carefully, Aggregator contract doesn't have function to
  *     get the supported token or base, so can not do any safe check here
  *   For flexibility, it should be done by trusted operators
  */
  function updateAggregatorProxyData(
    address[] calldata tokens,
    address[] calldata quoteEthProxies,
    address[] calldata quoteUsdProxies
  ) external onlyOperator {

    require(
      tokens.length == quoteEthProxies.length &&
      tokens.length == quoteUsdProxies.length,
      'invalid length'
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
      emit UpdateAggregatorProxyData(tokens[i], quoteEthProxies[i], quoteUsdProxies[i]);
    }
  }

  function updateGroupPremiumData(
    address[] calldata _liquidators,
    uint64[] calldata _removeLiquidityBps,
    uint64[] calldata _liquidateLpBps,
    uint64[] calldata _liquidateTokensBps
  )
    external onlyAdmin
  {
    require(
      _liquidators.length == _removeLiquidityBps.length &&
      _liquidators.length == _liquidateLpBps.length &&
      _liquidators.length == _liquidateTokensBps.length,
      'invalid length'
    );
    for(uint256 i = 0; i < _liquidators.length; i++) {
      _setGroupPremiumData(
        _liquidators[i],
        _removeLiquidityBps[i],
        _liquidateLpBps[i],
        _liquidateTokensBps[i]
      );
    }
  }

  function updateDefaultPremiumData(
    uint64 _removeLiquidityBps,
    uint64 _liquidateLpBps,
    uint64 _liquidateTokensBps
  ) external onlyAdmin {
    _setDefaultPremiumData(_removeLiquidityBps, _liquidateLpBps, _liquidateTokensBps);
  }

  function updateWhitelistedTokens(address[] calldata tokens, bool isAdd)
    external onlyAdmin
  {
    _updateWhitelistedToken(tokens, isAdd);
  }

  /**
   * @dev Return list of min amounts that expected to get in return
   *  when liquidating corresponding list of src tokens
   *  3 types for hint: REMOVE_LIQUIDITY, LIQUIDATE_TOKENS, LIQUIDATE_LP
   *  - REMOVE_LIQUIDITY: Take a single LP token, and return 2 tokens in the pool
   *  - LIQUIDATE_TOKENS: Take list of tokens (must not be whitelisted tokens), then
   *      liquidate them to a single whitelisted token
   *  - LIQUIDATE_LP: Take list of LP tokens, then liquidate them to a single whitelisted token
   *  Apply premium discount, can be a different value for each liquidator.
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
    uint64 premiumBps;

    // Remove Liquidity given a LP token
    if (hintType == OracleHintType.REMOVE_LIQUIDITY) {
      require(tokenIns.length == 1, 'invalid number token in');
      require(tokenOuts.length == 2, 'invalid number token out');
      (IERC20Ext[2] memory tokens, uint256[2] memory amounts) = getExpectedTokensFromLp(
        address(tokenIns[0]), amountIns[0]
      );
      if (tokens[0] == tokenOuts[0]) {
        require(tokens[1] == tokenOuts[1], 'invalid token out 1');
        (minAmountOuts[0], minAmountOuts[1]) = (amounts[0], amounts[1]);
      } else {
        require(tokens[0] == tokenOuts[1], 'invalid token out 1');
        require(tokens[1] == tokenOuts[0], 'invalid token out 0');
        (minAmountOuts[0], minAmountOuts[1]) = (amounts[1], amounts[0]);
      }
      (premiumBps, ,) = getPremiumData(liquidator);
      return _applyPremiumFor(minAmountOuts, premiumBps);
    }

    require(tokenOuts.length == 1, 'invalid number token out');
    require(isWhitelistedToken(address(tokenOuts[0])), 'token out must be whitelisted');

    // special case to allow forwarding whitelisted token directly to reward pool
    if (hintType == OracleHintType.LIQUIDATE_TOKENS && tokenIns.length == 1 && tokenIns[0] == tokenOuts[0]) {
      minAmountOuts[0] = amountIns[0];
      // no premium
      return minAmountOuts;
    }

    uint256 tokenOutRateEth = getRateOverEth(address(tokenOuts[0]));
    uint256 tokenOutRateUsd = getRateOverUsd(address(tokenOuts[0]));

    for(uint256 i = 0; i < tokenIns.length; i++) {
      if (hintType == OracleHintType.LIQUIDATE_TOKENS) {
        require(
          !isWhitelistedToken(address(tokenIns[i])),
          'token in can not be a whitelisted token'
        );
      }
      minAmountOuts[0] = minAmountOuts[0].add(
        _getExpectedReturnFromToken(
          tokenIns[i],
          amountIns[i],
          tokenOuts[0],
          tokenOutRateEth,
          tokenOutRateUsd,
          hintType == OracleHintType.LIQUIDATE_LP
        )
      );
    }

    if (hintType == OracleHintType.LIQUIDATE_LP) {
      (, premiumBps, ) = getPremiumData(liquidator);
    } else {
      (, , premiumBps) = getPremiumData(liquidator);
    }
    minAmountOuts = _applyPremiumFor(minAmountOuts, premiumBps);
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
   * @return amounts [expectedAmount0, expectedAmount1s]
   */
  function getExpectedTokensFromLp(
    address pool,
    uint256 lpAmount
  )
    public view
    returns (
      IERC20Ext[2] memory tokens,
      uint256[2] memory amounts
    )
  {
    uint256 totalSupply = IERC20Ext(pool).totalSupply();
    (tokens[0], tokens[1]) = (IDMMPool(pool).token0(), IDMMPool(pool).token1());
    (uint256 amount0, uint256 amount1) = IDMMPool(pool).getReserves();

    (amounts[0], amounts[1]) = (
      amount0.mul(lpAmount) / totalSupply,
      amount1.mul(lpAmount) / totalSupply
    );
  }

  function getTokenAggregatorProxyData(address token)
    external view returns (
      address quoteEthProxy,
      address quoteUsdProxy,
      uint8 quoteEthDecimals,
      uint8 quoteUsdDecimals
    )
  {
    (quoteEthProxy, quoteUsdProxy) = (_tokenData[token].quoteEthProxy, _tokenData[token].quoteUsdProxy);
    (quoteEthDecimals, quoteUsdDecimals) = (
      _tokenData[token].quoteEthProxyDecimals,
      _tokenData[token].quoteUsdProxyDecimals
    );
  }

  function getDefaultPremiumData()
    external view
    returns (
      uint64 removeLiquidityBps,
      uint64 liquidateLpBps,
      uint64 liquidateTokensBps
    )
  {
    removeLiquidityBps = _defaultPremiumData.removeLiquidityBps;
    liquidateLpBps = _defaultPremiumData.liquidateLpBps;
    liquidateTokensBps = _defaultPremiumData.liquidateTokensBps;
  }

  /**
  *   @dev Get token rate over eth with units of PRECISION
  */
  function getRateOverEth(address token) public view returns (uint256 rate) {
    if (token == address(ETH_TOKEN_ADDRESS) || token == weth) return PRECISION;
    int256 answer;
    IChainLinkAggregatorProxy proxy = IChainLinkAggregatorProxy(_tokenData[token].quoteEthProxy);
    if (proxy != IChainLinkAggregatorProxy(0)) {
      (, answer, , ,) = proxy.latestRoundData();
    }
    if (answer <= 0) return 0; // safe check in case ChainLink returns invalid data
    rate = uint256(answer);
    uint256 decimals = uint256(_tokenData[token].quoteEthProxyDecimals);
    rate = (decimals < MAX_DECIMALS) ? rate.mul(10 ** (MAX_DECIMALS - decimals)) :
      rate / (10 ** (decimals - MAX_DECIMALS));
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
    if (answer <= 0) return 0; // safe check in case ChainLink returns invalid data
    rate = uint256(answer);
    uint256 decimals = uint256(_tokenData[token].quoteUsdProxyDecimals);
    rate = (decimals < MAX_DECIMALS) ? rate.mul(10 ** (MAX_DECIMALS - decimals)) :
      rate / (10 ** (decimals - MAX_DECIMALS));
  }

  function isWhitelistedToken(address token)
    public view returns (bool)
  {
    return _whitelistedTokens.contains(token);
  }

  function getPremiumData(address liquidator)
    public view
    returns (
      uint64 removeLiquidityBps,
      uint64 liquidateLpBps,
      uint64 liquidateTokensBps
    )
  {
    PremiumData memory data = _groupPremiumData[liquidator];
    if (data.removeLiquidityBps == 0 && data.liquidateLpBps == 0 && data.liquidateTokensBps == 0) {
      removeLiquidityBps = _defaultPremiumData.removeLiquidityBps;
      liquidateLpBps = _defaultPremiumData.liquidateLpBps;
      liquidateTokensBps = _defaultPremiumData.liquidateTokensBps;
    } else {
      removeLiquidityBps = data.removeLiquidityBps;
      liquidateLpBps = data.liquidateLpBps;
      liquidateTokensBps = data.liquidateTokensBps;
    }
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

  function _setDefaultPremiumData(
    uint64 _removeLiquidityBps,
    uint64 _liquidateLpBps,
    uint64 _liquidateTokensBps
  ) internal {
    require(_removeLiquidityBps < BPS, 'invalid remove liquidity bps');
    require(_liquidateLpBps < BPS, 'invalid liquidate lp bps');
    require(_liquidateTokensBps < BPS, 'invalid liquidate tokens bps');
    _defaultPremiumData.removeLiquidityBps = _removeLiquidityBps;
    _defaultPremiumData.liquidateLpBps = _liquidateLpBps;
    _defaultPremiumData.liquidateTokensBps = _liquidateTokensBps;
    emit DefaultPremiumDataSet(_removeLiquidityBps, _liquidateLpBps, _liquidateTokensBps);
  }

  function _setGroupPremiumData(
    address _liquidator,
    uint64 _removeLiquidityBps,
    uint64 _liquidateLpBps,
    uint64 _liquidateTokensBps
  ) internal {
    require(_removeLiquidityBps < BPS, 'invalid remove liquidity bps');
    require(_liquidateLpBps < BPS, 'invalid liquidate lp bps');
    require(_liquidateTokensBps < BPS, 'invalid liquidate tokens bps');
    _groupPremiumData[_liquidator].removeLiquidityBps = _removeLiquidityBps;
    _groupPremiumData[_liquidator].liquidateLpBps = _liquidateLpBps;
    _groupPremiumData[_liquidator].liquidateTokensBps = _liquidateTokensBps;
    emit UpdateGroupPremiumData(_liquidator, _removeLiquidityBps, _liquidateLpBps, _liquidateTokensBps);
  }

  function _applyPremiumFor(uint256[] memory amounts, uint64 premiumBps)
    internal pure
    returns (uint256[] memory finalAmounts)
  {
    finalAmounts = amounts;
    for(uint256 i = 0; i < finalAmounts.length; i++) {
      finalAmounts[i] -= finalAmounts[i].mul(premiumBps) / BPS;
    }
  }

  /**
  *   @dev Get expected return amount from src token given dest token data
  *   Save gas when liquidating multiple tokens or LP tokens
  */
  function _getExpectedReturnFromToken(
    IERC20Ext tokenIn,
    uint256 amountIn,
    IERC20Ext dest,
    uint256 destRateEth,
    uint256 destRateUsd,
    bool isFromLpToken
  )
    internal view
    returns (uint256 totalReturn)
  {
    bool isDestEth = dest == ETH_TOKEN_ADDRESS || dest == IERC20Ext(weth);
    uint256 rate;

    if (!isFromLpToken) {
      rate = isDestEth ? getRateOverEth(address(tokenIn)) :
        _getRateWithDestTokenData(address(tokenIn), destRateEth, destRateUsd);
      require(rate > 0, '0 aggregator rate');
      return calculateReturnAmount(amountIn, getDecimals(tokenIn), getDecimals(dest), rate);
    }

    (IERC20Ext[2] memory tokens, uint256[2] memory amounts) = getExpectedTokensFromLp(
      address(tokenIn), amountIn
    );

    uint256 destTokenDecimals = getDecimals(dest);

    // calc equivalent (tokens[0], amounts[0]) -> tokenOuts[0]
    if (tokens[0] == dest) {
      rate = PRECISION;
      totalReturn = totalReturn.add(amounts[0]);
    } else {
      rate = isDestEth ? getRateOverEth(address(tokens[0])) :
        _getRateWithDestTokenData(address(tokens[0]), destRateEth, destRateUsd);
      require(rate > 0, '0 aggregator rate');
      totalReturn = totalReturn.add(
        calculateReturnAmount(amounts[0], getDecimals(tokens[0]), destTokenDecimals, rate)
      );
    }

    // calc equivalent (tokens[1], amounts[1]) -> tokenOuts[0]
    if (tokens[1] == dest) {
      rate = PRECISION;
      totalReturn = totalReturn.add(amounts[1]);
    } else {
      rate = isDestEth ? getRateOverEth(address(tokens[1])) :
        _getRateWithDestTokenData(address(tokens[1]), destRateEth, destRateUsd);
        require(rate > 0, '0 aggregator rate');
      totalReturn = totalReturn.add(
        calculateReturnAmount(amounts[1], getDecimals(tokens[1]), destTokenDecimals, rate)
      );
    }
  }

  /**
  *   @dev Get rate from src token given dest token rates over eth and usd
  *   It is used to save gas when liquidating multiple tokens or LP tokens
  */
  function _getRateWithDestTokenData(
    address src,
    uint256 destTokenRateEth,
    uint256 destTokenRateUsd
  ) internal view returns (uint256) {
    if (src == address(ETH_TOKEN_ADDRESS) || src == weth) {
      if (destTokenRateEth == 0) return 0;
      return PRECISION.mul(PRECISION) / destTokenRateEth;
    }

    uint256 rateQuoteEth;
    uint256 rateQuoteUsd;

    if (destTokenRateEth > 0) {
      uint256 srcTokenRateEth = getRateOverEth(src);
      rateQuoteEth = PRECISION.mul(srcTokenRateEth) / destTokenRateEth;
    }

    if (destTokenRateUsd > 0) {
      uint256 srcTokenRateUsd = getRateOverUsd(src);
      rateQuoteUsd = PRECISION.mul(srcTokenRateUsd) / destTokenRateUsd;
    }

    if (rateQuoteEth == 0) return rateQuoteUsd;
    if (rateQuoteUsd == 0) return rateQuoteEth;
    return rateQuoteEth.add(rateQuoteUsd) / 2;
  }

  function calculateReturnAmount(
    uint256 srcQty,
    uint256 srcDecimals,
    uint256 dstDecimals,
    uint256 rate
  ) internal pure returns (uint256) {
    if (dstDecimals >= srcDecimals) {
      return srcQty.mul(rate).mul(10**(dstDecimals - srcDecimals)) / PRECISION;
    }
    return srcQty.mul(rate) / (PRECISION.mul(10**(srcDecimals - dstDecimals)));
  }
}
