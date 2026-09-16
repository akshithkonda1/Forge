"use client";

import { AriaMark } from "@/components/brand/aria-mark";
import {
  PremiumAtmosphere,
  PremiumPresenceBloom,
  PremiumPrimaryButton,
} from "@/components/brand/premium-atmosphere";
import { ARIA_INTRO } from "@/lib/aria-intro";

export function AriaIntro({
  ctaLabel = ARIA_INTRO.talkCta,
  skipLabel,
  onContinue,
  onSkip,
}: {
  ctaLabel?: string;
  skipLabel?: string;
  onContinue: () => void;
  onSkip?: () => void;
}) {
  return (
    <div className="relative flex min-h-[100dvh] flex-col overflow-hidden bg-background">
      <PremiumAtmosphere accent="#FF6B2B" secondary="#A9D8FF" intensity={0.85} />

      <div className="relative z-10 mx-auto flex w-full max-w-md flex-1 flex-col px-6 pb-8 pt-10">
        <div className="flex flex-1 flex-col items-center text-center">
          <div className="relative flex h-48 w-52 items-center justify-center">
            <PremiumPresenceBloom size={200} />
            <AriaMark size={128} speaking label="ARIA" className="relative z-10" />
          </div>
          <p className="mt-4 text-[11px] font-medium uppercase tracking-[0.22em] text-text-tertiary">
            {ARIA_INTRO.eyebrow}
          </p>
          <h1
            className="mt-2 text-[30px] font-semibold tracking-tight text-text-primary"
            style={{ fontFamily: "var(--font-display)" }}
          >
            {ARIA_INTRO.title}
          </h1>
          <p className="mt-3 max-w-sm text-sm font-normal leading-relaxed text-text-secondary">
            {ARIA_INTRO.lead}
          </p>

          <ul className="mt-8 w-full space-y-3 text-left">
            {ARIA_INTRO.capabilities.map((item) => (
              <li
                key={item.title}
                className="rounded-2xl border border-white/8 bg-white/[0.04] px-4 py-3.5"
              >
                <p className="text-sm font-semibold text-text-primary">{item.title}</p>
                <p className="mt-1 text-sm leading-relaxed text-text-secondary">{item.body}</p>
              </li>
            ))}
          </ul>
        </div>

        <div className="mt-8 space-y-3">
          <PremiumPrimaryButton onClick={onContinue}>
            <span>{ctaLabel}</span>
            <span aria-hidden>→</span>
          </PremiumPrimaryButton>
          {onSkip && (
            <button
              type="button"
              onClick={onSkip}
              className="w-full rounded-full px-8 py-3 text-sm font-medium text-text-tertiary focus:outline-none focus-visible:ring-2 focus-visible:ring-ember"
            >
              {skipLabel ?? ARIA_INTRO.skipCta}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
