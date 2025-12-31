"use client";

import { useCallback, useEffect, useState } from "react";
import type { NextPage } from "next";
import { formatUnits, keccak256, parseUnits, toHex } from "viem";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import {
  ArrowPathIcon,
  BanknotesIcon,
  ClockIcon,
  CubeIcon,
  MinusCircleIcon,
  PlusCircleIcon,
  SparklesIcon,
} from "@heroicons/react/24/outline";
import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

// USDC has 6 decimals, HOUSE has 18 decimals
const USDC_DECIMALS = 6;
const HOUSE_DECIMALS = 18;

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

const HousePage: NextPage = () => {
  const { address: connectedAddress } = useAccount();

  // State for user inputs
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawShares, setWithdrawShares] = useState("");
  const [gamblingSecret, setGamblingSecret] = useState("");
  const [pendingSecret, setPendingSecret] = useState<string | null>(null);

  // Get contract info
  const { data: housePoolContract } = useDeployedContractInfo({ contractName: "HousePool" });

  // Read pool stats
  const { data: totalPool, refetch: refetchTotalPool } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "totalPool",
  });

  const { data: effectivePool, refetch: refetchEffectivePool } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "effectivePool",
  });

  const { data: sharePrice, refetch: refetchSharePrice } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "sharePrice",
  });

  const { data: canRoll, refetch: refetchCanRoll } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "canRoll",
  });

  const { refetch: refetchTotalPendingShares } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "totalPendingShares",
  });

  // Read USDC address from contract
  const { data: usdcAddress } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "usdc",
  });

  // Read user balances
  const { data: userHouseBalance, refetch: refetchUserHouseBalance } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "balanceOf",
    args: [connectedAddress],
  });

  const { data: userUsdcValue, refetch: refetchUserUsdcValue } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "usdcValue",
    args: [connectedAddress],
  });

  const { data: userUsdcBalance, refetch: refetchUserUsdcBalance } = useReadContract({
    address: usdcAddress,
    abi: USDC_ABI,
    functionName: "balanceOf",
    args: connectedAddress ? [connectedAddress] : undefined,
  });

  // Read withdrawal request
  const { data: withdrawalRequest, refetch: refetchWithdrawalRequest } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "getWithdrawalRequest",
    args: [connectedAddress],
  });

  // Read commitment
  const { data: commitment, refetch: refetchCommitment } = useScaffoldReadContract({
    contractName: "HousePool",
    functionName: "getCommitment",
    args: [connectedAddress],
  });

  // Write hooks
  const { writeContractAsync: writeHousePool, isPending: isHousePoolWritePending } = useScaffoldWriteContract({
    contractName: "HousePool",
  });

  const { writeContractAsync: writeUsdc, isPending: isUsdcWritePending } = useWriteContract();

  // Refetch all data
  const refetchAll = useCallback(() => {
    refetchTotalPool();
    refetchEffectivePool();
    refetchSharePrice();
    refetchCanRoll();
    refetchTotalPendingShares();
    refetchUserHouseBalance();
    refetchUserUsdcValue();
    refetchUserUsdcBalance();
    refetchWithdrawalRequest();
    refetchCommitment();
  }, [
    refetchTotalPool,
    refetchEffectivePool,
    refetchSharePrice,
    refetchCanRoll,
    refetchTotalPendingShares,
    refetchUserHouseBalance,
    refetchUserUsdcValue,
    refetchUserUsdcBalance,
    refetchWithdrawalRequest,
    refetchCommitment,
  ]);

  // Auto-refresh
  useEffect(() => {
    const interval = setInterval(refetchAll, 10000);
    return () => clearInterval(interval);
  }, [refetchAll]);

  // Generate random secret for gambling
  const generateSecret = () => {
    const randomBytes = crypto.getRandomValues(new Uint8Array(32));
    const secret = toHex(randomBytes);
    setGamblingSecret(secret);
    return secret;
  };

  // Handle deposit
  const handleDeposit = async () => {
    if (!depositAmount || !housePoolContract || !usdcAddress) return;

    try {
      const amountUsdc = parseUnits(depositAmount, USDC_DECIMALS);

      // Approve USDC
      await writeUsdc({
        address: usdcAddress,
        abi: USDC_ABI,
        functionName: "approve",
        args: [housePoolContract.address, amountUsdc],
      });

      // Deposit
      await writeHousePool({
        functionName: "deposit",
        args: [amountUsdc],
      });

      setDepositAmount("");
      refetchAll();
    } catch (error) {
      console.error("Deposit failed:", error);
    }
  };

  // Handle request withdrawal
  const handleRequestWithdrawal = async () => {
    if (!withdrawShares) return;

    try {
      const shares = parseUnits(withdrawShares, HOUSE_DECIMALS);

      await writeHousePool({
        functionName: "requestWithdrawal",
        args: [shares],
      });

      setWithdrawShares("");
      refetchAll();
    } catch (error) {
      console.error("Request withdrawal failed:", error);
    }
  };

  // Handle execute withdrawal
  const handleWithdraw = async () => {
    try {
      await writeHousePool({
        functionName: "withdraw",
        args: [],
      });

      refetchAll();
    } catch (error) {
      console.error("Withdraw failed:", error);
    }
  };

  // Handle cancel withdrawal
  const handleCancelWithdrawal = async () => {
    try {
      await writeHousePool({
        functionName: "cancelWithdrawal",
        args: [],
      });

      refetchAll();
    } catch (error) {
      console.error("Cancel withdrawal failed:", error);
    }
  };

  // Handle commit roll
  const handleCommitRoll = async () => {
    if (!housePoolContract || !usdcAddress) return;

    try {
      // Generate or use existing secret
      const secret = gamblingSecret || generateSecret();
      const commitHash = keccak256(toHex(secret));

      // Store secret for reveal
      setPendingSecret(secret);
      localStorage.setItem("pendingGamblingSecret", secret);

      // Approve 1 USDC for roll
      const rollCost = parseUnits("1", USDC_DECIMALS);
      await writeUsdc({
        address: usdcAddress,
        abi: USDC_ABI,
        functionName: "approve",
        args: [housePoolContract.address, rollCost],
      });

      // Commit
      await writeHousePool({
        functionName: "commitRoll",
        args: [commitHash],
      });

      setGamblingSecret("");
      refetchAll();
    } catch (error) {
      console.error("Commit roll failed:", error);
    }
  };

  // Handle reveal roll
  const handleRevealRoll = async () => {
    // Try to get secret from state or localStorage
    const secret = pendingSecret || localStorage.getItem("pendingGamblingSecret");
    if (!secret) {
      alert("No pending secret found. Please commit first.");
      return;
    }

    try {
      await writeHousePool({
        functionName: "revealRoll",
        args: [toHex(secret)],
      });

      // Clear stored secret
      setPendingSecret(null);
      localStorage.removeItem("pendingGamblingSecret");
      refetchAll();
    } catch (error) {
      console.error("Reveal roll failed:", error);
    }
  };

  // Check for pending secret on load
  useEffect(() => {
    const stored = localStorage.getItem("pendingGamblingSecret");
    if (stored) {
      setPendingSecret(stored);
    }
  }, []);

  const isLoading = isHousePoolWritePending || isUsdcWritePending;

  // Format helpers
  const formatUsdc = (value: bigint | undefined) =>
    value ? parseFloat(formatUnits(value, USDC_DECIMALS)).toLocaleString(undefined, { maximumFractionDigits: 2 }) : "0";

  const formatHouse = (value: bigint | undefined) =>
    value
      ? parseFloat(formatUnits(value, HOUSE_DECIMALS)).toLocaleString(undefined, { maximumFractionDigits: 4 })
      : "0";

  const formatSharePrice = (value: bigint | undefined) => {
    if (!value) return "1.000000";
    // sharePrice is in 18 decimals but represents USDC (6 decimals)
    // So we divide by 1e18 then multiply by 1e6 to get USDC value
    const priceInUsdc = Number(value) / 1e18;
    return priceInUsdc.toFixed(6);
  };

  // Parse withdrawal request
  const hasWithdrawalRequest = withdrawalRequest && withdrawalRequest[0] > 0n;
  const withdrawalCanExecute = withdrawalRequest && withdrawalRequest[3];
  const withdrawalIsExpired = withdrawalRequest && withdrawalRequest[4];
  const withdrawalUnlockTime = withdrawalRequest ? new Date(Number(withdrawalRequest[1]) * 1000) : null;
  const withdrawalExpiryTime = withdrawalRequest ? new Date(Number(withdrawalRequest[2]) * 1000) : null;

  // Parse commitment
  const hasCommitment = commitment && commitment[0] !== "0x0000000000000000000000000000000000000000000000000000000000000000";
  const commitmentCanReveal = commitment && commitment[2];
  const commitmentIsExpired = commitment && commitment[3];

  return (
    <div className="flex flex-col items-center pt-8 px-4 pb-12 min-h-screen bg-gradient-to-b from-base-300 to-base-100">
      <h1 className="text-4xl font-bold mb-2 bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
        🏠 House Pool
      </h1>
      <p className="text-base-content/60 mb-6 text-center max-w-md">
        Deposit USDC to become the house. Your share value grows as the house profits from gambling.
      </p>

      {/* Pool Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 w-full max-w-4xl mb-8">
        <div className="bg-base-100 rounded-2xl p-4 shadow-lg border border-base-300">
          <p className="text-xs text-base-content/60 uppercase tracking-wide">Total Pool</p>
          <p className="text-2xl font-bold text-primary">${formatUsdc(totalPool)}</p>
        </div>
        <div className="bg-base-100 rounded-2xl p-4 shadow-lg border border-base-300">
          <p className="text-xs text-base-content/60 uppercase tracking-wide">Effective Pool</p>
          <p className="text-2xl font-bold text-secondary">${formatUsdc(effectivePool)}</p>
        </div>
        <div className="bg-base-100 rounded-2xl p-4 shadow-lg border border-base-300">
          <p className="text-xs text-base-content/60 uppercase tracking-wide">Share Price</p>
          <p className="text-2xl font-bold">${formatSharePrice(sharePrice)}</p>
        </div>
        <div className="bg-base-100 rounded-2xl p-4 shadow-lg border border-base-300">
          <p className="text-xs text-base-content/60 uppercase tracking-wide">Can Roll?</p>
          <p className={`text-2xl font-bold ${canRoll ? "text-success" : "text-error"}`}>{canRoll ? "Yes ✓" : "No ✗"}</p>
        </div>
      </div>

      {/* User Position */}
      {connectedAddress && (
        <div className="bg-gradient-to-br from-primary/10 to-secondary/10 rounded-3xl p-6 w-full max-w-4xl mb-8 border border-primary/20">
          <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
            <BanknotesIcon className="h-5 w-5" />
            Your Position
          </h2>
          <div className="grid grid-cols-3 gap-4">
            <div>
              <p className="text-sm text-base-content/60">HOUSE Tokens</p>
              <p className="text-xl font-bold">{formatHouse(userHouseBalance)}</p>
            </div>
            <div>
              <p className="text-sm text-base-content/60">USDC Value</p>
              <p className="text-xl font-bold text-primary">${formatUsdc(userUsdcValue)}</p>
            </div>
            <div>
              <p className="text-sm text-base-content/60">Wallet USDC</p>
              <p className="text-xl font-bold">${formatUsdc(userUsdcBalance as bigint | undefined)}</p>
            </div>
          </div>
        </div>
      )}

      {/* Main Panels */}
      <div className="grid md:grid-cols-2 gap-6 w-full max-w-4xl">
        {/* LP Panel */}
        <div className="bg-base-100 rounded-3xl p-6 shadow-xl border border-base-300">
          <h3 className="text-xl font-bold mb-4 flex items-center gap-2">
            <PlusCircleIcon className="h-6 w-6 text-primary" />
            Liquidity
          </h3>

          {/* Deposit Section */}
          <div className="space-y-3 mb-6">
            <h4 className="text-sm font-semibold text-base-content/80">Deposit USDC</h4>
            <input
              type="number"
              className="input input-bordered w-full"
              placeholder="Amount in USDC"
              value={depositAmount}
              onChange={e => setDepositAmount(e.target.value)}
            />
            <button
              className="btn btn-primary w-full"
              onClick={handleDeposit}
              disabled={isLoading || !depositAmount || !connectedAddress}
            >
              {isLoading ? <span className="loading loading-spinner loading-sm"></span> : "Deposit USDC → Get HOUSE"}
            </button>
          </div>

          {/* Withdrawal Section */}
          <div className="space-y-3 border-t border-base-300 pt-4">
            <h4 className="text-sm font-semibold text-base-content/80 flex items-center gap-2">
              <MinusCircleIcon className="h-4 w-4" />
              Withdraw
            </h4>

            {hasWithdrawalRequest ? (
              <div className="bg-base-200 rounded-xl p-4 space-y-3">
                <div className="flex justify-between items-center">
                  <span className="text-sm">Pending Withdrawal</span>
                  <span className="font-bold">{formatHouse(withdrawalRequest[0])} HOUSE</span>
                </div>

                {withdrawalIsExpired ? (
                  <div className="text-error text-sm">Request expired. Please request again.</div>
                ) : withdrawalCanExecute ? (
                  <>
                    <div className="text-success text-sm">Ready to withdraw!</div>
                    <div className="text-xs text-base-content/60">
                      Expires: {withdrawalExpiryTime?.toLocaleString()}
                    </div>
                  </>
                ) : (
                  <div className="text-warning text-sm flex items-center gap-1">
                    <ClockIcon className="h-4 w-4" />
                    Unlocks: {withdrawalUnlockTime?.toLocaleString()}
                  </div>
                )}

                <div className="flex gap-2">
                  <button
                    className="btn btn-secondary flex-1"
                    onClick={handleWithdraw}
                    disabled={isLoading || !withdrawalCanExecute}
                  >
                    Execute Withdrawal
                  </button>
                  <button className="btn btn-outline" onClick={handleCancelWithdrawal} disabled={isLoading}>
                    Cancel
                  </button>
                </div>
              </div>
            ) : (
              <>
                <input
                  type="number"
                  className="input input-bordered w-full"
                  placeholder="HOUSE tokens to withdraw"
                  value={withdrawShares}
                  onChange={e => setWithdrawShares(e.target.value)}
                />
                <p className="text-xs text-base-content/60">5 min cooldown, then 24hr window to execute</p>
                <button
                  className="btn btn-secondary w-full"
                  onClick={handleRequestWithdrawal}
                  disabled={isLoading || !withdrawShares || !connectedAddress}
                >
                  Request Withdrawal
                </button>
              </>
            )}
          </div>
        </div>

        {/* Gambling Panel */}
        <div className="bg-base-100 rounded-3xl p-6 shadow-xl border border-base-300">
          <h3 className="text-xl font-bold mb-4 flex items-center gap-2">
            <SparklesIcon className="h-6 w-6 text-secondary" />
            Roll the Dice
          </h3>

          <div className="bg-gradient-to-r from-primary/10 to-secondary/10 rounded-xl p-4 mb-4">
            <div className="grid grid-cols-3 text-center">
              <div>
                <p className="text-xs text-base-content/60">Cost</p>
                <p className="font-bold">1 USDC</p>
              </div>
              <div>
                <p className="text-xs text-base-content/60">Win Chance</p>
                <p className="font-bold">~9%</p>
              </div>
              <div>
                <p className="text-xs text-base-content/60">Payout</p>
                <p className="font-bold text-success">10 USDC</p>
              </div>
            </div>
          </div>

          {!canRoll ? (
            <div className="bg-error/10 border border-error/30 rounded-xl p-4 text-center">
              <p className="text-error font-semibold">Rolling Disabled</p>
              <p className="text-sm text-base-content/60">Pool needs more liquidity</p>
            </div>
          ) : hasCommitment ? (
            <div className="space-y-4">
              <div className="bg-base-200 rounded-xl p-4">
                <div className="flex items-center gap-2 mb-2">
                  <CubeIcon className="h-5 w-5 text-primary" />
                  <span className="font-semibold">Commitment Active</span>
                </div>
                <p className="text-sm text-base-content/60">Block: {commitment[1].toString()}</p>

                {commitmentIsExpired ? (
                  <p className="text-error text-sm mt-2">Commitment expired (256 blocks passed)</p>
                ) : commitmentCanReveal ? (
                  <p className="text-success text-sm mt-2">Ready to reveal!</p>
                ) : (
                  <p className="text-warning text-sm mt-2">Wait 2+ blocks to reveal...</p>
                )}
              </div>

              <button
                className="btn btn-primary w-full"
                onClick={handleRevealRoll}
                disabled={isLoading || !commitmentCanReveal || commitmentIsExpired}
              >
                {isLoading ? (
                  <span className="loading loading-spinner loading-sm"></span>
                ) : (
                  <>
                    <ArrowPathIcon className="h-5 w-5" />
                    Reveal & Roll!
                  </>
                )}
              </button>
            </div>
          ) : (
            <div className="space-y-4">
              <p className="text-sm text-base-content/60">
                Two-step process: First commit a secret hash, wait 2 blocks, then reveal to get your result.
              </p>

              <div className="form-control">
                <label className="label">
                  <span className="label-text">Secret (auto-generated)</span>
                  <button className="btn btn-xs btn-ghost" onClick={generateSecret}>
                    Generate New
                  </button>
                </label>
                <input
                  type="text"
                  className="input input-bordered input-sm font-mono text-xs"
                  placeholder="Click 'Generate New' or enter your own"
                  value={gamblingSecret}
                  onChange={e => setGamblingSecret(e.target.value)}
                />
              </div>

              <button
                className="btn btn-primary w-full"
                onClick={handleCommitRoll}
                disabled={isLoading || !connectedAddress}
              >
                {isLoading ? (
                  <span className="loading loading-spinner loading-sm"></span>
                ) : (
                  <>
                    <CubeIcon className="h-5 w-5" />
                    Commit (Pay 1 USDC)
                  </>
                )}
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Info Footer */}
      <div className="mt-8 text-center text-sm text-base-content/50 max-w-2xl">
        <p>
          <strong>How it works:</strong> Deposit USDC to mint HOUSE tokens. As gamblers play and lose, the pool grows,
          making your HOUSE tokens worth more USDC. The house has a ~9% edge.
        </p>
        <p className="mt-2">Withdrawals have a 5-minute cooldown to prevent front-running.</p>
      </div>
    </div>
  );
};

export default HousePage;

