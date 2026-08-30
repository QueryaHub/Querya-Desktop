// Demo data for Querya MongoDB testing.
const appDb = db.getSiblingDB('querya');

appDb.users.drop();
appDb.products.drop();
appDb.orders.drop();
appDb.types_showcase.drop();

// 1. All BSON Types Showcase Collection
appDb.types_showcase.insertMany([
  {
    _id: new ObjectId(),
    title: 'Rich BSON Document 1',
    col_string: 'MongoDB BSON String with emoji 🚀 🍃',
    col_int32: NumberInt(2147483647),
    col_int64: NumberLong('9223372036854775807'),
    col_double: 3.141592653589793,
    col_decimal: NumberDecimal('12345678901234.5678'),
    col_boolean: true,
    col_date: new Date('2026-08-26T10:30:00Z'),
    col_array_primitives: [1, 2, 3, 42, 99],
    col_array_strings: ['Alpha', 'Beta', 'Gamma'],
    col_array_objects: [
      { id: 1, label: 'First' },
      { id: 2, label: 'Second' }
    ],
    col_object: {
      nested_key: 'nested_value',
      level_2: {
        deep: true,
        count: NumberInt(10)
      }
    },
    col_binary: new BinData(0, '3q2+7w=='),
    col_regex: /^querya/i,
    col_null: null
  },
  {
    _id: new ObjectId(),
    title: 'Boundary & Min Values',
    col_string: '',
    col_int32: NumberInt(-2147483648),
    col_int64: NumberLong('-9223372036854775808'),
    col_double: -2.71828,
    col_decimal: NumberDecimal('-999999.99'),
    col_boolean: false,
    col_date: new Date('1970-01-01T00:00:00Z'),
    col_array_primitives: [],
    col_array_strings: [],
    col_array_objects: [],
    col_object: {},
    col_binary: new BinData(0, ''),
    col_regex: /.+/,
    col_null: null
  }
]);

// 2. Generate 100 Users
const users = [];
const cities = ['Berlin', 'London', 'Madrid', 'Paris', 'Tokyo', 'New York', 'San Francisco', 'Sydney', 'Toronto', 'Singapore'];
const countries = ['DEU', 'GBR', 'ESP', 'FRA', 'JPN', 'USA', 'USA', 'AUS', 'CAN', 'SGP'];

for (let i = 1; i <= 100; i++) {
  users.push({
    userId: i,
    name: 'Customer ' + i,
    email: 'customer' + i + '@example.org',
    city: cities[(i - 1) % cities.length],
    country: countries[(i - 1) % countries.length],
    role: (i % 5 === 0) ? 'admin' : (i % 3 === 0 ? 'editor' : 'customer'),
    active: (i % 15 !== 0),
    tags: (i % 2 === 0) ? ['vip', 'tech'] : ['standard'],
    metadata: {
      loyaltyTier: (i % 5 === 0) ? 'gold' : (i % 3 === 0 ? 'silver' : 'bronze'),
      score: i * 15
    },
    createdAt: new Date(Date.now() - i * 24 * 60 * 60 * 1000)
  });
}
appDb.users.insertMany(users);

// 3. Generate 50 Products
const products = [];
const categories = ['Peripherals', 'Hardware', 'Audio', 'Furniture', 'Accessories'];
for (let i = 1; i <= 50; i++) {
  products.push({
    sku: 'SKU-' + String(i).padStart(4, '0'),
    title: 'Product ' + i,
    category: categories[(i - 1) % categories.length],
    price: NumberDecimal((19.99 + i * 7.45).toFixed(2)),
    stock: NumberInt((i * 15) % 250),
    tags: ['electronics', 'gadget'],
    createdAt: new Date(Date.now() - i * 24 * 60 * 60 * 1000)
  });
}
appDb.products.insertMany(products);

// 4. Generate 250 Orders
const orders = [];
const statuses = ['new', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded'];
for (let i = 1; i <= 250; i++) {
  orders.push({
    orderId: i,
    customerEmail: 'customer' + (1 + (i % 100)) + '@example.org',
    status: statuses[(i - 1) % statuses.length],
    total: NumberDecimal((49.99 + i * 3.15).toFixed(2)),
    placedAt: new Date(Date.now() - (250 - i) * 60 * 60 * 1000),
    lines: [
      { sku: 'SKU-0001', qty: 1, unitPrice: NumberDecimal('29.99') },
      { sku: 'SKU-0002', qty: 2, unitPrice: NumberDecimal('45.50') }
    ]
  });
}
appDb.orders.insertMany(orders);

appDb.users.createIndex({ email: 1 }, { unique: true });
appDb.products.createIndex({ sku: 1 }, { unique: true });
appDb.orders.createIndex({ status: 1, placedAt: -1 });

// Analytics Database
const analyticsDb = db.getSiblingDB('analytics');
analyticsDb.metrics.drop();
const metrics = [];
for (let i = 1; i <= 60; i++) {
  metrics.push({
    day: new Date(Date.now() - (60 - i) * 24 * 60 * 60 * 1000),
    orders: NumberInt(10 + (i * 3) % 40),
    revenue: NumberDecimal((500.00 + i * 35.50).toFixed(2))
  });
}
analyticsDb.metrics.insertMany(metrics);
