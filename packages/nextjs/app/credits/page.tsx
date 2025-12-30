"use client";

import { useState } from "react";
import { AddressInput, EtherInput } from "@scaffold-ui/components";
import type { NextPage } from "next";
import { Address as AddressType, Hex, formatEther, parseEther } from "viem";
import { useAccount, useSignTypedData } from "wagmi";
import { DocumentDuplicateIcon, PaperAirplaneIcon, SparklesIcon } from "@heroicons/react/24/outline";
import {
  useCopyToClipboard,
  useDeployedContractInfo,
  useScaffoldReadContract,
  useScaffoldWriteContract,
  useTargetNetwork,
} from "~~/hooks/scaffold-eth";

// Generate a random 32-byte nonce
const generateNonce = (): Hex => {
  const randomBytes = new Uint8Array(32);
  crypto.getRandomValues(randomBytes);
  return `0x${Array.from(randomBytes)
    .map(b => b.toString(16).padStart(2, "0"))
    .join("")}` as Hex;
};

// Validity duration options
const VALIDITY_OPTIONS = [
  { label: "1 hour", seconds: 3600 },
  { label: "1 day", seconds: 86400 },
  { label: "1 week", seconds: 604800 },
];

// Type for the authorization JSON
type AuthorizationData = {
  from: AddressType;
  to: AddressType;
  value: string;
  validAfter: string;
  validBefore: string;
  nonce: Hex;
  v: number;
  r: Hex;
  s: Hex;
};

