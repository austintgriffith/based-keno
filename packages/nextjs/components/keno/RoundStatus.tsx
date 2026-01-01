"use client";

import { useEffect, useState } from "react";
import { formatUnits } from "viem";
import { CheckCircleIcon, ClockIcon, CubeIcon, SparklesIcon } from "@heroicons/react/24/outline";

// Round phases from contract
export enum RoundPhase {
  Idle = 0,
  Open = 1,
  Committed = 2,
  Revealed = 3,
}

interface RoundStatusProps {
  roundId: bigint;
  phase: RoundPhase;
  startTime: bigint; // Unix timestamp in seconds
  totalCards: bigint;
  totalBets: bigint;
  bettingPeriodSeconds: number;
  isHistorical?: boolean;
}

export const RoundStatus = ({
  roundId,
  phase,
  startTime,
  totalCards,
  totalBets,
  bettingPeriodSeconds,
  isHistorical = false,
}: RoundStatusProps) => {
  const [secondsRemaining, setSecondsRemaining] = useState(0);

  useEffect(() => {
    if (phase === RoundPhase.Open && startTime > 0n) {
      const updateRemaining = () => {
        const now = Math.floor(Date.now() / 1000);
        const endTime = Number(startTime) + bettingPeriodSeconds;
        const remaining = endTime - now;
        setSecondsRemaining(Math.max(0, remaining));
      };

      // Update immediately
      updateRemaining();

      // Update every second
      const interval = setInterval(updateRemaining, 1000);
      return () => clearInterval(interval);
    } else {
      setSecondsRemaining(0);
    }
  }, [phase, startTime, bettingPeriodSeconds]);

  const getPhaseInfo = () => {
    // For historical rounds, show simplified status
    if (isHistorical) {
      if (phase === RoundPhase.Revealed) {
        return {
          label: "Completed",
          color: "text-info",
          bgColor: "bg-info/10",
          borderColor: "border-info/30",
          icon: <CheckCircleIcon className="h-5 w-5" />,
          description: "Round complete. Claim any unclaimed winnings!",
        };
      }
      // Historical but not revealed (shouldn't happen normally)
      return {
        label: "Past Round",
        color: "text-base-content/50",
        bgColor: "bg-base-300/50",
        borderColor: "border-base-content/20",
        icon: <ClockIcon className="h-5 w-5" />,
        description: "This round is no longer active.",
      };
    }

    // Live round status
    switch (phase) {
      case RoundPhase.Idle:
        return {
          label: "Waiting for Players",
          color: "text-base-content/50",
          bgColor: "bg-base-300/50",
          borderColor: "border-base-content/20",
          icon: <ClockIcon className="h-5 w-5" />,
          description: "Place a bet to start the round!",
        };
      case RoundPhase.Open:
        return {
          label: "Betting Open",
          color: "text-success",
          bgColor: "bg-success/10",
          borderColor: "border-success/30",
          icon: <SparklesIcon className="h-5 w-5 animate-pulse" />,
          description: secondsRemaining > 0 ? `${secondsRemaining}s remaining to bet` : "Waiting for dealer...",
        };
      case RoundPhase.Committed:
        return {
          label: "Drawing Soon",
          color: "text-warning",
          bgColor: "bg-warning/10",
          borderColor: "border-warning/30",
          icon: <CubeIcon className="h-5 w-5 animate-spin" />,
          description: "Dealer committed, waiting for reveal...",
        };
      case RoundPhase.Revealed:
        return {
          label: "Results Ready",
          color: "text-primary",
          bgColor: "bg-primary/10",
          borderColor: "border-primary/30",
          icon: <CheckCircleIcon className="h-5 w-5" />,
          description: "Check your cards and claim winnings!",
        };
      default:
        return {
          label: "Unknown",
          color: "text-base-content/50",
          bgColor: "bg-base-300/50",
          borderColor: "border-base-content/20",
          icon: <ClockIcon className="h-5 w-5" />,
          description: "",
        };
    }
  };

  const phaseInfo = getPhaseInfo();

  // Format total bets (USDC has 6 decimals)
  const formatUsdc = (value: bigint) =>
    parseFloat(formatUnits(value, 6)).toLocaleString(undefined, { maximumFractionDigits: 2 });

  return (
    <div className={`rounded-xl p-4 border-2 ${phaseInfo.bgColor} ${phaseInfo.borderColor}`}>
      {/* Phase Header */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <span className={phaseInfo.color}>{phaseInfo.icon}</span>
          <span className={`font-bold ${phaseInfo.color}`}>{phaseInfo.label}</span>
        </div>
        <span className="text-xs text-base-content/50 font-mono">Round #{roundId.toString()}</span>
      </div>

      {/* Progress Bar for Open phase (live rounds only) */}
      {!isHistorical && phase === RoundPhase.Open && secondsRemaining > 0 && (
        <div className="mb-3">
          <div className="h-2 bg-base-300 rounded-full overflow-hidden">
            <div
              className="h-full bg-gradient-to-r from-success to-emerald-400 transition-all duration-1000"
              style={{ width: `${(secondsRemaining / bettingPeriodSeconds) * 100}%` }}
            />
          </div>
          <p className="text-xs text-base-content/50 mt-1 text-center">{secondsRemaining}s remaining</p>
        </div>
      )}

      {/* Phase Description */}
      <p className="text-sm text-base-content/60 mb-3">{phaseInfo.description}</p>

      {/* Round Stats */}
      <div className="grid grid-cols-2 gap-2 text-center">
        <div className="bg-base-100/50 rounded-lg p-2">
          <p className="text-xs text-base-content/50">Cards</p>
          <p className="font-bold text-lg">{totalCards.toString()}</p>
        </div>
        <div className="bg-base-100/50 rounded-lg p-2">
          <p className="text-xs text-base-content/50">Total Bets</p>
          <p className="font-bold text-lg">${formatUsdc(totalBets)}</p>
        </div>
      </div>
    </div>
  );
};
