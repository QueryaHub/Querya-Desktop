-- Querya SQLite Comprehensive Test Database Initialization
-- This script runs via Docker / init scripts to seed querya.db.

DROP TABLE IF EXISTS order_lines;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS all_sqlite_types;
DROP VIEW IF EXISTS customer_spending;

CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    city TEXT DEFAULT 'Berlin',
    is_active INTEGER DEFAULT 1,
    metadata TEXT DEFAULT '{}',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sku TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    category TEXT DEFAULT 'Peripherals',
    price REAL NOT NULL,
    stock INTEGER DEFAULT 0,
    is_available INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    total REAL NOT NULL,
    discount REAL DEFAULT 0.0,
    status TEXT DEFAULT 'pending',
    shipping_address TEXT DEFAULT '{}',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE all_sqlite_types (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    col_integer INTEGER,
    col_real REAL,
    col_text TEXT,
    col_blob BLOB,
    col_numeric NUMERIC,
    col_boolean INTEGER,
    col_datetime DATETIME,
    col_json TEXT,
    description TEXT
);

-- Seed all_sqlite_types
INSERT INTO all_sqlite_types (col_integer, col_real, col_text, col_blob, col_numeric, col_boolean, col_datetime, col_json, description)
VALUES
(
    9223372036854775807, 3.141592653589793, 'Unicode text with emoji 🚀 🗄️',
    X'DEADBEEFCAFE0102030405', 12345678.90, 1,
    '2026-08-26 10:30:00',
    '{"app": "Querya", "engine": "SQLite FFI", "features": ["VirtualGrid", "ASTFilter", "QuickCalc"]}',
    'Max boundary and rich row'
),
(
    -9223372036854775808, -2.71828, 'Negative boundaries',
    X'00000000', -12345678.90, 0,
    '1970-01-01 00:00:00',
    '["item1", "item2", 42]',
    'Min boundary row'
),
(
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    'All NULL row'
);

-- Seed 50 users
WITH RECURSIVE cnt(x) AS (
    SELECT 1
    UNION ALL
    SELECT x+1 FROM cnt WHERE x < 50
)
INSERT INTO users (username, email, full_name, city, is_active, metadata, created_at)
SELECT 
    'user_' || x,
    'user' || x || '@example.com',
    'User Name ' || x,
    CASE (x % 5) WHEN 0 THEN 'Berlin' WHEN 1 THEN 'London' WHEN 2 THEN 'Paris' WHEN 3 THEN 'Tokyo' ELSE 'New York' END,
    CASE WHEN (x % 5 = 0) THEN 0 ELSE 1 END,
    '{"tier": "' || (CASE WHEN x % 3 = 0 THEN 'gold' ELSE 'standard' END) || '", "points": ' || (x * 100) || '}',
    DATETIME('now', '-' || x || ' days')
FROM cnt;

-- Seed 30 products
WITH RECURSIVE cnt(x) AS (
    SELECT 1
    UNION ALL
    SELECT x+1 FROM cnt WHERE x < 30
)
INSERT INTO products (sku, name, category, price, stock, is_available, created_at)
SELECT 
    'SKU-' || PRINTF('%04d', x),
    'Product ' || x,
    CASE (x % 4) WHEN 0 THEN 'Hardware' WHEN 1 THEN 'Peripherals' WHEN 2 THEN 'Audio' ELSE 'Furniture' END,
    ROUND(19.99 + (x * 5.75), 2),
    (x * 10) % 150,
    1,
    DATETIME('now', '-' || x || ' days')
FROM cnt;

-- Seed 150 orders
WITH RECURSIVE cnt(x) AS (
    SELECT 1
    UNION ALL
    SELECT x+1 FROM cnt WHERE x < 150
)
INSERT INTO orders (user_id, total, discount, status, shipping_address, created_at)
SELECT 
    1 + (x % 50),
    ROUND(29.99 + (x * 4.25), 2),
    ROUND((x % 10) * 1.5, 2),
    CASE (x % 5) WHEN 0 THEN 'completed' WHEN 1 THEN 'shipped' WHEN 2 THEN 'processing' WHEN 3 THEN 'cancelled' ELSE 'pending' END,
    '{"street": "' || x || ' High St", "zip": "100' || (x % 90) || '"}',
    DATETIME('now', '-' || x || ' hours')
FROM cnt;

CREATE VIEW customer_spending AS
SELECT
    u.id AS user_id,
    u.username,
    u.email,
    u.city,
    COUNT(o.id) AS order_count,
    COALESCE(SUM(o.total), 0.0) AS total_spent,
    MAX(o.created_at) AS last_order_date
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.username, u.email, u.city;
