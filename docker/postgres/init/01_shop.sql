-- Demo schema for Querya manual testing (PostgreSQL).
CREATE SCHEMA IF NOT EXISTS shop;

CREATE TABLE shop.customers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  city TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE shop.products (
  id SERIAL PRIMARY KEY,
  sku TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  price NUMERIC(10, 2) NOT NULL CHECK (price >= 0)
);

CREATE TABLE shop.orders (
  id SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES shop.customers (id),
  status TEXT NOT NULL DEFAULT 'new',
  total NUMERIC(10, 2) NOT NULL DEFAULT 0,
  placed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE shop.order_lines (
  order_id INT NOT NULL REFERENCES shop.orders (id) ON DELETE CASCADE,
  product_id INT NOT NULL REFERENCES shop.products (id),
  qty INT NOT NULL CHECK (qty > 0),
  unit_price NUMERIC(10, 2) NOT NULL,
  PRIMARY KEY (order_id, product_id)
);

INSERT INTO shop.customers (name, email, city) VALUES
  ('Alice Martin', 'alice@example.com', 'Berlin'),
  ('Bob Smith', 'bob@example.com', 'London'),
  ('Carla Ruiz', 'carla@example.com', 'Madrid');

INSERT INTO shop.products (sku, title, price) VALUES
  ('SKU-001', 'Wireless Mouse', 29.99),
  ('SKU-002', 'Mechanical Keyboard', 89.00),
  ('SKU-003', 'USB-C Hub', 45.50),
  ('SKU-004', '27" Monitor', 329.00);

INSERT INTO shop.orders (customer_id, status, total, placed_at) VALUES
  (1, 'paid', 164.49, NOW() - INTERVAL '2 days'),
  (2, 'shipped', 404.49, NOW() - INTERVAL '1 day'),
  (3, 'new', 29.99, NOW());

INSERT INTO shop.order_lines (order_id, product_id, qty, unit_price) VALUES
  (1, 1, 1, 29.99),
  (1, 3, 1, 45.50),
  (1, 2, 1, 89.00),
  (2, 4, 1, 329.00),
  (2, 1, 1, 29.99),
  (2, 3, 1, 45.50),
  (3, 1, 1, 29.99);

CREATE OR REPLACE VIEW shop.customer_spending AS
SELECT
  c.id,
  c.name,
  c.city,
  COUNT(o.id) AS order_count,
  COALESCE(SUM(o.total), 0) AS lifetime_total
FROM shop.customers c
LEFT JOIN shop.orders o ON o.customer_id = c.id
GROUP BY c.id, c.name, c.city;

CREATE OR REPLACE FUNCTION shop.order_count_for_customer(p_customer_id INT)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
  SELECT COUNT(*)::INT FROM shop.orders WHERE customer_id = p_customer_id;
$$;
