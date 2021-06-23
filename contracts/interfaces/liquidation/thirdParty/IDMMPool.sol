// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';


interface IDMMPool {
  function getReserves() external view returns (uint112 reserve0, uint112 reserve1);

  function token0() external view returns (IERC20Ext);

  function token1() external view returns (IERC20Ext);
}
