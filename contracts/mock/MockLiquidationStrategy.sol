// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';
import {LiquidationStrategy} from '../treasury/LiquidationStrategy.sol';

contract MockLiquidationStrategy is LiquidationStrategy {

  constructor(
    address admin,
    address treasuryPoolAddress,
    address payable rewardPoolAddress,
    uint128 startTime,
    uint64 repeatedPeriod,
    uint64 duration,
    address[] memory whitelistedTokens
  ) LiquidationStrategy(
    admin, treasuryPoolAddress, rewardPoolAddress, startTime,
    repeatedPeriod, duration, whitelistedTokens
  ) {}

  function callLiquidate(
    IERC20Ext[] calldata sources,
    uint256[] calldata amounts,
    address payable recipient,
    IERC20Ext dest,
    uint256 minReturn,
    bytes calldata txData
  )
    external returns (uint256 destAmount)
  {
    destAmount = super.liquidate(sources, amounts, recipient, dest, minReturn, txData);
  }
}
