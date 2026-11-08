import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const successes = new Rate('successful_requests');
const poolTimeouts = new Rate('rails_pool_timeouts');
const connectionErrors = new Rate('database_connection_errors');
const lockTimeouts = new Rate('lock_timeouts');
const cancellations = new Rate('query_cancellations');
const successfulLatency = new Trend('successful_latency', true);
const experiment = __ENV.EXPERIMENT || 'connections';
if (!['connections', 'locks'].includes(experiment)) throw new Error('Unknown experiment');
const base = __ENV.BASE_URL || 'http://web:3000';
const thresholds = { checks: ['rate==1'] };
if (__ENV.REQUIRE_SUCCESS === '1') thresholds.http_req_failed = ['rate<0.01'];
export const options = {
  vus: Number(__ENV.K6_VUS || 12),
  duration: __ENV.K6_DURATION || '15s',
  thresholds,
};

export default function () {
  const response = experiment === 'connections'
    ? http.get(`${base}/lab/connections?hold_ms=${__ENV.HOLD_MS || 100}`, { timeout: '15s' })
    : http.post(`${base}/lab/locks/increment?mode=${__ENV.LOCK_MODE || 'long'}&work_ms=${__ENV.WORK_MS || 100}&lock_timeout_ms=${__ENV.LOCK_TIMEOUT_MS || 50}`, null, { timeout: '15s' });
  let body = {};
  try { body = response.json(); } catch (_) { /* unrecognized payload fails below */ }
  const ok = response.status === 200 && (experiment === 'connections'
    ? Number.isInteger(body.backend_pid) && body.hold_ms === Number(__ENV.HOLD_MS || 100)
    : Number.isInteger(body.value) && body.value > 0 && body.mode === (__ENV.LOCK_MODE || 'long'));
  successes.add(ok);
  poolTimeouts.add(response.status === 503 && body.error === 'rails_pool_timeout');
  connectionErrors.add(response.status === 503 && body.error === 'database_connection_unavailable');
  lockTimeouts.add(response.status === 423 && body.error === 'lock_timeout');
  cancellations.add(response.status === 503 && body.error === 'query_canceled');
  if (ok) successfulLatency.add(response.timings.duration);
  const recognized = ok
    || (experiment === 'connections' && response.status === 503 && ['rails_pool_timeout', 'database_connection_unavailable'].includes(body.error))
    || (experiment === 'locks' && response.status === 423 && body.error === 'lock_timeout')
    || (response.status === 503 && body.error === 'query_canceled');
  // Recognized failures stay failures in http_req_failed and successful_requests.
  check(response, { 'recognized success or explicit experiment failure': () => recognized });
}
