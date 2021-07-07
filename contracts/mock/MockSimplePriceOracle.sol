// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;


import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';


contract MockSimplePriceOracle {

  uint256[] public amountOuts;

  constructor() {}

  function setAmountOuts(uint256[] memory _amountOuts) external {
    amountOuts = _amountOuts;
  }

  function getExpectedReturns(
    address, // liquidator,
    IERC20Ext[] calldata,// tokenIns,
    uint256[] calldata,// amountIns,
    IERC20Ext[] calldata,// tokenOuts,
    bytes calldata// hint
  )
    external view returns (uint256[] memory minAmountOuts)
  {
    minAmountOuts = amountOuts;
  }
}