"use client";

import { useState } from "react";
import { formatUnits, parseUnits } from "viem";
import { ArrowPathIcon, InformationCircleIcon, SparklesIcon } from "@heroicons/react/24/outline";

// Payout multipliers from the contract (scaled by 10)
// payouts[picks-1][hits] = multiplier * 10
const PAYOUT_TABLE: { [picks: number]: { [hits: number]: number } } = {
  1: { 1: 38 },
  2: { 2: 150 },
  3: { 2: 20, 3: 650 },
  4: { 2: 10, 3: 80, 4: 3000 },
  5: { 3: 40, 4: 500, 5: 10000 },
  6: { 3: 20, 4: 150, 5: 1500, 6: 18000 },
  7: { 4: 60, 5: 400, 6: 4000, 7: 25000 },
  8: { 0: 100, 5: 150, 6: 1000, 7: 8000, 8: 25000 },
  9: { 0: 150, 5: 50, 6: 300, 7: 2000, 8: 15000, 9: 25000 },
  10: { 0: 200, 5: 20, 6: 200, 7: 750, 8: 5000, 9: 20000, 10: 25000 },
};

interface BetPanelProps {
  selectedNumbers: number[];
  maxBet: bigint;
  userBalance: bigint;
  onPlaceBet: (amount: bigint) => Promise<void>;
  onQuickPick: () => void;
  onClearSelection: () => void;
  isLoading: boolean;
  disabled?: boolean;
}

