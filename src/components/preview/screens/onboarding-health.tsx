"use client";

import { Check } from "lucide-react";
import { HEALTH } from "../copy";
import {
  Capsule,
  FootCtas,
  GhostCta,
  Hairline,
  PageHead,
  PrimaryCta,
  Screen,
  Stack,
  Tessera,
} from "../primitives";
import { cn } from "@/lib/utils";

export function OnboardingHealthScreen() {
  return (
    <Screen>
      <PageHead label="Meet · Name · Health" title={HEALTH.wrapper} lead={HEALTH.body} mark />
      <Stack>
        <Tessera inset>
          {HEALTH.rows.map((row, i) => {
            const connected = row.status === "Connected";
            return (
              <div key={row.id}>
                {i > 0 ? <Hairline className="mx-4" /> : null}
                <div className="preview-inset-row">
                  <div className="min-w-0 flex-1">
                    <p className="preview-body text-text-primary">{row.title}</p>
                    <p className="preview-body mt-0.5 text-[13px] text-text-tertiary">
                      {row.subtitle}
                    </p>
                  </div>
                  <Capsule tone={connected ? "selected" : "quiet"} className={cn(connected && "gap-1")}>
                    {connected ? <Check size={12} strokeWidth={2.5} /> : null}
                    {row.status}
                  </Capsule>
                </div>
              </div>
            );
          })}
        </Tessera>
        <p className="preview-body text-[13px] text-text-tertiary">{HEALTH.hint}</p>
      </Stack>
      <FootCtas>
        <PrimaryCta>{HEALTH.continue}</PrimaryCta>
        <GhostCta>{HEALTH.later}</GhostCta>
      </FootCtas>
    </Screen>
  );
}
