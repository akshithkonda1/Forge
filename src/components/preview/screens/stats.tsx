"use client";

import { PERSON, SAMPLE_FIRST, SAMPLE_LABEL } from "../copy";
import { SAMPLE_HISTORY, SAMPLE_PRS, SAMPLE_WEEK } from "../sample-data";
import {
  AskAria,
  Capsule,
  Eyebrow,
  PageHead,
  Row,
  Screen,
  Stack,
  Tessera,
  WeekRhythm,
} from "../primitives";

export function StatsScreen() {
  return (
    <Screen>
      <PageHead
        label={`${SAMPLE_LABEL} · ${PERSON.goalLine}`}
        title={`${SAMPLE_FIRST}’s progress`}
        lead="History, PRs, streaks — your training story. Lifestyle coaching only."
      />
      <Stack>
        <Tessera>
          <Eyebrow>This week</Eyebrow>
          <p className="preview-body mt-1 text-text-primary">
            Rest day. Three session days still on the week. Nothing logged since Thursday.
          </p>
          <div className="mt-4">
            <WeekRhythm days={SAMPLE_WEEK} />
          </div>
          <div className="mt-3 flex flex-wrap gap-1.5">
            <Capsule>12 sessions this month</Capsule>
            <Capsule>8h 40m</Capsule>
          </div>
        </Tessera>
        <Tessera>
          <Eyebrow>Recent sessions</Eyebrow>
          <div className="mt-2 space-y-1">
            {SAMPLE_HISTORY.map((session) => (
              <Row
                key={session.when}
                label={session.name}
                value={`${session.minutes}m`}
                hint={session.when}
              />
            ))}
          </div>
          <AskAria>Ask ARIA about this stretch</AskAria>
        </Tessera>
        <Tessera>
          <Eyebrow>Personal records</Eyebrow>
          <div className="mt-2 space-y-1">
            {SAMPLE_PRS.map((pr) => (
              <Row key={pr.exercise} label={pr.exercise} value={pr.value} hint={pr.date} />
            ))}
          </div>
        </Tessera>
      </Stack>
    </Screen>
  );
}
