"use client";

import { AriaMark } from "@/components/brand/aria-mark";
import { CHAT_SAMPLE, PERSONALITIES, PERSONALITY_HINT, SAMPLE_FIRST } from "../copy";
import { SAMPLE_METRICS } from "../sample-data";
import { Capsule } from "../primitives";
import { cn } from "@/lib/utils";

export function ChatScreen() {
  return (
    <div className="flex h-full flex-col">
      <header className="flex items-start gap-2.5 px-5 pb-3 pt-1">
        <AriaMark size={32} speaking={false} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between">
            <p className="preview-display text-[1.2rem] leading-none">ARIA</p>
            <span className="preview-metric text-[13px] text-text-primary">{SAMPLE_METRICS.readiness}</span>
          </div>
          <p className="type-micro mt-1 text-text-tertiary">On this phone · Coach</p>
        </div>
      </header>

      <div className="px-5">
        <p className="type-eyebrow">Personality</p>
        <p className="type-micro mt-1 text-text-tertiary">{PERSONALITY_HINT}</p>
        <div className="mt-2.5 space-y-1.5">
          {PERSONALITIES.map((p) => {
            const selected = p.id === "coach";
            return (
              <div
                key={p.id}
                className={cn(
                  "flex min-h-[44px] items-center justify-between rounded-[14px] px-3 py-2",
                  selected ? "bg-surface" : "bg-transparent"
                )}
                style={
                  selected
                    ? { boxShadow: "inset 0 0 0 0.8px var(--preview-hairline)" }
                    : undefined
                }
              >
                <div>
                  <p className="type-headline text-text-primary">{p.label}</p>
                  <p className="type-micro mt-0.5 text-text-tertiary">{p.tone}</p>
                </div>
                <Capsule tone={selected ? "paper" : "quiet"}>{p.pacing}</Capsule>
              </div>
            );
          })}
        </div>
      </div>

      <div className="mt-4 flex-1 space-y-3 px-5">
        <div className="flex justify-end">
          <div className="max-w-[75%] rounded-[18px] rounded-br-sm bg-ember px-4 py-3">
            <p className="preview-body text-text-primary">{CHAT_SAMPLE.user}</p>
          </div>
        </div>
        <div className="flex justify-start">
          <div className="max-w-[85%] rounded-[18px] rounded-bl-sm bg-surface px-4 py-3">
            <p className="preview-body text-text-primary">{CHAT_SAMPLE.aria}</p>
          </div>
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
