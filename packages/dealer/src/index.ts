import "dotenv/config";
import {
  createPublicClient,
  createWalletClient,
  http,
  keccak256,
  toHex,
  getAddress,
  type Abi,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { getConfig } from "./config.js";

// RoundPhase enum values (matches contract enum)
const RoundPhase = {
  Idle: 0,
  Open: 1,
  Committed: 2,
  Revealed: 3,
} as const;

// Configuration
const POLL_INTERVAL_MS = 2000; // 2 seconds
const REVEAL_DELAY_MS = 3000; // Wait 3 seconds after commit before revealing

// State for pending commits
let pendingSecret: `0x${string}` | null = null;
let pendingRoundId: bigint | null = null;
let commitBlockNumber: bigint | null = null;

// Store the contract ABI globally after loading
let contractAbi: Abi;

async function main() {
  const config = getConfig();

  // Store the dynamically loaded ABI
  contractAbi = config.contractAbi as Abi;

  console.log("🎲 Keno Dealer Starting...");
  console.log(`   Chain: ${config.chain.name} (${config.chainId})`);
  console.log(`   Contract: ${config.contractAddress}`);
  console.log(`   RPC: ${config.rpcUrl}`);

  // Create clients
  const account = privateKeyToAccount(config.privateKey);
  console.log(`   Dealer Address: ${account.address}`);

  const publicClient = createPublicClient({
    chain: config.chain,
    transport: http(config.rpcUrl),
  });

  const walletClient = createWalletClient({
    account,
    chain: config.chain,
    transport: http(config.rpcUrl),
  });

  // Verify dealer address matches contract
  const contractDealer = await publicClient.readContract({
    address: config.contractAddress,
    abi: contractAbi,
    functionName: "dealer",
  });

  if (getAddress(contractDealer as string) !== getAddress(account.address)) {
    console.error(`❌ Error: Account ${account.address} is not the dealer`);
    console.error(`   Contract dealer: ${contractDealer}`);
    process.exit(1);
  }

  console.log("✅ Dealer address verified");
  console.log("🔄 Starting dealer loop...\n");

  // Main loop
  while (true) {
    try {
      await runDealerCycle(publicClient, walletClient, config.contractAddress);
    } catch (error) {
      console.error("❌ Error in dealer cycle:", error);
    }

    await sleep(POLL_INTERVAL_MS);
  }
}

async function runDealerCycle(
  publicClient: ReturnType<typeof createPublicClient>,
  walletClient: ReturnType<typeof createWalletClient>,
  contractAddress: `0x${string}`
) {
  // Get current round info
  const roundInfo = (await publicClient.readContract({
    address: contractAddress,
    abi: contractAbi,
    functionName: "getCurrentRound",
  })) as [
    bigint,
    number,
    bigint,
    bigint,
    bigint,
    bigint,
    boolean,
    boolean,
    boolean
  ];

  const [
    roundId,
    phase,
    startTime,
    commitBlock,
    totalCards,
    totalBets,
    canBet,
    canCommit,
    canRefund,
  ] = roundInfo;

  const phaseNames = ["Idle", "Open", "Committed", "Revealed"];
  const phaseName = phaseNames[phase] || "Unknown";

  // Log status
  const now = new Date().toLocaleTimeString();

  if (phase === RoundPhase.Open && totalCards > 0n) {
    const elapsed = BigInt(Math.floor(Date.now() / 1000)) - startTime;
    console.log(
      `[${now}] Round ${roundId}: ${phaseName} | Cards: ${totalCards} | Bets: ${formatUsdc(
        totalBets
      )} | Elapsed: ${elapsed}s | canCommit: ${canCommit}`
    );
  } else if (phase === RoundPhase.Committed) {
    console.log(
      `[${now}] Round ${roundId}: ${phaseName} | Waiting to reveal...`
    );
  } else if (phase === RoundPhase.Idle) {
    // Silent when idle - no bets yet
  }

  // Handle state transitions
  if (phase === RoundPhase.Open && canCommit) {
    // Time to commit!
    await doCommit(walletClient, publicClient, contractAddress, roundId);
  } else if (
    phase === RoundPhase.Committed &&
    pendingSecret &&
    pendingRoundId === roundId
  ) {
    // We have a pending commit, check if we can reveal
    const currentBlock = await publicClient.getBlockNumber();

    if (commitBlockNumber && currentBlock > commitBlockNumber) {
      // At least 1 block has passed, reveal
      await doReveal(walletClient, contractAddress, roundId);
    }
  }

  // Clear stale pending state if round has moved on
  if (pendingRoundId !== null && pendingRoundId < roundId) {
    console.log(`⚠️ Clearing stale pending state from round ${pendingRoundId}`);
    pendingSecret = null;
    pendingRoundId = null;
    commitBlockNumber = null;
  }
}

async function doCommit(
  walletClient: ReturnType<typeof createWalletClient>,
  publicClient: ReturnType<typeof createPublicClient>,
  contractAddress: `0x${string}`,
  roundId: bigint
) {
  console.log(`\n🔐 Committing round ${roundId}...`);

  // Generate random secret
  const secret = generateRandomSecret();
  const commitHash = keccak256(secret);

  console.log(`   Secret: ${secret.slice(0, 10)}...`);
  console.log(`   Hash: ${commitHash.slice(0, 10)}...`);

  try {
    // @ts-expect-error - Dynamic ABI doesn't provide full type inference
    const hash = await walletClient.writeContract({
      address: contractAddress,
      abi: contractAbi,
      functionName: "commitRound",
      args: [commitHash],
    });

    console.log(`   Tx: ${hash}`);

    // Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash });

    if (receipt.status === "success") {
      console.log(`✅ Committed at block ${receipt.blockNumber}`);

      // Store for reveal
      pendingSecret = secret;
      pendingRoundId = roundId;
      commitBlockNumber = receipt.blockNumber;
    } else {
      console.error("❌ Commit transaction failed");
    }
  } catch (error) {
    console.error("❌ Commit error:", error);
  }
}

async function doReveal(
  walletClient: ReturnType<typeof createWalletClient>,
  contractAddress: `0x${string}`,
  roundId: bigint
) {
  if (!pendingSecret) {
    console.error("❌ No pending secret to reveal");
    return;
  }

  console.log(`\n🎰 Revealing round ${roundId}...`);
  console.log(`   Secret: ${pendingSecret.slice(0, 10)}...`);

  // Small delay to ensure block is mined
  await sleep(REVEAL_DELAY_MS);

  try {
    // @ts-expect-error - Dynamic ABI doesn't provide full type inference
    const hash = await walletClient.writeContract({
      address: contractAddress,
      abi: contractAbi,
      functionName: "revealRound",
      args: [pendingSecret],
    });

    console.log(`   Tx: ${hash}`);
    console.log(`✅ Round ${roundId} revealed!\n`);

    // Clear pending state
    pendingSecret = null;
    pendingRoundId = null;
    commitBlockNumber = null;
  } catch (error) {
    console.error("❌ Reveal error:", error);
  }
}

function generateRandomSecret(): `0x${string}` {
  // Generate 32 random bytes
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return toHex(bytes);
}

function formatUsdc(amount: bigint): string {
  const value = Number(amount) / 1e6;
  return `$${value.toFixed(2)}`;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Start
main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
