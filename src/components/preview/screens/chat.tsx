"use client";

import { CHAT_SAMPLE, PERSONALITIES, PERSONALITY_HINT, SAMPLE_FIRST } from "../copy";
import { Capsule, Eyebrow, PageHead, Screen, Tessera } from "../primitives";

export function ChatScreen() {
  return (
    <Screen>
      <PageHead
        label={`Talking with ${SAMPLE_FIRST}`}
        title="ARIA"
        lead="Coach is on. Changes the next reply — no restart."
        mark
      />
      <Tessera>
        <Eyebrow>How I show up</Eyebrow>
        <p className="preview-body mt-1 text-[13px] text-text-tertiary">{PERSONALITY_HINT}</p>
        <div className="mt-3 flex flex-wrap gap-1.5">
          {PERSONALITIES.map((p) => (
            <Capsule key={p.id} tone={p.id === "coach" ? "paper" : "quiet"}>
              {p.label}
            </Capsule>
          ))}
        </div>
        <p className="preview-body mt-3 text-[13px] text-text-secondary">
          {PERSONALITIES[0].tone}
        </p>
      </Tessera>
      <div className="preview-stack mt-3 flex-1">
        <div className="preview-bubble preview-bubble-you">
          <p className="preview-body text-text-primary">{CHAT_SAMPLE.user}</p>
        </div>
        <div className="preview-bubble preview-bubble-aria">
          <p className="preview-body text-text-primary">{CHAT_SAMPLE.aria}</p>
        </div>
      </div>
      <div className="preview-composer mt-3">{`Ask something true, ${SAMPLE_FIRST}`}</div>
    </Screen>
  );
}
