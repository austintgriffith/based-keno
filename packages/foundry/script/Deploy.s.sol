//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelpers.s.sol";
import "../contracts/DiceGame.sol";

/**
 * @notice Deployment script for DiceGame (which deploys HousePool + VaultManager)
 * @dev Uses real USDC and Summer.fi FleetCommander on Base
 * 
 * Usage:
 *   yarn fork --network base
 *   yarn deploy
 */
contract DeployScript is ScaffoldETHDeploy {
    // Base Mainnet addresses
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant FLEET_COMMANDER = 0x98C49e13bf99D7CAd8069faa2A370933EC9EcF17; // Summer.fi LVUSDC vault (FleetCommander)

    function run() external ScaffoldEthDeployerRunner {
        // Deploy DiceGame (which deploys VaultManager and HousePool internally)
        DiceGame diceGame = new DiceGame(USDC, FLEET_COMMANDER);
        
        // Export all contracts for Scaffold-ETH
        deployments.push(Deployment("DiceGame", address(diceGame)));
        deployments.push(Deployment("HousePool", address(diceGame.housePool())));
        deployments.push(Deployment("VaultManager", address(diceGame.vaultManager())));
        
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("DiceGame:", address(diceGame));
        console.log("HousePool:", address(diceGame.housePool()));
        console.log("VaultManager:", address(diceGame.vaultManager()));
        console.log("USDC:", USDC);
        console.log("FleetCommander:", FLEET_COMMANDER);
        console.log("");
        console.log("Next: Approve USDC and call housePool.deposit(amount) to seed liquidity");
        console.log("Idle USDC will automatically be invested in Summer.fi for yield!");
    }
}
