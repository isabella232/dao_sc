// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';
import {PermissionAdmin} from '@kyber.network/utils-sc/contracts/PermissionAdmin.sol';
import {IKyberFairLaunchv2} from '../interfaces/liquidityMining/IKyberFairLaunchv2.sol';
import {IKyberRewardLocker} from '../interfaces/liquidityMining/IKyberRewardLocker.sol';

/// FairLaunch contract for Kyber DMM Liquidity Mining program
/// Allow stakers to stake LP tokens and receive reward token
/// Part of the reward will be locked and vested
/// Allow extend or renew a pool to continue/restart the LM program
contract KyberFairLaunchv2 is IKyberFairLaunchv2, PermissionAdmin, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeCast for uint256;
  using SafeERC20 for IERC20Ext;

  uint256 public constant BPS = 10000;
  uint256 public constant PRECISION = 1e12;

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
  struct UserInfo {
    uint256 amount; // How many Staking tokens the user has provided.
    mapping(address => UserRewardInfo) rewardInfoPerToken;
  }
  struct UserRewardInfo {
    uint128 unclaimedReward; // Reward that is pending to claim
    uint128 lastRewardPerShare; // Last recorded reward per share
  }

  // Info of each pool
  // totalStake: total amount of stakeToken has been staked
  // stakeToken: token to stake, should be an ERC20 token
  struct PoolInfo {
    uint256 totalStake;
    address stakeToken;
    address[] rewardTokens;
    mapping(address => PoolRewardInfo) rewardInfoPerToken;
  }

  // Info of each reward token
  // rewardPerBlock: amount of reward token per block
  // accRewardPerShare: accumulated reward per share of token
  // startBlock: the block that the reward starts
  // endBlock: the block that the reward ends
  // lastRewardBlock: last block number that rewards distribution occurs
  struct PoolRewardInfo {
    uint128 accRewardPerShare;
    uint32 lastRewardBlock;
    uint128 rewardPerBlock;
    uint32 startBlock;
    uint32 endBlock;
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
    address indexed rewardToken,
    uint32 startBlock,
    uint32 endBlock,
    uint256 rewardPerBlock
  );

  event AddRewardToken(
    uint256 indexed pid,
    address indexed rewardToken,
    uint32 startBlock,
    uint32 endBlock,
    uint256 rewardPerBlock
  );

  event RenewPool(
    uint256 indexed pid,
    address indexed rewardToken,
    uint32 startBlock,
    uint32 endBlock,
    uint256 rewardPerBlock
  );
  event UpdatePool(
    uint256 indexed pid,
    address indexed rewardToken,
    uint32 endBlock,
    uint256 rewardPerBlock
  );
  event Deposit(address indexed user, uint256 indexed pid, uint256 blockNumber, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 blockNumber, uint256 amount);
  event Harvest(
    address indexed user,
    uint256 indexed pid,
    address indexed rewardToken,
    uint256 blockNumber,
    uint256 lockedAmount
  );
  event EmergencyWithdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 blockNumber,
    uint256 amount
  );

  constructor(address _admin, IKyberRewardLocker _rewardLocker) PermissionAdmin(_admin) {
    rewardLocker = _rewardLocker;
  }

  /**
   * @dev allow admin to withdraw only reward token
   */
  function adminWithdraw(address _rewardToken, uint256 amount) external onlyAdmin {
    require(!poolExists[_rewardToken], 'invalid _rewardToken');
    IERC20Ext(_rewardToken).safeTransfer(msg.sender, amount);
  }

  /**
   * @dev Add a new lp to the pool. Can only be called by the admin.
   * @param _stakeToken: token to be staked to the pool
   * @param _startBlock: block where the reward starts
   * @param _endBlock: block where the reward ends
   * @param _rewardPerBlock: amount of reward token per block for the pool
   */
  function addPool(
    address _stakeToken,
    address _rewardToken,
    uint32 _startBlock,
    uint32 _endBlock,
    uint128 _rewardPerBlock
  ) external override onlyAdmin {
    require(!poolExists[_stakeToken], 'add: duplicated pool');
    require(!poolExists[_rewardToken], 'invalid _rewardToken');
    require(_stakeToken != address(0), 'add: invalid stake token');
    require(_startBlock > block.number && _endBlock > _startBlock, 'add: invalid blocks');
    require(_rewardPerBlock != 0, '0 rewardPerBlock');

    PoolInfo storage poolData = poolInfo[poolLength];
    poolData.stakeToken = _stakeToken;
    poolData.totalStake = 0;
    poolData.rewardTokens.push(_rewardToken);
    poolData.rewardInfoPerToken[_rewardToken] = PoolRewardInfo({
      startBlock: _startBlock,
      endBlock: _endBlock,
      lastRewardBlock: _startBlock,
      rewardPerBlock: _rewardPerBlock,
      accRewardPerShare: 0
    });

    poolLength++;
    poolExists[_stakeToken] = true;
    _approveMaxIfNot(_rewardToken);

    emit AddNewPool(_stakeToken, _rewardToken, _startBlock, _endBlock, _rewardPerBlock);
  }

  function addRewardToken(
    uint256 _pid,
    address _rewardToken,
    uint32 _startBlock,
    uint32 _endBlock,
    uint128 _rewardPerBlock
  ) external override onlyAdmin {
    require(_pid < poolLength, 'invalid pool id');
    require(!poolExists[_rewardToken], 'invalid _rewardToken');
    require(_startBlock > block.number && _endBlock > _startBlock, 'add: invalid blocks');
    require(_rewardPerBlock != 0, '0 rewardPerBlock');

    PoolInfo storage poolData = poolInfo[_pid];
    require(
      poolData.rewardInfoPerToken[_rewardToken].rewardPerBlock == 0,
      'existing _rewardToken'
    );
    poolData.rewardTokens.push(_rewardToken);
    poolData.rewardInfoPerToken[_rewardToken] = PoolRewardInfo({
      startBlock: _startBlock,
      endBlock: _endBlock,
      lastRewardBlock: _startBlock,
      rewardPerBlock: _rewardPerBlock,
      accRewardPerShare: 0
    });
    _approveMaxIfNot(_rewardToken);

    emit AddRewardToken(_pid, _rewardToken, _startBlock, _endBlock, _rewardPerBlock);
  }

  /**
   * @dev Renew a pool to start another liquidity mining program
   * @param _pid: id of the pool to renew, must be pool that has not started or already ended
   * @param _startBlock: block where the reward starts
   * @param _endBlock: block where the reward ends
   * @param _rewardPerBlock: amount of reward token per block for the pool
   */
  function renewPool(
    uint256 _pid,
    address _rewardToken,
    uint32 _startBlock,
    uint32 _endBlock,
    uint128 _rewardPerBlock
  ) external override onlyAdmin {
    // checking data of new pool
    require(_startBlock > block.number && _endBlock > _startBlock, 'add: invalid blocks');
    require(_rewardPerBlock != 0, '0 rewardPerBlock');

    PoolRewardInfo storage pool = poolInfo[_pid].rewardInfoPerToken[_rewardToken];
    // check if pool has not started or already ended
    require(
      pool.startBlock > block.number || pool.endBlock < block.number,
      'renew: invalid pool state to renew'
    );
    updatePoolRewards(_pid);

    pool.startBlock = _startBlock;
    pool.endBlock = _endBlock;
    pool.rewardPerBlock = _rewardPerBlock;
    pool.lastRewardBlock = _startBlock;

    emit RenewPool(_pid, _rewardToken, _startBlock, _endBlock, _rewardPerBlock);
  }

  /**
   * @dev Update a pool, allow to change end block, reward per block
   * @param _pid: pool id to be renew
   * @param _endBlock: block where the reward ends
   * @param _rewardPerBlock: amount of reward token per block for the pool,
   *   0 if we want to stop the pool from accumulating rewards
   */
  function updatePool(
    uint256 _pid,
    address _rewardToken,
    uint32 _endBlock,
    uint128 _rewardPerBlock
  ) external override onlyAdmin {
    require(_rewardPerBlock != 0, '0 rewardPerBlock');
    updatePoolRewards(_pid);
    PoolRewardInfo storage pool = poolInfo[_pid].rewardInfoPerToken[_rewardToken];

    // should call renew pool if the pool has ended
    require(pool.endBlock > block.number, 'update: pool already ended');
    require(_endBlock > block.number && _endBlock > pool.startBlock, 'update: invalid end block');

    (pool.endBlock, pool.rewardPerBlock) = (_endBlock, _rewardPerBlock);

    emit UpdatePool(_pid, _rewardToken, _endBlock, _rewardPerBlock);
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
    (address[] memory rewardTokens, uint128[] memory accRewardPerShare) = updatePoolRewards(_pid);
    _updateUserReward(msg.sender, _pid, rewardTokens, accRewardPerShare, _shouldHarvest);

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
    pool.totalStake = pool.totalStake.sub(amount);

    if (amount > 0) {
      IERC20Ext(pool.stakeToken).safeTransfer(msg.sender, amount);
    }
    emit EmergencyWithdraw(msg.sender, _pid, block.number, amount);
  }

  /**
   * @dev harvest rewards from multiple pools for the sender
   *   combine rewards from all pools and only transfer once to save gas
   */
  function harvestMultiplePools(uint256[] calldata _pids) external override {
    for (uint256 i = 0; i < _pids.length; i++) {
      uint256 pid = _pids[i];
      (address[] memory rewardTokens, uint128[] memory accRewardPerShare) = updatePoolRewards(pid);
      _updateUserReward(msg.sender, pid, rewardTokens, accRewardPerShare, true);
    }
  }

  /**
   * @dev get pending reward of a user from a pool, mostly for front-end
   * @param _pid: id of the pool
   * @param _user: user to check for pending rewards
   */
  function pendingReward(
    uint256 _pid,
    address _user,
    address _rewardToken
  ) external override view returns (uint256 rewards) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 _accRewardPerShare = pool.rewardInfoPerToken[_rewardToken].accRewardPerShare;
    uint256 _totalStake = pool.totalStake;
    uint32 lastAccountedBlock = _lastAccountedRewardBlock(_pid, _rewardToken);
    uint32 cacheLastAccountedBlock = pool.rewardInfoPerToken[_rewardToken].lastRewardBlock;
    if (lastAccountedBlock > cacheLastAccountedBlock && _totalStake != 0) {
      uint256 reward = uint256(lastAccountedBlock - cacheLastAccountedBlock).mul(
        pool.rewardInfoPerToken[_rewardToken].rewardPerBlock
      );
      _accRewardPerShare = _accRewardPerShare.add(reward.mul(PRECISION) / _totalStake);
    }

    UserRewardInfo memory preInfo = user.rewardInfoPerToken[_rewardToken];
    rewards = user.amount.mul(_accRewardPerShare.sub(preInfo.lastRewardPerShare)) / PRECISION;
    rewards = rewards.add(preInfo.unclaimedReward);
  }

  /**
   * @dev harvest reward from pool for the sender
   * @param _pid: id of the pool
   */
  function harvest(uint256 _pid) public override {
    (address[] memory rewardTokens, uint128[] memory accRewardPerShare) = updatePoolRewards(_pid);
    _updateUserReward(msg.sender, _pid, rewardTokens, accRewardPerShare, true);
  }

  /**
   * @dev update reward for one pool
   */
  function updatePoolRewards(uint256 _pid)
    public
    override
    returns (address[] memory rewardTokens, uint128[] memory accRewardPerShare)
  {
    require(_pid < poolLength, 'invalid pool id');
    PoolInfo storage pool = poolInfo[_pid];
    rewardTokens = pool.rewardTokens;
    accRewardPerShare = new uint128[](rewardTokens.length);
    uint256 _totalStake = pool.totalStake;
    for (uint256 i = 0; i < rewardTokens.length; i++) {
      address _rewardToken = rewardTokens[i];
      uint32 lastAccountedBlock = _lastAccountedRewardBlock(_pid, _rewardToken);
      PoolRewardInfo memory rewardInfo = pool.rewardInfoPerToken[_rewardToken];
      if (lastAccountedBlock <= rewardInfo.lastRewardBlock) continue;
      if (_totalStake == 0) {
        pool.rewardInfoPerToken[_rewardToken].lastRewardBlock = lastAccountedBlock;
        continue;
      }
      // local scope for passedBlock and reward
      {
        uint256 passedBlock = uint256(lastAccountedBlock - rewardInfo.lastRewardBlock);
        uint256 reward = passedBlock.mul(uint256(rewardInfo.rewardPerBlock));
        accRewardPerShare[i] = uint256(rewardInfo.accRewardPerShare)
          .add(reward.mul(PRECISION) / _totalStake)
          .toUint128();
      }
      pool.rewardInfoPerToken[_rewardToken].accRewardPerShare = accRewardPerShare[i];
      pool.rewardInfoPerToken[_rewardToken].lastRewardBlock = lastAccountedBlock;
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
    (address[] memory rewardTokens, uint128[] memory accRewardPerShare) = updatePoolRewards(_pid);
    _updateUserReward(msg.sender, _pid, rewardTokens, accRewardPerShare, true);

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
    address[] memory rewardTokens,
    uint128[] memory accRewardPerShare,
    bool shouldHarvest
  ) internal {
    UserInfo storage _userInfo = userInfo[_pid][_to];
    uint256 amount = _userInfo.amount;

    if (amount == 0) {
      // update user last reward per share to the latest pool reward per share
      // by right if user.amount is 0, user.unclaimedReward should be 0 as well,
      // except when user uses emergencyWithdraw function
      for (uint256 i = 0; i < rewardTokens.length; i++) {
        _userInfo.rewardInfoPerToken[rewardTokens[i]].lastRewardPerShare = accRewardPerShare[i];
      }
      return;
    }

    // user's unclaim reward + user's amount * (pool's accRewardPerShare - user's lastRewardPerShare) / precision
    for (uint256 i = 0; i < rewardTokens.length; i++) {
      address rewardToken = rewardTokens[i];
      UserRewardInfo memory preInfo = _userInfo.rewardInfoPerToken[rewardTokens[i]];
      // prettier-ignore
      uint256 _pending = amount.mul(uint256(accRewardPerShare[i]).sub(preInfo.lastRewardPerShare)) / PRECISION;
      _pending = _pending.add(preInfo.unclaimedReward);

      // prettier-ignore
      _userInfo.rewardInfoPerToken[rewardToken].unclaimedReward = shouldHarvest ? 0 : _pending.toUint128();
      _userInfo.rewardInfoPerToken[rewardToken].lastRewardPerShare = accRewardPerShare[i];
      if (_pending > 0 && shouldHarvest) {
        rewardLocker.lock(IERC20Ext(rewardTokens[i]), _to, _pending);
        emit Harvest(_to, _pid, rewardTokens[i], block.number, _pending);
      }
    }
  }

  /**
   * @dev returns last accounted reward block, either the current block number or the endBlock of the pool
   */
  function _lastAccountedRewardBlock(uint256 _pid, address _rewardToken)
    internal
    view
    returns (uint32 _value)
  {
    _value = poolInfo[_pid].rewardInfoPerToken[_rewardToken].endBlock;
    if (_value > block.number) _value = block.number.toUint32();
  }

  function _approveMaxIfNot(address _rewardToken) internal {
    uint256 allowance = IERC20Ext(_rewardToken).allowance(address(this), address(rewardLocker));
    if (allowance == 0) {
      IERC20Ext(_rewardToken).safeApprove(address(rewardLocker), type(uint256).max);
    }
  }
}
