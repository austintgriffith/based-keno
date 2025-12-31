// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/HousePool.sol";
import "../contracts/DiceGame.sol";
import "../contracts/VaultManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @dev Simple mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    
    function decimals() public pure override returns (uint8) { return 6; }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Mock ERC4626 vault to simulate Summer.fi FleetCommander
contract MockFleetCommander is ERC20 {
    IERC20 public immutable asset;
    uint256 public yieldAccrued; // Simulated yield
    
    constructor(address _asset) ERC20("Mock Vault Shares", "mvUSDC") {
        asset = IERC20(_asset);
    }
    
    function decimals() public pure override returns (uint8) { return 6; }
    
    // ERC4626 functions
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        asset.transferFrom(msg.sender, address(this), assets);
        shares = assets; // 1:1 initially
        _mint(receiver, shares);
    }
    
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = previewWithdraw(assets);
        _burn(owner, shares);
        asset.transfer(receiver, assets);
    }
    
    function maxWithdraw(address owner) external view returns (uint256) {
        uint256 shares = balanceOf(owner);
        return convertToAssets(shares);
    }
    
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 totalAssets = asset.balanceOf(address(this));
        uint256 supply = totalSupply();
        if (supply == 0 || totalAssets == 0) return assets;
        return (assets * supply) / totalAssets;
    }
    
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        return (shares * asset.balanceOf(address(this))) / supply;
    }
    
    // Test helper: simulate yield accrual by minting USDC to the vault
    function simulateYield(uint256 amount) external {
        MockUSDC(address(asset)).mint(address(this), amount);
        yieldAccrued += amount;
    }
}

