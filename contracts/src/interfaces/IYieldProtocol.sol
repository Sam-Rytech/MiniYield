// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IYieldProtocol {
    function deposit(address token, uint256 amount) external returns (bool);
    function withdraw(address token, uint256 amount) external returns (bool);
    function getBalance(address user, address token) external view returns (uint256);
    function getCurrentAPY(address token) external view returns (uint256);
    function getProtocolName() external pure returns (string memory);
}