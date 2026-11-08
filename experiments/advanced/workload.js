import http from 'k6/http';
import { check } from 'k6';
import { Rate } from 'k6/metrics';

const hit = new Rate('cache_hits');
const unavailable = new Rate('cache_backend_unavailable');
const scenario = __ENV.ADVANCED_SCENARIO;
const base = __ENV.BASE_URL || 'http://web:3000';
export const options = {
  vus: Number(__ENV.K6_VUS || 10), duration: __ENV.K6_DURATION || '15s',
  thresholds: { checks: ['rate==1'], http_req_failed: ['rate==0'], cache_backend_unavailable: ['rate==0'] },
};
export default function () {
  let path;
  let customer;
  if (scenario.startsWith('cache-')) {
    const id = 1 + ((__VU * 17 + __ITER * 37) % 100);
    path = `/lab/cache/items/${id}?cache=${scenario === 'cache-on' ? 1 : 0}&ttl=30&work_ms=20`;
  } else if (scenario.startsWith('read-')) {
    path = `/lab/replica/items/1?source=${scenario === 'read-primary' ? 'primary' : 'replica'}`;
  } else if (scenario.startsWith('partition-')) {
    path = `/lab/partitions/summary?layout=${scenario === 'partition-heap' ? 'heap' : 'partitioned'}&pruning=${scenario === 'partition-fanout' ? 0 : 1}`;
  } else {
    customer = 1 + ((__VU * 997 + __ITER * 7919) % Number(__ENV.SHARD_CUSTOMERS || 10000));
    path = `/lab/shards/customers/${customer}/orders?mode=${scenario === 'shard-single' ? 'single' : 'sharded'}`;
  }
  const response = http.get(base + path, { tags: { name: scenario }, timeout: '15s' });
  let body = {};
  try { body = response.json(); } catch (_) { /* check below records invalid JSON */ }
  hit.add(body.cache_status === 'hit');
  unavailable.add(body.cache_status === 'unavailable');
  let correct = response.status === 200;
  if (scenario.startsWith('cache-')) correct = correct && body.value === body.id * 100 + body.version;
  if (scenario.startsWith('read-')) correct = correct && body.version === Number(__ENV.EXPECTED_VERSION) && body.in_recovery === (scenario === 'read-replica');
  if (scenario.startsWith('partition-')) correct = correct && body.count === Number(__ENV.EXPECTED_COUNT) && body.total_cents === Number(__ENV.EXPECTED_TOTAL);
  if (scenario.startsWith('shard-')) {
    correct = correct && body.shard === (scenario === 'shard-single' ? 'single' : (customer % 2 === 0 ? 'a' : 'b'))
      && Array.isArray(body.orders) && body.orders.length <= 20
      && body.orders.every((o, i) => o.customer_id === customer && (i === 0 || body.orders[i - 1].created_at > o.created_at
        || (body.orders[i - 1].created_at === o.created_at && body.orders[i - 1].id > o.id)));
  }
  check(response, { 'HTTP and dataset/route invariants': () => correct });
}