contract HousePoolTest is Test {
    HousePool public housePool;
    DiceGame public diceGame;
    VaultManager public vaultManager;
    MockUSDC public usdc;
    MockFleetCommander public mockVault;
    
    address public lp1 = address(2);
    address public lp2 = address(3);
    address public player1 = address(4);
    address public player2 = address(5);
    
    uint256 constant INITIAL_USDC = 10_000 * 10**6; // 10k USDC each
    
    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();
        
        // Deploy mock FleetCommander vault
        mockVault = new MockFleetCommander(address(usdc));
        
        // Deploy DiceGame (which deploys VaultManager and HousePool internally)
        diceGame = new DiceGame(address(usdc), address(mockVault));
        housePool = diceGame.housePool();
        vaultManager = diceGame.vaultManager();
        
        // Distribute USDC to test accounts
        usdc.mint(lp1, INITIAL_USDC);
        usdc.mint(lp2, INITIAL_USDC);
        usdc.mint(player1, INITIAL_USDC);
        usdc.mint(player2, INITIAL_USDC);
        
        // Approve HousePool for LP accounts (for deposits)
        vm.prank(lp1);
        usdc.approve(address(housePool), type(uint256).max);
        
        vm.prank(lp2);
        usdc.approve(address(housePool), type(uint256).max);
        
        // Approve HousePool for player accounts (for receivePayment)
        vm.prank(player1);
        usdc.approve(address(housePool), type(uint256).max);
        
        vm.prank(player2);
        usdc.approve(address(housePool), type(uint256).max);
    }

    /* ========== DEPLOYMENT TESTS ========== */
    
    function test_Deployment() public view {
        assertEq(address(housePool.game()), address(diceGame));
        assertEq(address(housePool.usdc()), address(usdc));
        assertEq(address(housePool.vaultManager()), address(vaultManager));
        assertEq(address(diceGame.housePool()), address(housePool));
        assertEq(address(diceGame.usdc()), address(usdc));
        assertEq(address(diceGame.vaultManager()), address(vaultManager));
        assertEq(vaultManager.housePool(), address(housePool));
    }

    /* ========== DEPOSIT TESTS ========== */
    
    function test_FirstDeposit() public {
        uint256 depositAmount = 100 * 10**6; // 100 USDC
        
        vm.prank(lp1);
        uint256 shares = housePool.deposit(depositAmount);
        
        // First deposit: 1 USDC = 1e12 HOUSE (scaling 6 → 18 decimals)
        assertEq(shares, depositAmount * 1e12);
        assertEq(housePool.balanceOf(lp1), shares);
        assertEq(housePool.totalPool(), depositAmount);
    }
    
    function test_FirstDeposit_MinimumEnforced() public {
        vm.prank(lp1);
        vm.expectRevert(HousePool.InsufficientPool.selector);
        housePool.deposit(0.5 * 10**6); // 0.5 USDC, below minimum
    }
    
    function test_SubsequentDeposit_ProportionalShares() public {
        // First deposit: 100 USDC
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        // Second deposit: 50 USDC (should get 50% of existing shares)
        vm.prank(lp2);
        uint256 shares2 = housePool.deposit(50 * 10**6);
        
        // LP2 should have half as many shares as LP1
        assertEq(shares2, housePool.balanceOf(lp1) / 2);
    }
    
    function test_Deposit_ZeroAmount_Reverts() public {
        vm.prank(lp1);
        vm.expectRevert(HousePool.ZeroAmount.selector);
        housePool.deposit(0);
    }

    /* ========== WITHDRAWAL TESTS ========== */
    
    function test_RequestWithdrawal() public {
        // Setup: deposit first
        vm.prank(lp1);
        uint256 shares = housePool.deposit(200 * 10**6);
        
        // Request withdrawal
        vm.prank(lp1);
        housePool.requestWithdrawal(shares);
        
        (uint256 reqShares, uint256 unlockTime, uint256 expiryTime, bool canWithdraw, bool isExpired) = 
            housePool.getWithdrawalRequest(lp1);
        
        assertEq(reqShares, shares);
        assertEq(unlockTime, block.timestamp + 10); // 10 second cooldown
        assertEq(expiryTime, unlockTime + 60);       // 1 minute window
        assertFalse(canWithdraw); // Can't withdraw yet
        assertFalse(isExpired);
        assertEq(housePool.totalPendingShares(), shares);
    }
    
    function test_Withdraw_AfterCooldown() public {
        // Setup: deposit 300 USDC
        vm.prank(lp1);
        housePool.deposit(300 * 10**6);
        
        // Calculate shares for 200 USDC worth
        uint256 totalShares = housePool.balanceOf(lp1);
        uint256 sharesToWithdraw = (totalShares * 200) / 300; // ~2/3 of shares
        
        // Request partial withdrawal
        vm.prank(lp1);
        housePool.requestWithdrawal(sharesToWithdraw);
        
        // Fast forward past cooldown (10 seconds) but within window (1 minute)
        vm.warp(block.timestamp + 11);
        
        uint256 usdcBefore = usdc.balanceOf(lp1);
        uint256 poolBefore = housePool.totalPool();
        
        vm.prank(lp1);
        uint256 usdcOut = housePool.withdraw();
        
        // Should get back ~200 USDC
        assertApproxEqAbs(usdcOut, 200 * 10**6, 1); // Within 1 wei
        assertEq(usdc.balanceOf(lp1), usdcBefore + usdcOut);
        assertEq(housePool.totalPool(), poolBefore - usdcOut);
        assertEq(housePool.totalPendingShares(), 0);
    }
    
    function test_Withdraw_BeforeCooldown_Reverts() public {
        vm.prank(lp1);
        housePool.deposit(300 * 10**6);
        
        // Request partial withdrawal
        uint256 sharesToWithdraw = (housePool.balanceOf(lp1) * 200) / 300;
        vm.prank(lp1);
        housePool.requestWithdrawal(sharesToWithdraw);
        
        // Try to withdraw immediately - should fail because cooldown not passed
        vm.prank(lp1);
        vm.expectRevert(HousePool.WithdrawalNotReady.selector);
        housePool.withdraw();
    }
    
    function test_Withdraw_AfterExpiry_Reverts() public {
        vm.prank(lp1);
        housePool.deposit(300 * 10**6);
        
        uint256 sharesToWithdraw = (housePool.balanceOf(lp1) * 200) / 300;
        vm.prank(lp1);
        housePool.requestWithdrawal(sharesToWithdraw);
        
        // Fast forward past expiry (10 seconds cooldown + 1 minute window + 1 second)
        vm.warp(block.timestamp + 10 + 60 + 1);
        
        vm.prank(lp1);
        vm.expectRevert(HousePool.WithdrawalExpired.selector);
        housePool.withdraw();
    }
    
    function test_CleanupExpiredWithdrawal() public {
        vm.prank(lp1);
        uint256 shares = housePool.deposit(200 * 10**6);
        
        vm.prank(lp1);
        housePool.requestWithdrawal(shares);
        
        assertEq(housePool.totalPendingShares(), shares);
        
        // Fast forward past expiry (10 seconds cooldown + 1 minute window + 1 second)
        vm.warp(block.timestamp + 10 + 60 + 1);
        
        // Anyone can cleanup
        vm.prank(player1);
        housePool.cleanupExpiredWithdrawal(lp1);
        
        // LP1 still has shares, but request is cleared
        assertEq(housePool.balanceOf(lp1), shares);
        assertEq(housePool.totalPendingShares(), 0);
        
        (uint256 reqShares,,,,) = housePool.getWithdrawalRequest(lp1);
        assertEq(reqShares, 0);
    }
    
    function test_CancelWithdrawal() public {
        vm.prank(lp1);
        uint256 shares = housePool.deposit(200 * 10**6);
        
        vm.prank(lp1);
        housePool.requestWithdrawal(shares);
        
        assertEq(housePool.totalPendingShares(), shares);
        
        vm.prank(lp1);
        housePool.cancelWithdrawal();
        
        assertEq(housePool.totalPendingShares(), 0);
        assertEq(housePool.balanceOf(lp1), shares); // Still has shares
    }

    /* ========== EFFECTIVE POOL TESTS ========== */
    
    function test_EffectivePool_ReducedByPendingWithdrawals() public {
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        uint256 poolBefore = housePool.effectivePool();
        assertEq(poolBefore, 200 * 10**6);
        
        // Request half withdrawal
        uint256 halfShares = housePool.balanceOf(lp1) / 2;
        vm.prank(lp1);
        housePool.requestWithdrawal(halfShares);
        
        // Effective pool should be reduced by half
        uint256 poolAfter = housePool.effectivePool();
        assertEq(poolAfter, 100 * 10**6);
    }

    /* ========== GAME FUNCTIONS TESTS ========== */
    
    function test_ReceivePayment_OnlyGame() public {
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        // Non-game caller should fail
        vm.prank(player1);
        vm.expectRevert(HousePool.Unauthorized.selector);
        housePool.receivePayment(player1, 1 * 10**6);
    }
    
    function test_Payout_OnlyGame() public {
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        // Non-game caller should fail
        vm.prank(player1);
        vm.expectRevert(HousePool.Unauthorized.selector);
        housePool.payout(player1, 10 * 10**6);
    }

    /* ========== VIEW FUNCTIONS TESTS ========== */
    
    function test_SharePrice() public {
        // Before any deposits
        assertEq(housePool.sharePrice(), 1e18);
        
        // After deposit
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        assertTrue(housePool.sharePrice() > 0);
    }
    
    function test_UsdcValue() public {
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        // LP1's USDC value should equal their deposit
        assertEq(housePool.usdcValue(lp1), 100 * 10**6);
    }

    /* ========== VAULT INTEGRATION TESTS ========== */
    
    function test_AllFundsGoToVault_OnDeposit() public {
        // Deposit 100 USDC - ALL should go to vault
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        // 100% should be in vault, 0 liquid
        assertEq(housePool.liquidPool(), 0);
        assertEq(housePool.vaultPool(), 100 * 10**6);
        assertEq(housePool.totalPool(), 100 * 10**6);
    }
    
    function test_VaultWithdraw_OnPayout() public {
        // Deposit 100 USDC (all goes to vault)
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        assertEq(housePool.vaultPool(), 100 * 10**6);
        
        // Player commits to use pool (adds 0.1 USDC)
        bytes32 secret = bytes32("test_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        diceGame.commitRoll(commitment);
        
        vm.roll(block.number + 2);
        
        // If player wins, needs to payout 1 USDC from vault
        vm.prank(player1);
        bool won = diceGame.revealRoll(secret);
        
        if (won) {
            // Pool should have paid out from vault
            assertLt(housePool.totalPool(), 100 * 10**6 + diceGame.ROLL_COST());
        }
    }
    
    function test_VaultYield_IncreasesSharePrice() public {
        // Deposit 100 USDC (all goes to vault)
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        uint256 sharePriceBefore = housePool.sharePrice();
        uint256 valueBeforeYield = housePool.usdcValue(lp1);
        
        // Simulate yield in vault (10 USDC = 10%)
        mockVault.simulateYield(10 * 10**6);
        
        uint256 sharePriceAfter = housePool.sharePrice();
        uint256 valueAfterYield = housePool.usdcValue(lp1);
        
        // Share price should increase
        assertGt(sharePriceAfter, sharePriceBefore);
        
        // LP's USDC value should increase by the yield amount
        assertApproxEqAbs(valueAfterYield, valueBeforeYield + 10 * 10**6, 1);
    }
    
    function test_TotalPool_IncludesVault() public {
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        uint256 liquid = housePool.liquidPool();
        uint256 vault = housePool.vaultPool();
        uint256 total = housePool.totalPool();
        
        assertEq(total, liquid + vault);
        assertEq(liquid, 0); // All in vault
        assertEq(vault, 100 * 10**6);
    }
    
    function test_Withdraw_FromVault() public {
        // Deposit 100 USDC - all goes to vault
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        assertEq(housePool.vaultPool(), 100 * 10**6);
        assertEq(housePool.liquidPool(), 0);
        
        uint256 shares = housePool.balanceOf(lp1);
        
        // Request full withdrawal
        vm.prank(lp1);
        housePool.requestWithdrawal(shares);
        
        vm.warp(block.timestamp + 11);
        
        uint256 usdcBefore = usdc.balanceOf(lp1);
        
        // Withdraw should pull from vault
        vm.prank(lp1);
        uint256 usdcOut = housePool.withdraw();
        
        // Should get full 100 USDC back
        assertEq(usdcOut, 100 * 10**6);
        assertEq(usdc.balanceOf(lp1), usdcBefore + 100 * 10**6);
    }
    
    function test_MultipleDeposits_AllGoToVault() public {
        // First deposit
        vm.prank(lp1);
        housePool.deposit(100 * 10**6);
        
        assertEq(housePool.vaultPool(), 100 * 10**6);
        assertEq(housePool.liquidPool(), 0);
        
        // Second deposit
        vm.prank(lp2);
        housePool.deposit(50 * 10**6);
        
        // All 150 should be in vault
        assertEq(housePool.vaultPool(), 150 * 10**6);
        assertEq(housePool.liquidPool(), 0);
        assertEq(housePool.totalPool(), 150 * 10**6);
    }

    /* ========== FUZZ TESTS ========== */
    
    function testFuzz_Deposit(uint256 amount) public {
        // Bound to reasonable range (1 USDC to available balance)
        amount = bound(amount, 1 * 10**6, INITIAL_USDC);
        
        vm.prank(lp1);
        uint256 shares = housePool.deposit(amount);
        
        assertTrue(shares > 0);
        assertEq(housePool.totalPool(), amount);
        assertEq(housePool.vaultPool(), amount); // All in vault
        assertEq(housePool.liquidPool(), 0);
    }
    
    function testFuzz_WithdrawalTiming(uint256 waitTime) public {
        vm.prank(lp1);
        uint256 shares = housePool.deposit(200 * 10**6);
        
        vm.prank(lp1);
        housePool.requestWithdrawal(shares);
        
        // Bound wait time (10 sec cooldown + 1 min window = 70 sec total)
        waitTime = bound(waitTime, 0, 5 minutes);
        vm.warp(block.timestamp + waitTime);
        
        (,,,bool canWithdraw, bool isExpired) = housePool.getWithdrawalRequest(lp1);
        
        if (waitTime < 10) {
            // Before cooldown
            assertFalse(canWithdraw);
            assertFalse(isExpired);
        } else if (waitTime <= 10 + 60) {
            // In withdrawal window
            assertTrue(canWithdraw);
            assertFalse(isExpired);
        } else {
            // After window expired
            assertFalse(canWithdraw);
            assertTrue(isExpired);
        }
    }
}

