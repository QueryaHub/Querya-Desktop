-- Querya SQLite Test Database Initialization
-- This script runs once via Docker to seed the local querya.db file.

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    price REAL NOT NULL,
    stock INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    total REAL NOT NULL,
    status TEXT DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id)
);

-- Seed Data
INSERT OR IGNORE INTO users (id, username, email) VALUES
(1, 'alice_smith', 'alice@example.com'),
(2, 'bob_jones', 'bob@example.com'),
(3, 'charlie_brown', 'charlie@example.com');

INSERT OR IGNORE INTO products (id, name, price, stock) VALUES
(1, 'Laptop Pro', 1299.99, 50),
(2, 'Wireless Mouse', 49.99, 200),
(3, 'Mechanical Keyboard', 149.50, 75);

INSERT OR IGNORE INTO orders (id, user_id, total, status) VALUES
(1, 1, 1299.99, 'completed'),
(2, 2, 49.99, 'shipped'),
(3, 1, 149.50, 'pending');
