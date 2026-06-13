-- Demo schema for Querya manual testing (MySQL / MariaDB-compatible).
USE querya;

CREATE TABLE customers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  email VARCHAR(160) NOT NULL UNIQUE,
  city VARCHAR(80),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE products (
  id INT AUTO_INCREMENT PRIMARY KEY,
  sku VARCHAR(32) NOT NULL UNIQUE,
  title VARCHAR(160) NOT NULL,
  price DECIMAL(10, 2) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE orders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  customer_id INT NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'new',
  total DECIMAL(10, 2) NOT NULL DEFAULT 0,
  placed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers (id)
) ENGINE=InnoDB;

CREATE TABLE order_lines (
  order_id INT NOT NULL,
  product_id INT NOT NULL,
  qty INT NOT NULL,
  unit_price DECIMAL(10, 2) NOT NULL,
  PRIMARY KEY (order_id, product_id),
  CONSTRAINT fk_lines_order FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
  CONSTRAINT fk_lines_product FOREIGN KEY (product_id) REFERENCES products (id)
) ENGINE=InnoDB;

INSERT INTO customers (name, email, city) VALUES
  ('Alice Martin', 'alice@example.com', 'Berlin'),
  ('Bob Smith', 'bob@example.com', 'London'),
  ('Carla Ruiz', 'carla@example.com', 'Madrid');

INSERT INTO products (sku, title, price) VALUES
  ('SKU-001', 'Wireless Mouse', 29.99),
  ('SKU-002', 'Mechanical Keyboard', 89.00),
  ('SKU-003', 'USB-C Hub', 45.50),
  ('SKU-004', '27 inch Monitor', 329.00);

INSERT INTO orders (customer_id, status, total, placed_at) VALUES
  (1, 'paid', 164.49, NOW() - INTERVAL 2 DAY),
  (2, 'shipped', 404.49, NOW() - INTERVAL 1 DAY),
  (3, 'new', 29.99, NOW());

INSERT INTO order_lines (order_id, product_id, qty, unit_price) VALUES
  (1, 1, 1, 29.99),
  (1, 3, 1, 45.50),
  (1, 2, 1, 89.00),
  (2, 4, 1, 329.00),
  (2, 1, 1, 29.99),
  (2, 3, 1, 45.50),
  (3, 1, 1, 29.99);

CREATE VIEW customer_spending AS
SELECT
  c.id,
  c.name,
  c.city,
  COUNT(o.id) AS order_count,
  COALESCE(SUM(o.total), 0) AS lifetime_total
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
GROUP BY c.id, c.name, c.city;

CREATE DATABASE IF NOT EXISTS analytics;

USE analytics;

CREATE TABLE daily_sales (
  day DATE PRIMARY KEY,
  orders INT NOT NULL,
  revenue DECIMAL(12, 2) NOT NULL
) ENGINE=InnoDB;

INSERT INTO daily_sales (day, orders, revenue) VALUES
  (CURDATE() - INTERVAL 2 DAY, 12, 842.50),
  (CURDATE() - INTERVAL 1 DAY, 9, 615.00),
  (CURDATE(), 4, 203.99);
