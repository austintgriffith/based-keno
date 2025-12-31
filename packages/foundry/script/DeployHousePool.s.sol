// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelpers.s.sol";
import "../contracts/BasedKeno.sol";

/// @notice Standalone deployment script for BasedKeno + HousePool + VaultManager
/// @dev Use Deploy.s.sol for the main deployment (auto-detects Base fork vs local)
contract DeployHousePool is ScaffoldETHDeploy {
    function run(address usdc, address fleetCommander, address dealer) external ScaffoldEthDeployerRunner {
        // Deploy BasedKeno (which deploys VaultManager and HousePool internally)
        BasedKeno basedKeno = new BasedKeno(usdc, fleetCommander, dealer);
        
        console.log("BasedKeno deployed at:", address(basedKeno));
        console.log("HousePool deployed at:", address(basedKeno.housePool()));
        console.log("VaultManager deployed at:", address(basedKeno.vaultManager()));
        console.log("Dealer:", dealer);
        console.log("USDC:", usdc);
        console.log("FleetCommander:", fleetCommander);
    }
}
