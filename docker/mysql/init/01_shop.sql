-- Demo schema for Querya manual testing (MySQL 8.4+).
USE querya;

CREATE TABLE IF NOT EXISTS customers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  email VARCHAR(160) NOT NULL UNIQUE,
  city VARCHAR(80),
  country VARCHAR(3) DEFAULT 'USA',
  is_vip BOOLEAN DEFAULT FALSE,
  metadata JSON,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS products (
  id INT AUTO_INCREMENT PRIMARY KEY,
  sku VARCHAR(32) NOT NULL UNIQUE,
  title VARCHAR(160) NOT NULL,
  category VARCHAR(64) NOT NULL DEFAULT 'General',
  price DECIMAL(10, 2) NOT NULL,
  cost DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  stock INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS orders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  customer_id INT NOT NULL,
  status ENUM('new', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded') NOT NULL DEFAULT 'new',
  total DECIMAL(10, 2) NOT NULL DEFAULT 0,
  discount DECIMAL(5, 2) NOT NULL DEFAULT 0,
  shipping_address JSON,
  placed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  delivered_at TIMESTAMP NULL,
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers (id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS order_lines (
  order_id INT NOT NULL,
  product_id INT NOT NULL,
  qty INT NOT NULL,
  unit_price DECIMAL(10, 2) NOT NULL,
  discount_applied DECIMAL(5, 2) NOT NULL DEFAULT 0,
  PRIMARY KEY (order_id, product_id),
  CONSTRAINT fk_lines_order FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
  CONSTRAINT fk_lines_product FOREIGN KEY (product_id) REFERENCES products (id)
) ENGINE=InnoDB;

-- Stored procedure to generate seed data in MySQL
DELIMITER //
CREATE PROCEDURE SeedShopData()
BEGIN
  DECLARE i INT DEFAULT 1;
  DECLARE cities VARCHAR(500) DEFAULT 'Berlin,London,Madrid,Paris,Tokyo,New York,San Francisco,Sydney,Toronto,Singapore';
  
  -- Seed 100 customers
  WHILE i <= 100 DO
    INSERT INTO customers (name, email, city, country, is_vip, metadata, created_at)
    VALUES (
      CONCAT('Customer ', i),
      CONCAT('customer', i, '@example.org'),
      ELT(1 + (i MOD 10), 'Berlin', 'London', 'Madrid', 'Paris', 'Tokyo', 'New York', 'San Francisco', 'Sydney', 'Toronto', 'Singapore'),
      ELT(1 + (i MOD 10), 'DEU', 'GBR', 'ESP', 'FRA', 'JPN', 'USA', 'USA', 'AUS', 'CAN', 'SGP'),
      (i MOD 5 = 0),
      JSON_OBJECT('loyalty_tier', IF(i MOD 5 = 0, 'gold', IF(i MOD 3 = 0, 'silver', 'bronze')), 'points', i * 42),
      DATE_SUB(NOW(), INTERVAL i DAY)
    );
    SET i = i + 1;
  END WHILE;

  -- Seed 50 products
  SET i = 1;
  WHILE i <= 50 DO
    INSERT INTO products (sku, title, category, price, cost, stock, is_active, created_at)
    VALUES (
      CONCAT('SKU-', LPAD(i, 4, '0')),
      CONCAT(ELT(1 + (i MOD 10), 'Wireless Mouse', 'Mechanical Keyboard', 'USB-C Hub', '27" 4K Monitor', 'Headphones Pro', 'Desk Chair', 'Webcam 1080p', 'Microphone', 'Laptop Stand', 'Desk Lamp'), ' v', (i DIV 10) + 1),
      ELT(1 + (i MOD 5), 'Peripherals', 'Hardware', 'Audio', 'Furniture', 'Accessories'),
      ROUND(19.99 + (i * 7.45), 2),
      ROUND(10.00 + (i * 4.20), 2),
      (i * 15) MOD 250,
      (i MOD 15 != 0),
      DATE_SUB(NOW(), INTERVAL i DAY)
    );
    SET i = i + 1;
  END WHILE;

  -- Seed 250 orders
  SET i = 1;
  WHILE i <= 250 DO
    INSERT INTO orders (customer_id, status, total, discount, shipping_address, placed_at, delivered_at)
    VALUES (
      1 + (i MOD 100),
      ELT(1 + (i MOD 6), 'new', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded'),
      ROUND(49.99 + (i * 3.15), 2),
      ROUND((i MOD 10) * 1.5, 2),
      JSON_OBJECT('street', CONCAT(i, ' Main St'), 'zip', CONCAT('1000', i MOD 90)),
      DATE_SUB(NOW(), INTERVAL (250 - i) HOUR),
      IF(i MOD 6 IN (3, 4), DATE_SUB(NOW(), INTERVAL (250 - i - 24) HOUR), NULL)
    );
    SET i = i + 1;
  END WHILE;

  -- Seed 500 order lines
  SET i = 1;
  WHILE i <= 500 DO
    INSERT IGNORE INTO order_lines (order_id, product_id, qty, unit_price, discount_applied)
    VALUES (
      1 + (i MOD 250),
      1 + ((i * 7) MOD 50),
      1 + (i MOD 5),
      ROUND(19.99 + ((1 + ((i * 7) MOD 50)) * 7.45), 2),
      0.00
    );
    SET i = i + 1;
  END WHILE;
END //
DELIMITER ;

CALL SeedShopData();
DROP PROCEDURE SeedShopData;

CREATE OR REPLACE VIEW customer_spending AS
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
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
GROUP BY c.id, c.name, c.email, c.city, c.country, c.is_vip;
