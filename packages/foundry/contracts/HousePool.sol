// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title IUniswapV2Router02 - Minimal interface for swaps
interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    function getAmountsOut(
        uint256 amountIn, 
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

/// @title HousePool - Simplified gambling pool where LP tokens = house ownership
/// @notice Deposit USDC to become the house. Share price grows as house profits.
/// @dev Auto buyback & burn on reveals keeps Uniswap price synced
contract HousePool is ERC20, Ownable {
    /* ========== CUSTOM ERRORS ========== */
    error InsufficientPool();
    error NoCommitment();
    error TooEarly();
    error TooLate();
    error InvalidReveal();
    error WithdrawalNotReady();
    error WithdrawalExpired();
    error NoPendingWithdrawal();
    error InsufficientShares();
    error AlreadySeeded();
    error ZeroAmount();
    error TransferFailed();

    /* ========== STATE VARIABLES ========== */
    
    IERC20 public immutable usdc;
    IUniswapV2Router02 public uniswapRouter;
    
    // Withdrawal tracking
    struct WithdrawalRequest {
        uint256 shares;
        uint256 unlockTime;
        uint256 expiryTime;
    }
    mapping(address => WithdrawalRequest) public withdrawals;
    uint256 public totalPendingShares;
    
    // Commit-reveal gambling
    struct Commitment {
        bytes32 hash;
        uint256 blockNumber;
    }
    mapping(address => Commitment) public commits;
    
    // Bootstrap tracking
    bool public liquiditySeeded;

    /* ========== CONSTANTS ========== */
    
    // Gambling parameters
    uint256 public constant ROLL_COST = 1e6;        // 1 USDC (6 decimals)
    uint256 public constant ROLL_PAYOUT = 10e6;     // 10 USDC
    uint256 public constant WIN_MODULO = 11;        // 1/11 ≈ 9% win rate, 9% house edge
    
    // Pool thresholds
    uint256 public constant MIN_RESERVE = 100e6;    // 100 USDC minimum for payouts
    uint256 public constant BUYBACK_THRESHOLD = 150e6; // 150 USDC triggers buyback
    
    // Withdrawal timing
    uint256 public constant WITHDRAWAL_DELAY = 5 minutes;
    uint256 public constant WITHDRAWAL_WINDOW = 24 hours;
    
    // First deposit minimum (prevents share manipulation attack)
    uint256 public constant MIN_FIRST_DEPOSIT = 1e6; // 1 USDC

    /* ========== EVENTS ========== */
    
    event Deposit(address indexed lp, uint256 usdcIn, uint256 sharesOut);
    event WithdrawalRequested(address indexed lp, uint256 shares, uint256 unlockTime, uint256 expiryTime);
    event WithdrawalCancelled(address indexed lp, uint256 shares);
    event WithdrawalExpiredCleanup(address indexed lp, uint256 shares);
    event Withdraw(address indexed lp, uint256 sharesIn, uint256 usdcOut);
    event RollCommitted(address indexed player, bytes32 commitment);
    event RollRevealed(address indexed player, bool won, uint256 payout);
    event BuybackAndBurn(uint256 usdcSpent, uint256 houseBurned);
    event LiquiditySeeded(address indexed to, uint256 amount);
    event UniswapRouterSet(address indexed router);

    /* ========== CONSTRUCTOR ========== */
    
    constructor(
        address _usdc,
        address _uniswapRouter
    ) ERC20("HouseShare", "HOUSE") Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        if (_uniswapRouter != address(0)) {
            uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        }
    }

    /* ========== LP FUNCTIONS ========== */
    
    /// @notice Deposit USDC, receive HOUSE shares proportional to pool
    /// @param usdcAmount Amount of USDC to deposit
    /// @return shares Amount of HOUSE tokens minted
    function deposit(uint256 usdcAmount) external returns (uint256 shares) {
        if (usdcAmount == 0) revert ZeroAmount();
        
        uint256 supply = totalSupply();
        uint256 pool = usdc.balanceOf(address(this));
        
        if (supply == 0) {
            // First deposit: enforce minimum and 1:1 ratio (scaled to 18 decimals)
            if (usdcAmount < MIN_FIRST_DEPOSIT) revert InsufficientPool();
            shares = usdcAmount * 1e12; // Scale 6 decimals → 18 decimals
        } else {
            // Proportional shares based on current pool
            shares = (usdcAmount * supply) / pool;
        }
        
        bool success = usdc.transferFrom(msg.sender, address(this), usdcAmount);
        if (!success) revert TransferFailed();
        
        _mint(msg.sender, shares);
        
        emit Deposit(msg.sender, usdcAmount, shares);
    }
    
    /// @notice Request withdrawal - starts cooldown period
    /// @param shares Amount of HOUSE tokens to withdraw
    function requestWithdrawal(uint256 shares) external {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < shares) revert InsufficientShares();
        
        // If there's an existing request, remove it from pending first
        if (withdrawals[msg.sender].shares > 0) {
            totalPendingShares -= withdrawals[msg.sender].shares;
        }
        
        uint256 unlockTime = block.timestamp + WITHDRAWAL_DELAY;
        uint256 expiryTime = unlockTime + WITHDRAWAL_WINDOW;
        
        withdrawals[msg.sender] = WithdrawalRequest({
            shares: shares,
            unlockTime: unlockTime,
            expiryTime: expiryTime
        });
        
        totalPendingShares += shares;
        
        emit WithdrawalRequested(msg.sender, shares, unlockTime, expiryTime);
    }
    
    /// @notice Execute withdrawal after cooldown, within window
    /// @return usdcOut Amount of USDC received
    function withdraw() external returns (uint256 usdcOut) {
        WithdrawalRequest memory req = withdrawals[msg.sender];
        
        if (req.shares == 0) revert NoPendingWithdrawal();
        if (block.timestamp < req.unlockTime) revert WithdrawalNotReady();
        if (block.timestamp > req.expiryTime) revert WithdrawalExpired();
        
        uint256 pool = usdc.balanceOf(address(this));
        uint256 supply = totalSupply();
        
        usdcOut = (req.shares * pool) / supply;
        
        // Ensure we keep minimum reserve for payouts
        if (pool - usdcOut < MIN_RESERVE) revert InsufficientPool();
        
        totalPendingShares -= req.shares;
        delete withdrawals[msg.sender];
        
        _burn(msg.sender, req.shares);
        
        bool success = usdc.transfer(msg.sender, usdcOut);
        if (!success) revert TransferFailed();
        
        emit Withdraw(msg.sender, req.shares, usdcOut);
    }
    
    /// @notice Cancel pending withdrawal request
    function cancelWithdrawal() external {
        WithdrawalRequest memory req = withdrawals[msg.sender];
        if (req.shares == 0) revert NoPendingWithdrawal();
        
        totalPendingShares -= req.shares;
        delete withdrawals[msg.sender];
        
        emit WithdrawalCancelled(msg.sender, req.shares);
    }
    
    /// @notice Clean up expired withdrawal requests (anyone can call)
    /// @param lp Address of the LP with expired request
    function cleanupExpiredWithdrawal(address lp) external {
        WithdrawalRequest memory req = withdrawals[lp];
        
        if (req.shares == 0) revert NoPendingWithdrawal();
        if (block.timestamp <= req.expiryTime) revert WithdrawalNotReady();
        
        totalPendingShares -= req.shares;
        delete withdrawals[lp];
        
        emit WithdrawalExpiredCleanup(lp, req.shares);
    }

    /* ========== GAMBLING FUNCTIONS ========== */
    
    /// @notice Step 1: Commit to a roll. Hash = keccak256(abi.encodePacked(secret))
    /// @param commitHash Hash of the player's secret
    function commitRoll(bytes32 commitHash) external {
        // Check effective pool can cover payout
        if (effectivePool() < MIN_RESERVE + ROLL_PAYOUT) revert InsufficientPool();
        
        // Take payment
        bool success = usdc.transferFrom(msg.sender, address(this), ROLL_COST);
        if (!success) revert TransferFailed();
        
        commits[msg.sender] = Commitment({
            hash: commitHash,
            blockNumber: block.number
        });
        
        emit RollCommitted(msg.sender, commitHash);
    }
    
    /// @notice Step 2: Reveal secret after 2+ blocks, within 256 blocks
    /// @param secret The secret that was hashed in commitRoll
    /// @return won Whether the player won
    function revealRoll(bytes32 secret) external returns (bool won) {
        Commitment memory c = commits[msg.sender];
        
        if (c.blockNumber == 0) revert NoCommitment();
        if (block.number <= c.blockNumber + 1) revert TooEarly();
        if (block.number > c.blockNumber + 256) revert TooLate();
        if (keccak256(abi.encodePacked(secret)) != c.hash) revert InvalidReveal();
        
        delete commits[msg.sender];
        
        // Fair randomness: player's secret + unknowable future blockhash
        bytes32 entropy = keccak256(abi.encodePacked(
            secret,
            blockhash(c.blockNumber + 1)
        ));
        
        won = (uint256(entropy) % WIN_MODULO) == 0;
        
        if (won) {
            bool success = usdc.transfer(msg.sender, ROLL_PAYOUT);
            if (!success) revert TransferFailed();
        }
        
        emit RollRevealed(msg.sender, won, won ? ROLL_PAYOUT : 0);
        
        // Auto buyback if threshold exceeded
        _tryBuybackAndBurn();
    }

    /* ========== BUYBACK & BURN ========== */
    
    /// @notice Internal: attempt buyback & burn if conditions met
    function _tryBuybackAndBurn() internal {
        // Skip if no router configured
        if (address(uniswapRouter) == address(0)) return;
        
        uint256 pool = effectivePool();
        if (pool <= BUYBACK_THRESHOLD) return;
        
        uint256 excess = pool - MIN_RESERVE;
        
        // Approve router
        usdc.approve(address(uniswapRouter), excess);
        
        // Build swap path
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(this);
        
        // Try swap - if it fails (no pool, bad liquidity), just skip
        try uniswapRouter.swapExactTokensForTokens(
            excess,
            0, // Accept any amount (could add slippage protection)
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory amounts) {
            uint256 houseBought = amounts[1];
            _burn(address(this), houseBought);
            emit BuybackAndBurn(excess, houseBought);
        } catch {
            // Swap failed - reset approval and continue
            usdc.approve(address(uniswapRouter), 0);
        }
    }
    
    /// @notice Manual buyback trigger (anyone can call)
    function buybackAndBurn() external {
        _tryBuybackAndBurn();
    }

    /* ========== OWNER FUNCTIONS ========== */
    
    /// @notice One-time mint for bootstrapping Uniswap liquidity
    /// @param to Address to receive minted tokens
    /// @param amount Amount of HOUSE to mint
    function mintForLiquidity(address to, uint256 amount) external onlyOwner {
        if (liquiditySeeded) revert AlreadySeeded();
        liquiditySeeded = true;
        
        _mint(to, amount);
        
        emit LiquiditySeeded(to, amount);
    }
    
    /// @notice Set or update Uniswap router address
    /// @param _router New router address
    function setUniswapRouter(address _router) external onlyOwner {
        uniswapRouter = IUniswapV2Router02(_router);
        emit UniswapRouterSet(_router);
    }

    /* ========== VIEW FUNCTIONS ========== */
    
    /// @notice Total USDC in contract
    function totalPool() public view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
    
    /// @notice Effective pool = total minus pending withdrawal value
    function effectivePool() public view returns (uint256) {
        uint256 pool = usdc.balanceOf(address(this));
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
        return (usdc.balanceOf(address(this)) * 1e18) / supply;
    }
    
    /// @notice USDC value of an LP's shares
    function usdcValue(address lp) external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        return (balanceOf(lp) * usdc.balanceOf(address(this))) / supply;
    }
    
    /// @notice Whether the pool can accept new rolls
    function canRoll() external view returns (bool) {
        return effectivePool() >= MIN_RESERVE + ROLL_PAYOUT;
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
    
    /// @notice Get commitment details for a player
    function getCommitment(address player) external view returns (
        bytes32 hash,
        uint256 blockNumber,
        bool canReveal,
        bool isExpired
    ) {
        Commitment memory c = commits[player];
        hash = c.hash;
        blockNumber = c.blockNumber;
        canReveal = c.blockNumber > 0 && 
                    block.number > c.blockNumber + 1 && 
                    block.number <= c.blockNumber + 256;
        isExpired = c.blockNumber > 0 && block.number > c.blockNumber + 256;
    }
}

