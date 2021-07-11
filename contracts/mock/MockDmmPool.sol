// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';


contract MockDmmPool {

  IERC20Ext public token0;
  IERC20Ext public token1;
  uint112 internal _reserve0;
  uint112 internal _reserve1;
  uint256 public totalSupply;

  mapping (address => uint256) public balanceOf;

  constructor() {}

  function setData(
    IERC20Ext _t0, IERC20Ext _t1,
    uint112 _r0, uint112 _r1, uint256 _totalSupply
  ) external {
    token0 = _t0;
    token1 = _t1;
    _reserve0 = _r0;
    _reserve1 = _r1;
    totalSupply = _totalSupply;
  }

  function getReserves() external view returns (uint112 reserve0, uint112 reserve1)
  {
    (reserve0, reserve1) = (_reserve0, _reserve1);
  }
}
