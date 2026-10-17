"use client";

import { AriaMark } from "@/components/brand/aria-mark";
import { MEET } from "../copy";
import { Capsule, DisplayTitle, GhostCta, PrimaryCta, Tessera } from "../primitives";

export function OnboardingMeetScreen() {
  return (
    <div className="flex h-full flex-col px-5 pb-3 pt-2">
      <div className="flex flex-1 flex-col items-center text-center">
        <div className="mt-4 flex h-[132px] w-[132px] items-center justify-center">
          <AriaMark size={112} speaking={false} label="ARIA" />
        </div>
        <p className="type-eyebrow mt-4">{MEET.eyebrow}</p>
        <DisplayTitle className="mt-1">{MEET.title}</DisplayTitle>
        <p className="preview-body mt-2 max-w-[18rem] text-text-secondary">{MEET.lead}</p>
        <ul className="mt-6 w-full space-y-2 text-left">
          {MEET.capabilities.map((item) => (
            <Tessera key={item.title} as="li" className="px-4 py-3">
              <p className="type-headline text-text-primary">{item.title}</p>
              <p className="preview-body mt-1 text-text-secondary">{item.body}</p>
            </Tessera>
          ))}
        </ul>
      </div>
      <div className="mt-4 space-y-2">
        <PrimaryCta>{MEET.talkCta}</PrimaryCta>
        <GhostCta>{MEET.skipCta}</GhostCta>
        <div className="flex justify-center">
          <Capsule>Skip is always here</Capsule>
        </div>
      </div>
    </div>
  );
}
