// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./HousePool.sol";
import "./VaultManager.sol";

/// @title BasedKeno - Commit-reveal Keno game using HousePool liquidity
/// @notice Players pick 1-10 numbers from 1-80, dealer draws 20 winning numbers
/// @dev Deploys its own HousePool and VaultManager with this contract as the immutable game
contract BasedKeno {
    /* ========== CUSTOM ERRORS ========== */
    error InvalidNumberCount();
    error InvalidNumber();
    error NumbersNotSorted();
    error DuplicateNumber();
    error BetTooLarge();
    error BetTooSmall();
    error RoundNotOpen();
    error RoundNotCommitted();
    error RoundNotRevealed();
    error BettingPeriodNotOver();
    error TooEarlyToReveal();
    error TooLateToReveal();
    error InvalidReveal();
    error NotDealer();
    error CardAlreadyClaimed();
    error InvalidCard();
    error TimeoutNotReached();
    error NothingToRefund();
    error RoundAlreadyActive();

    /* ========== ENUMS ========== */
    
    enum RoundPhase { Idle, Open, Committed, Revealed }

    /* ========== STRUCTS ========== */
    
    struct Card {
        address player;
        uint8[] numbers;      // 1-10 numbers picked by player
        uint256 betAmount;    // USDC amount (6 decimals)
        bool claimed;
    }
    
    struct Round {
        RoundPhase phase;
        uint256 startTime;      // block.timestamp when round started
        uint256 commitBlock;    // block.number when committed (needed for blockhash)
        bytes32 commitHash;
        uint8[20] winningNumbers;
        uint256 totalCards;
        uint256 totalBets;
    }

    /* ========== STATE VARIABLES ========== */
    
    HousePool public immutable housePool;
    VaultManager public immutable vaultManager;
    IERC20 public immutable usdc;
    address public immutable dealer;
    
    uint256 public currentRound;
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(uint256 => Card)) public cards; // roundId => cardId => Card
    mapping(address => mapping(uint256 => uint256[])) public playerCards; // player => roundId => cardIds

    /* ========== CONSTANTS ========== */
    
    // Game parameters
    uint256 public constant TOTAL_NUMBERS = 80;
    uint256 public constant NUMBERS_DRAWN = 20;
    uint256 public constant MIN_PICKS = 1;
    uint256 public constant MAX_PICKS = 10;
    
    // Betting parameters
    uint256 public constant MIN_BET = 1e4;        // 0.01 USDC minimum
    uint256 public constant MAX_MULTIPLIER = 2500; // Cap for max payout calculation
    
    // Timing
    uint256 public constant BETTING_PERIOD = 30;      // 30 seconds of betting
    uint256 public constant REVEAL_WINDOW = 256;      // Must reveal within 256 blocks (EVM blockhash constraint)
    uint256 public constant TIMEOUT_SECONDS = 3600;   // 1 hour timeout for refunds
    
    // Payout multipliers (scaled by 10 for decimal precision, e.g., 38 = 3.8x)
    // payouts[picks-1][hits] = multiplier * 10
    // 0 means no payout for that combination
    uint16[11][10] public payouts;

    /* ========== EVENTS ========== */
    
    event RoundStarted(uint256 indexed roundId, uint256 startTime);
    event BetPlaced(uint256 indexed roundId, uint256 indexed cardId, address indexed player, uint8[] numbers, uint256 betAmount);
    event RoundCommitted(uint256 indexed roundId, bytes32 commitHash, uint256 commitBlock);
    event RoundRevealed(uint256 indexed roundId, uint8[20] winningNumbers);
    event WinningsClaimed(uint256 indexed roundId, uint256 indexed cardId, address indexed player, uint256 payout, uint8 hits);
    event RoundRefunded(uint256 indexed roundId, uint256 totalRefunded);

    /* ========== CONSTRUCTOR ========== */
    
    /// @notice Deploys VaultManager and HousePool with this BasedKeno as the immutable game contract
    /// @param _usdc Address of the USDC token
    /// @param _fleetCommander Address of Summer.fi FleetCommander vault (LVUSDC on Base)
    /// @param _dealer Address authorized to commit/reveal rounds
    constructor(address _usdc, address _fleetCommander, address _dealer) {
        usdc = IERC20(_usdc);
        dealer = _dealer;
        
        // 1. Deploy VaultManager first
        vaultManager = new VaultManager(_fleetCommander, _usdc);
        
        // 2. Deploy HousePool with VaultManager
        housePool = new HousePool(_usdc, address(this), address(vaultManager));
        
        // 3. Link VaultManager to HousePool (one-time setup)
        vaultManager.setHousePool(address(housePool));
        
        // Initialize payout table
        _initializePayouts();
    }

    /* ========== PAYOUT INITIALIZATION ========== */
    
    /// @dev Initialize payout multipliers (scaled by 10)
    /// Based on hypergeometric distribution with ~5% house edge, capped at 2500x
    function _initializePayouts() internal {
        // Pick 1: hit 1 = 3.8x
        payouts[0][1] = 38;
        
        // Pick 2: hit 2 = 15x
        payouts[1][2] = 150;
        
        // Pick 3: hit 2 = 2x, hit 3 = 65x
        payouts[2][2] = 20;
        payouts[2][3] = 650;
        
        // Pick 4: hit 2 = 1x, hit 3 = 8x, hit 4 = 300x
        payouts[3][2] = 10;
        payouts[3][3] = 80;
        payouts[3][4] = 3000;
        
        // Pick 5: hit 3 = 4x, hit 4 = 50x, hit 5 = 1000x
        payouts[4][3] = 40;
        payouts[4][4] = 500;
        payouts[4][5] = 10000;
        
        // Pick 6: hit 3 = 2x, hit 4 = 15x, hit 5 = 150x, hit 6 = 1800x
        payouts[5][3] = 20;
        payouts[5][4] = 150;
        payouts[5][5] = 1500;
        payouts[5][6] = 18000;
        
        // Pick 7: hit 4 = 6x, hit 5 = 40x, hit 6 = 400x, hit 7 = 2500x
        payouts[6][4] = 60;
        payouts[6][5] = 400;
        payouts[6][6] = 4000;
        payouts[6][7] = 25000;
        
        // Pick 8: hit 0 = 10x, hit 5 = 15x, hit 6 = 100x, hit 7 = 800x, hit 8 = 2500x
        payouts[7][0] = 100;
        payouts[7][5] = 150;
        payouts[7][6] = 1000;
        payouts[7][7] = 8000;
        payouts[7][8] = 25000;
        
        // Pick 9: hit 0 = 15x, hit 5 = 5x, hit 6 = 30x, hit 7 = 200x, hit 8 = 1500x, hit 9 = 2500x
        payouts[8][0] = 150;
        payouts[8][5] = 50;
        payouts[8][6] = 300;
        payouts[8][7] = 2000;
        payouts[8][8] = 15000;
        payouts[8][9] = 25000;
        
        // Pick 10: hit 0 = 20x, hit 5 = 2x, hit 6 = 20x, hit 7 = 75x, hit 8 = 500x, hit 9 = 2000x, hit 10 = 2500x
        payouts[9][0] = 200;
        payouts[9][5] = 20;
        payouts[9][6] = 200;
        payouts[9][7] = 750;
        payouts[9][8] = 5000;
        payouts[9][9] = 20000;
        payouts[9][10] = 25000;
    }

    /* ========== BETTING FUNCTIONS ========== */
    
    /// @notice Place a bet on the current round
    /// @param numbers Array of 1-10 numbers (1-80), must be sorted ascending with no duplicates
    /// @param betAmount Amount of USDC to bet (6 decimals)
    /// @return cardId The ID of the card created
    function placeBet(uint8[] calldata numbers, uint256 betAmount) external returns (uint256 cardId) {
        // Validate numbers
        _validateNumbers(numbers);
        
        // Validate bet amount
        if (betAmount < MIN_BET) revert BetTooSmall();
        
        // Check max bet based on pool and actual max payout for this number of picks
        uint16 maxMult = _getMaxMultiplier(uint8(numbers.length));
        uint256 maxPayout = (betAmount * maxMult) / 10; // Divide by 10 since multipliers are scaled
        if (maxPayout > housePool.effectivePool()) revert BetTooLarge();
        
        // Get or start current round
        Round storage round = rounds[currentRound];
        
        if (round.phase == RoundPhase.Idle) {
            // First bet starts the round
            round.phase = RoundPhase.Open;
            round.startTime = block.timestamp;
            emit RoundStarted(currentRound, block.timestamp);
        } else if (round.phase != RoundPhase.Open) {
            revert RoundNotOpen();
        }
        
        // Take payment
        housePool.receivePayment(msg.sender, betAmount);
        
        // Create card
        cardId = round.totalCards;
        cards[currentRound][cardId] = Card({
            player: msg.sender,
            numbers: numbers,
            betAmount: betAmount,
            claimed: false
        });
        
        playerCards[msg.sender][currentRound].push(cardId);
        round.totalCards++;
        round.totalBets += betAmount;
        
        emit BetPlaced(currentRound, cardId, msg.sender, numbers, betAmount);
    }
    
    /// @dev Validate numbers array: 1-10 numbers, values 1-80, sorted ascending, no duplicates
    function _validateNumbers(uint8[] calldata numbers) internal pure {
        uint256 len = numbers.length;
        
        if (len < MIN_PICKS || len > MAX_PICKS) revert InvalidNumberCount();
        
        uint8 prev = 0;
        for (uint256 i = 0; i < len; i++) {
            uint8 num = numbers[i];
            
            if (num < 1 || num > TOTAL_NUMBERS) revert InvalidNumber();
            if (num <= prev) {
                if (num == prev) revert DuplicateNumber();
                revert NumbersNotSorted();
            }
            prev = num;
        }
    }

    /* ========== DEALER FUNCTIONS ========== */
    
    /// @notice Dealer commits to a secret after betting period ends
    /// @param commitHash Hash of dealer's secret: keccak256(abi.encodePacked(secret))
    function commitRound(bytes32 commitHash) external {
        if (msg.sender != dealer) revert NotDealer();
        
        Round storage round = rounds[currentRound];
        if (round.phase != RoundPhase.Open) revert RoundNotOpen();
        if (block.timestamp < round.startTime + BETTING_PERIOD) revert BettingPeriodNotOver();
        
        round.phase = RoundPhase.Committed;
        round.commitBlock = block.number;
        round.commitHash = commitHash;
        
        emit RoundCommitted(currentRound, commitHash, block.number);
    }
    
    /// @notice Dealer reveals secret after 1+ block, within 256 blocks
    /// @param secret The secret that was hashed in commitRound
    function revealRound(bytes32 secret) external {
        if (msg.sender != dealer) revert NotDealer();
        
        Round storage round = rounds[currentRound];
        if (round.phase != RoundPhase.Committed) revert RoundNotCommitted();
        if (block.number <= round.commitBlock) revert TooEarlyToReveal();
        if (keccak256(abi.encodePacked(secret)) != round.commitHash) revert InvalidReveal();
        
        // Get commit block hash (must not be 0)
        bytes32 commitBlockHash = blockhash(round.commitBlock);
        if (commitBlockHash == 0) revert TooLateToReveal();
        
        // Generate entropy from dealer's secret + unknowable commit block hash
        bytes32 entropy = keccak256(abi.encodePacked(secret, commitBlockHash));
        
        // Draw 20 unique winning numbers using Fisher-Yates
        round.winningNumbers = _drawWinningNumbers(entropy);
        round.phase = RoundPhase.Revealed;
        
        emit RoundRevealed(currentRound, round.winningNumbers);
        
        // Start next round
        currentRound++;
    }
    
    /// @dev Draw 20 unique numbers from 1-80 using Fisher-Yates shuffle
    /// @param entropy Random seed from commit-reveal
    /// @return winners Array of 20 unique winning numbers
    function _drawWinningNumbers(bytes32 entropy) internal pure returns (uint8[20] memory winners) {
        // Virtual array: position i initially contains value (i + 1)
        // We only track values that differ from identity mapping
        uint8[80] memory swapped;
        
        for (uint256 i = 0; i < NUMBERS_DRAWN; i++) {
            // Pick random index from remaining pool [i, 79]
            uint256 remaining = TOTAL_NUMBERS - i;
            uint256 pick = i + (uint256(entropy) % remaining);
            entropy = keccak256(abi.encodePacked(entropy));
            
            // Get value at picked position (0 means use index + 1)
            uint8 pickedValue = swapped[pick] == 0 ? uint8(pick + 1) : swapped[pick];
            uint8 currentValue = swapped[i] == 0 ? uint8(i + 1) : swapped[i];
            
            // Swap: move current to picked position
            swapped[pick] = currentValue;
            winners[i] = pickedValue;
        }
    }

    /* ========== CLAIM FUNCTIONS ========== */
    
    /// @notice Claim winnings for a card after round is revealed
    /// @param roundId The round number
    /// @param cardId The card ID within that round
    /// @return payout Amount of USDC won (0 if no win)
    function claimWinnings(uint256 roundId, uint256 cardId) external returns (uint256 payout) {
        Round storage round = rounds[roundId];
        if (round.phase != RoundPhase.Revealed) revert RoundNotRevealed();
        
        Card storage card = cards[roundId][cardId];
        if (card.player == address(0)) revert InvalidCard();
        if (card.claimed) revert CardAlreadyClaimed();
        
        card.claimed = true;
        
        // Count hits
        uint8 hits = _countHits(card.numbers, round.winningNumbers);
        
        // Calculate payout
        uint256 picks = card.numbers.length;
        uint16 multiplier = payouts[picks - 1][hits];
        
        if (multiplier > 0) {
            // Payout = bet * multiplier / 10 (since multipliers are scaled by 10)
            payout = (card.betAmount * multiplier) / 10;
            housePool.payout(card.player, payout);
        }
        
        emit WinningsClaimed(roundId, cardId, card.player, payout, hits);
    }
    
    /// @dev Count how many of the player's numbers match winning numbers
    /// @param playerNums Player's picked numbers (sorted)
    /// @param winningNums The 20 winning numbers (unsorted)
    /// @return hits Number of matches
    function _countHits(uint8[] memory playerNums, uint8[20] memory winningNums) internal pure returns (uint8 hits) {
        // Create bitmap of winning numbers for O(1) lookup
        uint256 winningBitmap = 0;
        for (uint256 i = 0; i < NUMBERS_DRAWN; i++) {
            winningBitmap |= (1 << (winningNums[i] - 1));
        }
        
        // Count matches
        for (uint256 i = 0; i < playerNums.length; i++) {
            if ((winningBitmap >> (playerNums[i] - 1)) & 1 == 1) {
                hits++;
            }
        }
    }

    /* ========== TIMEOUT / REFUND ========== */
    
    /// @notice Refund all bets if dealer times out (doesn't commit/reveal in time)
    /// @dev Anyone can call after timeout period
    function refundRound() external {
        Round storage round = rounds[currentRound];
        
        // Must be in Open or Committed phase
        if (round.phase == RoundPhase.Idle) revert NothingToRefund();
        if (round.phase == RoundPhase.Revealed) revert NothingToRefund();
        
        // Check timeout
        bool canRefund;
        if (round.phase == RoundPhase.Open) {
            // Betting phase timeout uses timestamp
            canRefund = block.timestamp > round.startTime + TIMEOUT_SECONDS;
        } else {
            // Committed phase - check if blockhash expired (uses blocks)
            canRefund = block.number > round.commitBlock + REVEAL_WINDOW;
        }
        
        if (!canRefund) revert TimeoutNotReached();
        
        // Refund all cards
        uint256 totalRefunded = 0;
        for (uint256 i = 0; i < round.totalCards; i++) {
            Card storage card = cards[currentRound][i];
            if (!card.claimed && card.betAmount > 0) {
                card.claimed = true; // Mark as processed
                totalRefunded += card.betAmount;
                housePool.payout(card.player, card.betAmount);
            }
        }
        
        emit RoundRefunded(currentRound, totalRefunded);
        
        // Move to next round
        currentRound++;
    }

    /* ========== VIEW FUNCTIONS ========== */
    
    /// @notice Get current round info
    function getCurrentRound() external view returns (
        uint256 roundId,
        RoundPhase phase,
        uint256 startTime,
        uint256 commitBlock,
        uint256 totalCards,
        uint256 totalBets,
        bool canBet,
        bool canCommit,
        bool canRefund
    ) {
        roundId = currentRound;
        Round storage round = rounds[currentRound];
        phase = round.phase;
        startTime = round.startTime;
        commitBlock = round.commitBlock;
        totalCards = round.totalCards;
        totalBets = round.totalBets;
        
        canBet = phase == RoundPhase.Idle || phase == RoundPhase.Open;
        canCommit = phase == RoundPhase.Open && block.timestamp >= round.startTime + BETTING_PERIOD;
        
        if (phase == RoundPhase.Open) {
            canRefund = block.timestamp > round.startTime + TIMEOUT_SECONDS;
        } else if (phase == RoundPhase.Committed) {
            canRefund = block.number > round.commitBlock + REVEAL_WINDOW;
        }
    }
    
    /// @notice Get winning numbers for a revealed round
    function getWinningNumbers(uint256 roundId) external view returns (uint8[20] memory) {
        if (rounds[roundId].phase != RoundPhase.Revealed) revert RoundNotRevealed();
        return rounds[roundId].winningNumbers;
    }
    
    /// @notice Get a player's card IDs for a round
    function getPlayerCards(address player, uint256 roundId) external view returns (uint256[] memory) {
        return playerCards[player][roundId];
    }
    
    /// @notice Get card details
    function getCard(uint256 roundId, uint256 cardId) external view returns (
        address player,
        uint8[] memory numbers,
        uint256 betAmount,
        bool claimed
    ) {
        Card storage card = cards[roundId][cardId];
        return (card.player, card.numbers, card.betAmount, card.claimed);
    }
    
    /// @notice Check potential payout for a card (after reveal)
    function checkPayout(uint256 roundId, uint256 cardId) external view returns (
        uint8 hits,
        uint256 payout
    ) {
        Round storage round = rounds[roundId];
        if (round.phase != RoundPhase.Revealed) revert RoundNotRevealed();
        
        Card storage card = cards[roundId][cardId];
        if (card.player == address(0)) revert InvalidCard();
        
        hits = _countHits(card.numbers, round.winningNumbers);
        
        uint256 picks = card.numbers.length;
        uint16 multiplier = payouts[picks - 1][hits];
        
        if (multiplier > 0) {
            payout = (card.betAmount * multiplier) / 10;
        }
    }
    
    /// @notice Get payout multiplier for a specific picks/hits combination
    /// @param picks Number of numbers picked (1-10)
    /// @param hits Number of hits (0-10)
    /// @return multiplier Payout multiplier scaled by 10 (e.g., 38 = 3.8x)
    function getPayoutMultiplier(uint8 picks, uint8 hits) external view returns (uint16 multiplier) {
        if (picks < MIN_PICKS || picks > MAX_PICKS) return 0;
        if (hits > picks) return 0;
        return payouts[picks - 1][hits];
    }
    
    /// @dev Get the maximum multiplier for a given number of picks
    /// @param picks Number of numbers picked (1-10)
    /// @return maxMult Maximum possible multiplier (scaled by 10)
    function _getMaxMultiplier(uint8 picks) internal view returns (uint16 maxMult) {
        if (picks < MIN_PICKS || picks > MAX_PICKS) return 0;
        
        // Find the highest multiplier for this number of picks
        uint16[11] storage pickPayouts = payouts[picks - 1];
        for (uint8 i = 0; i <= picks; i++) {
            if (pickPayouts[i] > maxMult) {
                maxMult = pickPayouts[i];
            }
        }
    }
    
    /// @notice Get the maximum multiplier for a given number of picks (public view)
    /// @param picks Number of numbers picked (1-10)
    /// @return maxMult Maximum possible multiplier (scaled by 10)
    function getMaxMultiplier(uint8 picks) external view returns (uint16) {
        return _getMaxMultiplier(picks);
    }
    
    /// @notice Calculate max bet based on current pool (uses most conservative multiplier)
    /// @dev For dynamic max bet based on picks, use maxBetForPicks()
    function maxBet() external view returns (uint256) {
        return housePool.effectivePool() / MAX_MULTIPLIER;
    }
    
    /// @notice Calculate max bet for a specific number of picks
    /// @param picks Number of numbers to pick (1-10)
    /// @return Maximum bet amount in USDC (6 decimals)
    function maxBetForPicks(uint8 picks) external view returns (uint256) {
        uint16 maxMult = _getMaxMultiplier(picks);
        if (maxMult == 0) return 0;
        // effectivePool * 10 / maxMult (since maxMult is scaled by 10)
        return (housePool.effectivePool() * 10) / maxMult;
    }
}

