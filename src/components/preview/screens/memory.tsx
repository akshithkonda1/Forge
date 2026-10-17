"use client";

import { ARIA_TONE_ORDER, ARIA_TONES } from "@/lib/aria-companion";
import { MEMORY, SAMPLE_FIRST } from "../copy";
import { SAMPLE_MEMORY_NOTES } from "../sample-data";
import {
  Capsule,
  Eyebrow,
  Hairline,
  PageHead,
  Screen,
  Stack,
  Tessera,
} from "../primitives";

export function MemoryScreen() {
  return (
    <Screen>
      <PageHead
        label={`${SAMPLE_FIRST} · You`}
        title={MEMORY.title}
        lead="On this phone. I don’t share this off-device."
      />
      <Stack>
        <Tessera>
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0">
              <p className="preview-display text-[1.2rem]">{MEMORY.rememberMe}</p>
              <p className="preview-body mt-1 text-[13px] text-text-tertiary">{MEMORY.rememberOn}</p>
            </div>
            <span className="preview-toggle" aria-hidden />
          </div>
        </Tessera>
        <Tessera inset>
          {SAMPLE_MEMORY_NOTES.map((note, i) => (
            <div key={note.folder}>
              {i > 0 ? <Hairline className="mx-4" /> : null}
              <div className="preview-inset-row flex-col items-start gap-0.5">
                <p className="preview-label">{note.folder}</p>
                <p className="preview-body text-[13px] text-text-primary">{note.note}</p>
              </div>
            </div>
          ))}
        </Tessera>
        <Tessera>
          <Eyebrow>{MEMORY.howITalk}</Eyebrow>
          <p className="preview-body mt-1 text-[13px] text-text-secondary">{MEMORY.howITalkLine}</p>
          <div className="mt-3 flex flex-wrap gap-1.5">
            {ARIA_TONE_ORDER.map((id) => (
              <Capsule key={id} tone={id === "balanced" ? "paper" : "quiet"}>
                {ARIA_TONES[id].title}
              </Capsule>
            ))}
          </div>
        </Tessera>
        <Tessera>
          <Eyebrow>{MEMORY.trainingModel}</Eyebrow>
          <p className="preview-body mt-2 text-[13px] text-text-primary">{MEMORY.trainingModelValue}</p>
          <p className="preview-label mt-3">{MEMORY.conditions}</p>
          <p className="preview-body mt-1 text-[13px] text-text-tertiary">{MEMORY.conditionsNote}</p>
        </Tessera>
      </Stack>
    </Screen>
  );
}
