import { sleep } from 'k6';
import { buildReport, fetchGuards, hitMix, requireLocalDummyEnv, textSummaryLocal } from './common.js';

const RESULTS_DIR = __ENV.LOADTEST_RESULTS_DIR || 'backend/loadtest/results';

export const options = {
  scenarios: {
    smoke: {
      executor: 'constant-vus',
      vus: 3,
      duration: '1m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(50)', 'p(95)', 'p(99)', 'max'],
};

export function setup() {
  const base = requireLocalDummyEnv();
  return { base };
}

export default function (data) {
  hitMix(data.base);
  sleep(0.2);
}

export function teardown(data) {
  fetchGuards(data.base);
}

export function handleSummary(data) {
  const report = buildReport(data, {
    scenario: 'baseline',
    breakingPoint: null,
    guards: null,
    aborted: false,
  });
  return {
    stdout: textSummaryLocal(data),
    [`${RESULTS_DIR}/summary.json`]: JSON.stringify(report, null, 2),
  };
}
