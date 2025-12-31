"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import type { NextPage } from "next";
import { formatUnits } from "viem";
import { useAccount, useBlockNumber, useReadContract, useWriteContract } from "wagmi";
import { HomeModernIcon } from "@heroicons/react/24/outline";
import { BetPanel, CardData, KenoBoard, PlayerCards, RoundPhase, RoundStatus } from "~~/components/keno";
import { useDeployedContractInfo, useScaffoldReadContract } from "~~/hooks/scaffold-eth";

// USDC has 6 decimals
const USDC_DECIMALS = 6;

// Base USDC address
const USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";

// USDC ABI for approve and balance
const USDC_ABI = [
  {
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

// Constants from contract
const BETTING_PERIOD_BLOCKS = 30;

// BasedKeno ABI (minimal - for functions we need before deploy regenerates deployedContracts.ts)
const BASED_KENO_ABI = [
  {
    inputs: [],
    name: "housePool",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "maxBet",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getCurrentRound",
    outputs: [
      { name: "roundId", type: "uint256" },
      { name: "phase", type: "uint8" },
      { name: "startBlock", type: "uint256" },
      { name: "commitBlock", type: "uint256" },
      { name: "totalCards", type: "uint256" },
      { name: "totalBets", type: "uint256" },
      { name: "canBet", type: "bool" },
      { name: "canCommit", type: "bool" },
      { name: "canRefund", type: "bool" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "roundId", type: "uint256" }],
    name: "getWinningNumbers",
    outputs: [{ name: "", type: "uint8[20]" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "player", type: "address" },
      { name: "roundId", type: "uint256" },
    ],
    name: "getPlayerCards",
    outputs: [{ name: "", type: "uint256[]" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "numbers", type: "uint8[]" },
      { name: "betAmount", type: "uint256" },
    ],
    name: "placeBet",
    outputs: [{ name: "cardId", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "roundId", type: "uint256" },
      { name: "cardId", type: "uint256" },
    ],
    name: "claimWinnings",
    outputs: [{ name: "payout", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

// Placeholder address until deployed - will be replaced by deployedContracts.ts
const BASED_KENO_ADDRESS = "0x0000000000000000000000000000000000000000";

const Home: NextPage = () => {
  const { address: connectedAddress } = useAccount();

  // State for number selection
  const [selectedNumbers, setSelectedNumbers] = useState<number[]>([]);
  const [isWaitingForApproval, setIsWaitingForApproval] = useState(false);
  const [isClaimingCard, setIsClaimingCard] = useState<bigint | null>(null);
  const [playerCards, setPlayerCards] = useState<CardData[]>([]);

  // Get current block number
  const { data: blockNumber } = useBlockNumber({ watch: true });

  // Get deployed contract addresses
  const { data: housePoolContractInfo } = useDeployedContractInfo({ contractName: "HousePool" });
  const housePoolAddress = housePoolContractInfo?.address;

  // BasedKeno address - will be populated when contracts are deployed
  // For now, we check if BasedKeno exists in deployed contracts
  const { data: basedKenoContractInfo } = useDeployedContractInfo({
    contractName: "BasedKeno" as "HousePool",
  });
  const basedKenoAddress = basedKenoContractInfo?.address || BASED_KENO_ADDRESS;

  // Read pool stats
  const { data: effectivePool, refetch: refetchEffectivePool } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "effectivePool",
  });

  // Read max bet
  const { data: maxBetData, refetch: refetchMaxBet } = useReadContract({
    address: basedKenoAddress as `0x${string}`,
    abi: BASED_KENO_ABI,
    functionName: "maxBet",
  });

  // Read current round info
  const { data: currentRoundData, refetch: refetchCurrentRound } = useReadContract({
    address: basedKenoAddress as `0x${string}`,
    abi: BASED_KENO_ABI,
    functionName: "getCurrentRound",
  });

  // Read user USDC balance
  const { data: userUsdcBalance, refetch: refetchUserUsdcBalance } = useReadContract({
    address: USDC_ADDRESS,
    abi: USDC_ABI,
    functionName: "balanceOf",
    args: connectedAddress ? [connectedAddress] : undefined,
  });

  // Read player's cards for current round
  const { data: playerCardIds, refetch: refetchPlayerCardIds } = useReadContract({
    address: basedKenoAddress as `0x${string}`,
    abi: BASED_KENO_ABI,
    functionName: "getPlayerCards",
    args: connectedAddress && currentRoundData ? [connectedAddress, currentRoundData[0]] : undefined,
  });

  // Read winning numbers (only when round is revealed)
  const roundId = currentRoundData ? currentRoundData[0] : 0n;

  // For revealed rounds, get winning numbers from previous round
  const { data: winningNumbersData } = useReadContract({
    address: basedKenoAddress as `0x${string}`,
    abi: BASED_KENO_ABI,
    functionName: "getWinningNumbers",
    args: roundId > 0n ? [roundId - 1n] : undefined,
  });

  // Write hooks
  const { writeContractAsync: writeBasedKeno, isPending: isBasedKenoWritePending } = useWriteContract();
  const { writeContractAsync: writeUsdc, isPending: isUsdcWritePending } = useWriteContract();

  // Parse round data
  const currentRound = {
    roundId: currentRoundData?.[0] ?? 0n,
    phase: (currentRoundData?.[1] ?? 0) as RoundPhase,
    startBlock: currentRoundData?.[2] ?? 0n,
    commitBlock: currentRoundData?.[3] ?? 0n,
    totalCards: currentRoundData?.[4] ?? 0n,
    totalBets: currentRoundData?.[5] ?? 0n,
    canBet: currentRoundData?.[6] ?? false,
    canCommit: currentRoundData?.[7] ?? false,
    canRefund: currentRoundData?.[8] ?? false,
  };

  // Parse winning numbers (convert from fixed array to regular array)
  const winningNumbers: number[] = winningNumbersData ? Array.from(winningNumbersData).filter(n => n > 0) : [];

  // Refetch all data
  const refetchAll = useCallback(() => {
    refetchEffectivePool();
    refetchMaxBet();
    refetchCurrentRound();
    refetchUserUsdcBalance();
    refetchPlayerCardIds();
  }, [refetchEffectivePool, refetchMaxBet, refetchCurrentRound, refetchUserUsdcBalance, refetchPlayerCardIds]);

  // Auto-refresh data
  useEffect(() => {
    const interval = setInterval(refetchAll, 5000);
    return () => clearInterval(interval);
  }, [refetchAll]);

  // Fetch card details when player card IDs change
  useEffect(() => {
    const fetchCardDetails = async () => {
      if (!playerCardIds || playerCardIds.length === 0) {
        setPlayerCards([]);
        return;
      }

      const cards: CardData[] = [];
      for (const cardId of playerCardIds) {
        try {
          // We need to call getCard for each card ID - using raw contract read
          // For now, we'll just track the card IDs and show basic info
          cards.push({
            cardId,
            numbers: [], // Will be filled in when we have more contract reads
            betAmount: 0n,
            claimed: false,
          });
        } catch (e) {
          console.error("Error fetching card:", e);
        }
      }
      setPlayerCards(cards);
    };

    fetchCardDetails();
  }, [playerCardIds, currentRound.roundId]);

  // Toggle number selection
  const toggleNumber = (num: number) => {
    setSelectedNumbers(prev => {
      if (prev.includes(num)) {
        return prev.filter(n => n !== num);
      }
      if (prev.length >= 10) return prev;
      return [...prev, num].sort((a, b) => a - b);
    });
  };

  // Quick pick random numbers
  const quickPick = () => {
    const count = Math.floor(Math.random() * 6) + 5; // 5-10 numbers
    const numbers: number[] = [];
    while (numbers.length < count) {
      const num = Math.floor(Math.random() * 80) + 1;
      if (!numbers.includes(num)) {
        numbers.push(num);
      }
    }
    setSelectedNumbers(numbers.sort((a, b) => a - b));
  };

  // Clear selection
  const clearSelection = () => {
    setSelectedNumbers([]);
  };

  // Place bet
  const handlePlaceBet = async (amount: bigint) => {
    if (!housePoolAddress || selectedNumbers.length === 0) return;

    try {
      // Approve USDC
      await writeUsdc({
        address: USDC_ADDRESS,
        abi: USDC_ABI,
        functionName: "approve",
        args: [housePoolAddress, amount],
      });

      setIsWaitingForApproval(true);
      await new Promise(resolve => setTimeout(resolve, 3000));
      setIsWaitingForApproval(false);

      // Place bet - convert numbers to uint8 array
      const numbersAsUint8 = selectedNumbers.map(n => n);

      await writeBasedKeno({
        address: basedKenoAddress as `0x${string}`,
        abi: BASED_KENO_ABI,
        functionName: "placeBet",
        args: [numbersAsUint8, amount],
      });

      setSelectedNumbers([]);
      refetchAll();
    } catch (error) {
      console.error("Place bet failed:", error);
      setIsWaitingForApproval(false);
    }
  };

  // Claim winnings
  const handleClaimCard = async (cardId: bigint) => {
    if (!currentRound.roundId) return;

    try {
      setIsClaimingCard(cardId);

      // Claim from previous round (since current round advances after reveal)
      const claimRoundId = currentRound.roundId > 0n ? currentRound.roundId - 1n : 0n;

      await writeBasedKeno({
        address: basedKenoAddress as `0x${string}`,
        abi: BASED_KENO_ABI,
        functionName: "claimWinnings",
        args: [claimRoundId, cardId],
      });

      refetchAll();
    } catch (error) {
      console.error("Claim failed:", error);
    } finally {
      setIsClaimingCard(null);
    }
  };

  const isLoading = isBasedKenoWritePending || isUsdcWritePending || isWaitingForApproval;

  // Format helpers
  const formatUsdc = (value: bigint | undefined) =>
    value ? parseFloat(formatUnits(value, USDC_DECIMALS)).toLocaleString(undefined, { maximumFractionDigits: 2 }) : "0";

  // Determine if we should show results (from previous round)
  const showResults = roundId > 0n && winningNumbers.length > 0;

  return (
    <div className="flex flex-col items-center min-h-screen bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-violet-900/20 via-base-100 to-base-100">
      {/* Hero Section */}
      <div className="flex flex-col items-center justify-center px-5 py-8 w-full">
        <h1 className="text-5xl font-black mb-2 tracking-tight">
          <span className="bg-gradient-to-r from-cyan-400 via-violet-500 to-fuchsia-500 bg-clip-text text-transparent">
            🎱 Based Keno
          </span>
        </h1>
        <p className="text-base-content/60 mb-4 text-center max-w-md">
          Pick up to 10 numbers. Match the 20 drawn to win up to 2500x your bet!
        </p>

        {/* Pool Display */}
        <div className="bg-base-100/80 backdrop-blur rounded-xl px-6 py-2 border border-base-300">
          <span className="text-sm text-base-content/50">House Pool: </span>
          <span className="font-bold text-lg">${formatUsdc(effectivePool)}</span>
        </div>
      </div>

      {/* Main Content */}
      <div className="w-full max-w-5xl px-4 pb-12">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Left Column - Keno Board */}
          <div className="lg:col-span-2">
            <KenoBoard
              selectedNumbers={selectedNumbers}
              winningNumbers={showResults ? winningNumbers : []}
              onToggleNumber={toggleNumber}
              disabled={!currentRound.canBet || isLoading}
              maxPicks={10}
              showResults={showResults}
            />

            {/* Winning Numbers Display (when revealed) */}
            {showResults && (
              <div className="mt-4 bg-gradient-to-r from-amber-500/10 to-yellow-500/10 rounded-xl p-4 border border-amber-500/20">
                <h3 className="font-bold text-amber-400 mb-2">🎯 Last Round&apos;s Winning Numbers</h3>
                <div className="flex flex-wrap gap-2">
                  {winningNumbers.map((num, idx) => (
                    <span
                      key={idx}
                      className="inline-flex items-center justify-center w-8 h-8 text-sm font-bold rounded-lg bg-gradient-to-br from-amber-400 to-yellow-500 text-amber-900"
                    >
                      {num}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Right Column - Controls */}
          <div className="space-y-4">
            {/* User Balance */}
            {connectedAddress && (
              <div className="bg-gradient-to-br from-green-500/10 to-emerald-500/10 rounded-xl px-4 py-3 border border-green-500/20">
                <div className="flex items-center gap-3">
                  <div className="text-2xl">💵</div>
                  <div>
                    <p className="text-xs text-base-content/60 uppercase tracking-wide">Your USDC</p>
                    <p className="text-xl font-bold text-green-400">
                      ${formatUsdc(userUsdcBalance as bigint | undefined)}
                    </p>
                  </div>
                </div>
              </div>
            )}

            {/* Round Status */}
            <RoundStatus
              roundId={currentRound.roundId}
              phase={currentRound.phase}
              startBlock={currentRound.startBlock}
              totalCards={currentRound.totalCards}
              totalBets={currentRound.totalBets}
              currentBlock={blockNumber ?? 0n}
              bettingPeriodBlocks={BETTING_PERIOD_BLOCKS}
            />

            {/* Bet Panel */}
            <BetPanel
              selectedNumbers={selectedNumbers}
              maxBet={maxBetData ?? 0n}
              userBalance={(userUsdcBalance as bigint) ?? 0n}
              onPlaceBet={handlePlaceBet}
              onQuickPick={quickPick}
              onClearSelection={clearSelection}
              isLoading={isLoading}
              disabled={!currentRound.canBet || !connectedAddress}
            />

            {/* Player Cards */}
            {connectedAddress && playerCards.length > 0 && (
              <PlayerCards
                cards={playerCards}
                winningNumbers={winningNumbers}
                roundRevealed={showResults}
                onClaimCard={handleClaimCard}
                isClaimingCard={isClaimingCard}
              />
            )}
          </div>
        </div>
      </div>

      {/* Link to House */}
      <div className="text-center pb-12">
        <p className="text-base-content/50 mb-3">Want to be the house instead?</p>
        <Link href="/house" className="btn btn-outline gap-2">
          <HomeModernIcon className="h-5 w-5" />
          Manage House Pool
        </Link>
      </div>
    </div>
  );
};

export default Home;
