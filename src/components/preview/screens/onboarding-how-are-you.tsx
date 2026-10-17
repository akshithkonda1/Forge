"use client";

import { HOW_ARE_YOU, SAMPLE_FIRST } from "../copy";
import { Capsule, PageHead, Screen } from "../primitives";

export function OnboardingHowAreYouScreen() {
  return (
    <Screen>
      <PageHead
        label="Here for you · first chat"
        title="How are you doing"
        lead="Best way to use me: one true sentence. “I slept badly and I have forty minutes.” Not a search box."
        mark
      />
      <div className="preview-bubble preview-bubble-aria">
        <p className="preview-body text-text-primary">{HOW_ARE_YOU.aria}</p>
      </div>
      <div className="mt-4 flex flex-wrap gap-2">
        {HOW_ARE_YOU.chips.map((chip, i) => (
          <Capsule key={chip} tone={i === 0 ? "paper" : "quiet"}>
            {chip}
          </Capsule>
        ))}
      </div>
      <div className="preview-composer mt-auto">{`Ask something true, ${SAMPLE_FIRST}`}</div>
    </Screen>
  );
}