/* ========== DICE GAME TESTS ========== */

contract DiceGameTest is Test {
    HousePool public housePool;
    DiceGame public diceGame;
    VaultManager public vaultManager;
    MockUSDC public usdc;
    MockFleetCommander public mockVault;
    
    address public lp1 = address(2);
    address public player1 = address(4);
    address public player2 = address(5);
    
    uint256 constant INITIAL_USDC = 10_000 * 10**6;
    
    function setUp() public {
        usdc = new MockUSDC();
        mockVault = new MockFleetCommander(address(usdc));
        diceGame = new DiceGame(address(usdc), address(mockVault));
        housePool = diceGame.housePool();
        vaultManager = diceGame.vaultManager();
        
        usdc.mint(lp1, INITIAL_USDC);
        usdc.mint(player1, INITIAL_USDC);
        usdc.mint(player2, INITIAL_USDC);
        
        // LPs approve HousePool for deposits
        vm.prank(lp1);
        usdc.approve(address(housePool), type(uint256).max);
        
        // Players approve HousePool for game payments
        vm.prank(player1);
        usdc.approve(address(housePool), type(uint256).max);
        
        vm.prank(player2);
        usdc.approve(address(housePool), type(uint256).max);
    }
    
    function test_CommitRoll() public {
        // Setup: LP deposits enough for gambling
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        bytes32 secret = bytes32("my_secret_123");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        diceGame.commitRoll(commitment);
        
        (bytes32 hash, uint256 blockNum, bool canReveal, bool isExpired) = 
            diceGame.getCommitment(player1);
        
        assertEq(hash, commitment);
        assertEq(blockNum, block.number);
        assertFalse(canReveal); // Can't reveal same block
        assertFalse(isExpired);
        
        // USDC transferred to pool (deposit + roll cost)
        assertEq(housePool.totalPool(), 200 * 10**6 + diceGame.ROLL_COST());
    }
    
    function test_CommitRoll_InsufficientPool_Reverts() public {
        // No deposits - pool is empty
        bytes32 secret = bytes32("my_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        vm.expectRevert(DiceGame.GameNotPlayable.selector);
        diceGame.commitRoll(commitment);
    }
    
    function test_RevealRoll_TooEarly_Reverts() public {
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        bytes32 secret = bytes32("my_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        diceGame.commitRoll(commitment);
        
        // Try to reveal in same block - should fail
        vm.prank(player1);
        vm.expectRevert(DiceGame.TooEarly.selector);
        diceGame.revealRoll(secret);
    }
    
    function test_RevealRoll_AfterOneBlock_Success() public {
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        bytes32 secret = bytes32("my_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        diceGame.commitRoll(commitment);
        
        // Advance 1 block - should now work
        vm.roll(block.number + 1);
        
        vm.prank(player1);
        diceGame.revealRoll(secret); // Should succeed
        
        // Commitment should be cleared
        (bytes32 hash,,,) = diceGame.getCommitment(player1);
        assertEq(hash, bytes32(0));
    }
    
    function test_RevealRoll_Success() public {
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        bytes32 secret = bytes32("my_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        diceGame.commitRoll(commitment);
        
        // Advance 2 blocks
        vm.roll(block.number + 2);
        
        uint256 poolBefore = housePool.totalPool();
        
        vm.prank(player1);
        bool won = diceGame.revealRoll(secret);
        
        // Commitment should be cleared
        (bytes32 hash,,,) = diceGame.getCommitment(player1);
        assertEq(hash, bytes32(0));
        
        // Pool should change based on win/loss
        if (won) {
            assertEq(housePool.totalPool(), poolBefore - diceGame.ROLL_PAYOUT()); // 1 USDC payout
        } else {
            assertEq(housePool.totalPool(), poolBefore); // No change (already received 0.1 USDC)
        }
    }
    
    function test_RevealRoll_TooLate_Reverts() public {
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        bytes32 secret = bytes32("my_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        diceGame.commitRoll(commitment);
        
        // Advance 257 blocks (past the 256 block limit)
        vm.roll(block.number + 257);
        
        vm.prank(player1);
        vm.expectRevert(DiceGame.TooLate.selector);
        diceGame.revealRoll(secret);
    }
    
    function test_CheckRoll() public {
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        bytes32 secret = bytes32("my_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        diceGame.commitRoll(commitment);
        
        // Can't check in same block
        (bool canCheck, bool isWinner) = diceGame.checkRoll(player1, secret);
        assertFalse(canCheck);
        
        // Advance 1 block
        vm.roll(block.number + 1);
        
        // Now can check
        (canCheck, isWinner) = diceGame.checkRoll(player1, secret);
        assertTrue(canCheck);
        
        // Wrong secret returns false for canCheck
        (canCheck, ) = diceGame.checkRoll(player1, bytes32("wrong"));
        assertFalse(canCheck);
        
        // Verify checkRoll matches actual reveal result
        vm.prank(player1);
        bool actualWon = diceGame.revealRoll(secret);
        assertEq(isWinner, actualWon);
    }
    
    function test_CheckRoll_TooLate() public {
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        bytes32 secret = bytes32("my_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        diceGame.commitRoll(commitment);
        
        // Advance 257 blocks
        vm.roll(block.number + 257);
        
        // Can't check anymore (blockhash is 0)
        (bool canCheck, ) = diceGame.checkRoll(player1, secret);
        assertFalse(canCheck);
    }
    
    function test_RevealRoll_InvalidSecret_Reverts() public {
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        bytes32 secret = bytes32("my_secret");
        bytes32 wrongSecret = bytes32("wrong_secret");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        diceGame.commitRoll(commitment);
        
        vm.roll(block.number + 2);
        
        vm.prank(player1);
        vm.expectRevert(DiceGame.InvalidReveal.selector);
        diceGame.revealRoll(wrongSecret);
    }
    
    function test_CommitRoll_BlockedByPendingWithdrawals() public {
        // Deposit just above minimum threshold (MIN_RESERVE + ROLL_PAYOUT)
        uint256 minRequired = diceGame.MIN_RESERVE() + diceGame.ROLL_PAYOUT();
        vm.prank(lp1);
        housePool.deposit(minRequired + 1 * 10**6); // Just above threshold
        
        // Request withdrawal of most of it (99%)
        uint256 mostShares = (housePool.balanceOf(lp1) * 99) / 100;
        vm.prank(lp1);
        housePool.requestWithdrawal(mostShares);
        
        // Effective pool should now be below threshold
        assertTrue(housePool.effectivePool() < minRequired);
        
        // Should not be able to commit
        bytes32 commitment = keccak256(abi.encodePacked(bytes32("secret")));
        vm.prank(player1);
        vm.expectRevert(DiceGame.GameNotPlayable.selector);
        diceGame.commitRoll(commitment);
    }
    
    function test_CanPlay() public {
        // Empty pool - can't play
        assertFalse(diceGame.canPlay());
        
        // Deposit enough
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        assertTrue(diceGame.canPlay());
    }

    /* ========== SHARE VALUE CONSISTENCY TESTS ========== */
    
    function test_ShareValue_PreservedAfterGamblingLoss() public {
        // LP deposits 200 USDC
        vm.prank(lp1);
        housePool.deposit(200 * 10**6);
        
        uint256 valueBeforeGambling = housePool.usdcValue(lp1);
        
        // Player commits and plays
        bytes32 secret = bytes32("will_probably_lose");
        bytes32 commitment = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        diceGame.commitRoll(commitment);
        
        vm.roll(block.number + 2);
        
        vm.prank(player1);
        bool won = diceGame.revealRoll(secret);
        
        uint256 valueAfterGambling = housePool.usdcValue(lp1);
        
        uint256 rollCost = diceGame.ROLL_COST();
        uint256 rollPayout = diceGame.ROLL_PAYOUT();
        
        if (won) {
            // Pool decreased by net payout (payout - cost)
            assertEq(valueAfterGambling, valueBeforeGambling - (rollPayout - rollCost));
        } else {
            // Pool increased by roll cost
            assertEq(valueAfterGambling, valueBeforeGambling + rollCost);
        }
    }
}

/* ========== VAULT MANAGER TESTS ========== */

contract VaultManagerTest is Test {
    VaultManager public vaultManager;
    MockUSDC public usdc;
    MockFleetCommander public mockVault;
    address public housePool = address(0x1234);
    
    function setUp() public {
        usdc = new MockUSDC();
        mockVault = new MockFleetCommander(address(usdc));
        vaultManager = new VaultManager(address(mockVault), address(usdc));
    }
    
    function test_SetHousePool() public {
        vaultManager.setHousePool(housePool);
        assertEq(vaultManager.housePool(), housePool);
        assertTrue(vaultManager.housePoolSet());
    }
    
    function test_SetHousePool_OnlyOnce() public {
        vaultManager.setHousePool(housePool);
        
        vm.expectRevert(VaultManager.HousePoolAlreadySet.selector);
        vaultManager.setHousePool(address(0x5678));
    }
    
    function test_SetHousePool_ZeroAddress_Reverts() public {
        vm.expectRevert(VaultManager.InvalidAddress.selector);
        vaultManager.setHousePool(address(0));
    }
    
    function test_DepositIntoVault() public {
        vaultManager.setHousePool(housePool);
        
        // Send USDC to vault manager
        usdc.mint(address(vaultManager), 100 * 10**6);
        
        vm.prank(housePool);
        uint256 shares = vaultManager.depositIntoVault(0);
        
        assertGt(shares, 0);
        assertEq(vaultManager.getCurrentValue(), 100 * 10**6);
        assertEq(vaultManager.getUSDCBalance(), 0);
    }
    
    function test_DepositIntoVault_Unauthorized() public {
        vaultManager.setHousePool(housePool);
        usdc.mint(address(vaultManager), 100 * 10**6);
        
        vm.prank(address(0x9999));
        vm.expectRevert(VaultManager.Unauthorized.selector);
        vaultManager.depositIntoVault(0);
    }
    
    function test_WithdrawFromVault() public {
        vaultManager.setHousePool(housePool);
        usdc.mint(address(vaultManager), 100 * 10**6);
        
        vm.prank(housePool);
        vaultManager.depositIntoVault(0);
        
        vm.prank(housePool);
        vaultManager.withdrawFromVault(50 * 10**6);
        
        // Should have withdrawn 50 USDC to housePool
        assertEq(usdc.balanceOf(housePool), 50 * 10**6);
        assertApproxEqAbs(vaultManager.getCurrentValue(), 50 * 10**6, 1);
    }
    
    function test_GetTotalValue() public {
        vaultManager.setHousePool(housePool);
        
        // Put 50 USDC in vault
        usdc.mint(address(vaultManager), 50 * 10**6);
        vm.prank(housePool);
        vaultManager.depositIntoVault(0);
        
        // Put 30 USDC directly in contract
        usdc.mint(address(vaultManager), 30 * 10**6);
        
        assertEq(vaultManager.getTotalValue(), 80 * 10**6);
    }
    
    function test_EmergencyWithdraw() public {
        vaultManager.setHousePool(housePool);
        usdc.mint(address(vaultManager), 100 * 10**6);
        
        address recipient = address(0xBEEF);
        
        vm.prank(housePool);
        vaultManager.emergencyWithdraw(address(usdc), 50 * 10**6, recipient);
        
        assertEq(usdc.balanceOf(recipient), 50 * 10**6);
        assertEq(usdc.balanceOf(address(vaultManager)), 50 * 10**6);
    }
}
