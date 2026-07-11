-- Demo OLAP data for Querya ClickHouse extension testing.
-- Runs once on first container start via /docker-entrypoint-initdb.d

CREATE DATABASE IF NOT EXISTS querya;

CREATE TABLE IF NOT EXISTS querya.customers
(
    id UInt32,
    name String,
    email String,
    city LowCardinality(String),
    created_at DateTime
)
ENGINE = MergeTree
ORDER BY id;

CREATE TABLE IF NOT EXISTS querya.products
(
    id UInt32,
    sku String,
    title String,
    category LowCardinality(String),
    price Decimal(10, 2)
)
ENGINE = MergeTree
ORDER BY id;

CREATE TABLE IF NOT EXISTS querya.orders
(
    id UInt64,
    customer_id UInt32,
    status LowCardinality(String),
    total Decimal(12, 2),
    placed_at DateTime
)
ENGINE = MergeTree
ORDER BY (placed_at, id);

CREATE TABLE IF NOT EXISTS querya.order_lines
(
    order_id UInt64,
    product_id UInt32,
    qty UInt16,
    unit_price Decimal(10, 2)
)
ENGINE = MergeTree
ORDER BY (order_id, product_id);

CREATE TABLE IF NOT EXISTS querya.events
(
    event_id UUID,
    event_time DateTime,
    user_id UInt32,
    event_type LowCardinality(String),
    path String,
    country LowCardinality(String),
    revenue Decimal(12, 4)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, user_id);

-- 500 customers
INSERT INTO querya.customers
SELECT
    toUInt32(number + 1) AS id,
    concat('Customer ', toString(number + 1)) AS name,
    concat('user', toString(number + 1), '@example.com') AS email,
    ['Berlin', 'London', 'Madrid', 'Paris', 'Tokyo', 'New York', 'São Paulo', 'Cairo'][number % 8 + 1] AS city,
    now() - toIntervalDay(number % 365) AS created_at
FROM numbers(500);

-- 80 products
INSERT INTO querya.products
SELECT
    toUInt32(number + 1) AS id,
    concat('SKU-', leftPad(toString(number + 1), 4, '0')) AS sku,
    concat('Product ', toString(number + 1)) AS title,
    ['Electronics', 'Books', 'Home', 'Sports', 'Fashion'][number % 5 + 1] AS category,
    toDecimal64(round(4.99 + (number % 200) * 1.37, 2), 2) AS price
FROM numbers(80);

-- 2_000 orders
INSERT INTO querya.orders
SELECT
    toUInt64(number + 1) AS id,
    toUInt32((number % 500) + 1) AS customer_id,
    ['new', 'paid', 'shipped', 'cancelled', 'refunded'][number % 5 + 1] AS status,
    toDecimal64(round(9.99 + (number % 150) * 2.41, 2), 2) AS total,
    now() - toIntervalHour(number % (24 * 120)) AS placed_at
FROM numbers(2000);

-- ~6_000 order lines (1–4 lines per order)
INSERT INTO querya.order_lines
SELECT
    toUInt64((number % 2000) + 1) AS order_id,
    toUInt32((number % 80) + 1) AS product_id,
    toUInt16((number % 5) + 1) AS qty,
    toDecimal64(round(4.99 + (number % 200) * 1.37, 2), 2) AS unit_price
FROM numbers(6000);

-- 50_000 analytics events
INSERT INTO querya.events
SELECT
    generateUUIDv4() AS event_id,
    now() - toIntervalSecond(number % (86400 * 30)) AS event_time,
    toUInt32((number % 500) + 1) AS user_id,
    ['page_view', 'add_to_cart', 'purchase', 'search', 'login'][number % 5 + 1] AS event_type,
    concat('/app/', ['home', 'catalog', 'product', 'checkout', 'account'][number % 5 + 1]) AS path,
    ['DE', 'GB', 'ES', 'FR', 'JP', 'US', 'BR', 'EG'][number % 8 + 1] AS country,
    if(number % 5 = 2, toDecimal64(round((number % 100) * 1.25, 4), 4), toDecimal64(0, 4)) AS revenue
FROM numbers(50000);
