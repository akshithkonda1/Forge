"use client";

import { AriaMark } from "@/components/brand/aria-mark";
import { MEET } from "../copy";
import { DisplayTitle, GhostCta, PrimaryCta, Tessera } from "../primitives";

export function OnboardingMeetScreen() {
  return (
    <div className="flex h-full flex-col px-5 pb-3 pt-2">
      <div className="flex flex-1 flex-col items-center text-center">
        <div className="mt-1 flex h-[92px] w-[92px] items-center justify-center">
          <AriaMark size={84} speaking={false} label="ARIA" />
        </div>
        <p className="type-eyebrow mt-3">{MEET.eyebrow}</p>
        <DisplayTitle className="mt-1">{MEET.title}</DisplayTitle>
        <p className="preview-body mt-1.5 max-w-[18rem] text-text-secondary">{MEET.lead}</p>
        <ul className="mt-4 w-full space-y-1.5 text-left">
          {MEET.capabilities.map((item) => (
            <Tessera key={item.title} as="li" className="px-4 py-2.5">
              <p className="type-headline text-text-primary">{item.title}</p>
              <p className="preview-body mt-0.5 text-[13px] text-text-secondary">{item.body}</p>
            </Tessera>
          ))}
        </ul>
      </div>
      <div className="mt-3 space-y-1">
        <PrimaryCta>{MEET.talkCta}</PrimaryCta>
        <GhostCta>{MEET.skipCta}</GhostCta>
      </div>
    </div>
  );
}
