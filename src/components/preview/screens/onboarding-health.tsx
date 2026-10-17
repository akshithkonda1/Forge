"use client";

import { Calendar, Check, HeartPulse, ListChecks, Users } from "lucide-react";
import { AriaMark } from "@/components/brand/aria-mark";
import { HEALTH } from "../copy";
import { Capsule, GhostCta, Hairline, PrimaryCta, Tessera } from "../primitives";
import { tokenHex } from "@/lib/design-tokens";
import { cn } from "@/lib/utils";

const ICONS = {
  health: HeartPulse,
  calendar: Calendar,
  contacts: Users,
  reminders: ListChecks,
} as const;

const TINT = {
  health: tokenHex("vitality"),
  calendar: tokenHex("steel"),
  contacts: tokenHex("plate"),
  reminders: tokenHex("ember"),
} as const;

export function OnboardingHealthScreen() {
  return (
    <div className="flex h-full flex-col px-5 pb-3 pt-1">
      <div className="flex items-center gap-2.5">
        <AriaMark size={28} speaking={false} />
        <p className="type-caption text-text-tertiary">Meet · Name · Health</p>
      </div>
      <p className="preview-display mt-5 text-[1.35rem]">{HEALTH.wrapper}</p>
      <p className="preview-body mt-2 text-text-secondary">{HEALTH.body}</p>

      <Tessera className="mt-5 px-0 py-1">
        {HEALTH.rows.map((row, i) => {
          const Icon = ICONS[row.id];
          const connected = row.status === "Connected";
          return (
            <div key={row.id}>
              {i > 0 ? <Hairline className="mx-4" /> : null}
              <div className="flex min-h-[64px] items-center gap-3 px-4 py-3">
                <span
                  className="flex h-9 w-9 items-center justify-center rounded-[10px] bg-surface-elevated"
                  style={{ color: TINT[row.id] }}
                >
                  <Icon size={16} strokeWidth={2.25} />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="type-headline text-text-primary">{row.title}</p>
                  <p className="preview-body mt-0.5 text-[13px] text-text-tertiary">{row.subtitle}</p>
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

      <p className="preview-body mt-4 text-[13px] text-text-tertiary">{HEALTH.hint}</p>
      <div className="mt-auto space-y-2 pt-4">
        <PrimaryCta>{HEALTH.continue}</PrimaryCta>
        <GhostCta>{HEALTH.later}</GhostCta>
      </div>
    </div>
  );
}
