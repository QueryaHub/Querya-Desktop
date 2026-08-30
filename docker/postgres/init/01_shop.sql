-- Demo schema for Querya testing (PostgreSQL).
CREATE SCHEMA IF NOT EXISTS shop;

CREATE TABLE IF NOT EXISTS shop.customers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  city TEXT,
  country VARCHAR(3) DEFAULT 'USA',
  is_vip BOOLEAN DEFAULT FALSE,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS shop.products (
  id SERIAL PRIMARY KEY,
  sku VARCHAR(32) NOT NULL UNIQUE,
  title TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'General',
  price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
  cost NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
  stock INT NOT NULL DEFAULT 0,
  tags TEXT[] DEFAULT '{}',
  specs JSONB DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS shop.orders (
  id SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES shop.customers (id),
  status TEXT NOT NULL DEFAULT 'new',
  total NUMERIC(10, 2) NOT NULL DEFAULT 0,
  discount NUMERIC(5, 2) NOT NULL DEFAULT 0,
  shipping_address JSONB DEFAULT '{}',
  placed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delivered_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS shop.order_lines (
  order_id INT NOT NULL REFERENCES shop.orders (id) ON DELETE CASCADE,
  product_id INT NOT NULL REFERENCES shop.products (id),
  qty INT NOT NULL CHECK (qty > 0),
  unit_price NUMERIC(10, 2) NOT NULL,
  discount_applied NUMERIC(5, 2) NOT NULL DEFAULT 0,
  PRIMARY KEY (order_id, product_id)
);

-- Seed 100 customers
INSERT INTO shop.customers (name, email, city, country, is_vip, metadata, created_at)
SELECT
  'Customer ' || i,
  'customer' || i || '@example.' || (CASE i % 4 WHEN 0 THEN 'com' WHEN 1 THEN 'org' WHEN 2 THEN 'io' ELSE 'net' END),
  (ARRAY['Berlin', 'London', 'Madrid', 'Paris', 'Tokyo', 'New York', 'San Francisco', 'Sydney', 'Toronto', 'Singapore'])[1 + (i % 10)],
  (ARRAY['DEU', 'GBR', 'ESP', 'FRA', 'JPN', 'USA', 'USA', 'AUS', 'CAN', 'SGP'])[1 + (i % 10)],
  (i % 5 = 0),
  jsonb_build_object('loyalty_tier', (CASE WHEN i % 5 = 0 THEN 'gold' WHEN i % 3 = 0 THEN 'silver' ELSE 'bronze' END), 'points', i * 42),
  NOW() - (i || ' days')::INTERVAL
FROM generate_series(1, 100) AS i;

-- Seed 50 products
INSERT INTO shop.products (sku, title, category, price, cost, stock, tags, specs, is_active, created_at)
SELECT
  'SKU-' || LPAD(i::TEXT, 4, '0'),
  (ARRAY['Wireless Mouse', 'Mechanical Keyboard', 'USB-C Hub', '27" 4K Monitor', 'Noise-Canceling Headphones', 'Ergonomic Desk Chair', 'Webcam 1080p', 'Microphone Pro', 'Laptop Stand', 'Smart Desk Lamp'])[1 + (i % 10)] || ' v' || (i / 10 + 1),
  (ARRAY['Peripherals', 'Hardware', 'Audio', 'Furniture', 'Accessories'])[1 + (i % 5)],
  ROUND((19.99 + (i * 7.45))::NUMERIC, 2),
  ROUND((10.00 + (i * 4.20))::NUMERIC, 2),
  (i * 15) % 250,
  ARRAY['bestseller', 'tech', (CASE i % 3 WHEN 0 THEN 'wireless' WHEN 1 THEN 'usb' ELSE 'ergonomic' END)],
  jsonb_build_object('weight_g', 150 + i * 10, 'warranty_months', (CASE WHEN i % 2 = 0 THEN 24 ELSE 12 END), 'color', (ARRAY['black', 'white', 'space_gray', 'silver'])[1 + (i % 4)]),
  (i % 15 != 0),
  NOW() - (i || ' days')::INTERVAL
FROM generate_series(1, 50) AS i;

-- Seed 300 orders
INSERT INTO shop.orders (customer_id, status, total, discount, shipping_address, placed_at, delivered_at)
SELECT
  1 + (i % 100),
  (ARRAY['new', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded'])[1 + (i % 6)],
  ROUND((49.99 + (i * 3.15))::NUMERIC, 2),
  ROUND(((i % 10) * 1.5)::NUMERIC, 2),
  jsonb_build_object('street', i || ' Main St', 'zip', '1000' || (i % 90)),
  NOW() - ((300 - i) || ' hours')::INTERVAL,
  (CASE WHEN i % 6 IN (3, 4) THEN NOW() - ((300 - i - 24) || ' hours')::INTERVAL ELSE NULL END)
FROM generate_series(1, 300) AS i;

-- Seed 800 order lines
INSERT INTO shop.order_lines (order_id, product_id, qty, unit_price, discount_applied)
SELECT
  1 + (i % 300),
  1 + ((i * 7) % 50),
  1 + (i % 5),
  ROUND((19.99 + ((1 + ((i * 7) % 50)) * 7.45))::NUMERIC, 2),
  0.00
FROM generate_series(1, 800) AS i
ON CONFLICT (order_id, product_id) DO NOTHING;

-- Views
CREATE OR REPLACE VIEW shop.customer_spending AS
SELECT
  c.id,
  c.name,
  c.email,
  c.city,
  c.country,
  c.is_vip,
  COUNT(o.id) AS order_count,
  COALESCE(SUM(o.total), 0) AS lifetime_total,
  MAX(o.placed_at) AS last_order_date
FROM shop.customers c
LEFT JOIN shop.orders o ON o.customer_id = c.id
GROUP BY c.id, c.name, c.email, c.city, c.country, c.is_vip;

CREATE MATERIALIZED VIEW IF NOT EXISTS shop.monthly_sales_summary AS
SELECT
  DATE_TRUNC('month', o.placed_at)::DATE AS sales_month,
  COUNT(DISTINCT o.id) AS total_orders,
  COUNT(DISTINCT o.customer_id) AS unique_customers,
  SUM(o.total) AS gross_revenue,
  ROUND(AVG(o.total), 2) AS avg_order_value
FROM shop.orders o
WHERE o.status NOT IN ('cancelled', 'refunded')
GROUP BY DATE_TRUNC('month', o.placed_at)::DATE
ORDER BY sales_month DESC;

-- Functions
CREATE OR REPLACE FUNCTION shop.order_count_for_customer(p_customer_id INT)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
  SELECT COUNT(*)::INT FROM shop.orders WHERE customer_id = p_customer_id;
$$;

CREATE OR REPLACE FUNCTION shop.get_customer_tier(p_lifetime_total NUMERIC)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_lifetime_total >= 5000 THEN
    RETURN 'PLATINUM';
  ELSIF p_lifetime_total >= 1000 THEN
    RETURN 'GOLD';
  ELSIF p_lifetime_total >= 250 THEN
    RETURN 'SILVER';
  ELSE
    RETURN 'BRONZE';
  END IF;
END;
$$;
