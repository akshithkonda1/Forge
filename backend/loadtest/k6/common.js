import http from 'k6/http';
import { check, fail } from 'k6';
import { Counter, Trend } from 'k6/metrics';

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 399 }));

const routeReqs = new Counter('route_reqs');
const routeErrs = new Counter('route_errors');
const routeDur = new Trend('route_duration', true);
const routeStatus = new Counter('route_status');

const LOOPBACK = new Set(['127.0.0.1', 'localhost', '::1']);

export const READ_ROUTES = [
  { name: 'GET /health', method: 'GET', path: '/health' },
  { name: 'GET /me', method: 'GET', path: '/me' },
  { name: 'GET /dashboard/today', method: 'GET', path: '/dashboard/today' },
  { name: 'GET /sleep', method: 'GET', path: '/sleep?days=14' },
  { name: 'GET /workouts/today', method: 'GET', path: '/workouts/today' },
  { name: 'GET /workouts/history', method: 'GET', path: '/workouts/history?days=30' },
  { name: 'GET /progress/summary', method: 'GET', path: '/progress/summary?days=30' },
  { name: 'GET /chat/threads/current', method: 'GET', path: '/chat/threads/current' },
  { name: 'GET /devices/catalog', method: 'GET', path: '/devices/catalog' },
];

export const WRITE_ROUTES = [
  {
    name: 'POST /ai/chat',
    method: 'POST',
    path: '/ai/chat',
    body: { message: 'how should I train today?', recent_metrics: { readiness: 70 } },
  },
  {
    name: 'POST /ai/observe',
    method: 'POST',
    path: '/ai/observe',
    body: {
      samples: [
        {
          type: 'hrv',
          value: 48,
          unit: 'ms',
          timestamp: '2026-01-15T08:00:00+00:00',
        },
      ],
    },
  },
];

export function requireLocalDummyEnv() {
  const base = (__ENV.BASE_URL || '').trim();
  if (!base) {
    fail('BASE_URL is required and must be a localhost URL');
  }
  let parsed;
  try {
    parsed = new URL(base);
  } catch (err) {
    fail(`BASE_URL is not a valid URL: ${base}`);
  }
  if (!LOOPBACK.has(parsed.hostname)) {
    fail(`BASE_URL must target localhost/127.0.0.1, got host ${parsed.hostname}`);
  }
  if (__ENV.ARIA_BEDROCK_ENABLED !== 'false') {
    fail("ARIA_BEDROCK_ENABLED must be the string 'false'");
  }
  if (__ENV.ARIA_VOICE_ENABLED !== 'false') {
    fail("ARIA_VOICE_ENABLED must be the string 'false'");
  }
  return base.replace(/\/$/, '');
}

export function requestRoute(base, route) {
  const url = `${base}${route.path}`;
  const tags = { route: route.name };
  const params = { tags, headers: { 'content-type': 'application/json' } };
  const res =
    route.method === 'POST'
      ? http.post(url, JSON.stringify(route.body || {}), params)
      : http.get(url, params);
  const failed = res.status === 0 || res.status >= 400;
  routeReqs.add(1, tags);
  routeErrs.add(failed ? 1 : 0, tags);
  routeDur.add(res.timings.duration, tags);
  routeStatus.add(1, { route: route.name, status: String(res.status) });
  check(
    res,
    {
      'got a response': (r) => r.status !== 0,
    },
    tags,
  );
  return res;
}

export function hitMix(base) {
  const routes = READ_ROUTES.concat(WRITE_ROUTES);
  const route = routes[Math.floor(Math.random() * routes.length)];
  return requestRoute(base, route);
}

export function fetchGuards(base) {
  const res = http.get(`${base}/__loadtest/guards`, { tags: { route: 'GET /__loadtest/guards' } });
  let payload = {};
  try {
    payload = res.json();
  } catch (err) {
    payload = { parse_error: String(err), body: res.body };
  }
  return { status: res.status, payload };
}

function ensureRoute(byRoute, route) {
  if (!byRoute[route]) {
    byRoute[route] = {
      requests: 0,
      errors: 0,
      error_rate: 0,
      requests_per_second: null,
      latency_ms: {},
      status_codes: {},
    };
  }
  return byRoute[route];
}

