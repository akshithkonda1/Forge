"use client";

import { AriaMark } from "@/components/brand/aria-mark";
import { MetricPill } from "@/components/shared/metric-pill";
import { TRANSLATION_TAGLINE } from "@/lib/translation";
import { tokenHex } from "@/lib/design-tokens";
import { MOSAIC, SAMPLE_FIRST } from "../copy";
import { SAMPLE_METRICS, SAMPLE_SESSION } from "../sample-data";
import { Capsule, Eyebrow, FillBar, PrimaryCta, Sweep, Tessera } from "../primitives";

export function HomeScreen({
  overlay,
}: {
  overlay?: { prompt: string; gotIt: string; skip: string };
}) {
  return (
    <div className="relative flex h-full flex-col">
      <div className="flex-1 overflow-hidden px-5 pb-3 pt-1">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="type-eyebrow">Saturday</p>
            <h1 className="preview-display mt-1 text-[1.5rem]">Morning, {SAMPLE_FIRST}.</h1>
          </div>
          <AriaMark size={36} speaking={false} />
        </div>
        <p className="preview-body mt-2 text-text-secondary">
          Last night actually rebuilt you. You’re good. {SAMPLE_SESSION.name} still fits if we stay
          honest.
        </p>

        <Tessera className="mt-4">
          <Eyebrow>Readiness</Eyebrow>
          <div className="mt-3 flex items-center gap-4">
            <Sweep score={SAMPLE_METRICS.readiness} size={128} stroke={5.5} />
            <div className="grid flex-1 grid-cols-1 gap-2">
              <StatRow label="Sleep" value={`${SAMPLE_METRICS.sleep}`} />
              <StatRow label="Rest" value={`${SAMPLE_METRICS.rest}`} />
              <StatRow label="Stress" value={`${100 - SAMPLE_METRICS.stress}`} inverted />
              <StatRow label="Energy" value={`${SAMPLE_METRICS.energy}`} />
            </div>
          </div>
        </Tessera>

        <Tessera className="mt-3">
          <div className="flex items-baseline justify-between">
            <Eyebrow>{MOSAIC.label}</Eyebrow>
            <span className="preview-metric text-[15px] text-text-primary">{MOSAIC.headline}</span>
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2">
            {MOSAIC.tiles.map((tile) => (
              <article key={tile.track} className="rounded-[14px] bg-surface-elevated px-3 py-2.5">
                <div className="flex items-center justify-between">
                  <span className="type-micro text-text-tertiary">{tile.track}</span>
                  <span
                    className="h-1.5 w-1.5 rounded-full"
                    style={{
                      backgroundColor: tile.almost
                        ? tokenHex("plate")
                        : tokenHex("ember"),
                    }}
                  />
                </div>
                <p className="preview-metric mt-1 text-[1.05rem] text-text-primary">{tile.headline}</p>
                <p className="type-micro mt-0.5 text-text-tertiary">{tile.detail}</p>
                <div className="mt-2">
                  <FillBar
                    fraction={tile.progress}
                    tint={tile.almost ? tokenHex("plate") : tokenHex("plate")}
                  />
                </div>
              </article>
            ))}
          </div>
        </Tessera>

        <Tessera className="mt-3">
          <Eyebrow>Today’s plan</Eyebrow>
          <h2 className="type-title mt-1 text-text-primary">{SAMPLE_SESSION.name}</h2>
          <div className="mt-2 flex flex-wrap gap-1.5">
            <Capsule>{SAMPLE_SESSION.type}</Capsule>
            <Capsule>~{SAMPLE_SESSION.duration} min</Capsule>
            <Capsule>{SAMPLE_SESSION.intensity}</Capsule>
          </div>
          <ul className="mt-3 space-y-1.5">
            {SAMPLE_SESSION.exercises.slice(0, 3).map((ex) => (
              <li key={ex.name} className="flex items-center justify-between text-[13px]">
                <span className="text-text-primary">
                  <span className="mr-2 tabular-nums text-text-tertiary">{ex.n}</span>
                  {ex.name}
                </span>
                <span className="text-text-tertiary">{ex.rx}</span>
              </li>
            ))}
          </ul>
          <PrimaryCta className="mt-4">Start session</PrimaryCta>
        </Tessera>

        <div className="mt-3 flex gap-2 overflow-hidden">
          <MetricPill icon={<span className="type-micro">ST</span>} label="Steps" value={SAMPLE_METRICS.steps} />
          <MetricPill icon={<span className="type-micro">HRV</span>} label="HRV" value={`${SAMPLE_METRICS.hrv} ms`} />
        </div>

        <p className="mt-4 type-caption text-text-tertiary">{TRANSLATION_TAGLINE}</p>
      </div>
      {overlay ? <TutorialBanner prompt={overlay.prompt} gotIt={overlay.gotIt} skip={overlay.skip} /> : null}
    </div>
  );
}

function StatRow({
  label,
  value,
  inverted,
}: {
  label: string;
  value: string;
  inverted?: boolean;
}) {
  return (
    <div className="flex items-center justify-between rounded-[10px] bg-surface-elevated px-2.5 py-1.5">
      <span className="type-caption text-text-secondary">{label}</span>
      <span className="preview-metric text-[13px] text-text-primary">
        {value}
        {inverted ? null : <span className="text-text-muted">%</span>}
      </span>
    </div>
  );
}

export function TutorialBanner({
  prompt,
  gotIt,
  skip,
}: {
  prompt: string;
  gotIt: string;
  skip: string;
}) {
  return (
    <div className="preview-tutorial pointer-events-none absolute inset-x-0 top-[8px] z-20 px-3">
      <div className="rounded-[18px] border border-[color:var(--preview-hairline)] bg-surface px-3.5 py-3">
        <div className="flex items-start gap-2.5">
          <AriaMark size={24} speaking={false} />
          <p className="preview-body text-[13px] text-text-primary">{prompt}</p>
        </div>
        <div className="mt-3 flex items-center justify-between gap-2">
          <span className="preview-capsule preview-capsule-quiet">{skip}</span>
          <span className="preview-capsule preview-capsule-paper">{gotIt}</span>
        </div>
      </div>
    </div>
  );
}
