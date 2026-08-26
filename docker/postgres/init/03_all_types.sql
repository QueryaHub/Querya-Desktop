-- Comprehensive PostgreSQL Data Types Showcase Schema
\connect querya

DROP SCHEMA IF EXISTS types_showcase CASCADE;
CREATE SCHEMA types_showcase;

-- 1. Custom User Types (Enums, Domains, Composite Types)
CREATE TYPE types_showcase.user_role_enum AS ENUM ('admin', 'editor', 'viewer', 'guest');
CREATE TYPE types_showcase.order_status_enum AS ENUM ('draft', 'pending', 'processing', 'completed', 'cancelled', 'refunded');

CREATE DOMAIN types_showcase.positive_int AS INTEGER CHECK (VALUE > 0);
CREATE DOMAIN types_showcase.valid_email AS TEXT CHECK (VALUE ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

CREATE TYPE types_showcase.geo_coordinate AS (
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  altitude REAL
);

CREATE TYPE types_showcase.address_type AS (
  street TEXT,
  city TEXT,
  postal_code VARCHAR(16),
  country VARCHAR(3)
);

-- 2. Numerics and Booleans
CREATE TABLE types_showcase.all_numerics (
  id SERIAL PRIMARY KEY,
  col_smallint SMALLINT,
  col_integer INTEGER,
  col_bigint BIGINT,
  col_numeric NUMERIC(18, 4),
  col_decimal DECIMAL(10, 2),
  col_real REAL,
  col_double DOUBLE PRECISION,
  col_money MONEY,
  col_boolean BOOLEAN,
  description TEXT
);

INSERT INTO types_showcase.all_numerics 
  (col_smallint, col_integer, col_bigint, col_numeric, col_decimal, col_real, col_double, col_money, col_boolean, description)
VALUES
  (32767, 2147483647, 9223372036854775807, 12345678901234.5678, 12345678.90, 3.14159, 2.718281828459045, '999.99'::MONEY, TRUE, 'Max boundary values'),
  (-32768, -2147483648, -9223372036854775808, -12345678901234.5678, -12345678.90, -3.14159, -2.718281828459045, '-999.99'::MONEY, FALSE, 'Min boundary values'),
  (0, 0, 0, 0.0000, 0.00, 0.0, 0.0, '0.00'::MONEY, TRUE, 'Zero values'),
  (42, 1000, 1000000000, 42.4200, 99.50, 1.23, 4.56789, '1500.50'::MONEY, FALSE, 'Typical sample row'),
  (NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'All NULLs');

-- 3. Strings and Text
CREATE TABLE types_showcase.all_strings (
  id SERIAL PRIMARY KEY,
  col_char CHAR(10),
  col_varchar VARCHAR(100),
  col_text TEXT,
  col_name NAME,
  description TEXT
);

INSERT INTO types_showcase.all_strings (col_char, col_varchar, col_text, col_name, description)
VALUES
  ('FIXED', 'Variable length string', 'Long multiline text paragraph with special characters: "quotes", \slashes\, and emoji 🚀 🐘 🔥', 'pg_identifier_name', 'Standard strings'),
  ('UTF8', 'Привет, мир! こんにちは世界', 'Русский текст, иероглифы и диакритика: résumé, naïve, über', 'utf8_name', 'International Unicode strings'),
  ('EMPTY', '', '', 'empty_test', 'Empty string test'),
  ('SQL_DANGER', ''' OR ''1''=''1', 'SELECT * FROM users; DROP TABLE test; --', 'sql_inject', 'SQL escape check'),
  (NULL, NULL, NULL, NULL, 'All NULL strings');

-- 4. Date, Time and Temporal
CREATE TABLE types_showcase.all_datetime (
  id SERIAL PRIMARY KEY,
  col_date DATE,
  col_time TIME,
  col_timetz TIMETZ,
  col_timestamp TIMESTAMP,
  col_timestamptz TIMESTAMPTZ,
  col_interval INTERVAL,
  description TEXT
);

INSERT INTO types_showcase.all_datetime (col_date, col_time, col_timetz, col_timestamp, col_timestamptz, col_interval, description)
VALUES
  ('2026-08-26', '10:30:00', '10:30:00+03:00', '2026-08-26 10:30:00', '2026-08-26 10:30:00+00:00', '1 year 2 months 3 days 4 hours 5 minutes 6 seconds', 'Present day full temporal'),
  ('1970-01-01', '00:00:00', '00:00:00+00:00', '1970-01-01 00:00:00', '1970-01-01 00:00:00+00:00', '0 seconds', 'Unix Epoch'),
  ('2099-12-31', '23:59:59', '23:59:59-08:00', '2099-12-31 23:59:59', '2099-12-31 23:59:59-08:00', '30 days', 'Future boundary'),
  (NULL, NULL, NULL, NULL, NULL, NULL, 'All NULL timestamps');

-- 5. JSON, JSONB, and XML
CREATE TABLE types_showcase.all_json_xml (
  id SERIAL PRIMARY KEY,
  col_json JSON,
  col_jsonb JSONB,
  col_xml XML,
  description TEXT
);

INSERT INTO types_showcase.all_json_xml (col_json, col_jsonb, col_xml, description)
VALUES
  (
    '{"name": "Querya", "type": "Desktop Client", "version": "0.4.14", "open_source": true, "stats": {"stars": 1200, "contributors": 15}}',
    '{"id": 42, "user": {"email": "alice@querya.dev", "roles": ["admin", "developer"]}, "settings": {"theme": "dark", "hz": 120, "telemetry": false}}',
    XML '<root><application name="Querya"><version>0.4.14</version><platform>Linux</platform><features><item>DataGrid</item><item>Sandbox</item></features></application></root>',
    'Rich nested JSON, JSONB and XML objects'
  ),
  (
    '["apple", "banana", "cherry", {"nested": [1, 2, 3]}]',
    '{"array": [10, 20, 30], "flags": {"a": true, "b": null}}',
    XML '<empty_doc status="ready"/>',
    'JSON Arrays and compact XML'
  ),
  (
    '{}',
    '[]',
    XML '<data></data>',
    'Empty JSON structures'
  ),
  (NULL, NULL, NULL, 'All NULL documents');

-- 6. UUID, Identifiers and Network Addresses
CREATE TABLE types_showcase.all_identifiers_and_network (
  id SERIAL PRIMARY KEY,
  col_uuid UUID,
  col_inet INET,
  col_cidr CIDR,
  col_macaddr MACADDR,
  col_macaddr8 MACADDR8,
  col_oid OID,
  description TEXT
);

INSERT INTO types_showcase.all_identifiers_and_network (col_uuid, col_inet, col_cidr, col_macaddr, col_macaddr8, col_oid, description)
VALUES
  ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', '192.168.1.100', '10.0.0.0/16', '08:00:2b:01:02:03', '08:00:2b:01:02:03:04:05', 16384, 'IPv4 & standard MAC'),
  ('f47ac10b-58cc-4372-a567-0e02b2c3d479', '2001:0db8:85a3:0000:0000:8a2e:0370:7334', '2001:db8::/32', '00-50-56-C0-00-08', '00-50-56-FF-FE-C0-00-08', 32768, 'IPv6 & Extended MAC'),
  (NULL, NULL, NULL, NULL, NULL, NULL, 'All NULL identifiers');

-- 7. Binary and Bit Strings
CREATE TABLE types_showcase.all_binary_and_bits (
  id SERIAL PRIMARY KEY,
  col_bytea BYTEA,
  col_bit BIT(8),
  col_varbit BIT VARYING(32),
  description TEXT
);

INSERT INTO types_showcase.all_binary_and_bits (col_bytea, col_bit, col_varbit, description)
VALUES
  (E'\\xDEADBEEFCAFE0102030405', B'10101010', B'110010101111', 'Hex binary bytes and bitmasks'),
  (E'Hello Querya Binary \\000 Test', B'11110000', B'1', 'ASCII text stored as BYTEA'),
  (E'\\x', B'00000000', B'0', 'Zero / Empty bytes'),
  (NULL, NULL, NULL, 'All NULL binary');

-- 8. Arrays (1D and Multi-dimensional)
CREATE TABLE types_showcase.all_arrays (
  id SERIAL PRIMARY KEY,
  col_int_array INT[],
  col_text_array TEXT[],
  col_uuid_array UUID[],
  col_bool_array BOOLEAN[],
  col_jsonb_array JSONB[],
  col_matrix INT[][],
  description TEXT
);

INSERT INTO types_showcase.all_arrays (col_int_array, col_text_array, col_uuid_array, col_bool_array, col_jsonb_array, col_matrix, description)
VALUES
  (
    ARRAY[1, 2, 3, 42, 999],
    ARRAY['Alpha', 'Beta', 'Gamma', 'Delta'],
    ARRAY['a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::UUID, 'f47ac10b-58cc-4372-a567-0e02b2c3d479'::UUID],
    ARRAY[TRUE, FALSE, TRUE, TRUE],
    ARRAY['{"key": "a"}'::JSONB, '{"key": "b"}'::JSONB],
    ARRAY[[1, 2, 3], [4, 5, 6], [7, 8, 9]],
    'Standard filled arrays and 2D matrix'
  ),
  (
    '{}',
    '{}',
    '{}',
    '{}',
    '{}',
    '{}',
    'Empty arrays'
  ),
  (NULL, NULL, NULL, NULL, NULL, NULL, 'All NULL arrays');

-- 9. Ranges and Multiranges
CREATE TABLE types_showcase.all_ranges (
  id SERIAL PRIMARY KEY,
  col_int4range INT4RANGE,
  col_int8range INT8RANGE,
  col_numrange NUMRANGE,
  col_tsrange TSRANGE,
  col_tstzrange TSTZRANGE,
  col_daterange DATERANGE,
  col_int4multirange INT4MULTIRANGE,
  col_datemultirange DATEMULTIRANGE,
  description TEXT
);

INSERT INTO types_showcase.all_ranges (col_int4range, col_int8range, col_numrange, col_tsrange, col_tstzrange, col_daterange, col_int4multirange, col_datemultirange, description)
VALUES
  (
    '[1, 100)',
    '[1000000, 9999999]',
    '(10.5, 99.9)',
    '[2026-01-01 00:00:00, 2026-12-31 23:59:59]',
    '[2026-08-01 00:00:00+00, 2026-08-31 23:59:59+00)',
    '[2026-01-01, 2026-06-30)',
    '{[1, 10), [20, 30], [50, 60)}'::INT4MULTIRANGE,
    '{[2026-01-01, 2026-01-31), [2026-03-01, 2026-03-31)}'::DATEMULTIRANGE,
    'Standard bounded ranges & multiranges'
  ),
  (
    '(10,)',
    '[, 1000]',
    '(,)',
    '(2026-01-01,)',
    '(, 2026-12-31+00)',
    'empty',
    '{}'::INT4MULTIRANGE,
    '{}'::DATEMULTIRANGE,
    'Unbounded & empty ranges'
  ),
  (NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'All NULL ranges');

-- 10. Geometric Types
CREATE TABLE types_showcase.all_geometric (
  id SERIAL PRIMARY KEY,
  col_point POINT,
  col_line LINE,
  col_lseg LSEG,
  col_box BOX,
  col_path PATH,
  col_polygon POLYGON,
  col_circle CIRCLE,
  description TEXT
);

INSERT INTO types_showcase.all_geometric (col_point, col_line, col_lseg, col_box, col_path, col_polygon, col_circle, description)
VALUES
  (
    POINT(10.5, 20.3),
    LINE '{1, -1, 0}',
    LSEG '[(0,0), (10,10)]',
    BOX '((10,10), (0,0))',
    PATH '((0,0), (10,0), (10,10), (0,10))',
    POLYGON '((0,0), (5,10), (10,0))',
    CIRCLE '<(5,5), 10>',
    '2D Geometric coordinates and shapes'
  ),
  (NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'All NULL geometric');

-- 11. Custom Types (Enums, Domains, Composite)
CREATE TABLE types_showcase.all_custom_entities (
  id SERIAL PRIMARY KEY,
  user_role types_showcase.user_role_enum NOT NULL DEFAULT 'viewer',
  order_status types_showcase.order_status_enum NOT NULL DEFAULT 'pending',
  age_positive types_showcase.positive_int,
  contact_email types_showcase.valid_email,
  location types_showcase.geo_coordinate,
  home_address types_showcase.address_type,
  notes TEXT
);

INSERT INTO types_showcase.all_custom_entities (user_role, order_status, age_positive, contact_email, location, home_address, notes)
VALUES
  ('admin', 'completed', 35, 'alex@querya.dev', ROW(52.5200, 13.4050, 34.0)::types_showcase.geo_coordinate, ROW('Unter den Linden 1', 'Berlin', '10117', 'DEU')::types_showcase.address_type, 'Admin user with composite fields'),
  ('editor', 'processing', 28, 'elena@querya.dev', ROW(40.7128, -74.0060, 10.5)::types_showcase.geo_coordinate, ROW('5th Avenue 100', 'New York', '10001', 'USA')::types_showcase.address_type, 'Editor profile in NYC'),
  ('guest', 'draft', 19, 'guest@example.com', NULL, NULL, 'Guest user without address');
