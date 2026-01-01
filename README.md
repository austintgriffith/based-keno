# 🎱 Based Keno

> A provably fair Keno game on Base with USDC betting and DeFi yield on the house pool.

Deposit USDC to become the house. HOUSE tokens = ownership. Idle funds auto-invest in Summer.fi to earn yield while waiting for bets.

## How Keno Works

1. **Pick 1-10 numbers** from 1-80
2. **Place your bet** in USDC
3. **Wait for the round** - betting is open for ~1 minute
4. **Dealer draws 20 numbers** using commit-reveal randomness
5. **Collect winnings** if your numbers hit!

### Payout Table (~3% House Edge)

| Picks | Hits to Win | Max Payout |
| ----- | ----------- | ---------- |
| 1     | 1           | 3.8x       |
| 2     | 2           | 15x        |
| 3     | 2-3         | 65x        |
| 4     | 2-4         | 300x       |
| 5     | 3-5         | 1000x      |
| 6     | 3-6         | 1800x      |
| 7     | 4-7         | 2500x      |
| 8     | 0, 5-8      | 2500x      |
| 9     | 0, 5-9      | 2500x      |
| 10    | 0, 5-10     | 2500x      |

_Picking 8-10 numbers? Catching ZERO also pays!_

## Architecture

Based Keno separates concerns into three immutable contracts:

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                                                                  │
│   ┌─────────────────────┐         ┌─────────────────────────────┐               │
│   │      BasedKeno      │────────▶│         HousePool           │               │
│   │   (Game Logic)      │         │     (Liquidity Pool)        │               │
│   └─────────────────────┘         └──────────────┬──────────────┘               │
│            │                                      │                              │
│    - Round management                            │                              │
│    - Commit/Reveal randomness                    ▼                              │
│    - Fisher-Yates shuffle         ┌─────────────────────────────┐               │
│    - Payout calculations          │       VaultManager          │               │
│                                   │   (DeFi Yield Strategy)     │               │
│                                   └──────────────┬──────────────┘               │
│                                                  │                               │
│                                   - Deposits idle USDC                          │
│                                   - Summer.fi FleetCommander                    │
│                                   - Earns LVUSDC yield                          │
│                                                  │                               │
│                                                  ▼                               │
│                                   ┌─────────────────────────────┐               │
│                                   │    Summer.fi LVUSDC Vault   │               │
│                                   │     (External Protocol)     │               │
│                                   └─────────────────────────────┘               │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### BasedKeno.sol

The game contract handles all Keno logic:

- **Round-based gameplay** - Idle → Open (betting) → Committed → Revealed
- **Commit-reveal randomness** - Dealer commits hash, reveals after 1 block
- **Virtual Fisher-Yates shuffle** - Generates 20 unique winning numbers from 1-80
- **Payout matrix** - Hypergeometric distribution with ~3% house edge
- **Max bet enforcement** - `bet * maxMultiplier <= effectivePool`

### HousePool.sol

The liquidity pool contract:

- **Issues HOUSE tokens** (ERC20) representing pool ownership
- **Auto-invests USDC** - all idle USDC deposited into VaultManager for yield
- **Delayed withdrawals** - 10 sec cooldown prevents front-running
- **`payout()` function** - only callable by the immutable game contract
- **Yield-aware accounting** - share price reflects total value (liquid + vault)

### VaultManager.sol

The DeFi yield strategy contract:

- **Integrates with Summer.fi** FleetCommander (LVUSDC) vault on Base
- **Automatic deposits** - HousePool sends all USDC here for yield generation
- **On-demand withdrawals** - pulls funds back when needed for payouts
- **One-time HousePool linkage** - immutable connection, no admin keys

## How It Works

### For Players

1. **Select numbers** - Pick 1-10 numbers from the 80-number board
2. **Place bet** - Enter USDC amount (min $0.10, max based on pool size)
3. **Wait for draw** - Betting window closes, dealer commits then reveals
4. **Check results** - 20 winning numbers are drawn
5. **Claim winnings** - If your numbers hit, collect your payout!

**Round Flow:**

```
Idle ──▶ Open (1 min) ──▶ Committed ──▶ Revealed ──▶ Idle
         (place bets)     (1 block)    (claim)
```

### For LPs (House Owners)

1. **Deposit USDC** → Receive HOUSE tokens at current share price
2. **Hold** → Earn from gambling losses + DeFi yield (Summer.fi)
3. **Withdraw** → Request withdrawal (10 sec cooldown) → Execute within 1 min window

```
Total Value = Liquid USDC + Vault Value (with accrued yield)
Share Price = Total Value / Total HOUSE Supply
Your Value  = Your HOUSE × Share Price
```

**Yield Sources:**

- 🎱 **Gambling Edge** - ~3% house edge on all bets
- 📈 **DeFi Yield** - Summer.fi FleetCommander vault returns

### Withdrawal Cooldown

To prevent front-running (LP sees winning reveal → tries to withdraw):

```
Request Withdrawal → 10 sec cooldown → 1 min window to execute → expires
```

If you don't execute within the window, request expires and you keep your HOUSE tokens.

## Contracts

### BasedKeno.sol

