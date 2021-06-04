// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';
import {PermissionAdmin} from '@kyber.network/utils-sc/contracts/PermissionAdmin.sol';
import {IKyberFairLaunch} from '../interfaces/liquidityMining/IKyberFairLaunch.sol';
import {IKyberRewardLocker} from '../interfaces/liquidityMining/IKyberRewardLocker.sol';

/// FairLaunch contract for Kyber DMM Liquidity Mining program
/// Allow stakers to stake LP tokens and receive reward token
/// Part of the reward will be locked and vested
/// Allow extend or renew a pool to continue/restart the LM program
contract KyberFairLaunch is IKyberFairLaunch, PermissionAdmin, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeCast for uint256;
  using SafeERC20 for IERC20Ext;

  uint256 public constant BPS = 10000;
  uint256 public constant PRECISION = 1e12;

  struct UserRewardData {
    uint256 unclaimedReward;
    uint256 lastRewardPerShare;
  }
  // Info of each user.
  struct UserInfo {
    uint256 amount; // How many Staking tokens the user has provided.
    mapping (address => UserRewardData) userRewardData;

    //
    // Basically, any point in time, the amount of reward token
    // entitled to a user but is pending to be distributed is:
    //
    //   pending reward = user.unclaimAmount + (user.amount * (pool.accRewardPerShare - user.lastRewardPerShare)
    //
    // Whenever a user deposits or withdraws Staking tokens to a pool. Here's what happens:
    //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
    //   2. User receives the pending reward sent to his/her address.
    //   3. User's `lastRewardPerShare` gets updated.
    //   4. User's `amount` gets updated.
  }

  struct PoolRewardData {
    uint256 rewardPerBlock;
    uint256 accRewardPerShare;
  }
  // Info of each pool
  // poolRewardData: reward data for each reward token
  //      rewardPerBlock: amount of reward token per block
  //      accRewardPerShare: accumulated reward per share of token
  // totalStake: total amount of stakeToken has been staked
  // stakeToken: token to stake, should be an ERC20 token
  // startBlock: the block that the reward starts
  // endBlock: the block that the reward ends
  // rewardTokens: list of reward tokens for this pool
  // lastRewardBlock: last block number that rewards distribution occurs
  struct PoolInfo {
    uint256 totalStake;
    address stakeToken;
    uint32 startBlock;
    uint32 endBlock;
    uint32 lastRewardBlock;
    address[] rewardTokens;
    mapping (address => PoolRewardData) poolRewardData;
  }

  // check if a pool exists for a stakeToken
  mapping(address => bool) public poolExists;
  // contract for locking reward
  IKyberRewardLocker public immutable rewardLocker;

  // Info of each pool.
  uint256 public override poolLength;
  mapping(uint256 => PoolInfo) public poolInfo;
  // Info of each user that stakes Staking tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;

  event AddNewPool(
    address indexed stakeToken,
    uint32 indexed startBlock,
    uint32 indexed endBlock,
    address[] rewardTokens,
    uint256[] rewardPerBlocks
  );
  event RenewPool(
    uint256 indexed pid,
    uint32 indexed startBlock,
    uint32 indexed endBlock,
    uint256[] rewardPerBlocks
  );
  event UpdatePool(
    uint256 indexed pid,
    uint32 indexed endBlock,
    uint256[] rewardPerBlocks
  );
  event AddRewardToken(
    uint256 indexed pid,
    address indexed rewardToken,
    uint256 indexed rewardPerBlock
  );
  event Deposit(
    address indexed user,
    uint256 indexed pid,
    uint256 indexed blockNumber,
    uint256 amount
  );
  event Withdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 indexed blockNumber,
    uint256 amount
  );
  event Harvest(
    address indexed user,
    uint256 indexed pid,
    address indexed rewardToken,
    uint256 lockedAmount,
    uint256 blockNumber
  );
  event EmergencyWithdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 indexed blockNumber,
    uint256 amount
  );

  constructor(
    address _admin,
    IKyberRewardLocker _rewardLocker
  ) PermissionAdmin(_admin) {
    rewardLocker = _rewardLocker;
  }

  receive() external payable {}

  /**
   * @dev allow admin to withdraw in case of anything happens
   */
  function adminWithdraw(IERC20Ext token, uint256 amount) external onlyAdmin {
    if (token == IERC20Ext(0)) {
      (bool success, ) = msg.sender.call{ value: amount }('');
      require(success, 'transfer reward token failed');
    } else {
      token.safeTransfer(msg.sender, amount);
    }
  }

  /**
   * @dev Add a new lp to the pool. Can only be called by the admin.
   * @param _stakeToken: token to be staked to the pool
   * @param _startBlock: block where the reward starts
   * @param _endBlock: block where the reward ends
   * @param _rewardTokens: list of reward tokens for the pool
   * @param _rewardPerBlocks: amount of reward token per block for the pool for each reward token
   */
  function addPool(
    address _stakeToken,
    uint32 _startBlock,
    uint32 _endBlock,
    address[] calldata _rewardTokens,
    uint256[] calldata _rewardPerBlocks
  ) external override onlyAdmin {
    require(!poolExists[_stakeToken], 'add: duplicated pool');
    require(_stakeToken != address(0), 'add: invalid stake token');
    require(_rewardTokens.length == _rewardPerBlocks.length, 'add: invalid length');

    require(_startBlock > block.number && _endBlock > _startBlock, 'add: invalid blocks');

    poolInfo[poolLength].stakeToken = _stakeToken;
    poolInfo[poolLength].startBlock = _startBlock;
    poolInfo[poolLength].endBlock = _endBlock;
    poolInfo[poolLength].lastRewardBlock = _startBlock;

    for(uint256 i = 0; i < _rewardPerBlocks.length; i++) {
      poolInfo[poolLength].rewardTokens.push(_rewardTokens[i]);
      poolInfo[poolLength].poolRewardData[_rewardTokens[i]].rewardPerBlock = _rewardPerBlocks[i];
      _approveAllowanceToLocker(IERC20Ext(_rewardTokens[i]));
    }

    poolLength++;

    poolExists[_stakeToken] = true;

    emit AddNewPool(_stakeToken, _startBlock, _endBlock, _rewardTokens, _rewardPerBlocks);
  }

  /**
   * @dev Renew a pool to start another liquidity mining program
   * @param _pid: id of the pool to renew, must be pool that has not started or already ended
   * @param _startBlock: block where the reward starts
   * @param _endBlock: block where the reward ends
   * @param _rewardPerBlocks: amount of reward token per block for the pool
   */
  function renewPool(
    uint256 _pid,
    uint32 _startBlock,
    uint32 _endBlock,
    uint256[] calldata _rewardPerBlocks
  ) external override onlyAdmin {
    updatePoolRewards(_pid);

    PoolInfo storage pool = poolInfo[_pid];
    // check if pool has not started or already ended
    require(
      pool.startBlock > block.number || pool.endBlock < block.number,
      'renew: invalid pool state to renew'
    );
    // checking data of new pool
    require(pool.rewardTokens.length == _rewardPerBlocks.length, 'renew: invalid length');
    require(_startBlock > block.number && _endBlock > _startBlock, 'renew: invalid blocks');

    pool.startBlock = _startBlock;
    pool.endBlock = _endBlock;
    pool.lastRewardBlock = _startBlock;

    for(uint256 i = 0; i < _rewardPerBlocks.length; i++) {
      pool.poolRewardData[pool.rewardTokens[i]].rewardPerBlock = _rewardPerBlocks[i];
    }

    emit RenewPool(_pid, _startBlock, _endBlock, _rewardPerBlocks);
  }

  /**
   * @dev Update a pool, allow to change end block, reward per block
   * @param _pid: pool id to be renew
   * @param _endBlock: block where the reward ends
   * @param _rewardPerBlocks: amount of reward token per block for the pool,
   *   0 if we want to stop the pool from accumulating rewards of any reward tokens
   */
  function updatePool(
    uint256 _pid,
    uint32 _endBlock,
    uint256[] calldata _rewardPerBlocks
  ) external override onlyAdmin {
    updatePoolRewards(_pid);

    PoolInfo storage pool = poolInfo[_pid];

    // should call renew pool if the pool has ended
    require(pool.endBlock > block.number, 'update: pool already ended');
    require(pool.rewardTokens.length == _rewardPerBlocks.length, 'renew: invalid length');
    require(_endBlock > block.number && _endBlock > pool.startBlock, 'update: invalid end block');

    pool.endBlock = _endBlock;
    for(uint256 i = 0; i < _rewardPerBlocks.length; i++) {
      pool.poolRewardData[pool.rewardTokens[i]].rewardPerBlock = _rewardPerBlocks[i];
    }

    emit UpdatePool(_pid, _endBlock, _rewardPerBlocks);
  }

  /**
   * @dev add reward token to the pool reward tokens
   * in case removing, call updatePool to set the reward per block to 0
   */
  function addRewardToken(uint256 _pid, address _rewardToken, uint256 _rewardPerBlock)
    external override onlyAdmin
  {
    updatePoolRewards(_pid);
    PoolInfo storage pool = poolInfo[_pid];

    pool.rewardTokens.push(_rewardToken);
    pool.poolRewardData[_rewardToken].rewardPerBlock = _rewardPerBlock;

    _approveAllowanceToLocker(IERC20Ext(_rewardToken));

    emit AddRewardToken(_pid, _rewardToken, _rewardPerBlock);
  }

  /**
   * @dev deposit to tokens to accumulate rewards
   * @param _pid: id of the pool
   * @param _amount: amount of stakeToken to be deposited
   * @param _shouldHarvest: whether to harvest the reward or not
   */
  function deposit(
    uint256 _pid,
    uint256 _amount,
    bool _shouldHarvest
  ) external override nonReentrant {
    // update pool rewards, user's rewards
    updatePoolRewards(_pid);
    _updateUserReward(msg.sender, _pid, _shouldHarvest);

    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    // collect stakeToken
    IERC20Ext(pool.stakeToken).safeTransferFrom(msg.sender, address(this), _amount);

    // update user staked amount, and total staked amount for the pool
    user.amount = user.amount.add(_amount);
    pool.totalStake = pool.totalStake.add(_amount);

    emit Deposit(msg.sender, _pid, block.number, _amount);
  }

  /**
   * @dev withdraw token (of the sender) from pool, also harvest reward
   * @param _pid: id of the pool
   * @param _amount: amount of stakeToken to withdraw
   */
  function withdraw(uint256 _pid, uint256 _amount) external override nonReentrant {
    _withdraw(_pid, _amount);
  }

  /**
   * @dev withdraw all tokens (of the sender) from pool, also harvest reward
   * @param _pid: id of the pool
   */
  function withdrawAll(uint256 _pid) external override nonReentrant {
    _withdraw(_pid, userInfo[_pid][msg.sender].amount);
  }

  /**
   * @notice EMERGENCY USAGE ONLY, USER'S REWARD WILL BE RESET
   * @dev emergency withdrawal function to allow withdraw all deposited token (of the sender)
   *   without harvesting the reward
   * @param _pid: id of the pool
   */
  function emergencyWithdraw(uint256 _pid) external override nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    uint256 amount = user.amount;

    user.amount = 0;
    for(uint256 i = 0; i < pool.rewardTokens.length; i++) {
      UserRewardData storage rewardData = user.userRewardData[pool.rewardTokens[i]];
      rewardData.lastRewardPerShare = 0;
      rewardData.unclaimedReward = 0;
    }

    pool.totalStake = pool.totalStake.sub(amount);

    if (amount > 0) {
      IERC20Ext(pool.stakeToken).safeTransfer(msg.sender, amount);
    }

    emit EmergencyWithdraw(msg.sender, _pid, block.number, amount);
  }

  /**
   * @dev harvest rewards from multiple pools for the sender
   */
  function harvestMultiplePools(uint256[] calldata _pids) external override {
    for (uint256 i = 0; i < _pids.length; i++) {
      harvest(_pids[i]);
    }
  }

  /**
   * @dev get pending reward of a user from a pool, mostly for front-end
   * @param _pid: id of the pool
   * @param _user: user to check for pending rewards
   */
  function pendingReward(uint256 _pid, address _user)
    external
    override
    view
    returns (uint256[] memory rewards)
  {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 _totalStake = pool.totalStake;
    uint256 _poolLastRewardBlock = pool.lastRewardBlock;
    address[] memory rTokens = pool.rewardTokens;
    rewards = new uint256[](rTokens.length);

    uint32 lastAccountedBlock = _lastAccountedRewardBlock(_pid);
    for(uint256 i = 0; i < rTokens.length; i++) {
      uint256 _accRewardPerShare = pool.poolRewardData[rTokens[i]].accRewardPerShare;
      if (lastAccountedBlock > _poolLastRewardBlock && _totalStake != 0) {
        uint256 reward = (lastAccountedBlock - _poolLastRewardBlock)
          .mul(pool.poolRewardData[rTokens[i]].rewardPerBlock);
        _accRewardPerShare = _accRewardPerShare.add(reward.mul(PRECISION) / _totalStake);
      }

      rewards[i] = user.amount.mul(
        _accRewardPerShare.sub(user.userRewardData[rTokens[i]].lastRewardPerShare)
        ) / PRECISION;
      rewards[i] = rewards[i].add(user.userRewardData[rTokens[i]].unclaimedReward);
    }
  }

  /**
   * @dev harvest reward from pool for the sender
   * @param _pid: id of the pool
   */
  function harvest(uint256 _pid) public override {
    updatePoolRewards(_pid);
    _updateUserReward(msg.sender, _pid, true);
  }

  /**
   * @dev update reward for one pool
   */
  function updatePoolRewards(uint256 _pid) public override {
    require(_pid < poolLength, 'invalid pool id');
    PoolInfo storage pool = poolInfo[_pid];
    uint32 lastAccountedBlock = _lastAccountedRewardBlock(_pid);
    if (lastAccountedBlock <= pool.lastRewardBlock) return;
    uint256 _totalStake = pool.totalStake;
    if (_totalStake == 0) {
      pool.lastRewardBlock = lastAccountedBlock;
      return;
    }
    uint256 numberBlocks = lastAccountedBlock - pool.lastRewardBlock;
    pool.lastRewardBlock = lastAccountedBlock;
    if (numberBlocks == 0) return;
    for(uint256 i = 0; i < pool.rewardTokens.length; i++) {
      PoolRewardData storage rewardData = pool.poolRewardData[pool.rewardTokens[i]];
      uint256 reward = numberBlocks.mul(rewardData.rewardPerBlock);
      rewardData.accRewardPerShare = rewardData.accRewardPerShare
        .add(reward.mul(PRECISION) / _totalStake);
    }
  }

  /**
   * @dev withdraw _amount of stakeToken from pool _pid, also harvest reward for the sender
   */
  function _withdraw(uint256 _pid, uint256 _amount) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount >= _amount, 'withdraw: insufficient amount');

    // update pool reward and harvest
    updatePoolRewards(_pid);
    _updateUserReward(msg.sender, _pid, true);

    user.amount = user.amount.sub(_amount);
    pool.totalStake = pool.totalStake.sub(_amount);

    IERC20Ext(pool.stakeToken).safeTransfer(msg.sender, _amount);

    emit Withdraw(msg.sender, _pid, block.number, user.amount);
  }

  /**
   * @dev update reward of _to address from pool _pid, harvest if needed
   */
  function _updateUserReward(
    address _to,
    uint256 _pid,
    bool shouldHarvest
  ) internal {
    uint256 userAmount = userInfo[_pid][_to].amount;
    address[] memory rTokens = poolInfo[_pid].rewardTokens;

    if (userAmount == 0) {
      // update user last reward per share to the latest pool reward per share
      // by right if user.amount is 0, user.unclaimedReward should be 0 as well,
      // except when user uses emergencyWithdraw function
      for(uint256 i = 0; i < rTokens.length; i++) {
        userInfo[_pid][_to].userRewardData[rTokens[i]].lastRewardPerShare =
          poolInfo[_pid].poolRewardData[rTokens[i]].accRewardPerShare;
      }
      return;
    }

    for(uint256 i = 0; i < rTokens.length; i++) {
      uint256 lastAccRewardPerShare = poolInfo[_pid].poolRewardData[rTokens[i]].accRewardPerShare;
      UserRewardData storage rewardData = userInfo[_pid][_to].userRewardData[rTokens[i]];
      // user's unclaim reward + user's amount * (pool's accRewardPerShare - user's lastRewardPerShare) / precision
      uint256 _pending = userAmount.mul(
        lastAccRewardPerShare.sub(rewardData.lastRewardPerShare)
      ) / PRECISION;
      _pending = _pending.add(rewardData.unclaimedReward);

      rewardData.unclaimedReward = shouldHarvest ? 0 : _pending;

      if (shouldHarvest && _pending > 0) {
        _lockReward(IERC20Ext(rTokens[i]), _to, _pending);
        emit Harvest(_to, _pid, rTokens[i], _pending, block.number);
      }

      // update user last reward per share to the latest pool reward per share
      rewardData.lastRewardPerShare = lastAccRewardPerShare;
    }
  }

  /**
   * @dev returns last accounted reward block, either the current block number or the endBlock of the pool
   */
  function _lastAccountedRewardBlock(uint256 _pid) internal view returns (uint32 _value) {
    _value = poolInfo[_pid].endBlock;
    if (_value > block.number) _value = block.number.toUint32();
  }

  function _lockReward(IERC20Ext token, address _account, uint256 _amount) internal {
    uint256 value = (token == IERC20Ext(0)) ? _amount : 0;
    rewardLocker.lock{ value: value }(token, _account, _amount);
  }

  /**
   * @dev approve allowance of a reward token to RewardLocker
   */
  function _approveAllowanceToLocker(IERC20Ext token) internal {
    if (token == IERC20Ext(0)) return; // no need approve allowance for native token
    if (token.allowance(address(this), address(rewardLocker)) == 0) {
      token.safeApprove(address(rewardLocker), type(uint256).max);
    }
  }
}
