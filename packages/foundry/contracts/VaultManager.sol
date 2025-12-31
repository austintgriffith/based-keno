// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title VaultManager
 * @notice Manages USDC deposits into Summer.fi's FleetCommander (LVUSDC) vault on Base
 * @dev Designed to be called by HousePool contract to automatically invest idle USDC
 */
contract VaultManager {
    using SafeERC20 for IERC20;

    /* ========== CUSTOM ERRORS ========== */
    error InvalidAddress();
    error HousePoolAlreadySet();
    error HousePoolNotSet();
    error Unauthorized();
    error NoUSDCToDeposit();
    error NoFundsInVault();
    error InsufficientBalance();
    error ETHTransferFailed();

    /* ========== STATE VARIABLES ========== */

    /// @notice The ERC4626 vault (Summer.fi FleetCommander LVUSDC)
    IERC4626 public immutable fleetCommander;
    
    /// @notice The USDC token
    IERC20 public immutable usdc;
    
    /// @notice The HousePool contract that can call protected functions
    address public housePool;
    
    /// @notice Whether the HousePool address has been set
    bool public housePoolSet;

    /* ========== EVENTS ========== */

    event HousePoolSet(address indexed housePool);
    event DepositedIntoVault(uint256 usdcAmount, uint256 sharesReceived);
    event WithdrawnFromVault(uint256 usdcAmount, uint256 sharesBurned);
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed to);

    /* ========== MODIFIERS ========== */

    modifier onlyHousePool() {
        if (!housePoolSet) revert HousePoolNotSet();
        if (msg.sender != housePool) revert Unauthorized();
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor
     * @param _fleetCommander Address of Summer.fi FleetCommander vault (LVUSDC)
     * @param _usdc Address of USDC token
     */
    constructor(address _fleetCommander, address _usdc) {
        if (_fleetCommander == address(0)) revert InvalidAddress();
        if (_usdc == address(0)) revert InvalidAddress();
        
        fleetCommander = IERC4626(_fleetCommander);
        usdc = IERC20(_usdc);
        housePoolSet = false;
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @notice Set the HousePool address (one-time only)
     * @param _housePool Address of HousePool contract
     */
    function setHousePool(address _housePool) external {
        if (housePoolSet) revert HousePoolAlreadySet();
        if (_housePool == address(0)) revert InvalidAddress();
        
        housePool = _housePool;
        housePoolSet = true;
        
        emit HousePoolSet(_housePool);
    }

    /* ========== VAULT FUNCTIONS ========== */

    /**
     * @notice Deposits USDC into the FleetCommander vault
     * @dev If amount is 0, deposits all USDC balance held by this contract
     * @param amount The amount of USDC to deposit (0 for all)
     * @return shares The amount of vault shares received
     */
    function depositIntoVault(uint256 amount) external onlyHousePool returns (uint256 shares) {
        uint256 usdcBalance = usdc.balanceOf(address(this));
        if (usdcBalance == 0) revert NoUSDCToDeposit();

        // If amount is 0 or exceeds balance, deposit everything
        uint256 depositAmount = (amount == 0 || amount > usdcBalance) 
            ? usdcBalance 
            : amount;

        // Approve FleetCommander to spend USDC
        usdc.forceApprove(address(fleetCommander), depositAmount);

        // Deposit USDC and receive vault shares
        shares = fleetCommander.deposit(depositAmount, address(this));

        emit DepositedIntoVault(depositAmount, shares);
    }

    /**
     * @notice Withdraws specified amount of USDC from the vault to HousePool contract
     * @dev If amount is 0, withdraws maximum available
     * @param amount The amount of USDC to withdraw (0 for max)
     * @return shares The amount of vault shares burned
     */
    function withdrawFromVault(uint256 amount) external onlyHousePool returns (uint256 shares) {
        uint256 maxWithdrawable = fleetCommander.maxWithdraw(address(this));
        if (maxWithdrawable == 0) revert NoFundsInVault();

        // If amount is 0 or exceeds max, withdraw everything
        uint256 withdrawAmount = (amount == 0 || amount > maxWithdrawable) 
            ? maxWithdrawable 
            : amount;

        // Withdraw USDC from vault directly to HousePool
        shares = fleetCommander.withdraw(withdrawAmount, housePool, address(this));

        emit WithdrawnFromVault(withdrawAmount, shares);
    }

    /**
     * @notice Emergency function to withdraw any tokens from this contract
     * @dev Only HousePool can call. Use to rescue tokens if needed.
     * @param token Address of token to withdraw (address(0) for ETH)
     * @param amount Amount to withdraw (0 for all)
     * @param to Address to send tokens to
     */
    function emergencyWithdraw(address token, uint256 amount, address to) external onlyHousePool {
        if (to == address(0)) revert InvalidAddress();
        
        if (token == address(0)) {
            // Withdraw ETH
            uint256 balance = address(this).balance;
            uint256 withdrawAmount = amount == 0 ? balance : amount;
            if (withdrawAmount > balance) revert InsufficientBalance();
            
            (bool success, ) = payable(to).call{value: withdrawAmount}("");
            if (!success) revert ETHTransferFailed();
            
            emit EmergencyWithdraw(address(0), withdrawAmount, to);
        } else {
            // Withdraw ERC20 token
            IERC20 tokenContract = IERC20(token);
            uint256 balance = tokenContract.balanceOf(address(this));
            uint256 withdrawAmount = amount == 0 ? balance : amount;
            if (withdrawAmount > balance) revert InsufficientBalance();
            
            tokenContract.safeTransfer(to, withdrawAmount);
            
            emit EmergencyWithdraw(token, withdrawAmount, to);
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the current USDC value of the vault position
     * @dev Uses maxWithdraw which accounts for vault share price and available liquidity
     * @return The current USDC value (with 6 decimals)
     */
    function getCurrentValue() external view returns (uint256) {
        return fleetCommander.maxWithdraw(address(this));
    }

    /**
     * @notice Returns the amount of vault shares this contract holds
     * @return The vault share balance
     */
    function getVaultShares() external view returns (uint256) {
        return fleetCommander.balanceOf(address(this));
    }

    /**
     * @notice Returns the USDC balance held by this contract (not in vault)
     * @return The USDC balance
     */
    function getUSDCBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /**
     * @notice Returns total USDC value (vault + contract balance)
     * @return The total USDC value
     */
    function getTotalValue() external view returns (uint256) {
        return fleetCommander.maxWithdraw(address(this)) + usdc.balanceOf(address(this));
    }

    /**
     * @notice Allow contract to receive ETH
     */
    receive() external payable {}
}

