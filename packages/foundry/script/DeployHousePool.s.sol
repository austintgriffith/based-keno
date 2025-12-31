// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelpers.s.sol";
import "../contracts/DiceGame.sol";

/// @notice Standalone deployment script for DiceGame + HousePool + VaultManager
/// @dev Use Deploy.s.sol for the main deployment (auto-detects Base fork vs local)
contract DeployHousePool is ScaffoldETHDeploy {
    function run(address usdc, address fleetCommander) external ScaffoldEthDeployerRunner {
        // Deploy DiceGame (which deploys VaultManager and HousePool internally)
        DiceGame diceGame = new DiceGame(usdc, fleetCommander);
        
        console.log("DiceGame deployed at:", address(diceGame));
        console.log("HousePool deployed at:", address(diceGame.housePool()));
        console.log("VaultManager deployed at:", address(diceGame.vaultManager()));
        console.log("USDC:", usdc);
        console.log("FleetCommander:", fleetCommander);
    }
}
