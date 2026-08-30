-- Demo OLAP data for Querya ClickHouse extension testing.
-- Runs once on first container start via /docker-entrypoint-initdb.d

CREATE DATABASE IF NOT EXISTS querya;

CREATE TABLE IF NOT EXISTS querya.customers
(
    id UInt32,
    name String,
    email String,
    city LowCardinality(String),
    country LowCardinality(String),
    is_vip Bool,
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
    price Decimal(10, 2),
    cost Decimal(10, 2),
    stock UInt32,
    tags Array(String)
)
ENGINE = MergeTree
ORDER BY id;

CREATE TABLE IF NOT EXISTS querya.orders
(
    id UInt64,
    customer_id UInt32,
    status LowCardinality(String),
    total Decimal(12, 2),
    discount Decimal(5, 2),
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
    event_time DateTime64(3),
    user_id UInt32,
    event_type LowCardinality(String),
    path String,
    country LowCardinality(String),
    ip_v4 IPv4,
    properties Map(String, String),
    revenue Decimal(12, 4)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, user_id);

-- Comprehensive ClickHouse Data Types Table
CREATE TABLE IF NOT EXISTS querya.all_clickhouse_types
(
    id UInt32,
    col_int8 Int8,
    col_int16 Int16,
    col_int32 Int32,
    col_int64 Int64,
    col_uint8 UInt8,
    col_uint16 UInt16,
    col_uint32 UInt32,
    col_uint64 UInt64,
    col_float32 Float32,
    col_float64 Float64,
    col_decimal Decimal(18, 4),
    col_string String,
    col_fixed_string FixedString(8),
    col_low_card LowCardinality(String),
    col_date Date,
    col_date32 Date32,
    col_datetime DateTime,
    col_datetime64 DateTime64(3),
    col_uuid UUID,
    col_ipv4 IPv4,
    col_ipv6 IPv6,
    col_enum Enum8('alpha' = 1, 'beta' = 2, 'gamma' = 3),
    col_bool Bool,
    col_array_str Array(String),
    col_array_int Array(Int32),
    col_tuple Tuple(title String, count UInt16),
    col_map Map(String, String),
    col_nullable_str Nullable(String),
    col_nullable_int Nullable(Int32)
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO querya.all_clickhouse_types VALUES
(
    1, -128, -32768, -2147483648, -9223372036854775808,
    255, 65535, 4294967295, 18446744073709551615,
    3.14159, 2.718281828459045, 1234567890.1234,
    'ClickHouse String with emoji 🚀', 'CLICKHSE', 'Berlin',
    '2026-08-26', '2026-08-26', '2026-08-26 10:30:00', '2026-08-26 10:30:00.123',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', '192.168.1.1', '2001:db8::1',
    'alpha', true,
    ['one', 'two', 'three'], [10, 20, 30],
    ('Tuple Example', 42),
    map('env', 'production', 'tier', 'gold'),
    'Non-null string', 100
),
(
    2, 0, 0, 0, 0,
    0, 0, 0, 0,
    0.0, 0.0, 0.0000,
    '', '00000000', 'London',
    '1970-01-01', '1970-01-01', '1970-01-01 00:00:00', '1970-01-01 00:00:00.000',
    '00000000-0000-0000-0000-000000000000', '0.0.0.0', '::',
    'beta', false,
    [], [],
    ('', 0),
    map(),
    NULL, NULL
);

-- 500 customers
INSERT INTO querya.customers
SELECT
    toUInt32(number + 1) AS id,
    concat('Customer ', toString(number + 1)) AS name,
    concat('user', toString(number + 1), '@example.com') AS email,
    ['Berlin', 'London', 'Madrid', 'Paris', 'Tokyo', 'New York', 'São Paulo', 'Cairo'][number % 8 + 1] AS city,
    ['DEU', 'GBR', 'ESP', 'FRA', 'JPN', 'USA', 'BRA', 'EGY'][number % 8 + 1] AS country,
    (number % 5 = 0) AS is_vip,
    now() - toIntervalDay(number % 365) AS created_at
FROM numbers(500);

-- 80 products
INSERT INTO querya.products
SELECT
    toUInt32(number + 1) AS id,
    concat('SKU-', leftPad(toString(number + 1), 4, '0')) AS sku,
    concat('Product ', toString(number + 1)) AS title,
    ['Electronics', 'Books', 'Home', 'Sports', 'Fashion'][number % 5 + 1] AS category,
    toDecimal64(round(4.99 + (number % 200) * 1.37, 2), 2) AS price,
    toDecimal64(round(2.00 + (number % 100) * 0.95, 2), 2) AS cost,
    toUInt32(number * 12 % 300) AS stock,
    ['popular', 'new_arrival', 'sale'] AS tags
FROM numbers(80);

-- 2_000 orders
INSERT INTO querya.orders
SELECT
    toUInt64(number + 1) AS id,
    toUInt32((number % 500) + 1) AS customer_id,
    ['new', 'paid', 'shipped', 'cancelled', 'refunded'][number % 5 + 1] AS status,
    toDecimal64(round(9.99 + (number % 150) * 2.41, 2), 2) AS total,
    toDecimal64(round((number % 10) * 1.5, 2), 2) AS discount,
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

-- 10_000 events
INSERT INTO querya.events
SELECT
    generateUUIDv4() AS event_id,
    now64(3) - toIntervalMinute(number % (60 * 24 * 30)) AS event_time,
    toUInt32((number % 500) + 1) AS user_id,
    ['pageview', 'click', 'scroll', 'purchase', 'add_to_cart'][number % 5 + 1] AS event_type,
    ['/home', '/products', '/checkout', '/cart', '/profile'][number % 5 + 1] AS path,
    ['DEU', 'USA', 'GBR', 'FRA', 'JPN', 'CAN'][number % 6 + 1] AS country,
    toIPv4(concat('192.168.1.', toString(1 + (number % 254)))) AS ip_v4,
    map('browser', 'Chrome', 'version', '128.0') AS properties,
    toDecimal64(round((number % 50) * 1.25, 4), 4) AS revenue
FROM numbers(10000);
