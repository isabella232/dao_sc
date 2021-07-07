// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';
import {Utils} from '@kyber.network/utils-sc/contracts/Utils.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {MockLiquidationStrategy} from './MockLiquidationStrategy.sol';
import {ILiquidationPriceOracleBase} from '../interfaces/liquidation/ILiquidationPriceOracleBase.sol';

contract MockLiquidatorWithCallback is Utils {
  using SafeERC20 for IERC20Ext;

  uint256[] public transferBackAmounts;
  bool public shouldTestReentrancy = false;

  constructor( ) {}

  receive() external payable {}

  function setTransferBackAmounts(uint256[] memory amounts) external {
    transferBackAmounts = amounts;
  }

  function setTestReentrancy(bool shouldTest) external {
    shouldTestReentrancy = shouldTest;
  }

  function liquidationCallback(
    address, // caller,
    IERC20Ext[] calldata sources,
    uint256[] calldata amounts,
    address payable recipient,
    IERC20Ext[] calldata dests,
    uint256[] calldata,// minReturns,
    bytes calldata txData
  ) external {
    if (shouldTestReentrancy) {
      MockLiquidationStrategy(msg.sender).liquidate(
        ILiquidationPriceOracleBase(MockLiquidationStrategy(msg.sender).getWhitelistedPriceOracleAt(0)),
        sources, amounts, recipient, dests, '', txData
      );
    }
    for(uint256 i = 0; i < dests.length; i++) {
      if (dests[i] == ETH_TOKEN_ADDRESS) {
        (bool success, ) = msg.sender.call { value: transferBackAmounts[i] }('');
        require(success, 'transfer failed');
      } else {
        dests[i].safeTransfer(msg.sender, transferBackAmounts[i]);
      }
    }
  }
}