const Credits: NextPage = () => {
  const { address: connectedAddress } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const { copyToClipboard, isCopiedToClipboard } = useCopyToClipboard();

  // Get contract info for domain
  const { data: creditsContract } = useDeployedContractInfo({ contractName: "Credits" });

  // Read user's balance
  const { data: balance, refetch: refetchBalance } = useScaffoldReadContract({
    contractName: "Credits",
    functionName: "balanceOf",
    args: [connectedAddress],
  });

  // Sign panel state
  const [toAddress, setToAddress] = useState<AddressType | "">("");
  const [amount, setAmount] = useState("");
  const [validityDuration, setValidityDuration] = useState(VALIDITY_OPTIONS[0].seconds);
  const [signedAuth, setSignedAuth] = useState<AuthorizationData | null>(null);

  // Execute panel state
  const [pastedAuth, setPastedAuth] = useState("");
  const [parseError, setParseError] = useState("");

  // Mint panel state
  const [mintToAddress, setMintToAddress] = useState<AddressType | "">("");
  const [mintAmount, setMintAmount] = useState("");

  // Read contract owner
  const { data: owner } = useScaffoldReadContract({
    contractName: "Credits",
    functionName: "owner",
  });

  const isOwner = connectedAddress && owner && connectedAddress.toLowerCase() === owner.toLowerCase();

  // Wagmi sign typed data hook
  const { signTypedDataAsync } = useSignTypedData();

  // Write contract hook
  const { writeContractAsync, isMining } = useScaffoldWriteContract({ contractName: "Credits" });

  // Handle signing
  const handleSign = async () => {
    if (!connectedAddress || !toAddress || !amount || !creditsContract) return;

    const now = Math.floor(Date.now() / 1000);
    const validAfter = BigInt(now - 60); // Valid from 1 minute ago (to handle clock skew)
    const validBefore = BigInt(now + validityDuration);
    const nonce = generateNonce();
    const value = parseEther(amount);

    try {
      const signature = await signTypedDataAsync({
        domain: {
          name: "Credits",
          version: "1",
          chainId: targetNetwork.id,
          verifyingContract: creditsContract.address,
        },
        types: {
          TransferWithAuthorization: [
            { name: "from", type: "address" },
            { name: "to", type: "address" },
            { name: "value", type: "uint256" },
            { name: "validAfter", type: "uint256" },
            { name: "validBefore", type: "uint256" },
            { name: "nonce", type: "bytes32" },
          ],
        },
        primaryType: "TransferWithAuthorization",
        message: {
          from: connectedAddress,
          to: toAddress as AddressType,
          value: value,
          validAfter: validAfter,
          validBefore: validBefore,
          nonce: nonce,
        },
      });

      // Parse signature into v, r, s
      const r = `0x${signature.slice(2, 66)}` as Hex;
      const s = `0x${signature.slice(66, 130)}` as Hex;
      const v = parseInt(signature.slice(130, 132), 16);

      const authData: AuthorizationData = {
        from: connectedAddress,
        to: toAddress as AddressType,
        value: value.toString(),
        validAfter: validAfter.toString(),
        validBefore: validBefore.toString(),
        nonce,
        v,
        r,
        s,
      };

      setSignedAuth(authData);
    } catch (error) {
      console.error("Signing failed:", error);
    }
  };

  // Handle execute
  const handleExecute = async () => {
    setParseError("");

    try {
      const auth = JSON.parse(pastedAuth) as AuthorizationData;

      // Validate required fields
      if (
        !auth.from ||
        !auth.to ||
        !auth.value ||
        !auth.validAfter ||
        !auth.validBefore ||
        !auth.nonce ||
        !auth.v ||
        !auth.r ||
        !auth.s
      ) {
        setParseError("Missing required fields in authorization JSON");
        return;
      }

      await writeContractAsync({
        functionName: "transferWithAuthorization",
        args: [
          auth.from as AddressType,
          auth.to as AddressType,
          BigInt(auth.value),
          BigInt(auth.validAfter),
          BigInt(auth.validBefore),
          auth.nonce as Hex,
          auth.v,
          auth.r as Hex,
          auth.s as Hex,
        ],
      });

      setPastedAuth("");
    } catch (error: unknown) {
      if (error instanceof SyntaxError) {
        setParseError("Invalid JSON format");
      } else {
        setParseError((error as Error).message || "Transaction failed");
      }
    }
  };

  // Handle mint (owner only)
  const handleMint = async () => {
    if (!mintToAddress || !mintAmount) return;

    try {
      await writeContractAsync({
        functionName: "mint",
        args: [mintToAddress as AddressType, parseEther(mintAmount)],
      });

      setMintAmount("");
      refetchBalance();
    } catch (error) {
      console.error("Mint failed:", error);
    }
  };

  const formattedBalance = balance ? formatEther(balance) : "0";

  return (
    <div className="flex flex-col items-center pt-10 px-4">
      {/* Balance Display */}
      <div className="bg-base-200 rounded-3xl px-8 py-6 mb-8 text-center shadow-lg">
        <h2 className="text-lg text-base-content/70 mb-1">Your Credits Balance</h2>
        <p className="text-4xl font-bold text-primary">
          {parseFloat(formattedBalance).toLocaleString(undefined, { maximumFractionDigits: 4 })} CRED
        </p>
      </div>

      {/* Mint Panel (Owner Only) */}
      {isOwner && (
        <div className="bg-gradient-to-br from-primary/20 to-secondary/20 rounded-3xl p-6 shadow-lg mb-8 w-full max-w-md border border-primary/30">
          <h3 className="text-xl font-bold mb-4 text-center flex items-center justify-center gap-2">
            <SparklesIcon className="h-6 w-6 text-primary" />
            Mint Credits (Owner)
          </h3>

          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium mb-1 block">Recipient Address</label>
              <AddressInput
                placeholder="0x..."
                value={mintToAddress}
                onChange={value => setMintToAddress(value as AddressType)}
              />
            </div>

            <div>
              <label className="text-sm font-medium mb-1 block">Amount to Mint (CRED)</label>
              <EtherInput
                placeholder="1000"
                onValueChange={({ valueInEth }) => setMintAmount(valueInEth)}
                style={{ width: "100%" }}
              />
            </div>

            <button
              className="btn btn-primary w-full"
              onClick={handleMint}
              disabled={!mintToAddress || !mintAmount || isMining}
            >
              {isMining ? (
                <span className="loading loading-spinner loading-sm"></span>
              ) : (
                <SparklesIcon className="h-5 w-5" />
              )}
              Mint Credits
            </button>
          </div>
        </div>
      )}

      {/* Two Column Layout */}
      <div className="flex flex-col lg:flex-row gap-6 w-full max-w-4xl">
        {/* Sign Panel */}
        <div className="flex-1 bg-base-100 rounded-3xl p-6 shadow-lg">
          <h3 className="text-xl font-bold mb-4 text-center">Sign Transfer Authorization</h3>

          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium mb-1 block">Recipient Address</label>
              <AddressInput
                placeholder="0x..."
                value={toAddress}
                onChange={value => setToAddress(value as AddressType)}
              />
            </div>

            <div>
              <label className="text-sm font-medium mb-1 block">Amount (CRED)</label>
              <EtherInput
                placeholder="100"
                onValueChange={({ valueInEth }) => setAmount(valueInEth)}
                style={{ width: "100%" }}
              />
            </div>

            <div>
              <label className="text-sm font-medium mb-1 block">Valid For</label>
              <select
                className="select select-bordered w-full"
                value={validityDuration}
                onChange={e => setValidityDuration(Number(e.target.value))}
              >
                {VALIDITY_OPTIONS.map(opt => (
                  <option key={opt.seconds} value={opt.seconds}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </div>

            <button
              className="btn btn-primary w-full"
              onClick={handleSign}
              disabled={!connectedAddress || !toAddress || !amount}
            >
              <PaperAirplaneIcon className="h-5 w-5" />
              Sign Authorization
            </button>

            {/* Signed Auth Output */}
            {signedAuth && (
              <div className="mt-4">
                <label className="text-sm font-medium mb-1 block">Authorization JSON (copy this):</label>
                <div className="relative">
                  <pre className="bg-base-300 rounded-xl p-4 text-xs overflow-x-auto max-h-48">
                    {JSON.stringify(signedAuth, null, 2)}
                  </pre>
                  <button
                    className="btn btn-sm btn-secondary absolute top-2 right-2"
                    onClick={() => copyToClipboard(JSON.stringify(signedAuth))}
                  >
                    <DocumentDuplicateIcon className="h-4 w-4" />
                    {isCopiedToClipboard ? "Copied!" : "Copy"}
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Execute Panel */}
        <div className="flex-1 bg-base-100 rounded-3xl p-6 shadow-lg">
          <h3 className="text-xl font-bold mb-4 text-center">Execute Transfer Authorization</h3>

          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium mb-1 block">Paste Authorization JSON</label>
              <textarea
                className="textarea textarea-bordered w-full h-48 font-mono text-xs"
                placeholder='{"from": "0x...", "to": "0x...", ...}'
                value={pastedAuth}
                onChange={e => {
                  setPastedAuth(e.target.value);
                  setParseError("");
                }}
              />
            </div>

            {parseError && (
              <div className="alert alert-error">
                <span>{parseError}</span>
              </div>
            )}

            <button className="btn btn-primary w-full" onClick={handleExecute} disabled={!pastedAuth || isMining}>
              {isMining ? (
                <span className="loading loading-spinner loading-sm"></span>
              ) : (
                <PaperAirplaneIcon className="h-5 w-5" />
              )}
              Execute Transfer
            </button>

            <p className="text-sm text-base-content/60 text-center">
              The executor pays the gas fee. The signer&apos;s tokens are transferred without them paying gas.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Credits;
