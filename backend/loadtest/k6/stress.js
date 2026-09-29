import { buildReport, fetchGuards, hitMix, requireLocalDummyEnv, textSummaryLocal } from './common.js';
import { inferBreakingPoint, stressOptions } from './ramp.js';

const RESULTS_DIR = __ENV.LOADTEST_RESULTS_DIR || 'backend/loadtest/results';

// Backward-compatible alias of stress-capacity (spread synthetic users).
export const options = stressOptions();

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
