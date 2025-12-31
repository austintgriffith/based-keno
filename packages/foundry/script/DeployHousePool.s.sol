// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelpers.s.sol";
import "../contracts/HousePool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC - Simple mock for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        // Mint 1M USDC to deployer for testing
        _mint(msg.sender, 1_000_000 * 10**6);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    // Allow anyone to mint for testing
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DeployHousePool is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        // For local testing, deploy mock USDC
        // For mainnet/testnet, use actual USDC address
        MockUSDC usdc = new MockUSDC();
        
        // Deploy HousePool with no Uniswap router initially (for local testing)
        // On mainnet, pass actual router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D (Uniswap V2)
        HousePool housePool = new HousePool(
            address(usdc),
            address(0) // No router for local testing
        );
        
        // For local testing: seed initial liquidity
        // 1. Approve HousePool to spend USDC
        usdc.approve(address(housePool), type(uint256).max);
        
        // 2. Deposit initial USDC to bootstrap the pool (200 USDC)
        uint256 initialDeposit = 200 * 10**6; // 200 USDC
        housePool.deposit(initialDeposit);
        
        console.log("MockUSDC deployed at:", address(usdc));
        console.log("HousePool deployed at:", address(housePool));
        console.log("Initial deposit:", initialDeposit / 10**6, "USDC");
        console.log("HOUSE tokens minted:", housePool.balanceOf(msg.sender) / 10**18);
    }
}

