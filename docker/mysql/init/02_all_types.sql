USE querya;

-- Comprehensive MySQL Data Types Showcase Table
CREATE TABLE IF NOT EXISTS all_mysql_types (
  id INT AUTO_INCREMENT PRIMARY KEY,
  col_tinyint TINYINT,
  col_smallint SMALLINT,
  col_mediumint MEDIUMINT,
  col_int INT,
  col_bigint BIGINT,
  col_decimal DECIMAL(12, 4),
  col_float FLOAT,
  col_double DOUBLE,
  col_bit BIT(8),
  col_boolean BOOLEAN,
  col_char CHAR(10),
  col_varchar VARCHAR(255),
  col_text TEXT,
  col_json JSON,
  col_date DATE,
  col_time TIME,
  col_datetime DATETIME,
  col_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  col_year YEAR,
  col_enum ENUM('alpha', 'beta', 'gamma', 'delta') DEFAULT 'alpha',
  col_set SET('read', 'write', 'execute', 'admin') DEFAULT 'read',
  col_binary BINARY(16),
  col_varbinary VARBINARY(64),
  col_blob BLOB,
  description VARCHAR(100)
) ENGINE=InnoDB;

INSERT INTO all_mysql_types (
  col_tinyint, col_smallint, col_mediumint, col_int, col_bigint,
  col_decimal, col_float, col_double, col_bit, col_boolean,
  col_char, col_varchar, col_text, col_json,
  col_date, col_time, col_datetime, col_year,
  col_enum, col_set, col_binary, col_varbinary, col_blob, description
) VALUES
(
  127, 32767, 8388607, 2147483647, 9223372036854775807,
  12345678.9012, 3.14159, 2.718281828459045, b'10101010', TRUE,
  'FIXED', 'Variable length string test', 'Long multiline text paragraph with emoji 🚀 🐬',
  JSON_OBJECT('name', 'Querya MySQL', 'version', '8.4', 'features', JSON_ARRAY('DataGrid', 'Inspector', 'Calc')),
  '2026-08-26', '10:30:00', '2026-08-26 10:30:00', 2026,
  'alpha', 'read,write',
  UNHEX('DEADBEEFCAFE0102030405060708090A'), UNHEX('CAFEBABE'), 'Binary BLOB payload', 'Max / Standard row'
),
(
  -128, -32768, -8388608, -2147483648, -9223372036854775808,
  -12345678.9012, -3.14159, -2.718281828459045, b'00000000', FALSE,
  'MIN', 'Negative boundaries', 'Negative numbers test',
  JSON_ARRAY('one', 'two', 'three'),
  '1970-01-01', '00:00:00', '1970-01-01 00:00:00', 1970,
  'gamma', 'execute,admin',
  UNHEX('00000000000000000000000000000000'), UNHEX('00'), 'Min bytes', 'Min / Boundary row'
),
(
  NULL, NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL, NULL, 'All NULL row'
);

-- Second database: analytics
CREATE DATABASE IF NOT EXISTS analytics;
USE analytics;

CREATE TABLE IF NOT EXISTS daily_sales (
  day DATE PRIMARY KEY,
  orders INT NOT NULL,
  gross_revenue DECIMAL(12, 2) NOT NULL,
  net_revenue DECIMAL(12, 2) NOT NULL,
  refunds DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  new_customers INT NOT NULL DEFAULT 0
) ENGINE=InnoDB;

DELIMITER //
CREATE PROCEDURE SeedDailySales()
BEGIN
  DECLARE i INT DEFAULT 1;
  WHILE i <= 90 DO
    INSERT IGNORE INTO daily_sales (day, orders, gross_revenue, net_revenue, refunds, new_customers)
    VALUES (
      DATE_SUB(CURDATE(), INTERVAL (90 - i) DAY),
      10 + (i * 3) MOD 45,
      ROUND(500.00 + (i * 45.20) + ((i MOD 7) * 120.00), 2),
      ROUND(450.00 + (i * 40.00) + ((i MOD 7) * 110.00), 2),
      ROUND((i MOD 5) * 25.50, 2),
      2 + (i MOD 12)
    );
    SET i = i + 1;
  END WHILE;
END //
DELIMITER ;

CALL SeedDailySales();
DROP PROCEDURE SeedDailySales;
