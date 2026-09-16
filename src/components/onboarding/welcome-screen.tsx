"use client";

import { useEffect, useState } from "react";
import { AriaMark } from "@/components/brand/aria-mark";
import {
  ForgeBrandMark,
  PremiumAtmosphere,
  PremiumPresenceBloom,
  PremiumPrimaryButton,
} from "@/components/brand/premium-atmosphere";
import { cn } from "@/lib/utils";

const HOOKS = [
  {
    id: "aria",
    kicker: "Meet your coach",
    title: "Hey — I'm ARIA.",
    body: "ARIA is an adaptive lifestyle coach, not a commander. You are meeting someone who will be in your mornings — readiness, sleep, the session you'd skip. Small moves compound. You still decide.",
    reward: "A coach who already knows you",
    accent: "#FF6B2B",
    frost: "#A9D8FF",
  },
  {
    id: "readiness",
    kicker: "Train on signal",
    title: "Know when to push or protect.",
    body: "ARIA takes standardized metrics and creates a standardized plan that's best for you. All your stats are saved daily so you don't erase progress but rather you build on it the next day. Everytime you use ARIA it feels intentional not like its a burden.",
    reward: "Sessions that match how you feel",
    accent: "#60A5FA",
    frost: "#A9D8FF",
  },
  {
    id: "life",
    kicker: "Built around your life",
    title: "Workouts, lifestyle, and cycle rhythm.",
    body: "ARIA looks into how you eat and sleep, but it also seeks to learn more about how you spend your free time, how you provide support to those you love in their time of need — one control center and its private by design.",
    reward: "Private by design",
    accent: "#34D399",
    frost: "#A9D8FF",
  },
  {
    id: "forge",
    kicker: "Start today",
    title: "Forge starts with one choice.",
    body: "It doesn't take long. Name your goal and how you want to train. Connect Health if you want and walk out with a first plan and a coach that already knows you.",
    reward: "Meet ARIA →",
    accent: "#F7F4F0",
    frost: "#FF6B2B",
  },
] as const;

interface WelcomeScreenProps {
  onNext: () => void;
}

export default function WelcomeScreen({ onNext }: WelcomeScreenProps) {
  const [page, setPage] = useState(0);
  const hook = HOOKS[page];

  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || page >= HOOKS.length - 1) return;
    const t = window.setTimeout(() => setPage((p) => Math.min(HOOKS.length - 1, p + 1)), 4800);
    return () => window.clearTimeout(t);
  }, [page]);

  return (
    <div className="relative flex min-h-[100dvh] flex-col overflow-hidden bg-background">
      <PremiumAtmosphere accent={hook.accent} secondary={hook.frost} />

      <div className="relative z-10 flex flex-1 flex-col px-6 pb-9 pt-5">
        <header className="flex items-center gap-3">
          <div className="flex items-center gap-2.5">
            <ForgeBrandMark size={18} />
            <span className="text-[15px] font-semibold tracking-wide text-text-primary">Forge</span>
          </div>
          <div className="flex-1" />
          <span className="rounded-full border border-white/12 bg-white/[0.06] px-3.5 py-2 text-sm font-medium text-text-primary/90">
            Sign in
          </span>
        </header>

        <div className="flex flex-1 flex-col items-center justify-center px-1 text-center">
          <div className="relative mb-7 flex h-48 w-52 items-center justify-center">
            <PremiumPresenceBloom size={210} accent={hook.accent} frost={hook.frost} />
            {hook.id === "aria" || hook.id === "forge" ? (
              <AriaMark size={140} speaking={hook.id === "aria"} label="ARIA" className="relative z-10" />
            ) : (
              <div className="relative z-10 flex h-28 w-28 items-center justify-center rounded-full border border-white/10 bg-white/[0.04]">
                <div
                  className="h-3 w-3 rounded-full"
                  style={{ background: hook.accent, boxShadow: `0 0 24px ${hook.accent}` }}
                />
              </div>
            )}
          </div>

          <p className="text-[12px] font-medium uppercase tracking-[0.24em] text-text-tertiary">
            {hook.kicker}
          </p>
          <h1
            className="mt-3 max-w-sm text-[30px] font-semibold leading-tight tracking-tight text-text-primary"
            style={{ fontFamily: "var(--font-display)" }}
          >
            {hook.title}
          </h1>
          <p className="mt-4 max-w-sm text-[15px] font-normal leading-relaxed text-text-secondary">
            {hook.body}
          </p>
          <p
            className={cn(
              "mt-4 text-[13px] font-medium",
              hook.id === "forge" ? "text-ember/90" : "text-text-tertiary"
            )}
          >
            {hook.reward}
          </p>
        </div>

        <div className="space-y-4">
          <div className="flex flex-col items-center gap-3">
            <div className="flex items-center gap-1.5">
              {HOOKS.map((_, i) => (
                <button
                  key={HOOKS[i].id}
                  type="button"
                  aria-label={`Go to slide ${i + 1}`}
                  onClick={() => setPage(i)}
                  className={cn(
                    "h-1 rounded-full transition-all duration-300",
                    i === page ? "w-5 bg-[#F7F4F0]" : "w-1.5 bg-white/16"
                  )}
                />
              ))}
            </div>
            <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-text-tertiary">
              {page + 1} of {HOOKS.length}
            </p>
          </div>

          <PremiumPrimaryButton onClick={onNext}>
            <span>Get started</span>
            <span aria-hidden>→</span>
          </PremiumPrimaryButton>

          {page < HOOKS.length - 1 && (
            <button
              type="button"
              onClick={() => setPage((p) => Math.min(HOOKS.length - 1, p + 1))}
              className="w-full py-2 text-sm font-medium text-text-secondary"
            >
              See how it works
            </button>
          )}

          <p className="text-center text-[11px] text-text-muted">
            Lifestyle fitness coaching · Live your best life
          </p>
        </div>
      </div>
    </div>
  );
}
