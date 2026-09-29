import { buildReport, fetchGuards, hitMix, requireLocalDummyEnv, textSummaryLocal } from './common.js';
import { inferBreakingPoint, stressOptions } from './ramp.js';

const RESULTS_DIR = __ENV.LOADTEST_RESULTS_DIR || 'backend/loadtest/results';

// Single shared Dummy user so the built-in 60/hour aria-chat limiter is what
// this pass measures. 429s are reported; they never abort.
export const LIMITER_USER = 'loadtest-limiter';
export const options = stressOptions();

export function setup() {
  const base = requireLocalDummyEnv();
  return { base };
}

export default function (data) {
  hitMix(data.base, LIMITER_USER, { tagUser: true });
}

export function teardown(data) {
  fetchGuards(data.base);
}

export function handleSummary(data) {
  const durationMs = (data.state && data.state.testRunDurationMs) || 0;
  const aborted = Object.values(data.thresholds || {}).some((t) => t && t.ok === false);
  const report = buildReport(data, {
    scenario: 'stress-limiter',
    breakingPoint: inferBreakingPoint(durationMs, aborted),
    guards: null,
    aborted,
  });
  return {
    stdout: textSummaryLocal(data),
    [`${RESULTS_DIR}/summary.json`]: JSON.stringify(report, null, 2),
  };
}
