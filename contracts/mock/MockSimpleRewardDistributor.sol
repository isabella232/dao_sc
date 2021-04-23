// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';

contract MockSimpleRewardDistributor {
  IERC20Ext internal constant ETH_TOKEN_ADDRESS = IERC20Ext(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

  function claim(
    uint256 cycle,
    uint256 index,
    address user,
    IERC20Ext[] calldata tokens,
    uint256[] calldata cumulativeAmounts,
    bytes32[] calldata merkleProof
  ) external {
    cycle;
    index;
    merkleProof;
    // claim each token
    for (uint256 i = 0; i < tokens.length; i++) {
      uint256 claimAmount = cumulativeAmounts[i];
      // if none claimable, skip
      if (claimAmount == 0) continue;
      if (tokens[i] == ETH_TOKEN_ADDRESS) {
        (bool success, ) = user.call{value: claimAmount}('');
        require(success, 'eth transfer failed');
      } else {
        tokens[i].transfer(user, claimAmount);
      }
    }
  }
}