| Function                          | Description                           |
| --------------------------------- | ------------------------------------- |
| `placeBet(numbers[], amount)`     | Place a bet with selected numbers     |
| `commitRound(hash)`               | Dealer commits randomness hash        |
| `revealRound(secret)`             | Dealer reveals, draws winning numbers |
| `claimWinnings(roundId, cardId)`  | Claim winnings for a winning card     |
| `getCurrentRound()`               | Get current round state               |
| `getWinningNumbers(roundId)`      | Get 20 winning numbers for a round    |
| `getPlayerCards(player, roundId)` | Get player's card IDs for a round     |
| `maxBet()`                        | Maximum allowed bet (pool / 2500)     |

**Constants:**

| Constant              | Value      | Description              |
| --------------------- | ---------- | ------------------------ |
| MIN_BET               | $0.10 USDC | Minimum bet amount       |
| MAX_PICKS             | 10         | Maximum numbers per card |
| TOTAL_NUMBERS         | 80         | Numbers to choose from   |
| DRAW_COUNT            | 20         | Numbers drawn per round  |
| BETTING_PERIOD        | 30 blocks  | ~1 minute betting window |
| MAX_PAYOUT_MULTIPLIER | 2500x      | Limits max bet size      |

### HousePool.sol

**LP Functions:**

| Function                            | Description                                       |
| ----------------------------------- | ------------------------------------------------- |
| `deposit(usdcAmount)`               | Deposit USDC, receive HOUSE shares (auto-invests) |
| `deposit(usdcAmount, minSharesOut)` | Deposit with slippage protection                  |
| `requestWithdrawal(shares)`         | Start 10 sec cooldown                             |
| `withdraw()`                        | Execute within 1 min window                       |
| `withdraw(minUsdcOut)`              | Execute with slippage protection                  |
| `cancelWithdrawal()`                | Cancel pending request                            |

**View Functions:**

| Function             | Description                                   |
| -------------------- | --------------------------------------------- |
| `totalPool()`        | Total USDC value (liquid + vault)             |
| `effectivePool()`    | Total pool minus pending withdrawal value     |
| `sharePrice()`       | Current USDC per HOUSE (18 decimal precision) |
| `usdcValue(address)` | USDC value of an LP's holdings                |

### VaultManager.sol

| Function                    | Description                       |
| --------------------------- | --------------------------------- |
| `getCurrentValue()`         | USDC value of vault position      |
| `depositIntoVault(amount)`  | Deposit USDC into Summer.fi vault |
| `withdrawFromVault(amount)` | Withdraw USDC from vault          |

## Quickstart

1. Clone the repo (with submodules):

```bash
git clone --recurse-submodules https://github.com/YOUR_USERNAME/based-keno.git
cd based-keno
```

> **Note:** If you already cloned without `--recurse-submodules`, run: `git submodule update --init --recursive`

2. Install dependencies:

```bash
yarn install
```

3. Fork Base mainnet locally (required for Summer.fi vault integration):

```bash
yarn fork --network base
```

4. Deploy contracts:

```bash
yarn deploy
```

5. Start the frontend:

```bash
yarn start
```

Visit `http://localhost:3000` to play Based Keno!

> **Note:** The DeFi yield integration uses Summer.fi's FleetCommander vault (LVUSDC) which is deployed on Base. When running locally, you must fork Base mainnet to interact with the real vault contract.

## Testing

```bash
cd packages/foundry
forge test -vv
```

**47 tests covering:**

- BasedKeno: Round flow, betting, commit-reveal, payouts
- HousePool: Deposits, withdrawals, share calculations, vault integration
- VaultManager: Summer.fi deposits/withdrawals, yield accounting
- Security: Front-running protection, authorization checks, attack vectors

## Project Structure

```
packages/
├── foundry/
│   ├── contracts/
│   │   ├── BasedKeno.sol     # Keno game logic, round management
│   │   ├── HousePool.sol     # Liquidity pool, HOUSE token, auto-invests
│   │   └── VaultManager.sol  # DeFi yield strategy (Summer.fi)
│   ├── script/
│   │   └── Deploy.s.sol      # Deployment script
│   └── test/
│       ├── HousePool.t.sol       # Main test suite
│       └── HousePoolAttacks.t.sol # Security tests
└── nextjs/
    ├── app/
    │   ├── page.tsx          # Keno game UI
    │   └── house/            # LP management UI
    └── components/
        └── keno/             # Keno-specific components
            ├── KenoBoard.tsx     # 80-number selection grid
            ├── RoundStatus.tsx   # Round phase display
            ├── BetPanel.tsx      # Bet input & payouts
            └── PlayerCards.tsx   # Card management
```

## Key Design Decisions

1. **Three contracts, immutable linkage**: BasedKeno deploys VaultManager and HousePool, linking them together. No admin functions, no way to change relationships.

2. **Round-based gameplay**: Rounds have distinct phases (Idle → Open → Committed → Revealed) to ensure fair play and prevent manipulation.

3. **Virtual Fisher-Yates shuffle**: Draws 20 unique winning numbers deterministically from commit + blockhash, using only ~1KB of memory.

4. **Hypergeometric payouts**: Mathematically fair payouts based on probability of catching X numbers out of 20 drawn from 80, with ~3% house edge.

5. **Auto-invest strategy**: All idle USDC automatically deposited to Summer.fi vault. Withdrawals happen on-demand when funds are needed.

6. **Dealer role**: A designated dealer address manages commit-reveal. Could be an EOA, multisig, or automated keeper.

7. **Max bet protection**: `maxBet = effectivePool / MAX_PAYOUT_MULTIPLIER` ensures the house can always pay winners.

## License

MIT
