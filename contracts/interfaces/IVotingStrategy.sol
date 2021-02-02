// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;
pragma abicoder v2;

interface IVotingStrategy {
  function getVotingPowerAt(address user, uint256 blockNumber) external view returns (uint256);
}