export const BetPanel = ({
  selectedNumbers,
  maxBet,
  userBalance,
  onPlaceBet,
  onQuickPick,
  onClearSelection,
  isLoading,
  disabled = false,
}: BetPanelProps) => {
  const [betAmount, setBetAmount] = useState("");
  const [showPayoutTable, setShowPayoutTable] = useState(false);

  const picks = selectedNumbers.length;
  const hasValidPicks = picks >= 1 && picks <= 10;

  // Calculate potential max win for current picks
  const getMaxMultiplier = (numPicks: number): number => {
    if (numPicks < 1 || numPicks > 10) return 0;
    const pickPayouts = PAYOUT_TABLE[numPicks];
    return Math.max(...Object.values(pickPayouts)) / 10;
  };

  const maxMultiplier = getMaxMultiplier(picks);

  // Format values
  const formatUsdc = (value: bigint) =>
    parseFloat(formatUnits(value, 6)).toLocaleString(undefined, { maximumFractionDigits: 2 });

  const betAmountBigInt = betAmount ? parseUnits(betAmount, 6) : 0n;
  const potentialWin = betAmount ? (parseFloat(betAmount) * maxMultiplier).toFixed(2) : "0";

  const canBet =
    hasValidPicks &&
    betAmountBigInt > 0n &&
    betAmountBigInt <= maxBet &&
    betAmountBigInt <= userBalance &&
    betAmountBigInt >= parseUnits("0.1", 6); // MIN_BET = 0.1 USDC

  const handlePlaceBet = async () => {
    if (!canBet) return;
    await onPlaceBet(betAmountBigInt);
    setBetAmount("");
  };

  // Get payout info for display
  const getPayoutInfo = () => {
    if (picks < 1 || picks > 10) return [];
    const pickPayouts = PAYOUT_TABLE[picks];
    return Object.entries(pickPayouts)
      .map(([hits, mult]) => ({
        hits: parseInt(hits),
        multiplier: mult / 10,
      }))
      .sort((a, b) => a.hits - b.hits);
  };

  return (
    <div className="bg-base-100 rounded-2xl p-5 border border-base-300 shadow-lg">
      {/* Selection Summary */}
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="font-bold text-lg">Your Selection</h3>
          <p className="text-sm text-base-content/60">
            {picks > 0 ? (
              <span className="font-mono">{selectedNumbers.sort((a, b) => a - b).join(", ")}</span>
            ) : (
              "No numbers selected"
            )}
          </p>
        </div>
        <div className="flex gap-2">
          <button
            onClick={onQuickPick}
            disabled={disabled}
            className="btn btn-sm btn-ghost gap-1"
            title="Random selection"
          >
            <ArrowPathIcon className="h-4 w-4" />
            Quick Pick
          </button>
          <button
            onClick={onClearSelection}
            disabled={disabled || picks === 0}
            className="btn btn-sm btn-ghost text-error"
          >
            Clear
          </button>
        </div>
      </div>

      {/* Bet Input */}
      <div className="space-y-3">
        <div className="flex gap-2">
          <div className="form-control flex-1">
            <label className="label py-1">
              <span className="label-text text-sm">Bet Amount (USDC)</span>
              <span className="label-text-alt text-xs">Max: ${formatUsdc(maxBet)}</span>
            </label>
            <input
              type="number"
              className="input input-bordered w-full"
              placeholder="0.10"
              value={betAmount}
              onChange={e => setBetAmount(e.target.value)}
              disabled={disabled || !hasValidPicks}
              min="0.1"
              step="0.1"
            />
          </div>
          <button
            className="btn btn-ghost btn-sm self-end mb-1"
            onClick={() => {
              const max = maxBet < userBalance ? maxBet : userBalance;
              setBetAmount(formatUnits(max, 6));
            }}
            disabled={disabled || !hasValidPicks}
          >
            MAX
          </button>
        </div>

        {/* Potential Win Display */}
        {hasValidPicks && betAmount && parseFloat(betAmount) > 0 && (
          <div className="bg-gradient-to-r from-amber-500/10 to-yellow-500/10 rounded-xl p-3 border border-amber-500/20">
            <div className="flex justify-between items-center">
              <span className="text-sm text-base-content/70">Max potential win:</span>
              <span className="font-bold text-lg text-amber-400">${potentialWin}</span>
            </div>
            <p className="text-xs text-base-content/50 mt-1">
              If all {picks} numbers hit ({maxMultiplier}x)
            </p>
          </div>
        )}

        {/* Payout Table Toggle */}
        <button
          onClick={() => setShowPayoutTable(!showPayoutTable)}
          className="btn btn-ghost btn-xs gap-1 text-base-content/60"
        >
          <InformationCircleIcon className="h-4 w-4" />
          {showPayoutTable ? "Hide" : "Show"} Payout Table
        </button>

        {/* Payout Table */}
        {showPayoutTable && hasValidPicks && (
          <div className="bg-base-200 rounded-lg p-3 text-sm">
            <p className="font-semibold mb-2">Payouts for {picks} picks:</p>
            <div className="grid grid-cols-2 gap-1">
              {getPayoutInfo().map(({ hits, multiplier }) => (
                <div key={hits} className="flex justify-between px-2 py-1 rounded bg-base-100/50">
                  <span className="text-base-content/60">{hits} hits:</span>
                  <span className="font-bold text-primary">{multiplier}x</span>
                </div>
              ))}
            </div>
            {picks >= 8 && (
              <p className="text-xs text-amber-500 mt-2">✨ Catch-0 pays {PAYOUT_TABLE[picks][0] / 10}x!</p>
            )}
          </div>
        )}

        {/* Place Bet Button */}
        <button
          onClick={handlePlaceBet}
          disabled={!canBet || isLoading || disabled}
          className="btn btn-primary w-full gap-2 text-lg"
        >
          {isLoading ? (
            <>
              <span className="loading loading-spinner loading-md"></span>
              Placing Bet...
            </>
          ) : (
            <>
              <SparklesIcon className="h-5 w-5" />
              Place Bet {betAmount && `($${betAmount})`}
            </>
          )}
        </button>

        {/* Validation Messages */}
        {!hasValidPicks && <p className="text-xs text-warning text-center">Select 1-10 numbers to bet</p>}
        {hasValidPicks && betAmountBigInt > maxBet && (
          <p className="text-xs text-error text-center">Bet exceeds maximum allowed (${formatUsdc(maxBet)})</p>
        )}
        {hasValidPicks && betAmountBigInt > userBalance && (
          <p className="text-xs text-error text-center">Insufficient USDC balance</p>
        )}
      </div>
    </div>
  );
};
