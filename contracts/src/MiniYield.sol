// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IYieldProtocol.sol";

contract MiniYield is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Events
    event Deposit(address indexed user, address indexed token, uint256 amount, uint256 timestamp);
    event Withdraw(address indexed user, address indexed token, uint256 amount, uint256 timestamp);
    event ProtocolSwitch(address indexed token, string from, string to, uint256 amount, uint256 timestamp);
    event RewardsDistributed(address indexed user, address indexed token, uint256 amount, uint256 timestamp);

    // Structs
    struct UserBalance {
        uint256 totalDeposited;
        uint256 shares;
        uint256 lastRewardTimestamp;
        uint256 unclaimedRewards;
    }

    struct ProtocolInfo {
        address protocolAddress;
        bool isActive;
        uint256 currentAPY;
        uint256 totalDeposited;
    }

}