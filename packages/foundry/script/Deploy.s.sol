//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelpers.s.sol";
import "../contracts/BasedKeno.sol";

/**
 * @notice Deployment script for BasedKeno (which deploys HousePool + VaultManager)
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
    
    // Dealer address for commit/reveal
    address constant DEALER = 0xDBF21195C3980abcD9AB19646b90AE8dc17b33Ec;

    function run() external ScaffoldEthDeployerRunner {
        address deployer = msg.sender;
        
        // Deploy BasedKeno (which deploys VaultManager and HousePool internally)
        BasedKeno basedKeno = new BasedKeno(USDC, FLEET_COMMANDER, DEALER);
        
        // Export all contracts for Scaffold-ETH
        deployments.push(Deployment("BasedKeno", address(basedKeno)));
        deployments.push(Deployment("HousePool", address(basedKeno.housePool())));
        deployments.push(Deployment("VaultManager", address(basedKeno.vaultManager())));
        
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("BasedKeno:", address(basedKeno));
        console.log("HousePool:", address(basedKeno.housePool()));
        console.log("VaultManager:", address(basedKeno.vaultManager()));
        console.log("Dealer:", DEALER);
        console.log("USDC:", USDC);
        console.log("FleetCommander:", FLEET_COMMANDER);
        console.log("");
        console.log("Next steps:");
        console.log("1. Approve USDC and call housePool.deposit(amount) to seed liquidity");
        console.log("2. Players can placeBet() to start a round");
        console.log("3. Dealer commits after betting period, then reveals to draw winning numbers");
    }
}
