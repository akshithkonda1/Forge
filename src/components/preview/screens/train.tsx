"use client";

import { DISCOVERY, SAMPLE_FIRST } from "../copy";
import { SAMPLE_SESSION, SAMPLE_WEEK } from "../sample-data";
import {
  Capsule,
  Eyebrow,
  Hairline,
  PageHead,
  PrimaryCta,
  Row,
  Screen,
  Stack,
  Tessera,
  WeekRhythm,
} from "../primitives";

export function TrainScreen() {
  return (
    <Screen>
      <PageHead
        label={`${SAMPLE_FIRST}’s session`}
        title={SAMPLE_SESSION.name}
        lead={`${SAMPLE_SESSION.exercises.length} moves · ${SAMPLE_SESSION.duration} min. I never coach form.`}
      />
      <Stack>
        <Tessera>
          <Eyebrow>This week · Monday</Eyebrow>
          <div className="mt-3">
            <WeekRhythm days={SAMPLE_WEEK} />
          </div>
          <PrimaryCta className="mt-4">Start session</PrimaryCta>
        </Tessera>
        <Tessera inset>
          {SAMPLE_SESSION.exercises.slice(0, 3).map((ex, i) => (
            <div key={ex.name}>
              {i > 0 ? <Hairline className="mx-4" /> : null}
              <Row label={ex.name} value={ex.rx} />
            </div>
          ))}
          <Hairline className="mx-4" />
          <Row label="+3 more" value="in the session" />
        </Tessera>
        <Tessera>
          <Eyebrow>Something new</Eyebrow>
          <h2 className="preview-display mt-2 text-[1.25rem]">{DISCOVERY.move}</h2>
          <p className="preview-body mt-1 text-[13px] text-text-secondary">{DISCOVERY.reason}</p>
          <div className="mt-3 flex flex-wrap gap-1.5">
            <Capsule tone="paper">{DISCOVERY.tried}</Capsule>
            <Capsule>{DISCOVERY.notInterested}</Capsule>
            <Capsule>{DISCOVERY.save}</Capsule>
          </div>
        </Tessera>
      </Stack>
    </Screen>
  );
}
