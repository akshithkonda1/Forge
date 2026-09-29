import { buildReport, fetchGuards, hitMix, requireLocalDummyEnv, textSummaryLocal } from './common.js';

const RESULTS_DIR = __ENV.LOADTEST_RESULTS_DIR || 'backend/loadtest/results';

// Ramp arrival rate until non-429 errors or p95 trip abortOnFail. Ceiling is
// 1000 rps — high enough to find Dummy ThreadingHTTPServer degradation on
// 4 CPUs. 429s are counted but do not abort (per-user limiter is still on).
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

export const options = {
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
    non_429_errors: [{ threshold: 'rate<0.01', abortOnFail: true }],
    http_req_duration: [{ threshold: 'p(95)<2000', abortOnFail: true }],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(50)', 'p(95)', 'p(99)', 'max'],
};

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
        ceiling_rps: STAGES[STAGES.length - 1].target,
        note: aborted
          ? `p95 or non-429 error-rate abort during ramp to ${stage.target} rps`
          : `cap reached at ${stage.target} rps without abort`,
      };
    }
    lastTarget = stage.target;
  }
  const cap = STAGES[STAGES.length - 1].target;
  return {
    aborted,
    last_completed_target_rps: cap,
    failed_at_target_rps: null,
    held_through_target_rps: cap,
    duration_seconds: durationSec,
    ceiling_rps: cap,
    note: `cap reached at ${cap} rps without abort`,
  };
}

export function setup() {
  const base = requireLocalDummyEnv();
  return { base };
}

export default function (data) {
  hitMix(data.base, `loadtest-${__VU}-${__ITER}`);
}

export function teardown(data) {
  fetchGuards(data.base);
}

export function handleSummary(data) {
  const durationMs = (data.state && data.state.testRunDurationMs) || 0;
  const aborted = Object.values(data.thresholds || {}).some((t) => t && t.ok === false);
  const report = buildReport(data, {
    scenario: 'stress',
    breakingPoint: inferBreakingPoint(durationMs, aborted),
    guards: null,
    aborted,
  });
  return {
    stdout: textSummaryLocal(data),
    [`${RESULTS_DIR}/summary.json`]: JSON.stringify(report, null, 2),
  };
}
