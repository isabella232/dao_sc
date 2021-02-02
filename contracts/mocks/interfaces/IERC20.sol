// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;
pragma abicoder v2;

interface IERC20 {
  function totalSupplyAt(uint256 blockNumber) external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  function transfer(address recipient, uint256 amount) external returns (bool);
}
