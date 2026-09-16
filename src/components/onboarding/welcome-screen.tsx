"use client";

import { useEffect, useRef, useState } from "react";
import { AriaMark } from "@/components/brand/aria-mark";
import {
  ForgeBrandMark,
  PremiumAtmosphere,
  PremiumEntrance,
  PremiumFloat,
  PremiumPresenceBloom,
  PremiumPrimaryButton,
  PremiumProgressDots,
} from "@/components/brand/premium-atmosphere";
import { cn } from "@/lib/utils";

const HOOKS = [
  {
    id: "aria",
    kicker: "Meet your coach",
    title: "Hey — I'm ARIA.",
    body: "ARIA is an adaptive lifestyle coach — present for readiness, sleep, and the session you'd skip. Small moves compound. You still decide.",
    reward: "A coach who already knows you",
    accent: "#FF6B2B",
    frost: "#A9D8FF",
    icon: "✦",
  },
  {
    id: "readiness",
    kicker: "Train on signal",
    title: "Know when to push or protect.",
    body: "ARIA turns your metrics into a plan that fits today. Progress compounds day to day — each session intentional, never a burden.",
    reward: "Sessions that match how you feel",
    accent: "#60A5FA",
    frost: "#A9D8FF",
    icon: "⌒",
  },
  {
    id: "life",
    kicker: "Built around your life",
    title: "Workouts, lifestyle, and cycle rhythm.",
    body: "Sleep, nutrition, free time, and how you show up for people you love — one private control center that respects the life you already have.",
    reward: "Private by design",
    accent: "#34D399",
    frost: "#A9D8FF",
    icon: "❀",
  },
  {
    id: "forge",
    kicker: "Start today",
    title: "Forge starts with one choice.",
    body: "Name your goal and how you want to train. Connect Health if you want. Walk out with a first plan and a coach that already knows you.",
    reward: "Meet ARIA →",
    accent: "#F7F4F0",
    frost: "#FF6B2B",
    icon: "→",
  },
] as const;

interface WelcomeScreenProps {
  onNext: () => void;
}

