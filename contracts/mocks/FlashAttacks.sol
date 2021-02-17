// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import {IKyberGovernance} from '../interfaces/IKyberGovernance.sol';
import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';
import {IExecutorWithTimelock} from '../interfaces/IExecutorWithTimelock.sol';

// contract FlashAttacks {
//   IERC20Ext internal immutable TOKEN;
//   address internal immutable MINTER;
//   IKyberGovernance internal immutable GOV;

//   constructor(
//     address _token,
//     address _MINTER,
//     address _governance
//   ) {
//     TOKEN = IERC20Ext(_token);
//     MINTER = _MINTER;
//     GOV = IKyberGovernance(_governance);
//   }

//   function flashVote(
//     uint256 votePower,
//     uint256 proposalId,
//     bool support
//   ) external {
//     TOKEN.transferFrom(MINTER, address(this), votePower);
//     GOV.submitVote(proposalId, support);
//     TOKEN.transfer(MINTER, votePower);
//   }

//   function flashVotePermit(
//     uint256 votePower,
//     uint256 proposalId,
//     bool support,
//     uint8 v,
//     bytes32 r,
//     bytes32 s
//   ) external {
//     TOKEN.transferFrom(MINTER, address(this), votePower);
//     GOV.submitVoteBySignature(proposalId, support, v, r, s);
//     TOKEN.transfer(MINTER, votePower);
//   }

//   function flashProposal(
//     uint256 proposalPower,
//     IExecutorWithTimelock executor,
//     address[] memory targets,
//     uint256[] memory values,
//     string[] memory signatures,
//     bytes[] memory calldatas,
//     bool[] memory withDelegatecalls,
//     bytes32 ipfsHash
//   ) external {
//     TOKEN.transferFrom(MINTER, address(this), proposalPower);
//     GOV.create(executor, targets, values, signatures, calldatas, withDelegatecalls, ipfsHash);
//     TOKEN.transfer(MINTER, proposalPower);
//   }
// }
