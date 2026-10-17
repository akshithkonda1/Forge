"use client";

import { tokenHex } from "@/lib/design-tokens";
import { MOSAIC } from "../copy";
import { Capsule, Eyebrow, FillBar, Tessera } from "../primitives";

const PRS = [
  { exercise: "Bench Press", value: "225 lb", date: "28 Jan" },
  { exercise: "Squat", value: "315 lb", date: "1 Feb" },
  { exercise: "Deadlift", value: "365 lb", date: "15 Jan" },
] as const;

export function StatsScreen() {
  return (
    <div className="flex h-full flex-col px-5 pb-3 pt-1">
      <p className="type-eyebrow">Progress</p>
      <h1 className="preview-display mt-1 text-[1.5rem]">Stats</h1>
      <p className="preview-body mt-1 text-text-secondary">
        History, PRs, streaks — your training story. Lifestyle coaching only.
      </p>

      <Tessera className="mt-4">
        <div className="flex items-baseline justify-between">
          <Eyebrow>{MOSAIC.label}</Eyebrow>
          <span className="type-micro text-ember">Log</span>
        </div>
        <p className="preview-display mt-1 text-[1.25rem]">{MOSAIC.headline}</p>
        <div className="mt-3 grid grid-cols-2 gap-2">
          {MOSAIC.tiles.map((tile, i) => (
            <article
              key={tile.track}
              className="rounded-[14px] bg-surface-elevated px-3 py-2.5"
              style={i === MOSAIC.tiles.length - 1 ? { gridColumn: "1 / -1" } : undefined}
            >
              <div className="flex items-center justify-between">
                <span className="type-micro text-text-tertiary">{tile.track}</span>
                <span
                  className="h-1.5 w-1.5 rounded-full"
                  style={{ backgroundColor: tile.almost ? tokenHex("plate") : tokenHex("ember") }}
                />
              </div>
              <p className="preview-metric mt-1 text-[1.15rem] text-text-primary">{tile.headline}</p>
              <p className="type-micro mt-0.5 text-text-tertiary">{tile.detail}</p>
              <div className="mt-2">
                <FillBar fraction={tile.progress} tint={tokenHex("plate")} />
              </div>
            </article>
          ))}
        </div>
        <p className="type-caption mt-3 text-center text-ember">{MOSAIC.ask}</p>
      </Tessera>

      <Tessera className="mt-3">
        <Eyebrow>This month</Eyebrow>
        <div className="mt-3 flex gap-2">
          <Capsule tone="quiet">12 sessions</Capsule>
          <Capsule tone="quiet">8h 40m</Capsule>
          <Capsule tone="quiet">Peak 93</Capsule>
        </div>
        <div className="mt-4 space-y-2">
          {PRS.map((pr) => (
            <div key={pr.exercise} className="flex items-baseline justify-between">
              <span className="preview-body text-text-primary">{pr.exercise}</span>
              <span className="preview-metric text-[13px] text-text-primary">
                {pr.value}
                <span className="ml-2 type-micro font-normal text-text-tertiary">{pr.date}</span>
              </span>
            </div>
          ))}
        </div>
      </Tessera>
    </div>
  );
}
