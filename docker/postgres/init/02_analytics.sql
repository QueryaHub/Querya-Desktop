-- Second database for multi-DB testing in Querya.
CREATE DATABASE analytics;

\connect analytics

CREATE SCHEMA IF NOT EXISTS metrics;

CREATE TABLE IF NOT EXISTS metrics.daily_sales (
  day DATE PRIMARY KEY,
  orders INT NOT NULL,
  gross_revenue NUMERIC(12, 2) NOT NULL,
  net_revenue NUMERIC(12, 2) NOT NULL,
  refunds NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  new_customers INT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS metrics.user_events (
  event_id BIGSERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  event_type VARCHAR(64) NOT NULL,
  page_url TEXT NOT NULL,
  referrer TEXT,
  user_agent TEXT,
  ip_address INET,
  duration_seconds NUMERIC(8, 2),
  event_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed 90 days of daily sales
INSERT INTO metrics.daily_sales (day, orders, gross_revenue, net_revenue, refunds, new_customers)
SELECT
  (CURRENT_DATE - (90 - i)) AS day,
  10 + (i * 3) % 45,
  ROUND((500.00 + (i * 45.20) + ((i % 7) * 120.00))::NUMERIC, 2),
  ROUND((450.00 + (i * 40.00) + ((i % 7) * 110.00))::NUMERIC, 2),
  ROUND(((i % 5) * 25.50)::NUMERIC, 2),
  2 + (i % 12)
FROM generate_series(1, 90) AS i
ON CONFLICT (day) DO NOTHING;

-- Seed 500 user events
INSERT INTO metrics.user_events (user_id, event_type, page_url, referrer, user_agent, ip_address, duration_seconds, event_time)
SELECT
  1 + (i % 150),
  (ARRAY['pageview', 'button_click', 'add_to_cart', 'search', 'checkout_start', 'payment_success'])[1 + (i % 6)],
  (ARRAY['/home', '/products', '/cart', '/checkout', '/account', '/search?q=keyboard', '/pricing'])[1 + (i % 7)],
  (ARRAY['https://google.com', 'https://github.com', 'https://twitter.com', NULL, 'https://reddit.com'])[1 + (i % 5)],
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)',
  ('192.168.1.' || (1 + (i % 254)))::INET,
  ROUND((1.5 + (i % 60) * 2.3)::NUMERIC, 2),
  NOW() - ((500 - i) * 10 || ' minutes')::INTERVAL
FROM generate_series(1, 500) AS i;
