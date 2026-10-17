"use client";

import { TRANSLATION_PILLARS, TRANSLATION_TAGLINE } from "@/lib/translation";
import { tokenHex } from "@/lib/design-tokens";
import { LIFESTYLE } from "../copy";
import { SAMPLE_NUTRITION } from "../sample-data";
import { Capsule, Eyebrow, FillBar, Tessera } from "../primitives";

export function LifestyleScreen() {
  return (
    <div className="flex h-full flex-col px-5 pb-3 pt-1">
      <p className="type-eyebrow">Life</p>
      <h1 className="preview-display mt-1 text-[1.5rem]">{LIFESTYLE.title}</h1>
      <p className="preview-body mt-1 text-text-secondary">{LIFESTYLE.subtitle}</p>

      <div className="mt-4 flex gap-1.5 overflow-hidden">
        {LIFESTYLE.segments.map((seg) => (
          <Capsule key={seg} tone={seg === "Nutrition" ? "paper" : "quiet"}>
            {seg}
          </Capsule>
        ))}
      </div>

      <Tessera className="mt-4">
        <Eyebrow>Today’s eating</Eyebrow>
        <p className="type-headline mt-2 text-text-primary">{SAMPLE_NUTRITION.lastMeal}</p>
        <div className="mt-4 space-y-3">
          <Nutrient
            label="Protein"
            value={SAMPLE_NUTRITION.protein.current}
            hint={SAMPLE_NUTRITION.protein.target}
            fill={SAMPLE_NUTRITION.protein.fill}
          />
          <Nutrient
            label="Water"
            value={SAMPLE_NUTRITION.water.current}
            hint={SAMPLE_NUTRITION.water.target}
            fill={SAMPLE_NUTRITION.water.fill}
          />
        </div>
      </Tessera>

      <Tessera className="mt-3">
        <Eyebrow>ARIA life analysis</Eyebrow>
        <p className="type-headline mt-2 text-text-primary">{TRANSLATION_TAGLINE}</p>
        <p className="preview-body mt-1 text-text-secondary">
          Protein is the gap, not a lecture. Water is almost there. Movement stays one tile.
        </p>
        <div className="mt-3 grid grid-cols-2 gap-2">
          {TRANSLATION_PILLARS.slice(0, 4).map((pillar) => (
            <article key={pillar.id} className="rounded-[14px] bg-surface-elevated px-3 py-2.5">
              <p className="type-caption text-text-primary">{pillar.title}</p>
              <p className="mt-1 text-[12px] leading-snug text-text-tertiary">{pillar.bullets[0]}</p>
            </article>
          ))}
        </div>
      </Tessera>
    </div>
  );
}

function Nutrient({
  label,
  value,
  hint,
  fill,
}: {
  label: string;
  value: string;
  hint: string;
  fill: number;
}) {
  return (
    <div>
      <div className="flex items-baseline justify-between">
        <span className="type-caption text-text-secondary">{label}</span>
        <span className="preview-metric text-[14px] text-text-primary">
          {value}
          <span className="ml-1 type-micro font-normal text-text-tertiary">/ {hint}</span>
        </span>
      </div>
      <div className="mt-1.5">
        <FillBar fraction={fill} tint={fill >= 0.8 ? tokenHex("plate") : tokenHex("ember")} />
      </div>
    </div>
  );
}
