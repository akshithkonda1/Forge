"use client";

import { SAMPLE_FIRST } from "../copy";
import { SAMPLE_SLEEP } from "../sample-data";
import {
  AskAria,
  Capsule,
  Eyebrow,
  NightHours,
  PageHead,
  Row,
  Screen,
  Stack,
  Tessera,
} from "../primitives";

export function SleepScreen() {
  return (
    <Screen>
      <PageHead
        label="Last night"
        title={`${SAMPLE_FIRST}’s sleep`}
        lead="Last night, in plain words. I use it to size today — not to grade you."
      />
      <Stack>
        <Tessera>
          <Eyebrow>How long</Eyebrow>
          <p className="preview-display mt-1 text-[2rem]">{SAMPLE_SLEEP.total}</p>
          <p className="preview-body mt-1 text-[13px] text-text-secondary">
            A solid night. Energy first. Night second.
          </p>
          <div className="mt-3 flex flex-wrap gap-1.5">
            <Capsule>Day</Capsule>
            <Capsule tone="paper">Night</Capsule>
            <Capsule>Alarms</Capsule>
          </div>
        </Tessera>
        <Tessera>
          <Eyebrow>How the night went</Eyebrow>
          <div className="mt-3">
            <NightHours hours={SAMPLE_SLEEP.hours} />
          </div>
          <div className="mt-3 space-y-1">
            <Row label="Deep" value={formatMin(SAMPLE_SLEEP.deep)} />
            <Row label="REM" value={formatMin(SAMPLE_SLEEP.rem)} />
            <Row label="Light" value={formatMin(SAMPLE_SLEEP.light)} />
            <Row label="Awake" value={formatMin(SAMPLE_SLEEP.awake)} hint="a brief stir at 3" />
          </div>
        </Tessera>
        <Tessera>
          <Eyebrow>ARIA</Eyebrow>
          <p className="preview-body mt-2 text-text-primary">
            Deep and REM held. One small step tonight: lights out a little earlier. No scores, no
            guilt.
          </p>
          <p className="preview-body mt-2 text-[13px] text-text-tertiary">
            No alarm set. That’s fine — I’ll still size Monday from this night.
          </p>
          <AskAria>Ask ARIA about this</AskAria>
        </Tessera>
      </Stack>
    </Screen>
  );
}

function formatMin(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}
