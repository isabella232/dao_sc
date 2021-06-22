// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

import {ILiquidationPriceOracleBase} from '../../../interfaces/liquidation/ILiquidationPriceOracleBase.sol';
import {PermissionAdmin} from '@kyber.network/utils-sc/contracts/PermissionAdmin.sol';
import {Utils} from '@kyber.network/utils-sc/contracts/Utils.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';

// solhint-disable-next-line max-line-length
// Refer to https://github.com/smartcontractkit/chainlink/blob/develop/evm-contracts/src/v0.6/interfaces/AggregatorV3Interface.sol
interface IChainLinkAggregatorProxy {
  function decimals() external view returns (uint8);
  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer, // rate in PRECISION of 10^18
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

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

  struct AggregatorProxyData {
    address quoteEthProxy;
    uint8 quoteEthProxyDecimals;
    address quoteUsdProxy;
    uint8 quoteUsdProxyDecimals;
  }

  mapping (address => AggregatorProxyData) internal _tokenData;

  uint256 internal _defaultPremiumBps;
  mapping (address => uint256) internal _groupPremiumBps;

  event DefaultPremiumBpsSet(uint256 indexed premiumBps);
  event UpdateGroupPremiumBps(address indexed liquidator, uint256 indexed premiumBps);

  constructor(address admin) PermissionAdmin(admin) {}

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
    external onlyAdmin
  {
    require(liquidators.length == premiumBps.length, 'invalid length');
    for(uint256 i = 0; i < liquidators.length; i++) {
      _setGroupPremiumBps(liquidators[i], premiumBps[i]);
    }
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
    require(tokenOuts.length == 1, 'invalid number token out');
    minAmountOuts = new uint256[](tokenOuts.length);
    for(uint256 i = 0; i < tokenIns.length; i++) {
      uint256 rate = conversionRate(tokenIns[i], tokenOuts[0], amountIns[i]);
      require(rate > 0, 'invalid conversion rate');
      minAmountOuts[0] = minAmountOuts.add(
        calcDestAmount(tokenIns[i], tokenOuts[i], amountIns[i], rate)
      );
    }
  }

  function getExpectedTokensFromLp() {
    
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
