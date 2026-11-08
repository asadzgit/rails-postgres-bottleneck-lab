-- psql -v customer_id=1 -v order_limit=20 -f ...
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT orders.* FROM orders
WHERE customer_id = :'customer_id'::bigint
ORDER BY created_at DESC, id DESC
LIMIT :'order_limit'::integer;
