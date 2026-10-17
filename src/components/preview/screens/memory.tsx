"use client";

import { ARIA_TONE_ORDER, ARIA_TONES } from "@/lib/aria-companion";
import { MEMORY, SAMPLE_PERSON } from "../copy";
import { SAMPLE_MEMORY_NOTES } from "../sample-data";
import { Capsule, Eyebrow, Hairline, Tessera } from "../primitives";

export function MemoryScreen() {
  return (
    <div className="flex h-full flex-col px-5 pb-3 pt-1">
      <p className="type-eyebrow">You · Settings</p>
      <h1 className="preview-display mt-1 text-[1.45rem]">{MEMORY.title}</h1>
      <p className="preview-body mt-2 text-text-secondary">{MEMORY.privacy}</p>

      <Tessera className="mt-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="type-headline text-text-primary">{MEMORY.rememberMe}</p>
            <p className="preview-body mt-1 text-[13px] text-text-tertiary">{MEMORY.rememberOn}</p>
          </div>
          <span className="preview-toggle" aria-hidden />
        </div>
      </Tessera>

      <Tessera className="mt-3 px-0 py-1">
        {SAMPLE_MEMORY_NOTES.map((note, i) => (
          <div key={note.folder}>
            {i > 0 ? <Hairline className="mx-4" /> : null}
            <div className="px-4 py-3">
              <p className="type-caption text-text-tertiary">{note.folder}</p>
              <p className="preview-body mt-1 text-text-primary">{note.note}</p>
            </div>
          </div>
        ))}
      </Tessera>

      <Tessera className="mt-3">
        <Eyebrow>{MEMORY.howITalk}</Eyebrow>
        <p className="preview-body mt-1 text-text-secondary">{MEMORY.howITalkLine}</p>
        <div className="mt-3 flex flex-wrap gap-1.5">
          {ARIA_TONE_ORDER.map((id) => (
            <Capsule key={id} tone={id === "balanced" ? "paper" : "quiet"}>
              {ARIA_TONES[id].title}
            </Capsule>
          ))}
        </div>
      </Tessera>

      <Tessera className="mt-3">
        <div className="flex items-baseline justify-between">
          <Eyebrow>{MEMORY.trainingModel}</Eyebrow>
          <span className="type-micro text-text-tertiary">{SAMPLE_PERSON.split(" ")[0]}</span>
        </div>
        <p className="preview-body mt-2 text-text-primary">{MEMORY.trainingModelValue}</p>
        <Hairline className="my-3" />
        <p className="type-caption text-text-tertiary">{MEMORY.conditions}</p>
        <p className="preview-body mt-1 text-text-primary">{MEMORY.conditionsNote}</p>
        <p className="type-micro mt-1 text-text-tertiary">{MEMORY.conditionsValue}</p>
      </Tessera>
    </div>
  );
}
