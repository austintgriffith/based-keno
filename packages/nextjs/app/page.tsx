"use client";

import Link from "next/link";
import type { NextPage } from "next";
import { BanknotesIcon, CubeIcon, HomeModernIcon, SparklesIcon } from "@heroicons/react/24/outline";

const Home: NextPage = () => {
  return (
    <div className="flex flex-col items-center min-h-screen">
      {/* Hero Section */}
      <div className="flex flex-col items-center justify-center px-5 py-16 w-full bg-gradient-to-b from-primary/10 to-transparent">
        <h1 className="text-center mb-4">
          <span className="block text-6xl font-bold bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
            🏠 House Pool
          </span>
        </h1>
        <p className="text-xl text-base-content/70 text-center max-w-2xl mb-8">
          A simplified gambling pool where <strong>you are the house</strong>. Deposit USDC, get HOUSE tokens, and earn
          as gamblers play.
        </p>

        <Link href="/house" className="btn btn-primary btn-lg gap-2 shadow-lg">
          <HomeModernIcon className="h-6 w-6" />
          Enter House Pool
        </Link>
      </div>

      {/* How it Works */}
      <div className="w-full max-w-5xl px-8 py-12">
        <h2 className="text-3xl font-bold text-center mb-8">How It Works</h2>

        <div className="grid md:grid-cols-3 gap-6">
          <div className="bg-base-100 rounded-3xl p-6 shadow-lg border border-base-300 text-center">
            <div className="bg-primary/10 rounded-full w-16 h-16 flex items-center justify-center mx-auto mb-4">
              <BanknotesIcon className="h-8 w-8 text-primary" />
            </div>
            <h3 className="text-xl font-bold mb-2">1. Deposit USDC</h3>
            <p className="text-base-content/70">
              Deposit USDC into the pool and receive HOUSE tokens representing your ownership share.
            </p>
          </div>

          <div className="bg-base-100 rounded-3xl p-6 shadow-lg border border-base-300 text-center">
            <div className="bg-secondary/10 rounded-full w-16 h-16 flex items-center justify-center mx-auto mb-4">
              <SparklesIcon className="h-8 w-8 text-secondary" />
            </div>
            <h3 className="text-xl font-bold mb-2">2. House Edge Works</h3>
            <p className="text-base-content/70">
              Gamblers roll: 1 USDC cost, ~9% win rate, 10 USDC payout. The house has a ~9% edge.
            </p>
          </div>

          <div className="bg-base-100 rounded-3xl p-6 shadow-lg border border-base-300 text-center">
            <div className="bg-success/10 rounded-full w-16 h-16 flex items-center justify-center mx-auto mb-4">
              <CubeIcon className="h-8 w-8 text-success" />
            </div>
            <h3 className="text-xl font-bold mb-2">3. Value Grows</h3>
            <p className="text-base-content/70">
              As the house profits, your HOUSE tokens become worth more USDC. Withdraw anytime (5 min cooldown).
            </p>
          </div>
        </div>
      </div>

      {/* Stats Preview */}
      <div className="w-full bg-base-200 py-12 px-8">
        <div className="max-w-4xl mx-auto">
          <h2 className="text-2xl font-bold text-center mb-6">Key Features</h2>

          <div className="grid md:grid-cols-2 gap-4">
            <div className="bg-base-100 rounded-2xl p-4 flex items-center gap-4">
              <div className="text-3xl">🎲</div>
              <div>
                <h4 className="font-semibold">Fair Commit-Reveal</h4>
                <p className="text-sm text-base-content/60">Two-step gambling prevents manipulation</p>
              </div>
            </div>

            <div className="bg-base-100 rounded-2xl p-4 flex items-center gap-4">
              <div className="text-3xl">⏱️</div>
              <div>
                <h4 className="font-semibold">5-Min Withdrawal Cooldown</h4>
                <p className="text-sm text-base-content/60">Prevents front-running reveals</p>
              </div>
            </div>

            <div className="bg-base-100 rounded-2xl p-4 flex items-center gap-4">
              <div className="text-3xl">🔥</div>
              <div>
                <h4 className="font-semibold">Auto Buyback & Burn</h4>
                <p className="text-sm text-base-content/60">Excess profits buy back HOUSE tokens</p>
              </div>
            </div>

            <div className="bg-base-100 rounded-2xl p-4 flex items-center gap-4">
              <div className="text-3xl">💎</div>
              <div>
                <h4 className="font-semibold">Simple Token Model</h4>
                <p className="text-sm text-base-content/60">HOUSE = your share of the USDC pool</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* CTA */}
      <div className="py-12 text-center">
        <p className="text-lg text-base-content/70 mb-4">Ready to become the house?</p>
        <Link href="/house" className="btn btn-secondary btn-lg gap-2">
          <HomeModernIcon className="h-5 w-5" />
          Start Now
        </Link>
      </div>
    </div>
  );
};

export default Home;