function extractRouteStats(metrics) {
  const byRoute = {};
  for (const [name, metric] of Object.entries(metrics || {})) {
    const tagged = /^route_(reqs|errors|duration|status)\{(.+)\}$/.exec(name);
    if (tagged) {
      const kind = tagged[1];
      const tags = tagged[2];
      const routeMatch = /route:([^,}]+)/.exec(tags);
      const statusMatch = /status:([^,}]+)/.exec(tags);
      if (!routeMatch) continue;
      const stats = ensureRoute(byRoute, routeMatch[1]);
      const values = metric.values || {};
      if (kind === 'reqs') stats.requests = values.count || 0;
      if (kind === 'errors') stats.errors = values.count || 0;
      if (kind === 'duration') {
        stats.latency_ms = {
          p50: values['p(50)'] || values.med || null,
          p95: values['p(95)'] || null,
          p99: values['p(99)'] || null,
        };
      }
      if (kind === 'status' && statusMatch) {
        stats.status_codes[statusMatch[1]] = values.count || 0;
      }
      continue;
    }
    const sub = metric.submetrics || {};
    for (const [subName, subMetric] of Object.entries(sub)) {
      const routeMatch = /route:([^,}]+)/.exec(subName);
      if (!routeMatch) continue;
      const stats = ensureRoute(byRoute, routeMatch[1]);
      const values = subMetric.values || {};
      if (name === 'route_reqs') stats.requests = values.count || 0;
      if (name === 'route_errors') stats.errors = values.count || 0;
      if (name === 'route_duration') {
        stats.latency_ms = {
          p50: values['p(50)'] || values.med || null,
          p95: values['p(95)'] || null,
          p99: values['p(99)'] || null,
        };
      }
      if (name === 'route_status') {
        const statusMatch = /status:([^,}]+)/.exec(subName);
        if (statusMatch) stats.status_codes[statusMatch[1]] = values.count || 0;
      }
    }
  }
  return byRoute;
}

export function textSummaryLocal(data) {
  const metrics = data.metrics || {};
  const reqs = (metrics.http_reqs && metrics.http_reqs.values) || {};
  const failed = (metrics.http_req_failed && metrics.http_req_failed.values) || {};
  const dur = (metrics.http_req_duration && metrics.http_req_duration.values) || {};
  const lines = [
    `http_reqs: ${reqs.count || 0} (${(reqs.rate || 0).toFixed(2)}/s)`,
    `http_req_failed: ${((failed.rate || 0) * 100).toFixed(2)}%`,
    `http_req_duration p50=${dur['p(50)'] ?? 'n/a'} p95=${dur['p(95)'] ?? 'n/a'} p99=${dur['p(99)'] ?? 'n/a'}`,
  ];
  return lines.join('\n') + '\n';
}

export function buildReport(data, extra) {
  const metrics = data.metrics || {};
  const durationMs = (data.state && data.state.testRunDurationMs) || 0;
  const durationSec = durationMs / 1000 || 1;
  const reqs = (metrics.http_reqs && metrics.http_reqs.values && metrics.http_reqs.values.count) || 0;
  const failed =
    (metrics.http_req_failed && metrics.http_req_failed.values && metrics.http_req_failed.values.rate) || 0;
  const dur = (metrics.http_req_duration && metrics.http_req_duration.values) || {};
  const byRoute = extractRouteStats(metrics);
  if (extra && extra.routeStats) {
    Object.assign(byRoute, extra.routeStats);
  }
  for (const stats of Object.values(byRoute)) {
    stats.error_rate = stats.requests ? stats.errors / stats.requests : 0;
    stats.requests_per_second = stats.requests ? stats.requests / durationSec : 0;
  }
  return {
    scenario: extra.scenario,
    generated_at: new Date().toISOString(),
    duration_seconds: durationSec,
    requests: reqs,
    requests_per_second: reqs / durationSec,
    latency_ms: {
      p50: dur['p(50)'] || null,
      p95: dur['p(95)'] || null,
      p99: dur['p(99)'] || null,
      avg: dur.avg || null,
    },
    error_rate: failed,
    error_rate_overall: failed,
    per_route: byRoute,
    breaking_point: extra.breakingPoint || null,
    guards: extra.guards || null,
    thresholds: data.thresholds || {},
    aborted: Boolean(extra.aborted),
  };
}
