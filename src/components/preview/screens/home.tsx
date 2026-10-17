"use client";

import { AriaMark } from "@/components/brand/aria-mark";
import { MOSAIC, PERSON, SAMPLE_FIRST, SAMPLE_LABEL } from "../copy";
import { SAMPLE_SESSION, SAMPLE_WEEK } from "../sample-data";
import {
  AskAria,
  Capsule,
  Eyebrow,
  PageHead,
  PrimaryCta,
  Row,
  Screen,
  Stack,
  Tessera,
  WeekRhythm,
} from "../primitives";

export function HomeScreen({
  overlay,
}: {
  overlay?: { prompt: string; gotIt: string; skip: string };
}) {
  return (
    <Screen>
      {overlay ? null : (
        <PageHead
          label={`${SAMPLE_LABEL} · ${PERSON.name}`}
          title={`Morning, ${SAMPLE_FIRST}.`}
          lead="Last night actually rebuilt you. You’re in a good place. Monday still holds Upper Body Power."
          mark
        />
      )}
      <Stack>
        {overlay ? (
          <Tessera>
            <div className="flex items-start gap-2.5">
              <AriaMark size={24} speaking={false} />
              <p className="preview-body text-[13px] text-text-primary">{overlay.prompt}</p>
            </div>
            <div className="mt-3 flex items-center justify-between gap-2">
              <span className="preview-capsule preview-capsule-quiet">{overlay.skip}</span>
              <span className="preview-capsule preview-capsule-paper">{overlay.gotIt}</span>
            </div>
          </Tessera>
        ) : null}
        <Tessera>
          <Eyebrow>How you are</Eyebrow>
          <p className="preview-display mt-1 text-[1.65rem]">Good today</p>
          <p className="preview-body mt-1 text-[13px] text-text-secondary">
            Sleep held. Rest and energy are with you. Sat is a rest day on your week.
          </p>
          <div className="mt-4">
            <WeekRhythm days={SAMPLE_WEEK} />
          </div>
        </Tessera>
        {overlay ? null : (
          <Tessera>
            <Eyebrow>{MOSAIC.label}</Eyebrow>
            <p className="preview-body mt-1 text-text-primary">{MOSAIC.headline}</p>
            <div className="mt-3 space-y-1">
              {MOSAIC.tiles.map((tile) => (
                <Row key={tile.track} label={tile.track} value={tile.headline} hint={tile.detail} />
              ))}
            </div>
            <AskAria>{MOSAIC.ask}</AskAria>
          </Tessera>
        )}
        <Tessera>
          <Eyebrow>Your session</Eyebrow>
          <h2 className="preview-display mt-1 text-[1.25rem]">{SAMPLE_SESSION.name}</h2>
          <div className="mt-2 flex flex-wrap gap-1.5">
            <Capsule>Monday</Capsule>
            <Capsule>{SAMPLE_SESSION.type}</Capsule>
            <Capsule>{SAMPLE_SESSION.duration} min</Capsule>
          </div>
          <p className="preview-body mt-2 text-[13px] text-text-secondary">
            {SAMPLE_SESSION.exercises[0].name} · {SAMPLE_SESSION.exercises[1].name} · +4
          </p>
          <PrimaryCta className="mt-3">Start session</PrimaryCta>
        </Tessera>
      </Stack>
    </Screen>
  );
}
