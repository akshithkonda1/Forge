"use client";

import { tokenHex } from "@/lib/design-tokens";
import { SAMPLE_SLEEP } from "../sample-data";
import { Capsule, Eyebrow, FillBar, Sweep, Tessera } from "../primitives";

const STAGES = [
  { key: "deep", label: "Deep", minutes: SAMPLE_SLEEP.deep, tint: tokenHex("plate") },
  { key: "rem", label: "REM", minutes: SAMPLE_SLEEP.rem, tint: tokenHex("aurora") },
  { key: "light", label: "Light", minutes: SAMPLE_SLEEP.light, tint: tokenHex("steel") },
  { key: "awake", label: "Awake", minutes: SAMPLE_SLEEP.awake, tint: tokenHex("miss") },
] as const;

export function SleepScreen() {
  const total = STAGES.reduce((sum, s) => sum + s.minutes, 0);

  return (
    <div className="flex h-full flex-col px-5 pb-3 pt-1">
      <div className="flex items-baseline justify-between">
        <div>
          <p className="type-eyebrow">Night</p>
          <h1 className="preview-display mt-1 text-[1.5rem]">Sleep</h1>
        </div>
        <Capsule>Day · Night · Alarms</Capsule>
      </div>
      <p className="preview-body mt-1 text-text-secondary">
        Last night, in plain words. I use it to size today — not to grade you.
      </p>

      <Tessera className="mt-4 flex flex-col items-center">
        <Sweep score={SAMPLE_SLEEP.score} size={148} stroke={5.5} label="Last night" />
        <p className="preview-metric mt-2 text-[1.05rem] text-text-primary">{SAMPLE_SLEEP.total}</p>
        <p className="type-micro text-text-tertiary">Energy first. Night second.</p>
      </Tessera>

      <Tessera className="mt-3">
        <Eyebrow>Stages</Eyebrow>
        <div className="mt-3 flex h-7 w-full overflow-hidden rounded-[10px]">
          {STAGES.map((stage) => (
            <div
              key={stage.key}
              style={{
                width: `${(stage.minutes / total) * 100}%`,
                backgroundColor: stage.tint,
              }}
            />
          ))}
        </div>
        <div className="mt-3 grid grid-cols-2 gap-2">
          {STAGES.map((stage) => (
            <div key={stage.key} className="flex items-center justify-between rounded-[10px] bg-surface-elevated px-2.5 py-2">
              <span className="flex items-center gap-1.5 type-caption text-text-secondary">
                <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: stage.tint }} />
                {stage.label}
              </span>
              <span className="preview-metric text-[12px] text-text-primary">{formatMin(stage.minutes)}</span>
            </div>
          ))}
        </div>
      </Tessera>

      <Tessera className="mt-3">
        <Eyebrow>ARIA</Eyebrow>
        <p className="preview-body mt-2 text-text-primary">
          Deep and REM held. One small step tonight: lights out a little earlier. No scores, no
          guilt.
        </p>
        <div className="mt-3">
          <FillBar fraction={0.88} tint={tokenHex("plate")} />
        </div>
        <p className="type-micro mt-2 text-text-tertiary">Ask ARIA about this</p>
      </Tessera>
    </div>
  );
}

function formatMin(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}
