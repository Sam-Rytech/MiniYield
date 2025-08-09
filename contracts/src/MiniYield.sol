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

    // State variables
    mapping(address => mapping(address => UserBalance)) public userBalances; // user -> token -> balance
    mapping(address => ProtocolInfo[]) public supportedProtocols; // token -> protocols array
    mapping(address => uint256) public activeProtocolIndex; // token -> active protocol index
    mapping(address => uint256) public totalSupply; // token -> total supply of shares
    mapping(address => uint256) public totalAssets; // token -> total assets managed
    
    address[] public supportedTokens;
    uint256 public constant PRECISION = 1e18;
    uint256 public performanceFee = 100; // 1% = 100 basis points
    uint256 public constant MAX_PERFORMANCE_FEE = 2000; // Max 20%
    
    address public feeCollector;
    bool public paused = false;

    // Modifiers
    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier validToken(address token) {
        require(isTokenSupported(token), "Token not supported");
        _;
    }

    constructor() {
        feeCollector = msg.sender;
    }

}