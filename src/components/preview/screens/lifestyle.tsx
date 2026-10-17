"use client";

import { tokenHex } from "@/lib/design-tokens";
import { TRANSLATION_TAGLINE } from "@/lib/translation";
import { LIFESTYLE, SAMPLE_FIRST } from "../copy";
import { SAMPLE_NUTRITION } from "../sample-data";
import {
  AskAria,
  Capsule,
  Eyebrow,
  FillBar,
  PageHead,
  Screen,
  Sips,
  Stack,
  Tessera,
} from "../primitives";

export function LifestyleScreen() {
  return (
    <Screen>
      <PageHead
        label="Life"
        title={`${SAMPLE_FIRST}’s lifestyle`}
        lead={LIFESTYLE.subtitle}
      />
      <Stack>
        <div className="flex flex-wrap gap-1.5">
          {LIFESTYLE.segments.map((seg) => (
            <Capsule key={seg} tone={seg === "Nutrition" ? "paper" : "quiet"}>
              {seg}
            </Capsule>
          ))}
        </div>
        <Tessera>
          <Eyebrow>What you ate</Eyebrow>
          <p className="preview-display mt-2 text-[1.25rem]">{SAMPLE_NUTRITION.lastMeal}</p>
          <div className="mt-4">
            <div className="flex items-baseline justify-between">
              <span className="preview-row-label">Protein</span>
              <span className="preview-row-value">
                {SAMPLE_NUTRITION.protein.current}
                <span className="preview-row-hint"> / {SAMPLE_NUTRITION.protein.target}</span>
              </span>
            </div>
            <div className="mt-2">
              <FillBar fraction={SAMPLE_NUTRITION.protein.fill} tint={tokenHex("ember")} />
            </div>
          </div>
          <div className="mt-4">
            <div className="flex items-baseline justify-between">
              <span className="preview-row-label">Water</span>
              <span className="preview-row-value">
                {SAMPLE_NUTRITION.water.current} of {SAMPLE_NUTRITION.water.target} glasses
              </span>
            </div>
            <div className="mt-2">
              <Sips total={SAMPLE_NUTRITION.water.target} filled={SAMPLE_NUTRITION.water.current} />
            </div>
            <p className="preview-body mt-2 text-[13px] text-text-tertiary">
              One glass left. Almost there.
            </p>
          </div>
        </Tessera>
        <Tessera>
          <Eyebrow>ARIA</Eyebrow>
          <p className="preview-display mt-2 text-[1.2rem]">{TRANSLATION_TAGLINE}</p>
          <p className="preview-body mt-2 text-text-secondary">
            Protein is the gap for {SAMPLE_FIRST}, not a lecture. Water is almost there. Movement
            stays one part of the day.
          </p>
          <AskAria>Ask ARIA about today</AskAria>
        </Tessera>
      </Stack>
    </Screen>
  );
}
