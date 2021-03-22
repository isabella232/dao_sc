// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;


contract MockChainLinkAggregatorProxy {
  function decimals() external view returns (uint8) {}

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer, // rate in PRECISION of 10^18
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {}
}