export default function WelcomeScreen({ onNext }: WelcomeScreenProps) {
  const [page, setPage] = useState(0);
  const [showSignIn, setShowSignIn] = useState(false);
  const [autoplayPaused, setAutoplayPaused] = useState(false);
  const hook = HOOKS[page];
  const advancingRef = useRef(false);

  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || autoplayPaused || page >= HOOKS.length - 1 || showSignIn) return;
    const t = window.setTimeout(() => setPage((p) => Math.min(HOOKS.length - 1, p + 1)), 4800);
    return () => window.clearTimeout(t);
  }, [page, showSignIn, autoplayPaused]);

  useEffect(() => {
    const pause = () => setAutoplayPaused(true);
    document.addEventListener("pointerdown", pause, true);
    return () => document.removeEventListener("pointerdown", pause, true);
  }, []);

  const advance = () => {
    if (advancingRef.current) return;
    advancingRef.current = true;
    setAutoplayPaused(true);
    onNext();
  };

  return (
    <div className="relative flex min-h-[100dvh] flex-col overflow-hidden bg-background pb-[env(safe-area-inset-bottom)] pt-[env(safe-area-inset-top)]">
      <PremiumAtmosphere accent={hook.accent} secondary={hook.frost} />

      <div className="relative z-10 flex flex-1 flex-col px-6 pb-9 pt-5">
        <PremiumEntrance index={0}>
          <header className="flex items-center gap-3">
            <div className="flex items-center gap-2.5">
              <ForgeBrandMark size={18} />
              <span className="text-[15px] font-semibold tracking-wide text-text-primary">Forge</span>
            </div>
            <div className="flex-1" />
            <button
              type="button"
              onClick={() => setShowSignIn(true)}
              className="rounded-full border border-white/12 bg-white/[0.06] px-3.5 py-2 text-sm font-medium text-text-primary/90 transition hover:border-white/20 hover:bg-white/[0.1]"
            >
              Sign in
            </button>
          </header>
        </PremiumEntrance>

        <div className="flex flex-1 flex-col items-center justify-center px-1 text-center">
          <PremiumEntrance key={`visual-${hook.id}`} index={0} className="mb-7">
            <PremiumFloat className="relative flex h-48 w-52 items-center justify-center">
              <PremiumPresenceBloom size={210} accent={hook.accent} frost={hook.frost} />
              {hook.id === "aria" || hook.id === "forge" ? (
                <AriaMark size={140} speaking={hook.id === "aria"} label="ARIA" className="relative z-10" />
              ) : (
                <div className="relative z-10 flex h-28 w-28 items-center justify-center rounded-full border border-white/10 bg-white/[0.04] shadow-[0_0_40px_rgba(247,244,240,0.06)]">
                  <span className="text-2xl text-[#F7F4F0]/85" aria-hidden>
                    {hook.icon}
                  </span>
                </div>
              )}
            </PremiumFloat>
          </PremiumEntrance>

          <PremiumEntrance key={`kicker-${hook.id}`} index={1}>
            <p className="premium-kicker-glow text-[12px] font-medium uppercase tracking-[0.24em] text-text-tertiary">
              {hook.kicker}
            </p>
          </PremiumEntrance>
          <PremiumEntrance key={`title-${hook.id}`} index={2}>
            <h1
              className="mt-3 max-w-sm text-[30px] font-semibold leading-tight tracking-tight text-text-primary"
              style={{ fontFamily: "var(--font-display)" }}
            >
              {hook.title}
            </h1>
          </PremiumEntrance>
          <PremiumEntrance key={`body-${hook.id}`} index={3}>
            <p className="mt-4 max-w-sm text-[15px] font-normal leading-relaxed text-text-secondary">
              {hook.body}
            </p>
          </PremiumEntrance>
          <PremiumEntrance key={`reward-${hook.id}`} index={4}>
            <p
              className={cn(
                "mt-4 text-[13px] font-medium",
                hook.id === "forge" ? "text-ember/90" : "text-text-tertiary"
              )}
            >
              {hook.reward}
            </p>
          </PremiumEntrance>
        </div>

        {/* CTA outside PremiumEntrance — no sheen/overflow/transform on the press target. */}
        <div className="relative z-40 mt-auto">
          <div className="pointer-events-none relative z-[60] mb-3 flex flex-col items-center gap-3">
            <div className="pointer-events-auto">
              <PremiumProgressDots
                count={HOOKS.length}
                current={page}
                onSelect={(i) => {
                  setAutoplayPaused(true);
                  setPage(i);
                }}
              />
            </div>
            <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-text-tertiary">
              {page + 1} of {HOOKS.length}
            </p>
          </div>

          <button
            type="button"
            aria-label="Get started"
            onPointerUp={(e) => {
              e.preventDefault();
              advance();
            }}
            onClick={(e) => {
              e.preventDefault();
              advance();
            }}
            className={cn(
              "relative z-40 flex w-full min-h-[64px] items-center justify-between rounded-full bg-[#F7F4F0] px-6 py-5 text-[17px] font-semibold text-[#0A0A0A]",
              "shadow-[0_10px_30px_rgba(247,244,240,0.14)] transition-[filter,box-shadow] duration-150",
              "active:brightness-[0.92] active:shadow-none",
              "touch-manipulation select-none"
            )}
          >
            {/* Modest expanded hit area for near-misses above the pearl. */}
            <span aria-hidden className="absolute inset-x-[-4px] -top-10 bottom-[-4px] z-50" />
            <span className="relative z-[51]">Get started</span>
            <span aria-hidden className="relative z-[51] opacity-80">
              →
            </span>
          </button>

          {page < HOOKS.length - 1 && (
            <button
              type="button"
              onClick={() => {
                setAutoplayPaused(true);
                setPage((p) => Math.min(HOOKS.length - 1, p + 1));
              }}
              className="relative z-40 mt-2 w-full py-2 text-sm font-medium text-text-secondary transition hover:text-text-primary"
            >
              See how it works
            </button>
          )}

          <p className="mt-2 text-center text-[11px] text-text-muted">
            Lifestyle fitness coaching · Live your best life
          </p>
        </div>
      </div>

      {showSignIn && (
        <SignInSheet
          onClose={() => setShowSignIn(false)}
          onContinueAsGuest={() => {
            setShowSignIn(false);
            onNext();
          }}
          onContinueAsTester={() => {
            // Keep until Cognito is paired — web uses the same onboarding path.
            setShowSignIn(false);
            onNext();
          }}
        />
      )}
    </div>
  );
}

