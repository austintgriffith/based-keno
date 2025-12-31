//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelpers.s.sol";
import "../contracts/HousePool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Main deployment script for HousePool
 * @dev Run this when you want to deploy: yarn deploy
 * 
 * Works on both:
 * - Local chain (yarn chain) - uses MockUSDC
 * - Base fork (yarn fork --network base) - uses real USDC
 */
contract DeployScript is ScaffoldETHDeploy {
    // Base Mainnet addresses
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    // Uniswap V2 Router on Base (Aerodrome uses similar interface)
    // Set to address(0) to disable auto-buyback initially
    address constant UNISWAP_ROUTER = address(0);

    function run() external ScaffoldEthDeployerRunner {
        address usdcAddress;
        
        // Check if we're on a fork with real USDC
        if (_hasCode(USDC_BASE)) {
            // We're on Base fork - use real USDC
            usdcAddress = USDC_BASE;
            console.log("Detected Base fork - using real USDC");
        } else {
            // Local chain - deploy mock USDC
            MockUSDC mockUsdc = new MockUSDC();
            usdcAddress = address(mockUsdc);
            console.log("Local chain - deployed MockUSDC");
            
            // Mint some USDC to deployer for testing
            mockUsdc.mint(msg.sender, 10_000 * 10**6);
        }
        
        // Deploy HousePool
        HousePool housePool = new HousePool(
            usdcAddress,
            UNISWAP_ROUTER
        );
        
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("USDC:", usdcAddress);
        console.log("HousePool:", address(housePool));
        console.log("");
        console.log("To seed liquidity, approve USDC and call housePool.deposit(amount)");
    }
    
    /// @notice Check if an address has code (is a contract)
    function _hasCode(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}

/// @title MockUSDC - Simple mock for local testing
contract MockUSDC is IERC20 {
    string public constant name = "USD Coin";
    string public constant symbol = "USDC";
    uint8 public constant decimals = 6;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    constructor() {
        // Mint 1M USDC to deployer
        _mint(msg.sender, 1_000_000 * 10**6);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        _allowances[from][msg.sender] = currentAllowance - amount;
        _transfer(from, to, amount);
        return true;
    }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(_balances[from] >= amount, "ERC20: insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }
    
    function _mint(address to, uint256 amount) internal {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}
