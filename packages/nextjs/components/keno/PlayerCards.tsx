"use client";

import { formatUnits } from "viem";
import { CheckCircleIcon, ClockIcon, TrophyIcon, XCircleIcon } from "@heroicons/react/24/outline";

export interface CardData {
  cardId: bigint;
  numbers: number[];
  betAmount: bigint;
  claimed: boolean;
  hits?: number;
  payout?: bigint;
}

interface PlayerCardsProps {
  cards: CardData[];
  winningNumbers: number[];
  roundRevealed: boolean;
  onClaimCard: (cardId: bigint) => Promise<void>;
  isClaimingCard: bigint | null;
}

export const PlayerCards = ({
  cards,
  winningNumbers,
  roundRevealed,
  onClaimCard,
  isClaimingCard,
}: PlayerCardsProps) => {
  const formatUsdc = (value: bigint) =>
    parseFloat(formatUnits(value, 6)).toLocaleString(undefined, { maximumFractionDigits: 2 });

  const countHits = (numbers: number[]): number => {
    return numbers.filter(n => winningNumbers.includes(n)).length;
  };

  const getCardStatus = (card: CardData) => {
    if (card.claimed) {
      return {
        label: "Claimed",
        color: "text-base-content/50",
        bgColor: "bg-base-200",
        borderColor: "border-base-content/10",
        icon: <CheckCircleIcon className="h-5 w-5" />,
      };
    }

    if (!roundRevealed) {
      return {
        label: "Pending",
        color: "text-warning",
        bgColor: "bg-warning/10",
        borderColor: "border-warning/30",
        icon: <ClockIcon className="h-5 w-5" />,
      };
    }

    const hits = countHits(card.numbers);
    const hasPayout = card.payout && card.payout > 0n;

    if (hasPayout) {
      return {
        label: `${hits} Hits - Winner!`,
        color: "text-success",
        bgColor: "bg-success/10",
        borderColor: "border-success/30",
        icon: <TrophyIcon className="h-5 w-5" />,
      };
    }

    return {
      label: `${hits} Hits - No Win`,
      color: "text-error/70",
      bgColor: "bg-error/5",
      borderColor: "border-error/20",
      icon: <XCircleIcon className="h-5 w-5" />,
    };
  };

  if (cards.length === 0) {
    return (
      <div className="bg-base-100 rounded-xl p-6 border border-base-300 text-center">
        <p className="text-base-content/50">No cards this round</p>
        <p className="text-sm text-base-content/40 mt-1">Place a bet to get started!</p>
      </div>
    );
  }

  // Calculate totals for claim all
  const unclaimedWinners = cards.filter(c => !c.claimed && c.payout && c.payout > 0n);
  const totalPayout = unclaimedWinners.reduce((sum, c) => sum + (c.payout || 0n), 0n);

  return (
    <div className="space-y-3">
      <div className="flex justify-between items-center">
        <h3 className="font-bold text-lg">Your Cards</h3>
        <span className="text-sm text-base-content/60">
          {cards.length} card{cards.length !== 1 ? "s" : ""}
        </span>
      </div>

      {/* Card List */}
      <div className="space-y-2 max-h-64 overflow-y-auto pr-1">
        {cards.map(card => {
          const status = getCardStatus(card);
          const isWinner = card.payout && card.payout > 0n;
          const isClaiming = isClaimingCard === card.cardId;

          return (
            <div
              key={card.cardId.toString()}
              className={`rounded-xl p-3 border ${status.bgColor} ${status.borderColor}`}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 min-w-0">
                  {/* Card Header */}
                  <div className="flex items-center gap-2 mb-1">
                    <span className={status.color}>{status.icon}</span>
                    <span className={`text-sm font-semibold ${status.color}`}>{status.label}</span>
                  </div>

                  {/* Numbers */}
                  <div className="flex flex-wrap gap-1 mb-2">
                    {card.numbers.map(num => {
                      const isHit = roundRevealed && winningNumbers.includes(num);
                      return (
                        <span
                          key={num}
                          className={`inline-flex items-center justify-center w-7 h-7 text-xs font-bold rounded ${
                            isHit
                              ? "bg-success text-success-content"
                              : roundRevealed
                                ? "bg-error/20 text-error"
                                : "bg-base-300 text-base-content/70"
                          }`}
                        >
                          {num}
                        </span>
                      );
                    })}
                  </div>

                  {/* Bet Amount */}
                  <p className="text-xs text-base-content/60">Bet: ${formatUsdc(card.betAmount)}</p>
                </div>

                {/* Claim Button or Payout Display */}
                <div className="text-right">
                  {roundRevealed && !card.claimed && isWinner && (
                    <div>
                      <p className="text-lg font-bold text-success">${formatUsdc(card.payout!)}</p>
                      <button
                        onClick={() => onClaimCard(card.cardId)}
                        disabled={isClaiming}
                        className="btn btn-success btn-xs mt-1"
                      >
                        {isClaiming ? <span className="loading loading-spinner loading-xs"></span> : "Claim"}
                      </button>
                    </div>
                  )}
                  {card.claimed && card.payout && card.payout > 0n && (
                    <p className="text-sm text-base-content/50">Won ${formatUsdc(card.payout)}</p>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Claim All Button */}
      {roundRevealed && unclaimedWinners.length > 1 && (
        <button
          onClick={async () => {
            for (const card of unclaimedWinners) {
              await onClaimCard(card.cardId);
            }
          }}
          className="btn btn-success w-full gap-2"
          disabled={isClaimingCard !== null}
        >
          <TrophyIcon className="h-5 w-5" />
          Claim All (${formatUsdc(totalPayout)})
        </button>
      )}
    </div>
  );
};
