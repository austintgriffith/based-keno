// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./VaultManager.sol";

/// @title HousePool - Liquidity pool for gambling games with DeFi yield generation
/// @notice Deposit USDC to become the house. Share price grows as house profits + DeFi yield.
/// @dev Game contract is set immutably at deployment. All USDC is invested in Summer.fi vault.
contract HousePool is ERC20 {
    /* ========== CUSTOM ERRORS ========== */
    error InsufficientPool();
    error WithdrawalNotReady();
    error WithdrawalExpired();
    error NoPendingWithdrawal();
    error InsufficientShares();
    error ZeroAmount();
    error ZeroShares();
    error TransferFailed();
    error Unauthorized();
    error ZeroAddress();
    error WithdrawalAlreadyPending();
    error SlippageExceeded();

    /* ========== STATE VARIABLES ========== */
    
    IERC20 public immutable usdc;
    address public immutable game;
    VaultManager public immutable vaultManager;
    
    // Withdrawal tracking
    struct WithdrawalRequest {
        uint256 shares;
        uint256 unlockTime;
        uint256 expiryTime;
    }
    mapping(address => WithdrawalRequest) public withdrawals;
    uint256 public totalPendingShares;

    /* ========== CONSTANTS ========== */
    
    // Withdrawal timing
    uint256 public constant WITHDRAWAL_DELAY = 10 seconds;
    uint256 public constant WITHDRAWAL_WINDOW = 1 minutes;
    
    // First deposit minimum (prevents share manipulation attack)
    uint256 public constant MIN_FIRST_DEPOSIT = 1e6; // 1 USDC

    /* ========== EVENTS ========== */
    
    event Deposit(address indexed lp, uint256 usdcIn, uint256 sharesOut);
    event WithdrawalRequested(address indexed lp, uint256 shares, uint256 unlockTime, uint256 expiryTime);
    event WithdrawalCancelled(address indexed lp, uint256 shares);
    event WithdrawalExpiredCleanup(address indexed lp, uint256 shares);
    event Withdraw(address indexed lp, uint256 sharesIn, uint256 usdcOut);
    event PaymentReceived(address indexed player, uint256 amount);
    event PayoutSent(address indexed player, uint256 amount);
    event DepositedToVault(uint256 amount);
    event WithdrawnFromVault(uint256 amount);

    /* ========== MODIFIERS ========== */
    
    modifier onlyGame() {
        if (msg.sender != game) revert Unauthorized();
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    
    constructor(
        address _usdc,
        address _game,
        address _vaultManager
    ) ERC20("HouseShare", "HOUSE") {
        if (_usdc == address(0) || _game == address(0) || _vaultManager == address(0)) revert ZeroAddress();
        usdc = IERC20(_usdc);
        game = _game;
        vaultManager = VaultManager(payable(_vaultManager));
    }

    /* ========== GAME FUNCTIONS ========== */
    
    /// @notice Receive payment from a player (called by game contract)
    /// @param player Address of the player
    /// @param amount Amount of USDC to receive
    function receivePayment(address player, uint256 amount) external onlyGame {
        if (amount == 0) revert ZeroAmount();
        
        bool success = usdc.transferFrom(player, address(this), amount);
        if (!success) revert TransferFailed();
        
        emit PaymentReceived(player, amount);
        
        // Deposit all USDC to vault for yield
        _depositAllToVault();
    }
    
    /// @notice Pay out winnings to a player (called by game contract)
    /// @param player Address of the player
    /// @param amount Amount of USDC to pay out
    function payout(address player, uint256 amount) external onlyGame {
        if (amount == 0) revert ZeroAmount();
        
        // Withdraw from vault to cover payout
        _withdrawFromVault(amount);
        
        if (usdc.balanceOf(address(this)) < amount) revert InsufficientPool();
        
        bool success = usdc.transfer(player, amount);
        if (!success) revert TransferFailed();
        
        emit PayoutSent(player, amount);
    }

    /* ========== LP FUNCTIONS ========== */
    
    /// @notice Deposit USDC, receive HOUSE shares proportional to pool
    /// @param usdcAmount Amount of USDC to deposit
    /// @param minSharesOut Minimum shares to receive (slippage protection, 0 to skip)
    /// @return shares Amount of HOUSE tokens minted
    function deposit(uint256 usdcAmount, uint256 minSharesOut) public returns (uint256 shares) {
        if (usdcAmount == 0) revert ZeroAmount();
        
        uint256 supply = totalSupply();
        uint256 pool = _getTotalValue(); // Use total value including vault
        
        if (supply == 0) {
            // First deposit: enforce minimum and 1:1 ratio (scaled to 18 decimals)
            if (usdcAmount < MIN_FIRST_DEPOSIT) revert InsufficientPool();
            shares = usdcAmount * 1e12; // Scale 6 decimals → 18 decimals
        } else {
            // Proportional shares based on current pool (including vault)
            shares = (usdcAmount * supply) / pool;
        }
        
        // Security: Ensure shares > 0 (prevents rounding to zero attack)
        if (shares == 0) revert ZeroShares();
        
        // Slippage protection
        if (shares < minSharesOut) revert SlippageExceeded();
        
        bool success = usdc.transferFrom(msg.sender, address(this), usdcAmount);
        if (!success) revert TransferFailed();
        
        _mint(msg.sender, shares);
        
        emit Deposit(msg.sender, usdcAmount, shares);
        
        // Deposit all USDC to vault for yield
        _depositAllToVault();
    }
    
    /// @notice Deposit USDC without slippage protection (convenience overload)
    /// @param usdcAmount Amount of USDC to deposit
    /// @return shares Amount of HOUSE tokens minted
    function deposit(uint256 usdcAmount) external returns (uint256 shares) {
        return deposit(usdcAmount, 0);
    }
    
    /// @notice Request withdrawal - starts cooldown period
    /// @dev Shares are transferred to contract to prevent transfer-while-pending attack
    /// @param shares Amount of HOUSE tokens to withdraw
    function requestWithdrawal(uint256 shares) external {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < shares) revert InsufficientShares();
        if (withdrawals[msg.sender].shares > 0) revert WithdrawalAlreadyPending();
        
        uint256 unlockTime = block.timestamp + WITHDRAWAL_DELAY;
        uint256 expiryTime = unlockTime + WITHDRAWAL_WINDOW;
        
        withdrawals[msg.sender] = WithdrawalRequest({
            shares: shares,
            unlockTime: unlockTime,
            expiryTime: expiryTime
        });
        
        totalPendingShares += shares;
        
        // Security fix: Lock shares by transferring to contract
        // This prevents the share-transfer-during-pending attack
        _transfer(msg.sender, address(this), shares);
        
        emit WithdrawalRequested(msg.sender, shares, unlockTime, expiryTime);
    }
    
    /// @notice Execute withdrawal after cooldown, within window
    /// @param minUsdcOut Minimum USDC to receive (slippage protection, 0 to skip)
    /// @return usdcOut Amount of USDC received
    function withdraw(uint256 minUsdcOut) public returns (uint256 usdcOut) {
        WithdrawalRequest memory req = withdrawals[msg.sender];
        
        if (req.shares == 0) revert NoPendingWithdrawal();
        if (block.timestamp < req.unlockTime) revert WithdrawalNotReady();
        if (block.timestamp > req.expiryTime) revert WithdrawalExpired();
        
        uint256 pool = _getTotalValue(); // Use total value including vault
        uint256 supply = totalSupply();
        
        usdcOut = (req.shares * pool) / supply;
        
        // Slippage protection
        if (usdcOut < minUsdcOut) revert SlippageExceeded();
        
        // Withdraw from vault to cover withdrawal
        _withdrawFromVault(usdcOut);
        
        totalPendingShares -= req.shares;
        delete withdrawals[msg.sender];
        
        // Shares are held by contract (transferred in requestWithdrawal)
        _burn(address(this), req.shares);
        
        bool success = usdc.transfer(msg.sender, usdcOut);
        if (!success) revert TransferFailed();
        
        emit Withdraw(msg.sender, req.shares, usdcOut);
    }
    
    /// @notice Execute withdrawal without slippage protection (convenience overload)
    /// @return usdcOut Amount of USDC received
    function withdraw() external returns (uint256 usdcOut) {
        return withdraw(0);
    }
    
    /// @notice Cancel pending withdrawal request
    /// @dev Returns locked shares to the user
    function cancelWithdrawal() external {
        WithdrawalRequest memory req = withdrawals[msg.sender];
        if (req.shares == 0) revert NoPendingWithdrawal();
        
        totalPendingShares -= req.shares;
        delete withdrawals[msg.sender];
        
        // Return locked shares to user
        _transfer(address(this), msg.sender, req.shares);
        
        emit WithdrawalCancelled(msg.sender, req.shares);
    }
    
    /// @notice Clean up expired withdrawal requests (anyone can call)
    /// @dev Returns locked shares to the LP
    /// @param lp Address of the LP with expired request
    function cleanupExpiredWithdrawal(address lp) external {
        WithdrawalRequest memory req = withdrawals[lp];
        
        if (req.shares == 0) revert NoPendingWithdrawal();
        if (block.timestamp <= req.expiryTime) revert WithdrawalNotReady();
        
        totalPendingShares -= req.shares;
        delete withdrawals[lp];
        
        // Return locked shares to LP
        _transfer(address(this), lp, req.shares);
        
        emit WithdrawalExpiredCleanup(lp, req.shares);
    }

    /* ========== VAULT INTEGRATION (INTERNAL) ========== */
    
    /// @notice Get total value including both liquid USDC and vault holdings
    /// @return Total USDC value (6 decimals)
    function _getTotalValue() internal view returns (uint256) {
        return usdc.balanceOf(address(this)) + vaultManager.getCurrentValue();
    }
    
    /// @notice Deposit all liquid USDC to the vault
    /// @dev Called after deposits and receiving payments
    function _depositAllToVault() internal {
        uint256 liquidBalance = usdc.balanceOf(address(this));
        
        if (liquidBalance > 0) {
            // Transfer USDC to vault manager
            bool success = usdc.transfer(address(vaultManager), liquidBalance);
            if (success) {
                // Deposit into vault
                vaultManager.depositIntoVault(0); // 0 = deposit all
                emit DepositedToVault(liquidBalance);
            }
        }
    }
    
    /// @notice Withdraw USDC from vault
    /// @dev Called before payouts and withdrawals
    /// @param amount Amount of USDC needed (6 decimals)
    function _withdrawFromVault(uint256 amount) internal {
        uint256 liquidBalance = usdc.balanceOf(address(this));
        
        // Only withdraw if we don't have enough liquid
        if (liquidBalance < amount) {
            uint256 needed = amount - liquidBalance;
            uint256 vaultValue = vaultManager.getCurrentValue();
            
            if (vaultValue > 0) {
                // Withdraw the minimum of needed or available vault funds
                uint256 toWithdraw = needed > vaultValue ? vaultValue : needed;
                vaultManager.withdrawFromVault(toWithdraw);
                emit WithdrawnFromVault(toWithdraw);
            }
        }
    }

    /* ========== VIEW FUNCTIONS ========== */
    
    /// @notice Total USDC value (liquid + vault)
    function totalPool() public view returns (uint256) {
        return _getTotalValue();
    }
    
    /// @notice Liquid USDC in contract (not in vault)
    function liquidPool() public view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
    
    /// @notice USDC value held in vault
    function vaultPool() public view returns (uint256) {
        return vaultManager.getCurrentValue();
    }
    
    /// @notice Effective pool = total minus pending withdrawal value
    function effectivePool() public view returns (uint256) {
        uint256 pool = _getTotalValue();
        uint256 supply = totalSupply();
        
        if (supply == 0 || totalPendingShares == 0) return pool;
        
        uint256 pendingValue = (totalPendingShares * pool) / supply;
        return pool > pendingValue ? pool - pendingValue : 0;
    }
    
    /// @notice Current USDC value per HOUSE share (18 decimal precision)
    function sharePrice() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18; // 1 USDC (in 18 decimals) before first deposit
        
        // Returns price with 18 decimal precision
        // pool is 6 decimals, supply is 18 decimals
        // (pool * 1e18) / supply gives price in 6 decimal USDC terms
        return (_getTotalValue() * 1e18) / supply;
    }
    
    /// @notice USDC value of an LP's shares
    function usdcValue(address lp) external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        return (balanceOf(lp) * _getTotalValue()) / supply;
    }
    
    /// @notice Get withdrawal request details for an LP
    function getWithdrawalRequest(address lp) external view returns (
        uint256 shares,
        uint256 unlockTime,
        uint256 expiryTime,
        bool canWithdraw,
        bool isExpired
    ) {
        WithdrawalRequest memory req = withdrawals[lp];
        shares = req.shares;
        unlockTime = req.unlockTime;
        expiryTime = req.expiryTime;
        canWithdraw = req.shares > 0 && 
                      block.timestamp >= req.unlockTime && 
                      block.timestamp <= req.expiryTime;
        isExpired = req.shares > 0 && block.timestamp > req.expiryTime;
    }
}
