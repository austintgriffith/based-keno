"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import type { NextPage } from "next";
import { formatUnits } from "viem";
import { useAccount } from "wagmi";
import { ChevronLeftIcon, ChevronRightIcon, HomeModernIcon } from "@heroicons/react/24/outline";
import { BetPanel, CardData, KenoBoard, PlayerCards, RoundPhase, RoundStatus } from "~~/components/keno";
import {
  useDeployedContractInfo,
  useScaffoldContract,
  useScaffoldReadContract,
  useScaffoldWriteContract,
} from "~~/hooks/scaffold-eth";

// USDC has 6 decimals
const USDC_DECIMALS = 6;

// Constants from contract (in seconds, not blocks!)
const BETTING_PERIOD_SECONDS = 30;

const Home: NextPage = () => {
  const { address: connectedAddress } = useAccount();

  // State for number selection
  const [selectedNumbers, setSelectedNumbers] = useState<number[]>([]);
  const [isWaitingForApproval, setIsWaitingForApproval] = useState(false);
  const [isClaimingCard, setIsClaimingCard] = useState<bigint | null>(null);

  // Round navigation state
  const [viewedRoundId, setViewedRoundId] = useState<bigint | null>(null);
  const [playerRoundIds, setPlayerRoundIds] = useState<bigint[]>([]);
  const [isDiscoveringRounds, setIsDiscoveringRounds] = useState(false);

  // Viewed round data state
  const [viewedRoundCards, setViewedRoundCards] = useState<CardData[]>([]);
  const [viewedRoundWinningNumbers, setViewedRoundWinningNumbers] = useState<number[]>([]);
  const [viewedRoundInfo, setViewedRoundInfo] = useState<{
    phase: RoundPhase;
    totalCards: bigint;
    totalBets: bigint;
    startTime: bigint;
  } | null>(null);

  // Get contract addresses and contract instance
  const { data: housePoolContractInfo } = useDeployedContractInfo({ contractName: "HousePool" });
  const housePoolAddress = housePoolContractInfo?.address;

  // Get BasedKeno contract for direct reads
  const { data: basedKenoContract } = useScaffoldContract({ contractName: "BasedKeno" });

  // Read pool stats
  const { data: effectivePool, refetch: refetchEffectivePool } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "effectivePool",
  });

  // Read current round info from contract
  const { data: currentRoundData, refetch: refetchCurrentRound } = useScaffoldReadContract({
    contractName: "BasedKeno",
    functionName: "getCurrentRound",
  });

  // Read user USDC balance
  const { data: userUsdcBalance, refetch: refetchUserUsdcBalance } = useScaffoldReadContract({
    contractName: "USDC",
    functionName: "balanceOf",
    args: [connectedAddress],
  });

  // Get the current (live) round ID from contract
  const liveRoundId = currentRoundData ? currentRoundData[0] : 0n;

  // Write hooks
  const { writeContractAsync: writeBasedKeno, isPending: isBasedKenoWritePending } =
    useScaffoldWriteContract("BasedKeno");
  const { writeContractAsync: writeUsdc, isPending: isUsdcWritePending } = useScaffoldWriteContract("USDC");

  // Parse live round data
  const liveRound = {
    roundId: currentRoundData?.[0] ?? 0n,
    phase: (currentRoundData?.[1] ?? 0) as RoundPhase,
    startTime: currentRoundData?.[2] ?? 0n,
    commitBlock: currentRoundData?.[3] ?? 0n,
    totalCards: currentRoundData?.[4] ?? 0n,
    totalBets: currentRoundData?.[5] ?? 0n,
    canBet: currentRoundData?.[6] ?? false,
    canCommit: currentRoundData?.[7] ?? false,
    canRefund: currentRoundData?.[8] ?? false,
  };

  // Determine if viewing the live round
  const isViewingLiveRound = viewedRoundId === null || viewedRoundId === liveRoundId;

  // Current displayed round info (either viewed historical or live)
  const displayedRound = isViewingLiveRound
    ? liveRound
    : {
        roundId: viewedRoundId!,
        phase: viewedRoundInfo?.phase ?? (0 as RoundPhase),
        startTime: viewedRoundInfo?.startTime ?? 0n,
        totalCards: viewedRoundInfo?.totalCards ?? 0n,
        totalBets: viewedRoundInfo?.totalBets ?? 0n,
        canBet: false, // Historical rounds cannot accept bets
      };

  // Refetch core data
  const refetchAll = useCallback(() => {
    refetchEffectivePool();
    refetchCurrentRound();
    refetchUserUsdcBalance();
  }, [refetchEffectivePool, refetchCurrentRound, refetchUserUsdcBalance]);

  // Auto-refresh data
  useEffect(() => {
    const interval = setInterval(refetchAll, 5000);
    return () => clearInterval(interval);
  }, [refetchAll]);

  // Refs to prevent infinite loops when fetching
  const lastDiscoveredKey = useRef<string>("");
  const lastFetchedViewedKey = useRef<string>("");
  const isFetchingViewed = useRef(false);
  const lastKnownLiveRoundId = useRef<bigint | null>(null);

  // When liveRoundId changes (a round was revealed), reset fetch key to refetch viewed round data
  // This ensures winning numbers appear when the round you're viewing gets revealed
  useEffect(() => {
    if (lastKnownLiveRoundId.current !== null && lastKnownLiveRoundId.current !== liveRoundId) {
      // Live round changed - reset fetch key to get updated data (including winning numbers)
      lastFetchedViewedKey.current = "";
    }
    lastKnownLiveRoundId.current = liveRoundId;
  }, [liveRoundId]);

  // Discover rounds where player has cards
  useEffect(() => {
    const discoverPlayerRounds = async () => {
      if (!basedKenoContract || !connectedAddress || liveRoundId === undefined) return;

      const discoveryKey = `${connectedAddress}-${liveRoundId.toString()}`;
      if (lastDiscoveredKey.current === discoveryKey || isDiscoveringRounds) return;

      setIsDiscoveringRounds(true);
      const foundRounds: bigint[] = [];

      // Scan from round 0 to current round
      for (let i = 0n; i <= liveRoundId; i++) {
        try {
          const cards = await basedKenoContract.read.getPlayerCards([connectedAddress, i]);
          if (cards && cards.length > 0) {
            foundRounds.push(i);
          }
        } catch {
          // Skip rounds that fail
        }
      }

      // Always include live round in navigation (even if no cards yet)
      if (!foundRounds.includes(liveRoundId)) {
        foundRounds.push(liveRoundId);
      }

      // Sort ascending
      foundRounds.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

      setPlayerRoundIds(foundRounds);
      lastDiscoveredKey.current = discoveryKey;
      setIsDiscoveringRounds(false);

      // Default to viewing live round
      if (viewedRoundId === null) {
        setViewedRoundId(liveRoundId);
      }
    };

    discoverPlayerRounds();
  }, [basedKenoContract, connectedAddress, liveRoundId, viewedRoundId, isDiscoveringRounds]);

  // Fetch data for the viewed round
  useEffect(() => {
    const fetchViewedRoundData = async () => {
      if (!basedKenoContract || viewedRoundId === null || !connectedAddress) return;

      const fetchKey = `${connectedAddress}-${viewedRoundId.toString()}`;
      if (lastFetchedViewedKey.current === fetchKey || isFetchingViewed.current) return;

      isFetchingViewed.current = true;

      try {
        // Fetch round info using the rounds mapping
        // Returns: [phase, startTime, commitBlock, commitHash, totalCards, totalBets]
        const roundData = await basedKenoContract.read.rounds([viewedRoundId]);
        const [phase, startTime, , , totalCards, totalBets] = roundData;

        setViewedRoundInfo({
          phase: phase as RoundPhase,
          startTime: startTime ?? 0n,
          totalCards: totalCards ?? 0n,
          totalBets: totalBets ?? 0n,
        });

        // Fetch winning numbers if round is revealed (phase === 3)
        let winningNums: number[] = [];
        if (phase === 3) {
          try {
            const nums = await basedKenoContract.read.getWinningNumbers([viewedRoundId]);
            winningNums = Array.from(nums).filter(n => n > 0);
          } catch {
            // Round not revealed yet
          }
        }
        setViewedRoundWinningNumbers(winningNums);

        // Fetch player's cards for this round
        const cardIds = await basedKenoContract.read.getPlayerCards([connectedAddress, viewedRoundId]);
        const cards: CardData[] = [];

        for (const cardId of cardIds) {
          try {
            const cardData = await basedKenoContract.read.getCard([viewedRoundId, cardId]);
            const [, numbers, betAmount, claimed] = cardData;

            let hits = 0;
            let payout = 0n;

            // Get payout info if round is revealed
            if (phase === 3) {
              try {
                const payoutData = await basedKenoContract.read.checkPayout([viewedRoundId, cardId]);
                hits = payoutData[0];
                payout = payoutData[1];
              } catch {
                // checkPayout will revert if round not revealed
              }
            }

            cards.push({
              cardId,
              numbers: Array.from(numbers),
              betAmount,
              claimed,
              hits,
              payout,
            });
          } catch (e) {
            console.error("Error fetching card:", e);
          }
        }

        setViewedRoundCards(cards);
        lastFetchedViewedKey.current = fetchKey;
      } catch (e) {
        console.error("Error fetching viewed round data:", e);
      } finally {
        isFetchingViewed.current = false;
      }
    };

    fetchViewedRoundData();
  }, [basedKenoContract, viewedRoundId, connectedAddress]);

  // Navigation handlers
  const navigateToPreviousRound = () => {
    if (viewedRoundId === null) return;
    const currentIndex = playerRoundIds.findIndex(id => id === viewedRoundId);
    if (currentIndex > 0) {
      lastFetchedViewedKey.current = ""; // Force refetch
      setViewedRoundId(playerRoundIds[currentIndex - 1]);
    }
  };

  const navigateToNextRound = () => {
    if (viewedRoundId === null) return;
    const currentIndex = playerRoundIds.findIndex(id => id === viewedRoundId);
    if (currentIndex < playerRoundIds.length - 1) {
      lastFetchedViewedKey.current = ""; // Force refetch
      setViewedRoundId(playerRoundIds[currentIndex + 1]);
    }
  };

  // Check navigation availability
  const currentNavIndex = playerRoundIds.findIndex(id => id === viewedRoundId);
  const canGoBack = currentNavIndex > 0;
  const canGoForward = currentNavIndex < playerRoundIds.length - 1;

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
      // Approve USDC to HousePool
      await writeUsdc({
        functionName: "approve",
        args: [housePoolAddress, amount],
      });

      setIsWaitingForApproval(true);
      await new Promise(resolve => setTimeout(resolve, 3000));
      setIsWaitingForApproval(false);

      // Place bet
      const numbersAsUint8 = selectedNumbers.map(n => n);

      await writeBasedKeno({
        functionName: "placeBet",
        args: [numbersAsUint8, amount],
      });

      setSelectedNumbers([]);

      // Reset discovery to include new round if needed
      lastDiscoveredKey.current = "";
      lastFetchedViewedKey.current = "";
      refetchAll();
    } catch (error) {
      console.error("Place bet failed:", error);
      setIsWaitingForApproval(false);
    }
  };

  // Claim winnings
  const handleClaimCard = async (cardId: bigint) => {
    if (viewedRoundId === null) return;

    try {
      setIsClaimingCard(cardId);

      await writeBasedKeno({
        functionName: "claimWinnings",
        args: [viewedRoundId, cardId],
      });

      // Reset fetch key so card details get refetched with updated claimed status
      lastFetchedViewedKey.current = "";
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

  // Determine what to show
  const showWinningNumbers = !isViewingLiveRound && viewedRoundWinningNumbers.length > 0;
  const isRoundRevealed = viewedRoundInfo?.phase === 3;

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

      {/* Round Navigation */}
      {connectedAddress && playerRoundIds.length > 0 && (
        <div className="w-full max-w-5xl px-4 mb-4">
          <div className="bg-base-100/80 backdrop-blur rounded-xl px-4 py-3 border border-base-300 flex items-center justify-between">
            {/* Previous Button */}
            <button
              onClick={navigateToPreviousRound}
              disabled={!canGoBack}
              className="btn btn-ghost btn-sm gap-1 disabled:opacity-30"
            >
              <ChevronLeftIcon className="h-5 w-5" />
              Previous
            </button>

            {/* Round Indicator */}
            <div className="flex items-center gap-3">
              <span className="text-lg font-bold">Round #{viewedRoundId?.toString() ?? "0"}</span>
              {isViewingLiveRound ? (
                <span className="badge badge-success badge-sm animate-pulse">LIVE</span>
              ) : (
                <span className="badge badge-ghost badge-sm">{isRoundRevealed ? "Completed" : "In Progress"}</span>
              )}
              {playerRoundIds.length > 1 && (
                <span className="text-xs text-base-content/50">
                  ({currentNavIndex + 1} of {playerRoundIds.length})
                </span>
              )}
            </div>

            {/* Next Button */}
            <button
              onClick={navigateToNextRound}
              disabled={!canGoForward}
              className="btn btn-ghost btn-sm gap-1 disabled:opacity-30"
            >
              Next
              <ChevronRightIcon className="h-5 w-5" />
            </button>
          </div>
        </div>
      )}

      {/* Main Content */}
      <div className="w-full max-w-5xl px-4 pb-12">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Left Column - Keno Board */}
          <div className="lg:col-span-2">
            <KenoBoard
              selectedNumbers={isViewingLiveRound ? selectedNumbers : []}
              winningNumbers={showWinningNumbers ? viewedRoundWinningNumbers : []}
              onToggleNumber={isViewingLiveRound ? toggleNumber : () => {}}
              disabled={!isViewingLiveRound || !liveRound.canBet || isLoading}
              maxPicks={10}
              showResults={showWinningNumbers}
            />

            {/* Winning Numbers Display (for historical revealed rounds) */}
            {showWinningNumbers && (
              <div className="mt-4 bg-gradient-to-r from-amber-500/10 to-yellow-500/10 rounded-xl p-4 border border-amber-500/20">
                <h3 className="font-bold text-amber-400 mb-2">🎯 Winning Numbers</h3>
                <div className="flex flex-wrap gap-2">
                  {viewedRoundWinningNumbers.map((num, idx) => (
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

            {/* Historical Round Notice */}
            {!isViewingLiveRound && (
              <div className="mt-4 bg-base-200/50 rounded-xl p-4 border border-base-300 text-center">
                <p className="text-base-content/60">
                  You are viewing a past round. Navigate to the latest round to place new bets.
                </p>
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
                    <p className="text-xl font-bold text-green-400">${formatUsdc(userUsdcBalance)}</p>
                  </div>
                </div>
              </div>
            )}

            {/* Round Status */}
            <RoundStatus
              roundId={displayedRound.roundId}
              phase={displayedRound.phase}
              startTime={displayedRound.startTime}
              totalCards={displayedRound.totalCards}
              totalBets={displayedRound.totalBets}
              bettingPeriodSeconds={BETTING_PERIOD_SECONDS}
              isHistorical={!isViewingLiveRound}
            />

            {/* Bet Panel - Only show for live round */}
            {isViewingLiveRound && (
              <BetPanel
                selectedNumbers={selectedNumbers}
                effectivePool={effectivePool ?? 0n}
                userBalance={userUsdcBalance ?? 0n}
                onPlaceBet={handlePlaceBet}
                onQuickPick={quickPick}
                onClearSelection={clearSelection}
                isLoading={isLoading}
                disabled={!liveRound.canBet || !connectedAddress}
              />
            )}

            {/* Player Cards for Viewed Round */}
            {connectedAddress && viewedRoundCards.length > 0 && (
              <div>
                <h3 className="font-bold text-lg mb-2">{isViewingLiveRound ? "🎫 Your Cards" : "🎯 Your Cards"}</h3>
                <PlayerCards
                  cards={viewedRoundCards}
                  winningNumbers={isRoundRevealed ? viewedRoundWinningNumbers : []}
                  roundRevealed={isRoundRevealed}
                  onClaimCard={handleClaimCard}
                  isClaimingCard={isClaimingCard}
                />
              </div>
            )}

            {/* No cards message for historical rounds */}
            {!isViewingLiveRound && viewedRoundCards.length === 0 && (
              <div className="bg-base-200/50 rounded-xl p-4 border border-base-300 text-center">
                <p className="text-base-content/50">No cards in this round</p>
              </div>
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
