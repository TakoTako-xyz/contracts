// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;

interface IStakingConfigurator {
  event ProxyCreated(bytes32 id, address indexed newAddress);
  event MultiFeeDistributionUpdated(address indexed newAddress);
  event ChefIncentivesControllerUpdated(address indexed newAddress);
  event MasterChefUpdated(address indexed newAddress);
  event ProtocolRevenueDistributionUpdated(address indexed newAddress);

  function getMultiFeeDistribution() external view returns (address);

  function setMultiFeeDistributionImpl(address impl, bytes calldata initParams) external;

  function getChefIncentivesController() external view returns (address);

  function setChefIncentivesControllerImpl(address impl, bytes calldata initParams) external;

  function getMasterChef() external view returns (address);

  function setMasterChefImpl(address impl, bytes calldata initParams) external;

  function getProtocolRevenueDistribution() external view returns (address);

  function setProtocolRevenueDistributionImpl(address impl, bytes calldata initParams) external;
}
