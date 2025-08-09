// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../src/interfaces/IYieldProtocol.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockYieldProtocol is IYieldProtocol {
    using SafeERC20 for IERC20;

    string private protocolName;
    uint256 private apy; // in basis points (e.g., 500 = 5%)
    mapping(address => mapping(address => uint256)) private balances; // user -> token -> balance
    mapping(address => uint256) private lastUpdateTime; // user -> timestamp

    constructor(string memory _name, uint256 _apy) {
        protocolName = _name;
        apy = _apy;
    }

    function deposit(address token, uint256 amount) external override returns (bool) {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update balance with any accrued interest
        _updateBalance(msg.sender, token);
        balances[msg.sender][token] += amount;
        lastUpdateTime[msg.sender] = block.timestamp;
        
        return true;
    }

    function withdraw(address token, uint256 amount) external override returns (bool) {
        _updateBalance(msg.sender, token);
        
        require(balances[msg.sender][token] >= amount, "Insufficient balance");
        
        balances[msg.sender][token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        
        return true;
    }

    function getBalance(address user, address token) external view override returns (uint256) {
        // Calculate balance with accrued interest
        uint256 currentBalance = balances[user][token];
        if (currentBalance == 0 || lastUpdateTime[user] == 0) {
            return currentBalance;
        }
        
        uint256 timeElapsed = block.timestamp - lastUpdateTime[user];
        uint256 interest = (currentBalance * apy * timeElapsed) / (365 days * 10000);
        
        return currentBalance + interest;
    }

    function getCurrentAPY(address) external view override returns (uint256) {
        return apy;
    }

    function getProtocolName() external view override returns (string memory) {
        return protocolName;
    }

    function _updateBalance(address user, address token) internal {
        uint256 newBalance = this.getBalance(user, token);
        balances[user][token] = newBalance;
        lastUpdateTime[user] = block.timestamp;
    }

    // Admin function to update APY for testing
    function updateAPY(uint256 newAPY) external {
        apy = newAPY;
    }
}