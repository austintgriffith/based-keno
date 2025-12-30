// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelpers.s.sol";
import "../contracts/CreditsDex.sol";

/**
 * @notice Deploy script for CreditsDex contract
 * @dev Deploys the DEX with Credits token and USDC on Base
 * Example:
 * yarn deploy --file DeployCreditsDex.s.sol  # local anvil chain (forked from Base)
 * yarn deploy --file DeployCreditsDex.s.sol --network base # live network
 */
contract DeployCreditsDex is ScaffoldETHDeploy {
    // USDC address on Base
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Credits contract address - will be set after Credits is deployed
    address public creditsAddress;

    function setCreditsAddress(address _credits) external {
        creditsAddress = _credits;
    }

    /**
     * @dev Deployer setup based on `ETH_KEYSTORE_ACCOUNT` in `.env`:
     *      - "scaffold-eth-default": Uses Anvil's account #9 (0xa0Ee7A142d267C1f36714E4a8F75612F20a79720)
     *      - "scaffold-eth-custom": requires password used while creating keystore
     */
    function run() external ScaffoldEthDeployerRunner {
        // Credits address must be set before deployment
        require(creditsAddress != address(0), "Credits address not set");
        
        new CreditsDex(creditsAddress, USDC_BASE);
    }

    /// @notice Alternative run function that accepts credits address as parameter
    function run(address _creditsAddress) external ScaffoldEthDeployerRunner {
        new CreditsDex(_creditsAddress, USDC_BASE);
    }
}

