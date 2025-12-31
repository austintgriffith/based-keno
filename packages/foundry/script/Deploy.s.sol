//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelpers.s.sol";
import "./DeployHousePool.s.sol";

/**
 * @notice Main deployment script for HousePool
 * @dev Run this when you want to deploy: yarn deploy
 * 
 * For local testing, this deploys MockUSDC + HousePool
 * For mainnet/testnet, update USDC_ADDRESS and UNISWAP_ROUTER
 */
contract DeployScript is ScaffoldETHDeploy {
    // Mainnet addresses (update these for production)
    // address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    // address constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    function run() external ScaffoldEthDeployerRunner {
        // For local testing: deploy mock USDC
        MockUSDC usdc = new MockUSDC();
        
        // Deploy HousePool (no Uniswap router for local testing)
        HousePool housePool = new HousePool(
            address(usdc),
            address(0) // Set to UNISWAP_V2_ROUTER for production
        );
        
        // Seed initial liquidity for testing
        usdc.approve(address(housePool), type(uint256).max);
        uint256 initialDeposit = 200 * 10**6; // 200 USDC
        housePool.deposit(initialDeposit);
        
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("MockUSDC:", address(usdc));
        console.log("HousePool:", address(housePool));
        console.log("Initial USDC deposited:", initialDeposit / 10**6);
        console.log("HOUSE tokens minted:", housePool.balanceOf(msg.sender) / 10**18);
    }
}
