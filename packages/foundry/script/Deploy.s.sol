//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelpers.s.sol";
import "../contracts/Credits.sol";
import "../contracts/CreditsDex.sol";

/**
 * @notice Main deployment script for all contracts
 * @dev Run this when you want to deploy multiple contracts at once
 *
 * Example: yarn deploy # runs this script(without`--file` flag)
 */
contract DeployScript is ScaffoldETHDeploy {
    // USDC address on Base
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() external ScaffoldEthDeployerRunner {
        // Deploy Credits token with specific owner for minting
        Credits credits = new Credits(0x05937Df8ca0636505d92Fd769d303A3D461587ed);
        
        // Deploy CreditsDex with Credits and USDC
        new CreditsDex(address(credits), USDC_BASE);
    }
}
