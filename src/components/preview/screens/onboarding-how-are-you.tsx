"use client";

import { AriaMark } from "@/components/brand/aria-mark";
import { HOW_ARE_YOU, SAMPLE_FIRST } from "../copy";
import { Capsule } from "../primitives";

export function OnboardingHowAreYouScreen() {
  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-2.5 px-5 pb-3 pt-1">
        <AriaMark size={28} speaking={false} />
        <div className="min-w-0">
          <p className="preview-display text-[1.15rem] leading-none">ARIA</p>
          <p className="type-micro mt-1 text-text-tertiary">Here for you · first chat</p>
        </div>
      </header>
      <div className="flex flex-1 flex-col px-5">
        <p className="type-eyebrow">How are you doing</p>
        <div className="mt-3 max-w-[85%] rounded-[18px] rounded-bl-sm bg-surface px-4 py-3">
          <p className="preview-body text-text-primary">{HOW_ARE_YOU.aria}</p>
        </div>
        <p className="preview-body mt-5 text-[13px] text-text-tertiary">
          Best way to use me: one true sentence. “I slept badly and I have forty minutes.” Not a
          search box.
        </p>
        <div className="mt-4 flex flex-wrap gap-2">
          {HOW_ARE_YOU.chips.map((chip, i) => (
            <Capsule key={chip} tone={i === 0 ? "paper" : "quiet"}>
              {chip}
            </Capsule>
          ))}
        </div>
      </div>
      <div className="px-5 pb-3 pt-2">
        <div className="flex min-h-[44px] items-center rounded-full border border-[color:var(--preview-hairline)] bg-surface px-4">
          <span className="preview-body text-text-muted">Ask something true, {SAMPLE_FIRST}</span>
        </div>
      </div>
    </div>
  );
}
