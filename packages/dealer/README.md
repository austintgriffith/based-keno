# Keno Dealer Script

Automated commit-reveal dealer for BasedKeno contract.

## Setup

1. Install dependencies:
```bash
yarn install
```

2. Create `.env` file with:
```
# Dealer private key (required) - the account set as dealer in BasedKeno
DEALER_PRIVATE_KEY=0x...

# Chain ID (optional, defaults to 31337 for local foundry)
# Use 8453 for Base mainnet
CHAIN_ID=31337

# RPC URL (optional)
# Defaults to http://127.0.0.1:8545 for local, or public Base RPC for mainnet
RPC_URL=http://127.0.0.1:8545
```

## Usage

From the monorepo root:

```bash
# Run dealer
yarn dealer

# Or from this directory
yarn start
```

## How It Works

1. Polls `getCurrentRound()` every 2 seconds
2. When `canCommit` is true (betting period over):
   - Generates random 32-byte secret
   - Computes `commitHash = keccak256(secret)`
   - Calls `commitRound(commitHash)`
3. Waits for next block
4. Calls `revealRound(secret)` to complete the round

