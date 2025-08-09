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

    // Core Functions
    
    /**
     * @dev Deposit tokens to start earning yield
     * @param token The token address to deposit
     * @param amount The amount to deposit
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
     * @dev Withdraw tokens and any earned yield
     * @param token The token address to withdraw
     * @param amount The amount to withdraw (0 = withdraw all)
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

    /**
     * @dev Get user's total value including earned yield
     * @param user The user address
     * @param token The token address
     * @return The total value of user's position
     */
    function getUserTotalValue(address user, address token) public view returns (uint256) {
        UserBalance memory userBalance = userBalances[user][token];
        if (userBalance.shares == 0 || totalSupply[token] == 0) return 0;
        
        return (userBalance.shares * totalAssets[token]) / totalSupply[token];
    }

    /**
     * @dev Calculate shares for deposit amount
     * @param token The token address
     * @param amount The deposit amount
     * @return Number of shares to mint
     */
    function calculateShares(address token, uint256 amount) public view returns (uint256) {
        if (totalSupply[token] == 0 || totalAssets[token] == 0) {
            return amount;
        }
        return (amount * totalSupply[token]) / totalAssets[token];
    }

    /**
     * @dev Calculate shares to burn for withdrawal
     * @param token The token address
     * @param amount The withdrawal amount
     * @return Number of shares to burn
     */
    function calculateSharesToBurn(address token, uint256 amount) public view returns (uint256) {
        if (totalAssets[token] == 0) return 0;
        return (amount * totalSupply[token]) / totalAssets[token];
    }

    // Protocol Management Functions

    /**
     * @dev Add a new yield protocol for a token
     * @param token The token address
     * @param protocol The protocol address
     */
    function addProtocol(address token, address protocol) external onlyOwner {
        supportedProtocols[token].push(ProtocolInfo({
            protocolAddress: protocol,
            isActive: true,
            currentAPY: 0,
            totalDeposited: 0
        }));
        
        if (!isTokenSupported(token)) {
            supportedTokens.push(token);
        }
    }

    /**
     * @dev Switch to the best yielding protocol
     * @param token The token address
     * @param newProtocolIndex The index of the new protocol
     */
    function switchProtocol(address token, uint256 newProtocolIndex) external onlyOwner {
        require(newProtocolIndex < supportedProtocols[token].length, "Invalid protocol index");
        require(supportedProtocols[token][newProtocolIndex].isActive, "Protocol not active");
        
        uint256 currentProtocolIndex = activeProtocolIndex[token];
        string memory fromProtocol = IYieldProtocol(supportedProtocols[token][currentProtocolIndex].protocolAddress).getProtocolName();
        string memory toProtocol = IYieldProtocol(supportedProtocols[token][newProtocolIndex].protocolAddress).getProtocolName();
        
        // Get current balance from old protocol
        uint256 currentBalance = totalAssets[token];
        
        if (currentBalance > 0) {
            // Withdraw from current protocol
            _withdrawFromActiveProtocol(token, currentBalance);
            
            // Switch to new protocol
            activeProtocolIndex[token] = newProtocolIndex;
            
            // Deposit to new protocol
            _depositToActiveProtocol(token, currentBalance);
            
            emit ProtocolSwitch(token, fromProtocol, toProtocol, currentBalance, block.timestamp);
        } else {
            activeProtocolIndex[token] = newProtocolIndex;
        }
    }

    // Internal Functions
    
    function _depositToActiveProtocol(address token, uint256 amount) internal {
        uint256 protocolIndex = activeProtocolIndex[token];
        address protocolAddress = supportedProtocols[token][protocolIndex].protocolAddress;
        
        IERC20(token).safeApprove(protocolAddress, amount);
        require(
            IYieldProtocol(protocolAddress).deposit(token, amount),
            "Protocol deposit failed"
        );
        
        supportedProtocols[token][protocolIndex].totalDeposited += amount;
    }
    
    function _withdrawFromActiveProtocol(address token, uint256 amount) internal {
        uint256 protocolIndex = activeProtocolIndex[token];
        address protocolAddress = supportedProtocols[token][protocolIndex].protocolAddress;
        
        require(
            IYieldProtocol(protocolAddress).withdraw(token, amount),
            "Protocol withdrawal failed"
        );
        
        supportedProtocols[token][protocolIndex].totalDeposited = 
            supportedProtocols[token][protocolIndex].totalDeposited > amount ? 
            supportedProtocols[token][protocolIndex].totalDeposited - amount : 0;
    }

    // View Functions
    
    function isTokenSupported(address token) public view returns (bool) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) return true;
        }
        return false;
    }

    function getProtocolCount(address token) external view returns (uint256) {
        return supportedProtocols[token].length;
    }

    function getActiveProtocol(address token) external view returns (address, string memory) {
        uint256 protocolIndex = activeProtocolIndex[token];
        address protocolAddress = supportedProtocols[token][protocolIndex].protocolAddress;
        string memory protocolName = IYieldProtocol(protocolAddress).getProtocolName();
        return (protocolAddress, protocolName);
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    // Admin Functions
    
    function updatePerformanceFee(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_PERFORMANCE_FEE, "Fee too high");
        performanceFee = newFee;
    }

    function updateFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "Invalid address");
        feeCollector = newCollector;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}