// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';

import {IVotingPowerStrategy} from '../interfaces/IVotingPowerStrategy.sol';
import {IKyberGovernance} from '../interfaces/IKyberGovernance.sol';
import {IKyberStaking} from '../interfaces/IKyberStaking.sol';
import {EpochUtils} from '../misc/EpochUtils.sol';

/**
 * @title Governance Strategy contract
 * @dev Smart contract containing logic to measure users' relative power to propose and vote.
 * @author Aave
 **/
contract KyberVotingPowerStrategy is IVotingPowerStrategy, EpochUtils {
  using SafeMath for uint256;

  uint256 public constant MAX_PROPOSAL_PER_EPOCH = 10;
  IKyberStaking public immutable staking;
  IKyberGovernance public immutable governance;

  mapping(uint256 => uint256[]) internal epochProposals;

  /**
   * @dev Constructor, register tokens used for Voting and Proposition Powers.
   * @param _staking The address of the knc staking contract.
   **/
  constructor(IKyberGovernance _governance, IKyberStaking _staking) {
    staking = _staking;
    governance = _governance;

    /// init epochutils
    epochPeriodInSeconds = _staking.epochPeriodInSeconds();
    firstEpochStartTimestamp = _staking.firstEpochStartTimestamp();
  }

  /// @dev endTimestamp: furture usage
  function handleProposalCreation(
    uint256 proposalID,
    uint256 startTimestamp,
    uint256 /*endTimestamp*/
  ) external override {
    require(msg.sender == address(governance), 'not governance');

    uint256 epoch = getEpochNumber(startTimestamp);

    epochProposals[epoch].push(proposalID);
  }

  function handleProposalCancellation(uint256 proposalID) external override {
    require(msg.sender == address(governance), 'not governance');

    IKyberGovernance.ProposalWithoutVote memory proposal = governance.getProposalById(proposalID);
    uint256 epoch = getEpochNumber(proposal.startTimestamp);

    uint256[] storage proposalIDs = epochProposals[epoch];
    for (uint256 i = 0; i < proposalIDs.length; i++) {
      if (proposalIDs[i] == proposalID) {
        // remove this campaign id out of list
        proposalIDs[i] = proposalIDs[proposalIDs.length - 1];
        proposalIDs.pop();
        break;
      }
    }
  }


  /// @dev assume that governance check start and end time
  /// @dev proposalID, choice: unused param for future use
  /// call to init data if needed, and return voter's voting power
  function handleVote(
    address voter,
    uint256 /*proposalID*/,
    uint256 /*choice*/
  ) external override returns (uint256 votingPower) {
    require(msg.sender == address(governance), 'not governance');

    (uint256 stake, uint256 dStake, address representative) =
      staking.initAndReturnStakerDataForCurrentEpoch(voter);
    return representative == voter ? stake.add(dStake) : dStake;
  }

  function handleWithdraw(address user, uint256 /*reduceAmount*/) external override {
    uint256 currentEpoch = getCurrentEpochNumber();
    (uint256 stake, uint256 dStake, address representative) =
      staking.getStakerData(user, currentEpoch);
    uint256 votingPower = representative == user ? stake.add(dStake) : dStake;
    governance.handleVotingPowerChanged(user, votingPower, epochProposals[currentEpoch]);
  }


  ///
  /// @dev call to get voter's voting power given timestamp
  /// @dev only for reading purpose. when submitVote, should call handleVote instead
  function getVotingPower(
    address voter,
    uint256 timestamp
  ) external view override returns (uint256 votingPower) {
    uint256 currentEpoch = getEpochNumber(timestamp);
    (uint256 stake, uint256 dStake, address representative) =
      staking.getStakerData(voter, currentEpoch);
    votingPower = representative == voter ? stake.add(dStake) : dStake;
  }

  function validateProposalCreation(
    uint256 startTimestamp,
    uint256 endTimestamp
  ) external view override returns (bool) {
    /// start in the past
    if(startTimestamp < block.timestamp) {
      return false;
    }
    uint256 startEpoch = getEpochNumber(startTimestamp);
    /// proposal must start and end within an epoch
    if(startEpoch != getEpochNumber(endTimestamp)) {
      return false;
    }
    /// proposal must be current or next epoch
    if(startEpoch > getCurrentEpochNumber().add(1)) {
      return false;
    }
    /// too many proposals
    if(epochProposals[startEpoch].length >= MAX_PROPOSAL_PER_EPOCH) {
      return false;
    }
    return true;
  }

  function getMaxVotingPower() external view override returns (uint256) {
    return staking.kncToken().totalSupply();
  }
}
