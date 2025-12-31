"use client";

import { useCallback } from "react";

interface KenoBoardProps {
  selectedNumbers: number[];
  winningNumbers?: number[];
  onToggleNumber: (num: number) => void;
  disabled?: boolean;
  maxPicks?: number;
  showResults?: boolean;
}

export const KenoBoard = ({
  selectedNumbers,
  winningNumbers = [],
  onToggleNumber,
  disabled = false,
  maxPicks = 10,
  showResults = false,
}: KenoBoardProps) => {
  const isSelected = useCallback((num: number) => selectedNumbers.includes(num), [selectedNumbers]);
  const isWinning = useCallback((num: number) => winningNumbers.includes(num), [winningNumbers]);

  const getNumberState = (num: number) => {
    const selected = isSelected(num);
    const winning = isWinning(num);

    if (showResults) {
      if (selected && winning) return "hit"; // Player picked and it won
      if (selected && !winning) return "miss"; // Player picked but didn't win
      if (winning) return "winning"; // Winning number (not picked)
    }

    if (selected) return "selected";
    return "default";
  };

  const getNumberStyles = (state: string) => {
    const base =
      "w-10 h-10 sm:w-11 sm:h-11 rounded-lg font-bold text-sm sm:text-base transition-all duration-200 border-2 flex items-center justify-center cursor-pointer select-none";

    switch (state) {
      case "hit":
        return `${base} bg-gradient-to-br from-emerald-500 to-green-600 border-emerald-300 text-white shadow-lg shadow-emerald-500/50 animate-pulse scale-110 z-10`;
      case "miss":
        return `${base} bg-gradient-to-br from-red-500/30 to-red-600/30 border-red-400/50 text-red-300 opacity-60`;
      case "winning":
        return `${base} bg-gradient-to-br from-amber-400 to-yellow-500 border-yellow-300 text-amber-900 shadow-lg shadow-amber-400/50`;
      case "selected":
        return `${base} bg-gradient-to-br from-cyan-500 to-blue-600 border-cyan-300 text-white shadow-lg shadow-cyan-500/40 scale-105`;
      default:
        return `${base} bg-base-300/80 border-base-content/10 text-base-content/70 hover:bg-base-300 hover:border-cyan-400/50 hover:text-base-content`;
    }
  };

  const handleClick = (num: number) => {
    if (disabled) return;

    // Don't allow selecting more if at max (unless deselecting)
    if (!isSelected(num) && selectedNumbers.length >= maxPicks) return;

    onToggleNumber(num);
  };

  // Generate 80 numbers in 8 rows of 10
  const rows = Array.from({ length: 8 }, (_, rowIndex) =>
    Array.from({ length: 10 }, (_, colIndex) => rowIndex * 10 + colIndex + 1),
  );

  return (
    <div className="bg-gradient-to-br from-base-200 to-base-300 rounded-2xl p-4 sm:p-6 border border-base-content/10 shadow-xl">
      {/* Board Header */}
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-lg font-bold text-base-content/80">Pick Your Numbers</h3>
        <div className="flex items-center gap-2">
          <span
            className={`text-sm font-mono ${selectedNumbers.length >= maxPicks ? "text-warning" : "text-base-content/60"}`}
          >
            {selectedNumbers.length}/{maxPicks}
          </span>
        </div>
      </div>

      {/* Number Grid */}
      <div className="grid gap-1.5 sm:gap-2">
        {rows.map((row, rowIndex) => (
          <div key={rowIndex} className="flex gap-1.5 sm:gap-2 justify-center">
            {row.map(num => {
              const state = getNumberState(num);
              return (
                <button
                  key={num}
                  onClick={() => handleClick(num)}
                  disabled={disabled && state === "default"}
                  className={getNumberStyles(state)}
                  style={{
                    animationDelay: showResults && isWinning(num) ? `${winningNumbers.indexOf(num) * 100}ms` : "0ms",
                  }}
                >
                  {num}
                </button>
              );
            })}
          </div>
        ))}
      </div>

      {/* Legend */}
      {showResults && (
        <div className="flex flex-wrap justify-center gap-4 mt-4 text-xs">
          <div className="flex items-center gap-1.5">
            <div className="w-4 h-4 rounded bg-gradient-to-br from-emerald-500 to-green-600 border border-emerald-300"></div>
            <span className="text-base-content/60">Hit!</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-4 h-4 rounded bg-gradient-to-br from-amber-400 to-yellow-500 border border-yellow-300"></div>
            <span className="text-base-content/60">Winning</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-4 h-4 rounded bg-gradient-to-br from-red-500/30 to-red-600/30 border border-red-400/50"></div>
            <span className="text-base-content/60">Miss</span>
          </div>
        </div>
      )}
    </div>
  );
};
