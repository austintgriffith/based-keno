//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelpers.s.sol";
import "../contracts/HousePool.sol";
import "../contracts/MockUSDC.sol";

/**
 * @notice Main deployment script for HousePool
 * @dev Run this when you want to deploy: yarn deploy
 * 
 * Works on both:
 * - Local chain (yarn chain) - deploys MockUSDC
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
