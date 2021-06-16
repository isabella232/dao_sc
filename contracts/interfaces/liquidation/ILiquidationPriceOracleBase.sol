// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;


import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';

/**
* Use different logics to compute price oracle
* If token is not supported, it should return 0 as conversion rate
*/
interface ILiquidationPriceOracleBase {

  /**
   * @dev Update premium bps for liquidators
   */
  function updatePremiumBps(
    address[] calldata liquidators,
    uint256[] calldata premiumBps
  )
    external;

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
  function getExpectedReturn(
    address liquidator,
    IERC20Ext[] calldata tokenIns,
    uint256[] calldata amountIns,
    IERC20Ext[] calldata tokenOuts,
    bytes calldata hint
  ) external view returns (uint256 minAmountOuts);

  /**
   * @dev Return premium in BPS for a liquidator
   */
  function getPremiumBps(address liquidator)
    external view returns (uint256 premiumBps);
}
