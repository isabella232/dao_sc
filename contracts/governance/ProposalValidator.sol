// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import {IKyberGovernance} from '../interfaces/IKyberGovernance.sol';
import {IVotingPowerStrategy} from '../interfaces/IVotingPowerStrategy.sol';
import {IProposalValidator} from '../interfaces/IProposalValidator.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Utils} from '@kyber.network/utils-sc/contracts/Utils.sol';

/**
 * @title Proposal Validator Contract, inherited by Kyber Executors
 * @dev Validates/Invalidates propositions state modifications
 * Proposition Power functions: Validates proposition creations/ cancellation
 * Voting Power functions: Validates success of propositions.
 * @author Aave
 **/
contract ProposalValidator is IProposalValidator, Utils {
  using SafeMath for uint256;

  uint256 public immutable override PROPOSITION_THRESHOLD;
  uint256 public immutable override MIN_VOTING_DURATION;
  uint256 public immutable override MAX_VOTING_OPTIONS;
  uint256 public immutable override VOTE_DIFFERENTIAL;
  uint256 public immutable override MINIMUM_QUORUM;

  uint256 public constant override ONE_HUNDRED_WITH_PRECISION = 10000; // Equivalent to 100%, but scaled for precision
  uint256 public constant YES_INDEX = 0;
  uint256 public constant NO_INDEX = 1;

  /**
   * @dev Constructor
   * @param propositionThreshold minimum percentage of supply needed to submit a proposal
   * - In ONE_HUNDRED_WITH_PRECISION units
   * @param minVotingDuration minimum duration in seconds of the voting period
   * @param maxVotingOptions maximum no. of vote options possible for a generic proposal
   * @param voteDifferential percentage of supply that `for` votes need to be over `against`
   *   in order for the proposal to pass
   * - In ONE_HUNDRED_WITH_PRECISION units
   * @param minimumQuorum minimum percentage of the supply in FOR-voting-power need for a proposal to pass
   * - In ONE_HUNDRED_WITH_PRECISION units
   **/
  constructor(
    uint256 propositionThreshold,
    uint256 minVotingDuration,
    uint256 maxVotingOptions,
    uint256 voteDifferential,
    uint256 minimumQuorum
  ) {
    PROPOSITION_THRESHOLD = propositionThreshold;
    MIN_VOTING_DURATION = minVotingDuration;
    MAX_VOTING_OPTIONS = maxVotingOptions;
    VOTE_DIFFERENTIAL = voteDifferential;
    MINIMUM_QUORUM = minimumQuorum;
  }

  /**
   * @dev Called to validate the cancellation of a proposal
   * @param governance governance contract to fetch proposals from
   * @param proposalId Id of the generic proposal
   * @param user entity initiating the cancellation
   * @return boolean, true if can be cancelled
   **/
  function validateProposalCancellation(
    IKyberGovernance governance,
    uint256 proposalId,
    address user
  ) external pure override returns (bool) {
    // silence compilation warnings
    governance;
    proposalId;
    user;
    return false;
  }

  /**
   * @dev Called to validate a binary proposal
   * @param strategy votingPowerStrategy contract to calculate voting power
   * @param creator address of the creator
   * @param startTime timestamp when vote starts
   * @param endTime timestamp when vote ends
   * @param daoOperator address of daoOperator
   * @return boolean, true if can be created
   **/
  function validateBinaryProposalCreation(
    IVotingPowerStrategy strategy,
    address creator,
    uint256 startTime,
    uint256 endTime,
    address daoOperator
  ) external view override returns (bool) {
    // check authorization
    if (creator != daoOperator) return false;
    // check vote duration
    if (endTime.sub(startTime) < MIN_VOTING_DURATION) return false;

    return strategy.validateProposalCreation(startTime, endTime);
  }

  /**
   * @dev Called to validate a generic proposal
   * @param strategy votingPowerStrategy contract to calculate voting power
   * @param creator address of the creator
   * @param startTime timestamp when vote starts
   * @param endTime timestamp when vote ends
   * @param options list of proposal vote options
   * @param daoOperator address of daoOperator
   * @return boolean, true if can be created
   **/
  function validateGenericProposalCreation(
    IVotingPowerStrategy strategy,
    address creator,
    uint256 startTime,
    uint256 endTime,
    string[] calldata options,
    address daoOperator
  ) external view override returns (bool) {
    // check authorization
    if (creator != daoOperator) return false;
    // check vote duration
    if (endTime.sub(startTime) < MIN_VOTING_DURATION) return false;
    // check options length
    if (options.length > MAX_VOTING_OPTIONS) return false;

    return strategy.validateProposalCreation(startTime, endTime);
  }

  /**
   * @dev Returns whether a binary proposal passed or not
   * @param governance governance contract to fetch proposals from
   * @param proposalId Id of the proposal to set
   * @return true if proposal passed
   **/
  function isBinaryProposalPassed(IKyberGovernance governance, uint256 proposalId)
    public
    view
    override
    returns (bool)
  {
    return (isQuorumValid(governance, proposalId) &&
      isVoteDifferentialValid(governance, proposalId));
  }

  /**
   * @dev Check whether a proposal has reached quorum
   * Here quorum is not the number of votes reached, but number of YES_VOTES
   * @param governance governance contract to fetch proposals from
   * @param proposalId Id of the proposal to verify
   * @return true if minimum quorum is reached
   **/
  function isQuorumValid(IKyberGovernance governance, uint256 proposalId)
    public
    override
    view
    returns (bool)
  {
    IKyberGovernance.ProposalWithoutVote memory proposal = governance.getProposalById(proposalId);
    if (proposal.proposalType == IKyberGovernance.ProposalType.Binary) {
      return isMinimumQuorumReached(proposal.voteCounts[YES_INDEX], proposal.maxVotingPower);
    } else if (proposal.proposalType == IKyberGovernance.ProposalType.Generic) {
      (,uint256 winningOptionVoteCount) = getWinningOptionData(proposal.voteCounts);
      return isMinimumQuorumReached(winningOptionVoteCount, proposal.maxVotingPower);
    } else {
      return false;
    }
  }

  /**
   * @dev Check whether a proposal has sufficient YES_VOTES
   * Binary proposal: YES_VOTES - NO_VOTES > VOTE_DIFFERENTIAL * voting supply
   * Binary proposal: MOST_VOTED_OPTION - ALL_OTHER_VOTES > VOTE_DIFFERENTIAL * voting supply
   * @param governance Governance Contract
   * @param proposalId Id of the proposal to verify
   * @return true if enough YES_VOTES
   **/
  function isVoteDifferentialValid(IKyberGovernance governance, uint256 proposalId)
    public
    override
    view
    returns (bool)
  {
    IKyberGovernance.ProposalWithoutVote memory proposal = governance.getProposalById(proposalId);
    if (proposal.proposalType == IKyberGovernance.ProposalType.Binary) {
      return (proposal.voteCounts[YES_INDEX].mul(ONE_HUNDRED_WITH_PRECISION).div(proposal.maxVotingPower) >
      proposal.voteCounts[NO_INDEX].mul(ONE_HUNDRED_WITH_PRECISION).div(proposal.maxVotingPower).add(
        VOTE_DIFFERENTIAL
      ));
    } else if (proposal.proposalType == IKyberGovernance.ProposalType.Generic) {
      (,uint256 winningOptionVoteCount) = getWinningOptionData(proposal.voteCounts);
      return isGenericVoteDifferentialValid(winningOptionVoteCount, proposal.totalVotes, proposal.maxVotingPower);
    } else {
      return false;
    }
  }

  /**
   * @dev Fetch the winning option of a generic proposal
   * @param governance Governance Contract
   * @param proposalId Id of the proposal to verify
   * @return winningOption option index with the most votes and sufficient quorum, 0 otherwise
   **/
  function getGenericProposalWinningOption(IKyberGovernance governance, uint256 proposalId)
    external
    view
    override
    returns (uint256 winningOption)
  {
    IKyberGovernance.ProposalWithoutVote memory proposal = governance.getProposalById(proposalId);
    if (proposal.proposalType != IKyberGovernance.ProposalType.Generic) return 0;

    uint256 winningVoteCount;
    (winningOption, winningVoteCount) = getWinningOptionData(proposal.voteCounts);
    if (winningOption == 0) return 0;
    if (!isMinimumQuorumReached(winningVoteCount, proposal.maxVotingPower)) return 0;
    return (isGenericVoteDifferentialValid(winningVoteCount, proposal.totalVotes, proposal.maxVotingPower)) ?
      winningOption : 0;
  }

  function getWinningOptionData(uint256[] memory voteCounts)
    internal
    pure
    returns (uint256 winningOption, uint256 winningVoteCount)
  {
    uint256 maxVotedCount;
    uint256 i;
    // first, get maxVoteCount
    for (i = 0; i < voteCounts.length; i++) {
      if (voteCounts[i] > maxVotedCount) {
        winningOption = i + 1;
        maxVotedCount = voteCounts[i];
        winningVoteCount = maxVotedCount;
      }
    }
    // if there are duplicates, return 0
    for (i = 0; i < voteCounts.length; i++) {
      if (winningOption == i + 1) continue;
      if (voteCounts[i] == maxVotedCount) {
        winningOption = 0;
        winningVoteCount = 0;
      }
    }
  }

  function isGenericVoteDifferentialValid(
    uint256 winningVoteCount,
    uint256 totalVotes,
    uint256 maxVotingPower
  ) internal view returns (bool) {
    return (winningVoteCount.mul(ONE_HUNDRED_WITH_PRECISION).div(maxVotingPower) >
      (totalVotes.sub(winningVoteCount)).mul(ONE_HUNDRED_WITH_PRECISION).div(maxVotingPower).add(
        VOTE_DIFFERENTIAL
      ));
  }

  function isMinimumQuorumReached(uint256 votes, uint256 voteSupply) internal view returns (bool) {
    return votes >= voteSupply.mul(MINIMUM_QUORUM).div(ONE_HUNDRED_WITH_PRECISION);
  }
}
