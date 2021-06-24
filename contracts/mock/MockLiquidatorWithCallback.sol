// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';
import {Utils} from '@kyber.network/utils-sc/contracts/Utils.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {MockLiquidationStrategy} from './MockLiquidationStrategy.sol';

contract MockLiquidatorWithCallback is Utils {
  using SafeERC20 for IERC20Ext;

  uint256 public transferBackAmount = 0;
  bool public shouldTestReentrancy = false;

  constructor( ) {}

  receive() external payable {}

  function setTransferBackAmount(uint256 amount) external {
    transferBackAmount = amount;
  }

  function setTestReentrancy(bool shouldTest) external {
    shouldTestReentrancy = shouldTest;
  }

  function liquidationCallback(
    address caller,
    IERC20Ext[] calldata sources,
    uint256[] calldata amounts,
    address payable recipient,
    IERC20Ext[] calldata dests,
    uint256[] calldata minReturns,
    bytes calldata
  ) external {
    // if (shouldTestReentrancy) {
    //   MockLiquidationStrategy(msg.sender).callLiquidate(
    //     sources, amounts, recipient, dest, 0, txData
    //   );
    // }
    // if (dest == ETH_TOKEN_ADDRESS) {
    //   (bool success, ) = msg.sender.call { value: transferBackAmount }('');
    //   require(success, 'transfer failed');
    // } else {
    //   dest.safeTransfer(msg.sender, transferBackAmount);
    // }
  }
}
