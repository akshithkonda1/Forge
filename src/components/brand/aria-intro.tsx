"use client";

import { AriaMark } from "@/components/brand/aria-mark";
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
      <div className="pointer-events-none fixed inset-0">
        <div
          className="absolute inset-0"
          style={{
            background:
              "radial-gradient(ellipse 60% 45% at 50% 28%, rgba(255,106,26,0.14) 0%, transparent 70%)",
          }}
        />
      </div>

      <div className="relative z-10 mx-auto flex w-full max-w-md flex-1 flex-col px-6 pb-8 pt-10">
        <div className="flex flex-1 flex-col items-center text-center">
          <AriaMark size={112} label="ARIA" />
          <p className="mt-6 text-[11px] font-black uppercase tracking-[0.22em] text-ember">
            {ARIA_INTRO.eyebrow}
          </p>
          <h1
            className="mt-2 text-3xl font-black tracking-tight text-text-primary"
            style={{ fontFamily: "var(--font-display)" }}
          >
            {ARIA_INTRO.title}
          </h1>
          <p className="mt-3 max-w-sm text-sm leading-relaxed text-text-secondary">
            {ARIA_INTRO.lead}
          </p>

          <ul className="mt-8 w-full space-y-3 text-left">
            {ARIA_INTRO.capabilities.map((item) => (
              <li
                key={item.title}
                className="rounded-2xl border border-border bg-surface/90 px-4 py-3.5"
              >
                <p className="text-sm font-semibold text-text-primary">{item.title}</p>
                <p className="mt-1 text-sm leading-relaxed text-text-secondary">{item.body}</p>
              </li>
            ))}
          </ul>
        </div>

        <div className="mt-8 space-y-3">
          <button
            type="button"
            onClick={onContinue}
            className="w-full rounded-xl px-8 py-4 text-lg font-semibold text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-ember focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            style={{ background: "linear-gradient(135deg, #FF4D00, #FF6B2B)" }}
          >
            {ctaLabel}
          </button>
          {onSkip && (
            <button
              type="button"
              onClick={onSkip}
              className="w-full rounded-xl px-8 py-3 text-sm font-medium text-text-tertiary focus:outline-none focus-visible:ring-2 focus-visible:ring-ember"
            >
              {skipLabel ?? ARIA_INTRO.skipCta}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
