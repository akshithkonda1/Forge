"use client";

import { ARIA_CINEMATIC_LINES } from "@/lib/aria-onboarding";
import { AriaOrb } from "./aria-companion";

interface WelcomeScreenProps {
  onNext: () => void;
}

export default function WelcomeScreen({ onNext }: WelcomeScreenProps) {
  const line = ARIA_CINEMATIC_LINES[0];

  return (
    <div className="relative flex min-h-[100dvh] flex-col overflow-hidden">
      <div className="pointer-events-none fixed inset-0">
        <div
          className="absolute inset-0"
          style={{
            background:
              "radial-gradient(ellipse 60% 45% at 50% 32%, rgba(168,85,247,0.14) 0%, transparent 70%)",
          }}
        />
      </div>

      <div className="relative z-10 flex flex-1 flex-col px-6 pb-8 pt-6">
        <div className="flex flex-1 flex-col items-center justify-center text-center">
          <div className="mb-8">
            <AriaOrb mood="focused" size={120} />
          </div>

          <p className="mb-2 text-[11px] font-black uppercase tracking-[0.28em] text-ember">
            FORGE × ARIA
          </p>
          <h1
            className="mb-6 max-w-sm text-3xl font-black tracking-tight text-text-primary"
            style={{ fontFamily: "var(--font-display)" }}
          >
            Meet your intelligence layer
          </h1>

          <div className="w-full max-w-md rounded-2xl border border-ember/30 bg-surface/90 p-5 text-left">
            <div className="mb-3 flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-ember" />
              <span className="text-[10px] font-black uppercase tracking-[0.16em] text-text-muted">
                ARIA
              </span>
            </div>
            <p className="text-base font-medium leading-relaxed text-text-primary">
              {line}
            </p>
          </div>
        </div>

        <div className="mx-auto w-full max-w-md">
          <button
            type="button"
            onClick={onNext}
            className="w-full rounded-xl px-8 py-4 text-lg font-semibold text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-ember focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            style={{ background: "linear-gradient(135deg, #FF4D00, #FF6B2B)" }}
          >
            Continue with ARIA
          </button>
        </div>
      </div>
    </div>
  );
}
