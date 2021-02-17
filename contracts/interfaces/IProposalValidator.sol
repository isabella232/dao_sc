// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import {IKyberGovernance} from './IKyberGovernance.sol';
import {IVotingPowerStrategy} from './IVotingPowerStrategy.sol';


interface IProposalValidator {
  /**
   * @dev Called to validate a generic proposal
   * @param strategy votingPowerStrategy contract to calculate voting power
   * @param creator address of the creator
   * @param proposalId Id of the binary proposal
   * @param startTimestamp timestamp when vote starts
   * @param endTimestamp timestamp when vote ends
   * @param daoOperator address of daoOperator
   * @return boolean, true if can be created
   **/
  function validateBinaryProposalCreation(
    IVotingPowerStrategy strategy,
    address creator,
    uint256 proposalId,
    uint256 startTimestamp,
    uint256 endTimestamp,
    address daoOperator
  ) external view returns (bool);

  /**
   * @dev Called to validate a generic proposal
   * @param strategy votingPowerStrategy contract to calculate voting power
   * @param creator address of the creator
   * @param proposalId Id of the generic proposal
   * @param startTimestamp timestamp when vote starts
   * @param endTimestamp timestamp when vote ends
   * @param options list of proposal vote options
   * @param daoOperator address of daoOperator
   * @return boolean, true if can be created
   **/
  function validateGenericProposalCreation(
    IVotingPowerStrategy strategy,
    address creator,
    uint256 proposalId,
    uint256 startTimestamp,
    uint256 endTimestamp,
    string[] options,
    address daoOperator
  ) external view returns (bool);

  /**
   * @dev Called to validate the cancellation of a proposal
   * @param proposalId Id of the generic proposal
   * @param creator address of the creator
   * @return boolean, true if can be cancelled
   **/
  function validateProposalCancellation(
    uint256 proposalId,
    address creator
  ) external view returns (bool);

  /**
   * @dev Returns whether a proposal passed or not
   * @param strategy votingPowerStrategy contract to calculate voting power
   * @param proposalId Id of the proposal to set
   * @return true if proposal passed
   **/
  function isProposalPassed(
    IVotingPowerStrategy strategy,
    uint256 proposalId
  ) external view returns (bool);

  /**
   * @dev Check whether a proposal has reached quorum
   * @param strategy votingPowerStrategy contract to calculate voting power
   * @param proposalId Id of the proposal to verify
   * @return voting power needed for a proposal to pass
   **/
  function isQuorumValid(
    IVotingPowerStrategy strategy,
    uint256 proposalId
  ) external view returns (bool);

  /**
   * @dev Check whether a proposal has enough extra FOR-votes than AGAINST-votes
   * @param strategy votingPowerStrategy contract to calculate voting power
   * @param proposalId Id of the proposal to verify
   * @return true if enough For-Votes
   **/
  function isVoteDifferentialValid(
    IVotingPowerStrategy strategy,
    uint256 proposalId
  ) external view returns (bool);
  
  /**
   * @dev Check whether...
   * @param proposalId Id of the proposal to verify
   * @param voter voter address
   * @param choice vote options the voter selected
   * @return true if
   **/
  function validateVote(
    uint256 proposalId,
    address voter,
    uint256 choice
  ) external view returns (bool);

  /**
   * @dev Get maximum voting duration constant value
   * @return the maximum voting duration value in seconds
   **/
  function MAX_VOTING_DURATION() external view returns (uint256);

  /**
   * @dev Get the vote differential threshold constant value
   * to compare with % of for votes/total supply - % of against votes/total supply
   * @return the vote differential threshold value (100 <=> 1%)
   **/
  function VOTE_DIFFERENTIAL() external view returns (uint256);

  /**
   * @dev Get quorum threshold constant value
   * to compare with % of for votes/total supply
   * @return the quorum threshold value (100 <=> 1%)
   **/
  function MINIMUM_QUORUM() external view returns (uint256);

  /**
   * @dev precision helper: 100% = 10000
   * @return one hundred percents with our chosen precision
   **/
  function ONE_HUNDRED_WITH_PRECISION() external view returns (uint256);
}
