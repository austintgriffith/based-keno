// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/HousePool.sol";
import "../contracts/BasedKeno.sol";
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
    BasedKeno public basedKeno;
    VaultManager public vaultManager;
    MockUSDC public usdc;
    MockFleetCommander public mockVault;
    
    address public dealer = address(1);
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
        
        // Deploy BasedKeno (which deploys VaultManager and HousePool internally)
        basedKeno = new BasedKeno(address(usdc), address(mockVault), dealer);
        housePool = basedKeno.housePool();
        vaultManager = basedKeno.vaultManager();
        
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
        assertEq(address(housePool.game()), address(basedKeno));
        assertEq(address(housePool.usdc()), address(usdc));
        assertEq(address(housePool.vaultManager()), address(vaultManager));
        assertEq(address(basedKeno.housePool()), address(housePool));
        assertEq(address(basedKeno.usdc()), address(usdc));
        assertEq(address(basedKeno.vaultManager()), address(vaultManager));
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

/* ========== BASED KENO TESTS ========== */

contract BasedKenoTest is Test {
    HousePool public housePool;
    BasedKeno public basedKeno;
    VaultManager public vaultManager;
    MockUSDC public usdc;
    MockFleetCommander public mockVault;
    
    address public dealer = address(1);
    address public lp1 = address(2);
    address public player1 = address(4);
    address public player2 = address(5);
    
    uint256 constant INITIAL_USDC = 10_000 * 10**6;
    
    function setUp() public {
        usdc = new MockUSDC();
        mockVault = new MockFleetCommander(address(usdc));
        basedKeno = new BasedKeno(address(usdc), address(mockVault), dealer);
        housePool = basedKeno.housePool();
        vaultManager = basedKeno.vaultManager();
        
        usdc.mint(lp1, INITIAL_USDC);
        usdc.mint(player1, INITIAL_USDC);
        usdc.mint(player2, INITIAL_USDC);
        usdc.mint(dealer, INITIAL_USDC);
        
        // LPs approve HousePool for deposits
        vm.prank(lp1);
        usdc.approve(address(housePool), type(uint256).max);
        
        // Players approve HousePool for game payments
        vm.prank(player1);
        usdc.approve(address(housePool), type(uint256).max);
        
        vm.prank(player2);
        usdc.approve(address(housePool), type(uint256).max);
    }
    
    function test_PlaceBet_StartsRound() public {
        // Setup: LP deposits enough for gambling (need 2500 USDC per 1 USDC bet due to 2500x max multiplier)
        vm.prank(lp1);
        housePool.deposit(5000 * 10**6);
        
        uint8[] memory picks = new uint8[](3);
        picks[0] = 5;
        picks[1] = 10;
        picks[2] = 15;
        
        vm.prank(player1);
        uint256 cardId = basedKeno.placeBet(picks, 1 * 10**6);
        
        assertEq(cardId, 0); // First card
        
        (uint256 roundId, BasedKeno.RoundPhase phase,,,,,,, ) = basedKeno.getCurrentRound();
        assertEq(roundId, 0);
        assertTrue(phase == BasedKeno.RoundPhase.Open);
    }
    
    function test_PlaceBet_InvalidNumbers_Reverts() public {
        vm.prank(lp1);
        housePool.deposit(1000 * 10**6);
        
        // Test: empty array
        uint8[] memory emptyPicks = new uint8[](0);
        vm.prank(player1);
        vm.expectRevert(BasedKeno.InvalidNumberCount.selector);
        basedKeno.placeBet(emptyPicks, 1 * 10**6);
        
        // Test: too many picks (11)
        uint8[] memory tooMany = new uint8[](11);
        for (uint8 i = 0; i < 11; i++) {
            tooMany[i] = i + 1;
        }
        vm.prank(player1);
        vm.expectRevert(BasedKeno.InvalidNumberCount.selector);
        basedKeno.placeBet(tooMany, 1 * 10**6);
        
        // Test: number out of range (0)
        uint8[] memory zeroNum = new uint8[](1);
        zeroNum[0] = 0;
        vm.prank(player1);
        vm.expectRevert(BasedKeno.InvalidNumber.selector);
        basedKeno.placeBet(zeroNum, 1 * 10**6);
        
        // Test: number out of range (81)
        uint8[] memory highNum = new uint8[](1);
        highNum[0] = 81;
        vm.prank(player1);
        vm.expectRevert(BasedKeno.InvalidNumber.selector);
        basedKeno.placeBet(highNum, 1 * 10**6);
        
        // Test: not sorted
        uint8[] memory unsorted = new uint8[](2);
        unsorted[0] = 10;
        unsorted[1] = 5;
        vm.prank(player1);
        vm.expectRevert(BasedKeno.NumbersNotSorted.selector);
        basedKeno.placeBet(unsorted, 1 * 10**6);
        
        // Test: duplicates
        uint8[] memory dupes = new uint8[](2);
        dupes[0] = 5;
        dupes[1] = 5;
        vm.prank(player1);
        vm.expectRevert(BasedKeno.DuplicateNumber.selector);
        basedKeno.placeBet(dupes, 1 * 10**6);
    }
    
    function test_PlaceBet_BetTooSmall_Reverts() public {
        vm.prank(lp1);
        housePool.deposit(1000 * 10**6);
        
        uint8[] memory picks = new uint8[](1);
        picks[0] = 1;
        
        vm.prank(player1);
        vm.expectRevert(BasedKeno.BetTooSmall.selector);
        basedKeno.placeBet(picks, 1000); // Less than MIN_BET
    }
    
    function test_PlaceBet_BetTooLarge_Reverts() public {
        vm.prank(lp1);
        housePool.deposit(100 * 10**6); // Only 100 USDC
        
        uint8[] memory picks = new uint8[](1);
        picks[0] = 1;
        
        // For 1 pick, max multiplier is 3.8x (38 scaled by 10)
        // Max payout = bet * 38 / 10 = bet * 3.8
        // Pool = 100 USDC, so max bet = 100 / 3.8 = ~26.3 USDC
        // Try to bet 30 USDC - should fail
        vm.prank(player1);
        vm.expectRevert(BasedKeno.BetTooLarge.selector);
        basedKeno.placeBet(picks, 30 * 10**6);
    }
    
    function test_CommitRound_OnlyDealer() public {
        vm.prank(lp1);
        housePool.deposit(5000 * 10**6);
        
        // Place a bet to start round
        uint8[] memory picks = new uint8[](1);
        picks[0] = 1;
        vm.prank(player1);
        basedKeno.placeBet(picks, 1 * 10**6);
        
        // Advance past betting period (30 seconds)
        vm.warp(block.timestamp + 31);
        
        // Non-dealer should fail
        bytes32 secret = bytes32("dealer_secret");
        bytes32 commitHash = keccak256(abi.encodePacked(secret));
        
        vm.prank(player1);
        vm.expectRevert(BasedKeno.NotDealer.selector);
        basedKeno.commitRound(commitHash);
        
        // Dealer should succeed
        vm.prank(dealer);
        basedKeno.commitRound(commitHash);
    }
    
    function test_CommitRound_TooEarly_Reverts() public {
        vm.prank(lp1);
        housePool.deposit(5000 * 10**6);
        
        uint8[] memory picks = new uint8[](1);
        picks[0] = 1;
        vm.prank(player1);
        basedKeno.placeBet(picks, 1 * 10**6);
        
        // Don't advance blocks - still in betting period
        bytes32 secret = bytes32("dealer_secret");
        bytes32 commitHash = keccak256(abi.encodePacked(secret));
        
        vm.prank(dealer);
        vm.expectRevert(BasedKeno.BettingPeriodNotOver.selector);
        basedKeno.commitRound(commitHash);
    }
    
    function test_FullRound_CommitReveal() public {
        vm.prank(lp1);
        housePool.deposit(5000 * 10**6);
        
        // Place bet
        uint8[] memory picks = new uint8[](3);
        picks[0] = 1;
        picks[1] = 2;
        picks[2] = 3;
        vm.prank(player1);
        uint256 cardId = basedKeno.placeBet(picks, 1 * 10**6);
        
        // Advance past betting period (30 seconds)
        vm.warp(block.timestamp + 31);
        
        // Dealer commits
        bytes32 secret = bytes32("dealer_secret");
        bytes32 commitHash = keccak256(abi.encodePacked(secret));
        vm.prank(dealer);
        basedKeno.commitRound(commitHash);
        
        // Advance 1 block for reveal (blockhash requires next block)
        vm.roll(block.number + 1);
        
        // Dealer reveals
        vm.prank(dealer);
        basedKeno.revealRound(secret);
        
        // Check round state
        (uint256 roundId, BasedKeno.RoundPhase phase,,,,,,,) = basedKeno.getCurrentRound();
        assertEq(roundId, 1); // Advanced to next round
        assertTrue(phase == BasedKeno.RoundPhase.Idle);
        
        // Get winning numbers from round 0
        uint8[20] memory winners = basedKeno.getWinningNumbers(0);
        
        // Verify 20 unique numbers between 1-80
        uint256 bitmap = 0;
        for (uint256 i = 0; i < 20; i++) {
            assertTrue(winners[i] >= 1 && winners[i] <= 80, "Number out of range");
            uint256 bit = 1 << (winners[i] - 1);
            assertTrue((bitmap & bit) == 0, "Duplicate number found");
            bitmap |= bit;
        }
        
        // Claim winnings (might be 0 if no hits)
        vm.prank(player1);
        basedKeno.claimWinnings(0, cardId);
    }
    
    function test_RevealRound_InvalidSecret_Reverts() public {
        vm.prank(lp1);
        housePool.deposit(5000 * 10**6);
        
        uint8[] memory picks = new uint8[](1);
        picks[0] = 1;
        vm.prank(player1);
        basedKeno.placeBet(picks, 1 * 10**6);
        
        // Advance past betting period (30 seconds)
        vm.warp(block.timestamp + 31);
        
        bytes32 secret = bytes32("dealer_secret");
        bytes32 commitHash = keccak256(abi.encodePacked(secret));
        vm.prank(dealer);
        basedKeno.commitRound(commitHash);
        
        // Advance 1 block for reveal
        vm.roll(block.number + 1);
        
        // Wrong secret
        vm.prank(dealer);
        vm.expectRevert(BasedKeno.InvalidReveal.selector);
        basedKeno.revealRound(bytes32("wrong_secret"));
    }
    
    function test_GetPayoutMultiplier() public view {
        // Pick 1, hit 1 = 3.8x (38 scaled)
        assertEq(basedKeno.getPayoutMultiplier(1, 1), 38);
        
        // Pick 2, hit 2 = 15x (150 scaled)
        assertEq(basedKeno.getPayoutMultiplier(2, 2), 150);
        
        // Pick 10, hit 10 = 2500x (25000 scaled)
        assertEq(basedKeno.getPayoutMultiplier(10, 10), 25000);
        
        // Pick 10, hit 0 = 20x (200 scaled) - catch zero payout
        assertEq(basedKeno.getPayoutMultiplier(10, 0), 200);
        
        // Invalid: more hits than picks
        assertEq(basedKeno.getPayoutMultiplier(5, 6), 0);
    }
    
    function test_MaxBet() public {
        vm.prank(lp1);
        housePool.deposit(2500 * 10**6); // 2500 USDC
        
        // Max bet = pool / 2500 = 1 USDC
        assertEq(basedKeno.maxBet(), 1 * 10**6);
    }
    
    function test_MultipleBetsPerRound() public {
        vm.prank(lp1);
        housePool.deposit(10000 * 10**6);
        
        // Player 1 places multiple bets
        uint8[] memory picks1 = new uint8[](3);
        picks1[0] = 1;
        picks1[1] = 2;
        picks1[2] = 3;
        
        uint8[] memory picks2 = new uint8[](5);
        picks2[0] = 10;
        picks2[1] = 20;
        picks2[2] = 30;
        picks2[3] = 40;
        picks2[4] = 50;
        
        vm.startPrank(player1);
        uint256 card1 = basedKeno.placeBet(picks1, 1 * 10**6);
        uint256 card2 = basedKeno.placeBet(picks2, 2 * 10**6);
        vm.stopPrank();
        
        assertEq(card1, 0);
        assertEq(card2, 1);
        
        // Check player's cards
        uint256[] memory playerCardIds = basedKeno.getPlayerCards(player1, 0);
        assertEq(playerCardIds.length, 2);
        assertEq(playerCardIds[0], 0);
        assertEq(playerCardIds[1], 1);
    }
}

