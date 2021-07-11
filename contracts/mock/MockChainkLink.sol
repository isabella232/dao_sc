// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;


contract MockChainkLink {

  uint8 public decimals;
  int256 public _answer;

  constructor(uint8 _decimals) {
    decimals = _decimals;
  }

  function setAnswerData(int256 _data) external {
    _answer = _data;
  }

  function latestRoundData()
    external
    view
    returns (
      uint80,
      int256, // rate in PRECISION of 10^18
      uint256,
      uint256,
      uint80
    )
  {
    return (0, _answer, 0, 0, 0);
  }
}
