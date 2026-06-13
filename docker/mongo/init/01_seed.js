// Demo data for Querya manual testing (MongoDB).
const appDb = db.getSiblingDB('querya');

appDb.users.drop();
appDb.products.drop();
appDb.orders.drop();

appDb.users.insertMany([
  {
    name: 'Alice Martin',
    email: 'alice@example.com',
    role: 'admin',
    city: 'Berlin',
    tags: ['staff', 'beta'],
    active: true,
  },
  {
    name: 'Bob Smith',
    email: 'bob@example.com',
    role: 'customer',
    city: 'London',
    tags: ['beta'],
    active: true,
  },
  {
    name: 'Carla Ruiz',
    email: 'carla@example.com',
    role: 'customer',
    city: 'Madrid',
    tags: [],
    active: false,
  },
]);

appDb.products.insertMany([
  { sku: 'SKU-001', title: 'Wireless Mouse', price: 29.99, stock: 120 },
  { sku: 'SKU-002', title: 'Mechanical Keyboard', price: 89.0, stock: 45 },
  { sku: 'SKU-003', title: 'USB-C Hub', price: 45.5, stock: 80 },
  { sku: 'SKU-004', title: '27" Monitor', price: 329.0, stock: 15 },
]);

appDb.orders.insertMany([
  {
    customerEmail: 'alice@example.com',
    status: 'paid',
    total: 164.49,
    placedAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000),
    lines: [
      { sku: 'SKU-001', qty: 1, unitPrice: 29.99 },
      { sku: 'SKU-003', qty: 1, unitPrice: 45.5 },
      { sku: 'SKU-002', qty: 1, unitPrice: 89.0 },
    ],
  },
  {
    customerEmail: 'bob@example.com',
    status: 'shipped',
    total: 404.0,
    placedAt: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000),
    lines: [{ sku: 'SKU-004', qty: 1, unitPrice: 329.0 }],
  },
  {
    customerEmail: 'carla@example.com',
    status: 'new',
    total: 29.99,
    placedAt: new Date(),
    lines: [{ sku: 'SKU-001', qty: 1, unitPrice: 29.99 }],
  },
]);

appDb.users.createIndex({ email: 1 }, { unique: true });
appDb.products.createIndex({ sku: 1 }, { unique: true });
appDb.orders.createIndex({ status: 1, placedAt: -1 });

const analyticsDb = db.getSiblingDB('analytics');
analyticsDb.metrics.drop();
analyticsDb.metrics.insertMany([
  { day: new Date(), orders: 4, revenue: 203.99 },
  {
    day: new Date(Date.now() - 24 * 60 * 60 * 1000),
    orders: 9,
    revenue: 615.0,
  },
]);
