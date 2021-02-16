// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.5;
pragma abicoder v2;

interface IEpochUtils {
  function epochPeriodInSeconds() external view returns (uint256);

  function firstEpochStartTimestamp() external view returns (uint256);
  
  function getCurrentEpochNumber() external view returns (uint256);
  
  function getEpochNumber(uint256 timestamp) external view returns (uint256);
}


interface IKyberStaking is IEpochUtils {
  function initAndReturnStakerDataForCurrentEpoch(address staker)
    external
    returns (
      uint256 stake,
      uint256 delegatedStake,
      address representative
    );

  function deposit(uint256 amount) external;

  function delegate(address dAddr) external;

  function withdraw(uint256 amount) external;

  /**
  * @notice return combine data (stake, delegatedStake, representative) of a staker
  * @dev allow to get staker data up to current epoch + 1
  */
  function getStakerData(address staker, uint256 epoch)
    external
    view
    returns (
      uint256 stake,
      uint256 delegatedStake,
      address representative
    );

  function getLatestStakerData(address staker)
    external
    view
    returns (
      uint256 stake,
      uint256 delegatedStake,
      address representative
    );

  /**
  * @notice return raw data of a staker for an epoch
  *         WARN: should be used only for initialized data
  *          if data has not been initialized, it will return all 0
  *          pool master shouldn't use this function to compute/distribute rewards of pool members
  */
  function getStakerRawData(address staker, uint256 epoch)
    external
    view
    returns (
      uint256 stake,
      uint256 delegatedStake,
      address representative
    );
}
