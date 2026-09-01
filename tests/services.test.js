const { test } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const frontend = require('../services/frontend/server');
const backend = require('../services/backend/src/index');
const payment = require('../services/payment/src/index');
const search = require('../services/search/src/index');
const cart = require('../services/cart/src/index');
const product = require('../services/product/src/index');
const api = require('../services/api/src/index');

test('all services expose healthy endpoints', async () => {
  const checks = [
    [frontend, '/api/health', 'frontend'],
    [backend, '/api/health', 'backend-api'],
    [payment, '/health', 'payment'],
    [search, '/health', 'search'],
    [cart, '/health', 'cart'],
    [product, '/health', 'product'],
    [api, '/health', 'api-gateway']
  ];

  for (const [app, path, service] of checks) {
    const response = await request(app).get(path).expect(200);
    assert.equal(response.body.status, 'healthy');
    assert.equal(response.body.service, service);
  }
});

test('frontend renders the Arabic storefront with a secure CSP', async () => {
  const response = await request(frontend).get('/').expect(200);
  assert.match(response.text, /dir="rtl"/);
  assert.match(response.text, /إتمام الطلب/);
  assert.match(response.headers['content-security-policy'], /nonce-/);
  assert.doesNotMatch(response.headers['content-security-policy'], /unsafe-inline/);
});

test('storefront client includes persisted bilingual and cart-drawer controls', async () => {
  const response = await request(frontend).get('/app.js').expect(200);
  assert.match(response.text, /store-language/);
  assert.match(response.text, /document\.documentElement\.dir/);
  assert.match(response.text, /close\('cart'\);checkout\(\)/);
  assert.match(response.text, /e\.key==='Escape'/);
  assert.match(response.text, /backdrop.*close\('cart'\)/);
});

test('product filtering and lookup work', async () => {
  const filtered = await request(product)
    .get('/products?category=computers&maxPrice=16000')
    .expect(200);
  assert.equal(filtered.body.total, 2);
  assert.ok(filtered.body.products.some(item => item.name === '27-inch 4K Monitor'));

  await request(product).get('/products/999').expect(404);
  await request(product).get('/products?category=invalid').expect(400);
});

test('canonical catalog has 20 unique products in nine categories', () => {
  const catalog = product.catalog;
  assert.equal(catalog.length, 20);
  assert.equal(new Set(catalog.map(item => item.id)).size, 20);
  assert.equal(new Set(catalog.map(item => item.slug)).size, 20);
  assert.equal(new Set(catalog.map(item => item.category)).size, 9);
  for (const item of catalog) {
    assert.ok(item.name && item.price > 0 && item.stock >= 0 && item.image);
  }
});

test('every catalog illustration is served locally', async () => {
  for (const item of product.catalog) {
    await request(frontend).get(item.image).expect(200).expect('Content-Type', /image\/svg\+xml/);
  }
});

test('search validates the query and returns matches', async (t) => {
  const server = product.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  process.env.PRODUCT_URL = `http://127.0.0.1:${server.address().port}`;
  t.after(() => { delete process.env.PRODUCT_URL; server.close(); });
  await request(search).get('/search').expect(400);
  const response = await request(search).get('/search?q=laptop').expect(200);
  assert.ok(response.body.results.some((item) => item.name === 'Laptop Pro'));
});

test('search uses the product service as its catalog when configured', async (t) => {
  const server = product.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(() => {
    delete process.env.PRODUCT_URL;
    server.close();
  });

  process.env.PRODUCT_URL = `http://127.0.0.1:${server.address().port}`;
  const response = await request(search).get('/categories').expect(200);
  assert.equal(response.body.categories.length, 9);
});

test('cart validates input and calculates totals', async () => {
  await request(cart).post('/cart/test-user/items').send({}).expect(400);

  const response = await request(cart)
    .post('/cart/test-user/items')
    .send({ productId: 1, name: 'Laptop Pro', price: 1299.99, quantity: 2 })
    .expect(200);
  assert.equal(response.body.total, 2599.98);
  assert.equal(response.body.items.length, 1);
});

test('manual Vodafone Cash orders are server-priced and token protected', async (t) => {
  const server = product.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  process.env.PRODUCT_URL = `http://127.0.0.1:${server.address().port}`;
  t.after(() => { delete process.env.PRODUCT_URL; server.close(); });
  await request(payment).post('/orders').send({ items: [] }).expect(400);
  const created = await request(payment).post('/orders').send({
    fullName: 'Test Customer', phone: '01000000000', shippingAddress: 'Cairo', city: 'Cairo',
    items: [{ productId: 6, quantity: 1, price: 1 }, { productId: 6, quantity: 2, price: 1 }]
  }).expect(201);
  assert.equal(created.body.amountCents, 359700);
  assert.equal(created.body.items[0].quantity, 3);
  assert.ok(created.body.trackingToken.length > 30);
  assert.equal(payment._test.orders.get(created.body.orderId).trackingTokenHash, payment._test.hash(created.body.trackingToken));
  await request(payment).post(`/orders/${created.body.orderId}/status`).send({}).expect(404);
  await request(payment).post(`/orders/${created.body.orderId}/status`).set('x-tracking-token', created.body.trackingToken).send({}).expect(200);
  await request(payment).post(`/orders/${created.body.orderId}/receipt`).field('trackingToken', created.body.trackingToken).field('transferPhone', '01000000000').attach('receipt', Buffer.from('<svg/>'), 'receipt.png').expect(400);
});

test('backend validates orders', async () => {
  await request(backend).post('/api/orders').send({ products: [] }).expect(400);
  const response = await request(backend)
    .post('/api/orders')
    .send({ products: [{ id: 1, quantity: 1 }] })
    .expect(200);
  assert.equal(response.body.status, 'confirmed');
});
