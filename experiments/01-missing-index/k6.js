import http from 'k6/http';
import { check } from 'k6';

function integer(name, fallback, maximum) {
  const value = __ENV[name] || String(fallback);
  if (!/^[1-9][0-9]*$/.test(value) || Number(value) > maximum) {
    throw new Error(`${name} must be an integer between 1 and ${maximum}`);
  }
  return Number(value);
}

const customers = integer('CUSTOMER_COUNT', 10000, 1000000);
const limit = integer('ORDER_LIMIT', 20, 100);
const base = (__ENV.BASE_URL || 'http://web:3000').replace(/\/$/, '');
export const options = {
  vus: integer('K6_VUS', 10, 10000),
  duration: __ENV.K6_DURATION || '30s',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    checks: ['rate==1'],
  },
};

export default function () {
  // Repeatable distribution independent of wall clock or random-number state.
  const customer = 1 + ((__VU * 997 + __ITER * 7919) % customers);
  const response = http.get(`${base}/customers/${customer}/orders?limit=${limit}`, {
    tags: { name: 'GET /customers/:id/orders' },
    timeout: '15s',
  });
  let orders = null;
  try { orders = response.json().orders; } catch (_) { /* checks record failures */ }
  check(response, {
    'HTTP 200': (r) => r.status === 200,
    'bounded orders from requested customer': () => Array.isArray(orders)
      && orders.length <= limit && orders.every((o) => o.customer_id === customer),
    'most recent first, stable ties': () => Array.isArray(orders)
      && orders.every((o, i) => i === 0 || orders[i - 1].created_at > o.created_at
        || (orders[i - 1].created_at === o.created_at && orders[i - 1].id > o.id)),
  });
}
