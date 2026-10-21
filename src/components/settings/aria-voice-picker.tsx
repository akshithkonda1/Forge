"use client";

import { useMemo, useState, type ComponentType, type ReactNode } from "react";
import { AudioLines } from "lucide-react";
import { cn } from "@/lib/utils";
import { Sheet } from "@/components/ui/sheet";
import {
  ARIA_VOICE_BUSY_MESSAGE,
  ARIA_VOICE_PREVIEW_TEXT,
  ARIA_VOICE_RECIPES,
  applyVoiceProfile,
  speakRequestBody,
  type AriaVoiceProfile,
  type AriaVoiceSelection,
} from "@/lib/aria-voice";

export function AriaVoicePicker({
  SettingsRow,
  selection,
  onSelect,
  lastSpeakBody,
}: {
  SettingsRow: ComponentType<{
    icon?: ReactNode;
    iconColor?: string;
    label: string;
    value?: ReactNode;
    showChevron?: boolean;
    onClick?: () => void;
  }>;
  selection: AriaVoiceSelection;
  onSelect: (next: AriaVoiceSelection, speakBody: Record<string, unknown>) => void;
  lastSpeakBody?: Record<string, unknown> | null;
}) {
  const [open, setOpen] = useState(false);
  const featured = ARIA_VOICE_RECIPES;
  const selected = useMemo(
    () => featured.find((row) => row.id === selection.profileId) ?? featured[0],
    [featured, selection.profileId]
  );

  return (
    <>
      <SettingsRow
        icon={<AudioLines size={18} />}
        iconColor="text-ember"
        label="ARIA voice"
        value={
          <span className="max-w-[160px] truncate text-right text-xs text-text-secondary">
            {selected.label}
          </span>
        }
        showChevron
        onClick={() => setOpen(true)}
      />
      <Sheet open={open} onClose={() => setOpen(false)} title="ARIA voice">
        <p className="mb-4 text-sm leading-relaxed text-text-secondary">
          How she sounds. Independent of Coach, Friend, or Drill Sergeant.
          Next spoken reply uses it — no restart.
        </p>
        <div role="radiogroup" aria-label="ARIA voice" className="flex flex-col gap-2">
          {featured.map((profile) => {
            const chosen = selection.profileId === profile.id;
            return (
              <button
                key={profile.id}
                type="button"
                role="radio"
                aria-checked={chosen}
                onClick={() => {
                  const next = applyVoiceProfile(selection, profile);
                  onSelect(next, speakRequestBody(ARIA_VOICE_PREVIEW_TEXT, next));
                  setOpen(false);
                }}
                className={cn(
                  "flex items-start gap-3 rounded-xl border p-3 text-left transition-colors",
                  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember/50",
                  chosen
                    ? "border-white/20 bg-white/[0.06]"
                    : "border-border bg-surface-elevated"
                )}
              >
                <span>
                  <span className="block text-sm font-semibold text-text-primary">
                    {profile.label}
                  </span>
                  <span className="mt-1 block text-xs text-text-tertiary">
                    {profile.description}
                  </span>
                </span>
              </button>
            );
          })}
        </div>
        {lastSpeakBody?.voice_id ? (
          <p className="mt-3 text-xs text-text-tertiary">
            Next spoken reply uses {String(lastSpeakBody.voice_id)}.
          </p>
        ) : null}
        <p className="mt-3 text-xs text-text-tertiary">{ARIA_VOICE_BUSY_MESSAGE}</p>
      </Sheet>
    </>
  );
}

export function defaultVoiceSelection(
  profile: AriaVoiceProfile = ARIA_VOICE_RECIPES[0]
): AriaVoiceSelection {
  return { profileId: profile.id, voiceId: profile.voiceId ?? null, speed: profile.speed };
}