/* ========== VAULT MANAGER TESTS ========== */

contract VaultManagerTest is Test {
    VaultManager public vaultManager;
    MockUSDC public usdc;
    MockFleetCommander public mockVault;
    address public housePoolAddr = address(0x1234);
    
    function setUp() public {
        usdc = new MockUSDC();
        mockVault = new MockFleetCommander(address(usdc));
        vaultManager = new VaultManager(address(mockVault), address(usdc));
    }
    
    function test_SetHousePool() public {
        vaultManager.setHousePool(housePoolAddr);
        assertEq(vaultManager.housePool(), housePoolAddr);
        assertTrue(vaultManager.housePoolSet());
    }
    
    function test_SetHousePool_OnlyOnce() public {
        vaultManager.setHousePool(housePoolAddr);
        
        vm.expectRevert(VaultManager.HousePoolAlreadySet.selector);
        vaultManager.setHousePool(address(0x5678));
    }
    
    function test_SetHousePool_ZeroAddress_Reverts() public {
        vm.expectRevert(VaultManager.InvalidAddress.selector);
        vaultManager.setHousePool(address(0));
    }
    
    function test_DepositIntoVault() public {
        vaultManager.setHousePool(housePoolAddr);
        
        // Send USDC to vault manager
        usdc.mint(address(vaultManager), 100 * 10**6);
        
        vm.prank(housePoolAddr);
        uint256 shares = vaultManager.depositIntoVault(0);
        
        assertGt(shares, 0);
        assertEq(vaultManager.getCurrentValue(), 100 * 10**6);
        assertEq(vaultManager.getUSDCBalance(), 0);
    }
    
    function test_DepositIntoVault_Unauthorized() public {
        vaultManager.setHousePool(housePoolAddr);
        usdc.mint(address(vaultManager), 100 * 10**6);
        
        vm.prank(address(0x9999));
        vm.expectRevert(VaultManager.Unauthorized.selector);
        vaultManager.depositIntoVault(0);
    }
    
    function test_WithdrawFromVault() public {
        vaultManager.setHousePool(housePoolAddr);
        usdc.mint(address(vaultManager), 100 * 10**6);
        
        vm.prank(housePoolAddr);
        vaultManager.depositIntoVault(0);
        
        vm.prank(housePoolAddr);
        vaultManager.withdrawFromVault(50 * 10**6);
        
        // Should have withdrawn 50 USDC to housePool
        assertEq(usdc.balanceOf(housePoolAddr), 50 * 10**6);
        assertApproxEqAbs(vaultManager.getCurrentValue(), 50 * 10**6, 1);
    }
    
    function test_GetTotalValue() public {
        vaultManager.setHousePool(housePoolAddr);
        
        // Put 50 USDC in vault
        usdc.mint(address(vaultManager), 50 * 10**6);
        vm.prank(housePoolAddr);
        vaultManager.depositIntoVault(0);
        
        // Put 30 USDC directly in contract
        usdc.mint(address(vaultManager), 30 * 10**6);
        
        assertEq(vaultManager.getTotalValue(), 80 * 10**6);
    }
    
    function test_EmergencyWithdraw() public {
        vaultManager.setHousePool(housePoolAddr);
        usdc.mint(address(vaultManager), 100 * 10**6);
        
        address recipient = address(0xBEEF);
        
        vm.prank(housePoolAddr);
        vaultManager.emergencyWithdraw(address(usdc), 50 * 10**6, recipient);
        
        assertEq(usdc.balanceOf(recipient), 50 * 10**6);
        assertEq(usdc.balanceOf(address(vaultManager)), 50 * 10**6);
    }
}