function SignInSheet({
  onClose,
  onContinueAsGuest,
  onContinueAsTester,
}: {
  onClose: () => void;
  onContinueAsGuest: () => void;
  onContinueAsTester: () => void;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  const canSubmit = email.includes("@") && password.length >= 8;

  return (
    <div className="premium-scrim-in fixed inset-0 z-50 flex items-end justify-center bg-black/55 sm:items-center">
      <button type="button" className="absolute inset-0" aria-label="Close sign in" onClick={onClose} />
      <div className="premium-sheet-rise relative z-10 w-full max-w-md rounded-t-3xl border border-white/10 bg-[#0A0A0A] px-6 pb-10 pt-5 shadow-2xl sm:rounded-3xl">
        <div className="mx-auto mb-5 h-1 w-10 rounded-full bg-white/15 sm:hidden" />
        <div className="mb-6 flex items-start justify-between gap-4">
          <div>
            <p className="premium-kicker-glow text-[12px] font-medium uppercase tracking-[0.2em] text-text-tertiary">
              Welcome back
            </p>
            <h2 className="mt-2 text-[28px] font-semibold tracking-tight text-text-primary">
              ARIA is still here.
            </h2>
            <p className="mt-2 text-sm text-text-secondary">
              Pick up with your coach where you left off.
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-full border border-white/12 px-3 py-1.5 text-sm text-text-secondary transition hover:border-white/20 hover:bg-white/[0.06]"
          >
            Close
          </button>
        </div>

        <div className="space-y-3">
          <label className="block">
            <span className="mb-2 block text-xs font-medium tracking-wide text-text-tertiary">Email</span>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="email"
              className="premium-field-idle w-full rounded-2xl border border-white/10 bg-white/[0.05] px-4 py-3.5 text-text-primary outline-none transition focus:border-white/25 focus:bg-white/[0.07]"
              placeholder="you@email.com"
            />
          </label>
          <label className="block">
            <span className="mb-2 block text-xs font-medium tracking-wide text-text-tertiary">Password</span>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
              className="premium-field-idle w-full rounded-2xl border border-white/10 bg-white/[0.05] px-4 py-3.5 text-text-primary outline-none transition focus:border-white/25 focus:bg-white/[0.07]"
              placeholder="••••••••"
            />
          </label>
        </div>

        {message && <p className="mt-3 text-sm text-text-secondary">{message}</p>}

        <div className="mt-6 space-y-3">
          <PremiumPrimaryButton
            disabled={!canSubmit}
            onClick={() =>
              setMessage("Cognito isn’t paired yet. Use Continue as tester for now.")
            }
          >
            <span>Sign in</span>
            <span aria-hidden>→</span>
          </PremiumPrimaryButton>

          {/* Keep until Cognito is paired — remove when real auth ships. */}
          <button
            type="button"
            onClick={onContinueAsTester}
            className="w-full rounded-full border border-steel/25 bg-steel/10 px-6 py-3.5 text-[15px] font-medium text-steel transition hover:bg-steel/15"
          >
            Continue as tester
          </button>
          <p className="text-center text-[11px] text-text-muted">
            Cognito isn’t paired yet — tester login stays for device work.
          </p>

          <button
            type="button"
            onClick={onContinueAsGuest}
            className="w-full py-3 text-sm font-medium text-text-secondary"
          >
            Continue to onboarding
          </button>
        </div>
      </div>
    </div>
  );
}
