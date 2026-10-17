"use client";

import { AriaMark } from "@/components/brand/aria-mark";
import { MEET } from "../copy";
import { Eyebrow, FootCtas, GhostCta, PageHead, PrimaryCta, Screen, Stack, Tessera } from "../primitives";

export function OnboardingMeetScreen() {
  return (
    <Screen>
      <div className="mb-3 flex justify-center">
        <AriaMark size={72} speaking={false} label="ARIA" />
      </div>
      <PageHead label={MEET.eyebrow} title={MEET.title} lead={MEET.lead} />
      <Stack>
        {MEET.capabilities.map((item) => (
          <Tessera key={item.title} as="article">
            <Eyebrow>{item.title}</Eyebrow>
            <p className="preview-body mt-1 text-[13px] text-text-secondary">{item.body}</p>
          </Tessera>
        ))}
      </Stack>
      <FootCtas>
        <PrimaryCta>{MEET.talkCta}</PrimaryCta>
        <GhostCta>{MEET.skipCta}</GhostCta>
      </FootCtas>
    </Screen>
  );
}
