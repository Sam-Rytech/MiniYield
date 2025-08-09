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

    //Core Functions

    /**
    * Deposit tokens to start earning Yield
    * The token address to deposit
    * The amount to deposit
    */
    function deposit(address token, uint256 amount)
        external
        nonReentrant
        notPaused
        validToken(token)
    {
        require(amount > 0, "Amount must be greater than 0");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 shares = calculateShares(token, amount);
        
        UserBalance storage userBalance = userBalances[msg.sender][token];
        
        // Update user balance
        userBalance.totalDeposited += amount;
        userBalance.shares += shares;
        userBalance.lastRewardTimestamp = block.timestamp;
        
        // Update global state
        totalSupply[token] += shares;
        totalAssets[token] += amount;
        
        // Deposit to active protocol
        _depositToActiveProtocol(token, amount);
        
        emit Deposit(msg.sender, token, amount, block.timestamp);
    }
    
    /**
     * Withdraw tokens and any earned yield
     * The token address to withdraw
     * The amount to withdraw (0 = withdraw all)
     */
     
    function withdraw(address token, uint256 amount) 
        external 
        nonReentrant 
        notPaused 
        validToken(token) 
    {
        UserBalance storage userBalance = userBalances[msg.sender][token];
        require(userBalance.shares > 0, "No balance to withdraw");
        
        uint256 userTotalValue = getUserTotalValue(msg.sender, token);
        uint256 withdrawAmount = amount == 0 ? userTotalValue : amount;
        
        require(withdrawAmount <= userTotalValue, "Insufficient balance");
        
        uint256 sharesToBurn = calculateSharesToBurn(token, withdrawAmount);
        
        // Update user balance
        userBalance.shares -= sharesToBurn;
        if (userBalance.shares == 0) {
            userBalance.totalDeposited = 0;
        } else {
            userBalance.totalDeposited = (userBalance.totalDeposited * userBalance.shares) / (userBalance.shares + sharesToBurn);
        }
        
        // Update global state
        totalSupply[token] -= sharesToBurn;
        totalAssets[token] -= withdrawAmount;
        
        // Withdraw from active protocol
        _withdrawFromActiveProtocol(token, withdrawAmount);
        
        // Transfer tokens to user
        IERC20(token).safeTransfer(msg.sender, withdrawAmount);
        
        emit Withdraw(msg.sender, token, withdrawAmount, block.timestamp);
    }





}