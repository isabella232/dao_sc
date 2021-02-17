// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {PermissionAdmin} from '@kyber.network/utils-sc/contracts/PermissionAdmin.sol';
import {IKyberGovernance} from '../interfaces/IKyberGovernance.sol';
import {IExecutorWithTimelock} from '../interfaces/IExecutorWithTimelock.sol';
import {IVotingPowerStrategy} from '../interfaces/IVotingPowerStrategy.sol';
import {IProposalValidator} from '../interfaces/IProposalValidator.sol';
import {getChainId} from '../misc/Helpers.sol';


/**
 * @title Kyber Governance contract for Kyber 3.0
 * - Create a Proposal
 * - Cancel a Proposal
 * - Queue a Proposal
 * - Execute a Proposal
 * - Submit Vote to a Proposal
 * Proposal States : Pending => Active => Succeeded(/Failed) => Queued => Executed(/Expired)
 *                   The transition to "Canceled" can appear in multiple states
 * @author Aave
 **/
contract KyberGovernance is IKyberGovernance, PermissionAdmin {
  using SafeMath for uint256;

  uint256 private _proposalsCount;
  mapping(uint256 => Proposal) private _proposals;
  mapping(address => bool) private _authorizedExecutors;
  mapping(address => bool) private _authorizedVotingPowerStrategies;

  address private _daoOperator;

  bytes32 public constant DOMAIN_TYPEHASH = keccak256(
    'EIP712Domain(string name,uint256 chainId,address verifyingContract)'
  );
  bytes32 public constant VOTE_EMITTED_TYPEHASH = keccak256('VoteEmitted(uint256 id,bool support)');
  string public constant NAME = 'Aave Governance v2';

  modifier onlyDaoOperator() {
    require(msg.sender == _daoOperator, 'ONLY_BY_DAO_OPERATOR');
    _;
  }

  constructor(
    address admin,
    address daoOperator,
    address[] memory executors,
    address[] memory votingPowerStrategies
  ) PermissionAdmin(admin) {
    require(daoOperator != address(0), "INVALID_DAO_OPERATOR");
    _daoOperator = _daoOperator;

    authorizeExecutors(executors);
    authorizeVotingPowerStrategies(votingPowerStrategies);
  }

  /**
   * @dev Creates a Binary Proposal (needs to be validated by the Proposal Validator)
   * @param executor The ExecutorWithTimelock contract that will execute the proposal
   * @param strategy voting power strategy of the proposal
   * @param targets list of contracts called by proposal's associated transactions
   * @param values list of value in wei for each proposal's associated transaction
   * @param signatures list of function signatures (can be empty) to be used when created the callData
   * @param calldatas list of calldatas: if associated signature empty, calldata ready, else calldata is arguments
   * @param withDelegatecalls boolean, true = transaction delegatecalls the taget, else calls the target
   * @param startTime start timestamp to allow vote
   * @param endTime end timestamp of the proposal
   * @param link link to the proposal description
   **/
  function createBinaryProposal(
    IExecutorWithTimelock executor,
    IVotingPowerStrategy strategy,
    address[] calldata targets,
    uint256[] calldata values,
    string[] calldata signatures,
    bytes[] calldata calldatas,
    bool[] calldata withDelegatecalls,
    uint256 startTime,
    uint256 endTime,
    string calldata link
  )
    external override returns (uint256 proposalId)
  {
    require(targets.length != 0, 'CREATE_BINARY_INVALID_EMPTY_TARGETS');
    require(
      targets.length == values.length &&
        targets.length == signatures.length &&
        targets.length == calldatas.length &&
        targets.length == withDelegatecalls.length,
      'CREATE_BINARY_INCONSISTENT_PARAMS_LENGTH'
    );

    require(isExecutorAuthorized(address(executor)), 'CREATE_BINARY_EXECUTOR_NOT_AUTHORIZED');
    require(isVotingPowerStrategyAuthorized(address(strategy)), 'CREATE_BINARY_STRATEGY_NOT_AUTHORIZED');

    proposalId = _proposalsCount;
    require(
      IProposalValidator(address(executor)).validateBinaryProposalCreation(
        strategy,
        msg.sender,
        proposalId,
        startTime,
        endTime,
        _daoOperator
      ),
      'PROPOSITION_CREATION_INVALID'
    );

    Proposal storage newProposal = _proposals[proposalId];
    ProposalWithoutVote storage newProposalData = newProposal.proposalData;
    newProposalData.id = proposalId;
    newProposalData.proposalType = ProposalType.Binary;
    newProposalData.creator = msg.sender;
    newProposalData.executor = executor;
    newProposalData.targets = targets;
    newProposalData.values = values;
    newProposalData.signatures = signatures;
    newProposalData.calldatas = calldatas;
    newProposalData.withDelegatecalls = withDelegatecalls;
    newProposalData.startTime = startTime;
    newProposalData.endTime = endTime;
    newProposalData.strategy = strategy;
    newProposalData.link = link;

    string[] memory options = new string[](2);
    (options[0], options[1]) = ("YES", "NO");
    uint256[] memory voteCounts = new uint256[](2);
    newProposalData.options = options;
    newProposalData.voteCounts = voteCounts;
    // use max voting power to finalise the proposal
    newProposalData.maxVotingPower = strategy.getMaxVotingPower();

    _proposalsCount++;
    // call strategy to record data if needed
    strategy.handleProposalCreation(proposalId, startTime, endTime);

    emit BinaryProposalCreated(
      proposalId,
      msg.sender,
      executor,
      strategy,
      targets,
      values,
      signatures,
      calldatas,
      withDelegatecalls,
      startTime,
      endTime,
      link
    );
  }

  /**
   * @dev Creates a Generic Proposal (needs to be validated by the Proposal Validator)
   *    It only gets the winning option without any executions
   * @param executor The ExecutorWithTimelock contract that will execute the proposal
   * @param strategy voting power strategy of the proposal
   * @param options list of options to vote for
   * @param startTime start timestamp to allow vote
   * @param endTime end timestamp of the proposal
   * @param link link to the proposal description
   **/
  function createGenericProposal(
    IExecutorWithTimelock executor,
    IVotingPowerStrategy strategy,
    string[] calldata options,
    uint256 startTime,
    uint256 endTime,
    string calldata link
  )
    external override returns (uint256 proposalId)
  {
    require(isExecutorAuthorized(address(executor)), 'CREATE_BINARY_EXECUTOR_NOT_AUTHORIZED');
    require(isVotingPowerStrategyAuthorized(address(strategy)), 'CREATE_BINARY_STRATEGY_NOT_AUTHORIZED');
    proposalId = _proposalsCount;
    require(
      IProposalValidator(address(executor)).validateGenericProposalCreation(
        strategy,
        msg.sender,
        proposalId,
        startTime,
        endTime,
        options,
        _daoOperator
      ),
      'PROPOSITION_CREATION_INVALID'
    );
    Proposal storage newProposal = _proposals[proposalId];
    ProposalWithoutVote storage newProposalData = newProposal.proposalData;
    newProposalData.id = proposalId;
    newProposalData.proposalType = ProposalType.Generic;
    newProposalData.creator = msg.sender;
    newProposalData.executor = executor;
    newProposalData.startTime = startTime;
    newProposalData.endTime = endTime;
    newProposalData.strategy = strategy;
    newProposalData.link = link;
    newProposalData.options = options;
    newProposalData.voteCounts = new uint256[](options.length);
    // use max voting power to finalise the proposal
    newProposalData.maxVotingPower = strategy.getMaxVotingPower();

    _proposalsCount++;
    // call strategy to record data if needed
    strategy.handleProposalCreation(proposalId, startTime, endTime);

    emit BinaryProposalCreated(
      proposalId,
      msg.sender,
      executor,
      strategy,
      options,
      startTime,
      endTime,
      link
    );
  }

  /**
   * @dev Cancels a Proposal.
   * - Callable by the _daoOperator with relaxed conditions, or by anybody if the conditions of
   *   cancellation on the executor are fulfilled
   * @param proposalId id of the proposal
   **/
  function cancel(uint256 proposalId) external override {
    ProposalState state = getProposalState(proposalId);
    require(
      state != ProposalState.Executed &&
        state != ProposalState.Canceled &&
        state != ProposalState.Expired,
      'ONLY_BEFORE_EXECUTED'
    );

    Proposal storage proposal = _proposals[proposalId];
    require(
      msg.sender == _daoOperator ||
        IProposalValidator(address(proposal.executor)).validateProposalCancellation(
          proposalId,
          proposal.creator
        ),
      'PROPOSITION_CANCELLATION_INVALID'
    );
    proposal.canceled = true;
    if (proposal.proposalType == ProposalType.Binary) {
      for (uint256 i = 0; i < proposal.targets.length; i++) {
        proposal.executor.cancelTransaction(
          proposal.targets[i],
          proposal.values[i],
          proposal.signatures[i],
          proposal.calldatas[i],
          proposal.executionTime,
          proposal.withDelegatecalls[i]
        );
      }
    }
    // notify voting power strategy about the cancellation
    proposal.strategy.handleProposalCancellation(proposalId);

    emit ProposalCanceled(proposalId);
  }

  /**
   * @dev Queue the proposal (If Proposal Succeeded)
   * @param proposalId id of the proposal to queue
   **/
  function queue(uint256 proposalId) external override {
    require(getProposalState(proposalId) == ProposalState.Succeeded, 'INVALID_STATE_FOR_QUEUE');
    Proposal storage proposal = _proposals[proposalId];
    require(proposal.proposalType == ProposalType.Binary, "PROPOSAL_DOES_NOT_HAVE_TXS");
    uint256 executionTime = block.timestamp.add(proposal.executor.getDelay());
    for (uint256 i = 0; i < proposal.targets.length; i++) {
      _queueOrRevert(
        proposal.executor,
        proposal.targets[i],
        proposal.values[i],
        proposal.signatures[i],
        proposal.calldatas[i],
        executionTime,
        proposal.withDelegatecalls[i]
      );
    }
    proposal.executionTime = executionTime;

    emit ProposalQueued(proposalId, executionTime, msg.sender);
  }

  /**
   * @dev Execute the proposal (If Proposal Queued)
   * @param proposalId id of the proposal to execute
   **/
  function execute(uint256 proposalId) external payable override {
    require(getProposalState(proposalId) == ProposalState.Queued, 'ONLY_QUEUED_PROPOSALS');
    Proposal storage proposal = _proposals[proposalId];
    require(proposal.proposalType == ProposalType.Binary, "ONLY_BINARY_PROPOSAL");
    proposal.executed = true;
    for (uint256 i = 0; i < proposal.targets.length; i++) {
      proposal.executor.executeTransaction{value: proposal.values[i]}(
        proposal.targets[i],
        proposal.values[i],
        proposal.signatures[i],
        proposal.calldatas[i],
        proposal.executionTime,
        proposal.withDelegatecalls[i]
      );
    }
    emit ProposalExecuted(proposalId, msg.sender);
  }

  /**
   * @dev Function allowing msg.sender to vote for/against a proposal
   * @param proposalId id of the proposal
   * @param choice bitmask choice of voter
   **/
  function submitVote(uint256 proposalId, uint256 choice) external override {
    return _submitVote(msg.sender, proposalId, choice);
  }

  /**
   * @dev Function to register the vote of user that has voted offchain via signature
   * @param proposalId id of the proposal
   * @param choice the bit mask of voted options
   * @param v v part of the voter signature
   * @param r r part of the voter signature
   * @param s s part of the voter signature
   **/
  function submitVoteBySignature(
    uint256 proposalId,
    uint256 choice,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external override {
    bytes32 digest = keccak256(
      abi.encodePacked(
        '\x19\x01',
        keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), getChainId(), address(this))),
        keccak256(abi.encode(VOTE_EMITTED_TYPEHASH, proposalId, choice))
      )
    );
    address signer = ecrecover(digest, v, r, s);
    require(signer != address(0), 'INVALID_SIGNATURE');
    return _submitVote(signer, proposalId, choice);
  }

  /**
   * @dev Function to handle voting power changed for a staker
   *  caller must be the voting power strategy of the proposal
   * @param staker address that has changed the voting power
   * @param newVotingPower new voting power of that address,
   *   old voting power can be taken from records
   * @param proposalIds list proposal ids that belongs to this voting power strategy
   *   should update the voteCound of the active proposals in the list
   **/
  function handleVotingPowerChanged(
    address staker,
    uint256 newVotingPower,
    uint256[] calldata proposalIds
  ) external override {
    for(uint256 i = 0; i < proposalIds.length; i++ ) {
      if (getProposalState(proposalIds[i]) == ProposalState.Active) {
        ProposalWithoutVote storage proposal = _proposals[proposalIds[i]];
        require(address(proposal.strategy) == msg.sender, "ONLY_VOTING_POWER_STRATEGY");
        Vote memory vote = proposal.votes[staker];
        if (vote.choice == 0) continue; // not voted yet
        uint256 oldVotingPower = uint256(vote.votingPower);
        // update vote count for each voted option
        for(uint256 j = 0; j < proposal.options.length; j++) {
          if (vote.choice && (2 ** j) == (2 ** j)) {
            // expect proposal.voteCounts[i] >= oldVotingPower
            proposal.voteCounts[j] = proposal.voteCounts[j] + newVotingPower - oldVotingPower;
          }
        }
        // update voting power of the staker
        _proposals[proposalIds[i]].votes[staker] = Vote({
          choice: vote.choice,
          votingPower: uint224(newVotingPower)
        });
      }
    }
  }

  /**
   * @dev Add new addresses to the list of authorized executors
   * @param executors list of new addresses to be authorized executors
   **/
  function authorizeExecutors(address[] memory executors) public override onlyAdmin {
    for (uint256 i = 0; i < executors.length; i++) {
      _authorizeExecutor(executors[i]);
    }
  }

  /**
   * @dev Remove addresses to the list of authorized executors
   * @param executors list of addresses to be removed as authorized executors
   **/
  function unauthorizeExecutors(address[] memory executors) public override onlyAdmin {
    for (uint256 i = 0; i < executors.length; i++) {
      _unauthorizeExecutor(executors[i]);
    }
  }

  /**
   * @dev Add new addresses to the list of authorized strategies
   * @param strategies list of new addresses to be authorized strategies
   **/
  function authorizeVotingPowerStrategies(address[] memory strategies) public override onlyAdmin {
    for (uint256 i = 0; i < strategies.length; i++) {
      _authorizedVotingPowerStrategy(strategies[i]);
    }
  }

  /**
   * @dev Remove addresses to the list of authorized strategies
   * @param strategies list of addresses to be removed as authorized strategies
   **/
  function unauthorizeVotingPowerStrategies(address[] memory strategies) public override onlyAdmin {
    for (uint256 i = 0; i < strategies.length; i++) {
      _unauthorizedVotingPowerStrategy(strategies[i]);
    }
  }

  /**
   * @dev Returns whether an address is an authorized executor
   * @param executor address to evaluate as authorized executor
   * @return true if authorized
   **/
  function isExecutorAuthorized(address executor) public view override returns (bool) {
    return _authorizedExecutors[executor];
  }

  /**
   * @dev Returns whether an address is an authorized strategy
   * @param strategy address to evaluate as authorized strategy
   * @return true if authorized
   **/
  function isVotingPowerStrategyAuthorized(address strategy) public view override returns (bool) {
    return _authorizedVotingPowerStrategies[strategy];
  }

  /**
   * @dev Getter the address of the daoOperator, that can mainly cancel proposals
   * @return The address of the daoOperator
   **/
  function getDaoOperator() external view override returns (address) {
    return _daoOperator;
  }

  /**
   * @dev Getter of the proposal count (the current number of proposals ever created)
   * @return the proposal count
   **/
  function getProposalsCount() external view override returns (uint256) {
    return _proposalsCount;
  }

  /**
   * @dev Getter of a proposal by id
   * @param proposalId id of the proposal to get
   * @return the proposal as ProposalWithoutVote memory object
   **/
  function getProposalById(uint256 proposalId)
    external
    view
    override
    returns (ProposalWithoutVote memory)
  {
    return _proposals[proposalId].proposalData;
  }

  /**
   * @dev Getter of the Vote of a voter about a proposal
   * Note: Vote is a struct: ({bool support, uint248 votingPower})
   * @param proposalId id of the proposal
   * @param voter address of the voter
   * @return The associated Vote memory object
   **/
  function getVoteOnProposal(uint256 proposalId, address voter)
    external
    view
    override
    returns (Vote memory)
  {
    return _proposals[proposalId].votes[voter];
  }

  /**
   * @dev Get the current state of a proposal
   * @param proposalId id of the proposal
   * @return The current state if the proposal
   **/
  function getProposalState(uint256 proposalId) public view override returns (ProposalState) {
    require(_proposalsCount >= proposalId, 'INVALID_PROPOSAL_ID');
    Proposal storage proposal = _proposals[proposalId];
    if (proposal.canceled) {
      return ProposalState.Canceled;
    } else if (block.timestamp < proposal.startTime) {
      return ProposalState.Pending;
    } else if (block.timestamp <= proposal.endTime) {
      return ProposalState.Active;
    } else if (!IProposalValidator(address(proposal.executor)).isProposalPassed(_proposals.strategy, proposalId)) {
      return ProposalState.Failed;
    } else if (proposal.executionTime == 0) {
      return ProposalState.Succeeded;
    } else if (proposal.executed) {
      return ProposalState.Executed;
    } else if (proposal.executor.isProposalOverGracePeriod(this, proposalId)) {
      return ProposalState.Expired;
    } else {
      return ProposalState.Queued;
    }
  }

  function _queueOrRevert(
    IExecutorWithTimelock executor,
    address target,
    uint256 value,
    string memory signature,
    bytes memory callData,
    uint256 executionTime,
    bool withDelegatecall
  ) internal {
    require(
      !executor.isActionQueued(
        keccak256(abi.encode(target, value, signature, callData, executionTime, withDelegatecall))
      ),
      'DUPLICATED_ACTION'
    );
    executor.queueTransaction(target, value, signature, callData, executionTime, withDelegatecall);
  }

  function _submitVote(
    address voter,
    uint256 proposalId,
    uint256 choice
  ) internal {
    require(choice > 0, "VOTING_NO_CHOICE_SPECIFIED");
    require(getProposalState(proposalId) == ProposalState.Active, 'VOTING_CLOSED');
    ProposalWithoutVote storage proposal = _proposals[proposalId].proposalData;
    uint256 numOptions;
    if (proposal.proposalType == ProposalType.Binary) {
      // either Yes or No
      require(choice == 1 || choice == 2, "VOTING_WRONG_VOTE_FOR_BINARY_PROPOSAL");
    } else {
      numOptions = proposal.options.length;
      require(choice < 2**numOptions, "VOTING_INVALID_OPTION_FOR_GENERIC_PROPOSAL");
    }

    Vote memory vote = _proposals[proposalId].votes[voter];
    uint256 votingPower = proposal.strategy.handleVote(voter, proposalId, choice);
    if (vote.optionBitMask == 0) {
      // first time vote
      proposal.totalVotes += votingPower;
    }
    for(uint256 i = 0; i < proposal.options.length; i++) {
      bool isVoted = vote.optionBitMask & 2**i == 2**i;
      bool isVoting = choice && 2**i == 2**i;
      if (isVoted && !isVoting) {
        proposal.voteCounts[i] -= votingPower;
      } else if (!isVoted && isVoting){
        proposal.voteCounts[i] += votingPower;
      }
    }

    proposal.votes[voter] = Vote({
      optionBitMask: uint32(choice),
      votingPower: uint224(votingPower)
    });
    // emit VoteEmitted(proposalId, voter, support, votingPower);
  }

  function _authorizeExecutor(address executor) internal {
    _authorizedExecutors[executor] = true;
    emit ExecutorAuthorized(executor);
  }

  function _unauthorizeExecutor(address executor) internal {
    _authorizedExecutors[executor] = false;
    emit ExecutorUnauthorized(executor);
  }

  function _authorizedVotingPowerStrategy(address strategy) internal {
    _authorizedVotingPowerStrategy[strategy] = true;
    // emit ExecutorAuthorized(strategy);
  }

  function _unauthorizedVotingPowerStrategy(address strategy) internal {
    _authorizedVotingPowerStrategy[strategy] = false;
    // emit ExecutorUnauthorized(strategy);
  }
}
