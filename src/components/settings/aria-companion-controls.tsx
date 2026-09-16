"use client";

import { useMemo, useState, type ComponentType, type ReactNode } from "react";
import { useReducedMotion } from "framer-motion";
import { Heart, MessageCircle, Pencil, Sparkles, Users } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import { useToast } from "@/stores/useToast";
import { Sheet } from "@/components/ui/sheet";
import {
  ARIA_MEMORY_FOLDERS,
  ARIA_TONE_ORDER,
  ARIA_TONES,
  WEEKLY_CHECKIN_QUESTIONS,
  weeklyCheckInIsDue,
  type AriaMemoryNote,
} from "@/lib/aria-companion";
import type { CoachingStyle } from "@/types";

const TONE_ICONS: Record<CoachingStyle, typeof MessageCircle> = {
  balanced: MessageCircle,
  patient: Heart,
  "data-driven": Sparkles,
  "push-hard": Users,
};

function formatMemoryDate(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

export function AriaCompanionControls({
  SettingsRow,
  ToggleSwitch,
}: {
  SettingsRow: ComponentType<{
    icon?: ReactNode;
    iconColor?: string;
    label: string;
    value?: ReactNode;
    showChevron?: boolean;
    rightElement?: ReactNode;
    onClick?: () => void;
  }>;
  ToggleSwitch: ComponentType<{
    enabled: boolean;
    onToggle: () => void;
    label: string;
  }>;
}) {
  const {
    userProfile,
    updateProfile,
    ariaMemoryEnabled,
    setAriaMemoryEnabled,
    ariaMemoryNotes,
    addMemoryNote,
    updateMemoryNote,
    deleteMemoryNote,
    forgetAllMemory,
    weeklyCheckInEnabled,
    setWeeklyCheckInEnabled,
    lastWeeklyCheckInAt,
    weeklyCheckInAnswers,
    setWeeklyCheckInAnswer,
    submitWeeklyCheckIn,
  } = useAppStore();
  const showToast = useToast((s) => s.show);
  const reduceMotion = useReducedMotion();

  const [sheet, setSheet] = useState<"tone" | "memory" | "checkin" | null>(null);
  const [draftNote, setDraftNote] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editText, setEditText] = useState("");
  const [confirmForget, setConfirmForget] = useState(false);

  const tone = ARIA_TONES[userProfile.coachingStyle];
  const due = weeklyCheckInIsDue(lastWeeklyCheckInAt);
  const noteCount = ariaMemoryNotes.length;

  const grouped = useMemo(() => {
    const map: Record<string, AriaMemoryNote[]> = {
      told: [],
      body: [],
      noticed: [],
    };
    for (const note of ariaMemoryNotes) {
      (map[note.folder] ?? map.told).push(note);
    }
    return map;
  }, [ariaMemoryNotes]);

  const closeSheet = () => {
    setSheet(null);
    setDraftNote("");
    setEditingId(null);
    setEditText("");
    setConfirmForget(false);
  };

  return (
    <>
      <SettingsRow
        icon={<Users size={18} />}
        iconColor="text-ember"
        label="How ARIA shows up"
        value={
          <span className="max-w-[160px] truncate text-right text-xs text-text-secondary">
            {tone.title}
          </span>
        }
        showChevron
        onClick={() => setSheet("tone")}
      />
      <div className="px-4 py-2.5">
        <p className="text-xs leading-relaxed text-text-tertiary">{tone.line}</p>
      </div>
      <SettingsRow
        icon={<MessageCircle size={18} />}
        iconColor="text-ember"
        label="What ARIA remembers"
        value={
          <span className="text-xs text-text-secondary">
            {!ariaMemoryEnabled
              ? "Off"
              : noteCount === 0
                ? "Empty"
                : `${noteCount} note${noteCount === 1 ? "" : "s"}`}
          </span>
        }
        showChevron
        onClick={() => setSheet("memory")}
      />
      <SettingsRow
        icon={<Heart size={18} />}
        iconColor="text-ember"
        label="Weekly check-in"
        rightElement={
          <ToggleSwitch
            enabled={weeklyCheckInEnabled}
            label="Weekly check-in"
            onToggle={() => {
              const next = !weeklyCheckInEnabled;
              setWeeklyCheckInEnabled(next);
              showToast(
                next
                  ? "ARIA will ask how the week went."
                  : "Weekly check-ins are off."
              );
            }}
          />
        }
      />
      {weeklyCheckInEnabled && (
        <SettingsRow
          label={due ? "This week's check-in" : "Review this week's check-in"}
          value={
            <span className="text-xs text-text-secondary">
              {due ? "Waiting" : "Saved"}
            </span>
          }
          showChevron
          onClick={() => setSheet("checkin")}
        />
      )}

      <Sheet
        open={sheet === "tone"}
        onClose={closeSheet}
        title="How ARIA shows up"
      >
        <p className="mb-4 text-sm leading-relaxed text-text-secondary">
          When the day is messy — a check-in, some space, the patterns, or an
          honest peer. Trainer is a flavor. She&apos;s still ARIA.
        </p>
        <div role="radiogroup" aria-label="How ARIA shows up" className="flex flex-col gap-2">
          {ARIA_TONE_ORDER.map((style) => {
            const option = ARIA_TONES[style];
            const selected = userProfile.coachingStyle === style;
            const Icon = TONE_ICONS[style];
            return (
              <button
                key={style}
                type="button"
                role="radio"
                aria-checked={selected}
                onClick={() => {
                  updateProfile({ coachingStyle: style });
                  setSheet(null);
                  showToast(`${option.title} — that's how she'll show up.`);
                }}
                className={cn(
                  "flex items-start gap-3 rounded-xl border p-3 text-left transition-colors",
                  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember/50",
                  selected
                    ? "border-white/20 bg-white/[0.06]"
                    : "border-border bg-surface-elevated"
                )}
              >
                <Icon
                  size={18}
                  className={selected ? "mt-0.5 text-[#F7F4F0]" : "mt-0.5 text-text-tertiary"}
                />
                <span>
                  <span className="block text-sm font-semibold text-text-primary">
                    {option.title}
                  </span>
                  <span className="mt-1 block text-xs text-text-tertiary">
                    {option.line}
                  </span>
                </span>
              </button>
            );
          })}
        </div>
      </Sheet>

      <Sheet
        open={sheet === "memory"}
        onClose={closeSheet}
        title="What ARIA remembers"
        footer={
          ariaMemoryEnabled ? (
            <div className="flex flex-col gap-2">
              <label className="sr-only" htmlFor="aria-memory-add">
                Add something for ARIA to remember
              </label>
              <textarea
                id="aria-memory-add"
                value={draftNote}
                onChange={(e) => setDraftNote(e.target.value)}
                rows={2}
                placeholder="Add something she should keep…"
                className="w-full resize-none rounded-xl border border-border bg-surface-elevated px-4 py-3 text-sm text-text-primary outline-none focus-visible:border-ember focus-visible:ring-2 focus-visible:ring-ember/40"
              />
              <button
                type="button"
                className="w-full rounded-xl bg-ember py-3 text-sm font-semibold text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember/50 disabled:opacity-40"
                disabled={!draftNote.trim()}
                onClick={() => {
                  addMemoryNote(draftNote);
                  setDraftNote("");
                  showToast("Saved. ARIA will keep that in mind.");
                }}
              >
                Save a note
              </button>
            </div>
          ) : undefined
        }
      >
        <div className="flex items-start justify-between gap-3">
          <p className="text-sm leading-relaxed text-text-secondary">
            These are notes ARIA uses so she doesn&apos;t start over. You can
            change them, drop one, or turn memory off.
          </p>
        </div>
        <div className="mt-4 flex items-center justify-between rounded-xl bg-surface-elevated px-4 py-3">
          <span className="text-sm font-medium text-text-primary">
            Keep notes between chats
          </span>
          <ToggleSwitch
            enabled={ariaMemoryEnabled}
            label="Keep notes between chats"
            onToggle={() => {
              const next = !ariaMemoryEnabled;
              setAriaMemoryEnabled(next);
              showToast(
                next
                  ? "ARIA will remember what you keep here."
                  : "ARIA won't use saved notes until you turn this back on."
              );
            }}
          />
        </div>

        {!ariaMemoryEnabled ? (
          <p className="mt-4 text-sm leading-relaxed text-text-tertiary">
            Memory is off. Notes stay on this device, hidden from ARIA, until
            you turn it back on.
          </p>
        ) : (
          <div className={cn("mt-5 space-y-5", reduceMotion && "motion-reduce:transition-none")}>
            {ARIA_MEMORY_FOLDERS.map((folder) => {
              const items = grouped[folder.id] ?? [];
              return (
                <section key={folder.id} aria-labelledby={`mem-${folder.id}`}>
                  <h3
                    id={`mem-${folder.id}`}
                    className="text-xs font-semibold uppercase tracking-wider text-text-tertiary"
                  >
                    {folder.title}
                  </h3>
                  {items.length === 0 ? (
                    <p className="mt-2 text-sm text-text-tertiary">{folder.empty}</p>
                  ) : (
                    <ul className="mt-2 space-y-2">
                      {items.map((note) => (
                        <li
                          key={note.id}
                          className="rounded-xl border border-border bg-surface-elevated px-3 py-3"
                        >
                          {editingId === note.id ? (
                            <div className="flex flex-col gap-2">
                              <label className="sr-only" htmlFor={`edit-${note.id}`}>
                                Edit this note
                              </label>
                              <textarea
                                id={`edit-${note.id}`}
                                value={editText}
                                onChange={(e) => setEditText(e.target.value)}
                                rows={3}
                                className="w-full resize-none rounded-lg border border-border bg-surface px-3 py-2 text-sm text-text-primary outline-none focus-visible:border-ember focus-visible:ring-2 focus-visible:ring-ember/40"
                              />
                              <div className="flex gap-2">
                                <button
                                  type="button"
                                  className="flex-1 rounded-lg bg-ember py-2 text-xs font-semibold text-white"
                                  onClick={() => {
                                    updateMemoryNote(note.id, editText);
                                    setEditingId(null);
                                    setEditText("");
                                    showToast("Updated.");
                                  }}
                                >
                                  Save
                                </button>
                                <button
                                  type="button"
                                  className="flex-1 rounded-lg bg-surface py-2 text-xs font-semibold text-text-secondary"
                                  onClick={() => {
                                    setEditingId(null);
                                    setEditText("");
                                  }}
                                >
                                  Cancel
                                </button>
                              </div>
                            </div>
                          ) : (
                            <>
                              <p className="text-sm leading-relaxed text-text-primary">
                                {note.text}
                              </p>
                              <div className="mt-2 flex items-center justify-between gap-2">
                                <span className="text-[11px] text-text-tertiary">
                                  {formatMemoryDate(note.createdAt)}
                                </span>
                                <div className="flex gap-3">
                                  <button
                                    type="button"
                                    className="inline-flex items-center gap-1 text-xs font-medium text-ember focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember/50"
                                    onClick={() => {
                                      setEditingId(note.id);
                                      setEditText(note.text);
                                    }}
                                  >
                                    <Pencil size={12} aria-hidden />
                                    Edit
                                  </button>
                                  <button
                                    type="button"
                                    className="text-xs font-medium text-danger focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember/50"
                                    onClick={() => {
                                      deleteMemoryNote(note.id);
                                      showToast("Forgotten.");
                                    }}
                                  >
                                    Forget
                                  </button>
                                </div>
                              </div>
                            </>
                          )}
                        </li>
                      ))}
                    </ul>
                  )}
                </section>
              );
            })}

            {noteCount > 0 && (
              <div className="pt-1">
                {confirmForget ? (
                  <div className="rounded-xl border border-danger/30 bg-danger/10 p-3">
                    <p className="text-sm text-text-secondary">
                      Forget everything ARIA has saved on this device?
                    </p>
                    <div className="mt-3 flex gap-2">
                      <button
                        type="button"
                        className="flex-1 rounded-lg bg-danger/90 py-2 text-xs font-semibold text-white"
                        onClick={() => {
                          forgetAllMemory();
                          setConfirmForget(false);
                          showToast("ARIA's notes on this device are gone.");
                        }}
                      >
                        Forget all
                      </button>
                      <button
                        type="button"
                        className="flex-1 rounded-lg bg-surface py-2 text-xs font-semibold text-text-secondary"
                        onClick={() => setConfirmForget(false)}
                      >
                        Keep them
                      </button>
                    </div>
                  </div>
                ) : (
                  <button
                    type="button"
                    className="text-xs font-medium text-text-tertiary underline-offset-2 hover:text-text-secondary hover:underline"
                    onClick={() => setConfirmForget(true)}
                  >
                    Forget everything
                  </button>
                )}
              </div>
            )}
          </div>
        )}
      </Sheet>

      <Sheet
        open={sheet === "checkin"}
        onClose={closeSheet}
        title="Weekly check-in"
        footer={
          <div className="flex gap-2">
            <button
              type="button"
              className="flex-1 rounded-xl bg-surface-elevated py-3 text-sm font-semibold text-text-secondary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember/50"
              onClick={closeSheet}
            >
              Later
            </button>
            <button
              type="button"
              className="flex-1 rounded-xl bg-ember py-3 text-sm font-semibold text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember/50"
              onClick={() => {
                submitWeeklyCheckIn();
                closeSheet();
                showToast(
                  ariaMemoryEnabled
                    ? "Saved. ARIA will keep what you asked her to remember."
                    : "Check-in saved. Memory is off, so notes stay out of chat."
                );
              }}
            >
              Save
            </button>
          </div>
        }
      >
        <p className="mb-4 text-sm leading-relaxed text-text-secondary">
          Once a week, ARIA sits down and asks — not a score, a conversation.
          Skip any question. Empty is fine.
        </p>
        <div className="flex flex-col gap-4">
          {WEEKLY_CHECKIN_QUESTIONS.map((question) => (
            <div key={question.id}>
              <label
                htmlFor={`checkin-${question.id}`}
                className="text-sm font-semibold text-text-primary"
              >
                {question.prompt}
              </label>
              <p className="mt-0.5 text-xs text-text-tertiary">{question.hint}</p>
              <textarea
                id={`checkin-${question.id}`}
                value={weeklyCheckInAnswers[question.id] ?? ""}
                onChange={(e) => setWeeklyCheckInAnswer(question.id, e.target.value)}
                rows={2}
                placeholder="Your answer"
                className="mt-2 w-full resize-none rounded-xl border border-border bg-surface-elevated px-4 py-3 text-sm text-text-primary outline-none focus-visible:border-ember focus-visible:ring-2 focus-visible:ring-ember/40"
              />
            </div>
          ))}
        </div>
      </Sheet>
    </>
  );
}
