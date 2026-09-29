// Shared ramping-arrival-rate ceiling for both stress passes.
export const STAGES = [
  { duration: '20s', target: 20 },
  { duration: '20s', target: 50 },
  { duration: '20s', target: 100 },
  { duration: '20s', target: 200 },
  { duration: '20s', target: 400 },
  { duration: '20s', target: 600 },
  { duration: '20s', target: 800 },
  { duration: '20s', target: 1000 },
  { duration: '20s', target: 1000 },
];

export const CEILING_RPS = STAGES[STAGES.length - 1].target;

export function stressOptions() {
  return {
    scenarios: {
      stress: {
        executor: 'ramping-arrival-rate',
        startRate: 1,
        timeUnit: '1s',
        preAllocatedVUs: 250,
        maxVUs: 2000,
        stages: STAGES,
      },
    },
    thresholds: {
      // 429s are counted but must never abort either pass.
      non_429_errors: [{ threshold: 'rate<0.01', abortOnFail: true }],
      http_req_duration: [{ threshold: 'p(95)<2000', abortOnFail: true }],
    },
    summaryTrendStats: ['avg', 'min', 'med', 'p(50)', 'p(95)', 'p(99)', 'max'],
  };
}

function stageSeconds(spec) {
  const raw = spec.duration || '0s';
  const match = /^(\d+)s$/.exec(raw);
  return match ? Number(match[1]) : 0;
}

export function inferBreakingPoint(durationMs, aborted) {
  const durationSec = durationMs / 1000;
  let elapsed = 0;
  let lastTarget = 1;
  for (const stage of STAGES) {
    const seconds = stageSeconds(stage);
    elapsed += seconds;
    if (durationSec <= elapsed) {
      return {
        aborted,
        last_completed_target_rps: lastTarget,
        failed_at_target_rps: aborted ? stage.target : null,
        held_through_target_rps: aborted ? lastTarget : stage.target,
        duration_seconds: durationSec,
        ceiling_rps: CEILING_RPS,
        note: aborted
          ? `p95 or non-429 error-rate abort during ramp to ${stage.target} rps`
          : `cap reached at ${stage.target} rps without abort`,
      };
    }
    lastTarget = stage.target;
  }
  return {
    aborted,
    last_completed_target_rps: CEILING_RPS,
    failed_at_target_rps: null,
    held_through_target_rps: CEILING_RPS,
    duration_seconds: durationSec,
    ceiling_rps: CEILING_RPS,
    note: `cap reached at ${CEILING_RPS} rps without abort`,
  };
}
