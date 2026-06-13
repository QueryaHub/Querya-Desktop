-- Second database to exercise PostgreSQL tree / database switching.
CREATE DATABASE analytics;

\connect analytics

CREATE SCHEMA metrics;

CREATE TABLE metrics.daily_sales (
  day DATE PRIMARY KEY,
  orders INT NOT NULL,
  revenue NUMERIC(12, 2) NOT NULL
);

INSERT INTO metrics.daily_sales (day, orders, revenue) VALUES
  (CURRENT_DATE - 2, 12, 842.50),
  (CURRENT_DATE - 1, 9, 615.00),
  (CURRENT_DATE, 4, 203.99);
