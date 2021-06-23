// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

import {PermissionAdmin} from '@kyber.network/utils-sc/contracts/PermissionAdmin.sol';
import {Utils} from '@kyber.network/utils-sc/contracts/Utils.sol';
import {IERC20Ext} from '@kyber.network/utils-sc/contracts/IERC20Ext.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/EnumerableSet.sol';
import {ILiquidationCallback} from '../interfaces/liquidation/ILiquidationCallback.sol';
import {ILiquidationStrategyBase} from '../interfaces/liquidation/ILiquidationStrategyBase.sol';
import {ILiquidationPriceOracleBase} from '../interfaces/liquidation/ILiquidationPriceOracleBase.sol';
import {IPool} from '../interfaces/liquidation/IPool.sol';

abstract contract LiquidationStrategyBase is ILiquidationStrategyBase, PermissionAdmin, Utils, ReentrancyGuard {

  using SafeERC20 for IERC20Ext;
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  // after repeatedPeriod since startTime, there will be duration (in seconds)
  // for liquidators to liquidate tokens in the treasury pool
  // for example: from deployed time, every 2 weeks liquidation is enabled for 4 days
  struct LiquidationSchedule {
    uint128 startTime;
    uint64 repeatedPeriod;
    uint64 duration;
  }

  // list of tokens that can be liquidate to
  EnumerableSet.AddressSet private _whitelistedLiquidators;
  EnumerableSet.AddressSet private _whitelistedPriceOracles;

  LiquidationSchedule private _liquidationSchedule;
  IPool private _treasuryPool;
  address payable private _rewardPool;

  event TreasuryPoolSet(address indexed treasuryPool);
  event RewardPoolSet(address indexed rewardPool);
  event LiquidationScheduleUpdated(uint128 startTime, uint64 repeatedPeriod, uint64 duration);
  event WhitelistedLiquidatorUpdated(address indexed liquidator, bool indexed isAdd);
  event WhitelistedPriceOracleUpdated(address indexed oracle, bool indexed isAdd);

  constructor(
    address admin,
    address treasuryPoolAddress,
    address payable rewardPoolAddress,
    uint128 startTime,
    uint64 repeatedPeriod,
    uint64 duration,
    address[] memory whitelistedLiquidators,
    address[] memory whitelistedOracles
  ) PermissionAdmin(admin) {
    _setTreasuryPool(treasuryPoolAddress);
    _setRewardPool(rewardPoolAddress);
    _setLiquidationSchedule(startTime, repeatedPeriod, duration);
    _updateWhitelistedLiquidators(whitelistedLiquidators, true);
    _updateWhitelistedPriceOracles(whitelistedOracles, true);
  }

  receive() external payable {}

  /**
   * @dev Update liquidation schedule
   *  to disable the liquidation: set repeatedPeriod to 0
   *  to always enable the liquidation: set duration >= repeatedPeriod
   * @param startTime: start time of the first liquidation schedule
   * @param repeatedPeriod period in seconds that the schedule will be repeated
   * @param duration duration of each schedule
   */
  function updateLiquidationSchedule(
    uint128 startTime,
    uint64 repeatedPeriod,
    uint64 duration
  )
    external onlyAdmin
  {
    _setLiquidationSchedule(startTime, repeatedPeriod, duration);
  }

  function updateTreasuryPool(address pool) external override onlyAdmin {
    _setTreasuryPool(pool);
  }

  function updateRewardPool(address payable pool) external override onlyAdmin {
    _setRewardPool(pool);
  }

  function updateWhitelistedLiquidators(address[] calldata liquidators, bool isAdd)
    external override onlyAdmin
  {
    _updateWhitelistedLiquidators(liquidators, isAdd);
  }

  function updateWhitelistedOracles(address[] calldata oracles, bool isAdd)
    external override onlyAdmin
  {
    _updateWhitelistedPriceOracles(oracles, isAdd);
  }

  /** @dev Liquidate list of tokens to a single dest token,
  *   source token must not be a whitelisted token, dest must be a whitelisted token
  *   in case whitelisted liquidator is enabled, sender must be whitelisted
  * @param oracle the whitelisted oracle that will be used to get conversion data
  * @param sources list of source tokens to liquidate
  * @param amounts list of amounts corresponding to each source token
  * @param recipient receiver of source tokens
  * @param dests list of tokens to liquidate to
  * @param oracleHint hint for getting data from oracle
  * @param txData data to callback to recipient
  */
  function liquidate(
    ILiquidationPriceOracleBase oracle,
    IERC20Ext[] calldata sources,
    uint256[] calldata amounts,
    address payable recipient,
    IERC20Ext[] calldata dests,
    bytes calldata oracleHint,
    bytes calldata txData
  )
    external virtual override nonReentrant
    returns (uint256[] memory destAmounts)
  {

    require(isWhitelistedLiquidator(msg.sender), 'liquidate: only whitelisted liquidator');
    require(isWhitelistedOracle(address(oracle)), 'liquidate: only whitelisted oracle');
    require(isLiquidationEnabled(), 'liquidate: only when liquidation enabled');

    // request funds from treasury pool to recipient
    _treasuryPool.withdrawFunds(sources, amounts, recipient);
    // request return data from oracle
    uint256[] memory minReturns = oracle.getExpectedReturns(
      msg.sender, sources, amounts, dests, oracleHint
    );

    uint256[] memory destBalances = new uint256[](dests.length);
    for(uint256 i = 0; i < destBalances.length; i++) {
      destBalances[i] = getBalance(dests[i], address(this));
    }

    // callback for them to transfer dest amount to reward
    ILiquidationCallback(recipient).liquidationCallback(
      msg.sender, sources, amounts, payable(address(this)), dests, minReturns, txData
    );

    destAmounts = new uint256[](dests.length);
    for(uint256 i = 0; i < destBalances.length; i++) {
      destAmounts[i] = getBalance(dests[i], address(this)).sub(destBalances[i]);
      require(destAmounts[i] >= minReturns[i], "liquidate: low return amount");
      _transferToken(dests[i], payable(rewardPool()), destAmounts[i]);
    }
  }

  // Whitelisted liquidators
  function getWhitelistedLiquidatorsLength() external override view returns (uint256) {
    return _whitelistedLiquidators.length();
  }

  function getWhitelistedLiquidatorAt(uint256 index) external override view returns (address) {
    return _whitelistedLiquidators.at(index);
  }

  function getAllWhitelistedLiquidators()
    external view override returns (address[] memory liquidators)
  {
    uint256 length = _whitelistedLiquidators.length();
    liquidators = new address[](length);
    for(uint256 i = 0; i < length; i++) {
      liquidators[i] = _whitelistedLiquidators.at(i);
    }
  }

  // Whitelisted Price Orcales
  function getWhitelistedPriceOraclesLength() external override view returns (uint256) {
    return _whitelistedPriceOracles.length();
  }

  function getWhitelistedPriceOracleAt(uint256 index) external override view returns (address) {
    return _whitelistedPriceOracles.at(index);
  }

  function getAllWhitelistedPriceOracles()
    external view override returns (address[] memory oracles)
  {
    uint256 length = _whitelistedPriceOracles.length();
    oracles = new address[](length);
    for(uint256 i = 0; i < length; i++) {
      oracles[i] = _whitelistedPriceOracles.at(i);
    }
  }

  function getLiquidationSchedule()
    external override view
    returns(
      uint128 startTime,
      uint64 repeatedPeriod,
      uint64 duration
    )
  {
    (startTime, repeatedPeriod, duration) = (
      _liquidationSchedule.startTime,
      _liquidationSchedule.repeatedPeriod,
      _liquidationSchedule.duration
    );
  }

  function treasuryPool() public override view returns (address) {
    return address(_treasuryPool);
  }

  function rewardPool() public override view returns (address) {
    return _rewardPool;
  }

  function isWhitelistedLiquidator(address liquidator)
    public view override returns (bool)
  {
    return _whitelistedLiquidators.contains(liquidator);
  }

  function isWhitelistedOracle(address oracle)
    public view override returns (bool)
  {
    return _whitelistedPriceOracles.contains(oracle);
  }

  function isLiquidationEnabled() public view override returns (bool) {
    return isLiquidationEnabledAt(block.timestamp);
  }

  /** @dev Only support getting data for current or future timestamp
  */
  function isLiquidationEnabledAt(uint256 timestamp) public override view returns (bool) {
    if (timestamp < block.timestamp) return false;
    LiquidationSchedule memory schedule = _liquidationSchedule;
    if (schedule.repeatedPeriod == 0) return false;
    if (timestamp < uint256(schedule.startTime)) return false;
    uint256 timeInPeriod = (timestamp - uint256(schedule.startTime)) % uint256(schedule.repeatedPeriod);
    return timeInPeriod <= schedule.duration;
  }

  function _setTreasuryPool(address _pool) internal {
    require(_pool != address(0), 'invalid treasury pool');
    _treasuryPool = IPool(_pool);
    emit TreasuryPoolSet(_pool);
  }

  function _setRewardPool(address payable _pool) internal {
    require(_pool != address(0), 'invalid reward pool');
    _rewardPool = _pool;
    emit RewardPoolSet(_pool);
  }

  function _updateWhitelistedLiquidators(address[] memory _liquidators, bool _isAdd) internal {
    for(uint256 i = 0; i < _liquidators.length; i++) {
      if (_isAdd) {
        _whitelistedLiquidators.add(_liquidators[i]);
      } else {
        _whitelistedLiquidators.remove(_liquidators[i]);
      }
      emit WhitelistedLiquidatorUpdated(_liquidators[i], _isAdd);
    }
  }

  function _updateWhitelistedPriceOracles(address[] memory _oracles, bool _isAdd) internal {
    for(uint256 i = 0; i < _oracles.length; i++) {
      if (_isAdd) {
        _whitelistedPriceOracles.add(_oracles[i]);
      } else {
        _whitelistedPriceOracles.remove(_oracles[i]);
      }
      emit WhitelistedPriceOracleUpdated(_oracles[i], _isAdd);
    }
  }

  function _setLiquidationSchedule(
    uint128 _startTime,
    uint64 _repeatedPeriod,
    uint64 _duration
  ) internal {
    _liquidationSchedule = LiquidationSchedule({
        startTime: _startTime,
        repeatedPeriod: _repeatedPeriod,
        duration: _duration
    });
    emit LiquidationScheduleUpdated(_startTime, _repeatedPeriod, _duration);
  }

  function _transferToken(IERC20Ext token, address payable recipient, uint256 amount) internal {
    if (token == ETH_TOKEN_ADDRESS) {
      (bool success, ) = recipient.call { value: amount }('');
      require(success, 'transfer eth failed');
    } else {
      token.safeTransfer(recipient, amount);
    }
  }
}