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
const email = require('../services/payment/src/email');
const { JSDOM } = require('jsdom');
const fs = require('fs');

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
  assert.match(response.text, /function closeCart/);
  assert.match(response.text, /event\.key==='Escape'/);
  assert.match(response.text, /backdrop.*onclick=closeCart/);
  assert.match(response.text, /const i18n/);
  assert.match(response.text, /state\.filters\.category/);
});

test('frontend keeps payment and admin requests behind the internal API gateway', () => {
  const source = fs.readFileSync(require.resolve('../services/frontend/server'), 'utf8');
  assert.match(source, /const API_URL = process\.env\.API_URL/);
  assert.match(source, /\['\/api\/payments', '\/api\/admin', '\/api\/cart'\]/);
  assert.match(source, /req\.pipe\(upstream\)/);
});

test('cart drawer opens, closes, reopens, accepts a product, and launches checkout through DOM clicks', async () => {
  const html = fs.readFileSync(require.resolve('../services/frontend/public/index.html'), 'utf8');
  const script = fs.readFileSync(require.resolve('../services/frontend/public/app.js'), 'utf8');
  const dom = new JSDOM(html, { runScripts: 'dangerously', url: 'http://localhost/' });
  const { window } = dom;
  window.fetch = async () => ({ json: async () => ({ products: [{ id: '1', name: 'Laptop Pro', description: 'Laptop', category: 'computers', price: 100, stock: 2, image: '/assets/products/laptop-pro.png' }] }) });
  window.alert = () => {};
  window.eval(script);
  window.document.dispatchEvent(new window.Event('DOMContentLoaded'));
  await new Promise(resolve => setTimeout(resolve, 20));
  const cart = window.document.getElementById('cart');
  const backdrop = window.document.getElementById('backdrop');
  window.document.getElementById('cartOpen').click();
  assert.ok(cart.classList.contains('open')); assert.ok(backdrop.classList.contains('open'));
  cart.querySelector('[data-close="cart"]').click(); assert.ok(!cart.classList.contains('open'));
  window.document.getElementById('cartOpen').click(); window.document.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Escape' })); assert.ok(!cart.classList.contains('open')); assert.ok(!backdrop.classList.contains('open'));
  window.document.querySelector('[data-add]').click(); window.document.getElementById('cartOpen').click();
  assert.match(window.document.getElementById('cartItems').textContent, /Laptop Pro/);
  window.document.getElementById('checkoutOpen').click(); assert.ok(window.document.getElementById('checkout').classList.contains('open')); assert.ok(!cart.classList.contains('open'));
  assert.match(window.document.getElementById('checkoutContent').textContent, /مراجعة الطلب/);
  window.document.querySelector('[data-next]').click(); assert.match(window.document.getElementById('checkoutContent').textContent, /بيانات التوصيل/);
  window.document.getElementById('language').click(); assert.equal(window.document.documentElement.lang, 'en');
  assert.equal(window.document.documentElement.dir, 'ltr');
  assert.match(window.document.getElementById('checkoutContent').textContent, /Delivery details/);
  assert.doesNotMatch(window.document.getElementById('checkoutContent').textContent, /بيانات التوصيل/);
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
    assert.ok(item.nameAr && item.nameEn && item.descriptionAr && item.descriptionEn);
    assert.ok(item.categoryAr && item.categoryEn);
  }
});

test('every catalog product image is served locally', async () => {
  for (const item of product.catalog) {
    await request(frontend).get(item.image).expect(200).expect('Content-Type', /image\/(png|webp|jpeg)/);
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

test('order emails use configured recipient, escape HTML, and omit tracking tokens', async () => {
  const order = { orderId: 'order-1', amountCents: 10000, currency: 'EGP', customer: { fullName: '<script>x</script>', phone: '0100', shippingAddress: 'Cairo', city: 'Cairo' }, items: [{ name: '<b>Item</b>', quantity: 1, unitPriceCents: 10000 }] };
  const message = email.created(order, { PUBLIC_BASE_URL: 'http://example.test' });
  assert.match(message.html, /&lt;script&gt;/);
  assert.doesNotMatch(message.html, /trackingToken/i);
  let calls = 0;
  await email.send(order, 'order_created', { EMAIL_NOTIFICATIONS_ENABLED: 'false' }, () => ({ sendMail: () => { calls += 1; } }));
  assert.equal(calls, 0);
  const sent = [];
  await email.send(order, 'order_created', { EMAIL_NOTIFICATIONS_ENABLED: 'true', ORDER_NOTIFICATION_EMAIL: 'recipient@example.test', SMTP_HOST: 'smtp.test', SMTP_USER: 'user', SMTP_PASS: 'pass', EMAIL_FROM: 'store@example.test' }, () => ({ sendMail: message => sent.push(message) }));
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'recipient@example.test');
});

// ---------------------------------------------------------------------------
// Regression: the public route wiring that silently broke on the first AWS
// deployment. /api/health answered while /api/payments/* and /api/admin/*
// 404'd because traffic reached the frontend instead of the API gateway.
// ---------------------------------------------------------------------------

test('gateway routes every required public path to the right service', () => {
  const { target } = api._test;
  const expectations = [
    ['health', 'backend', '/api/health'],
    ['products', 'product', '/products'],
    ['products/12', 'product', '/products/12'],
    ['categories', 'product', '/categories'],
    ['search', 'search', '/search'],
    ['cart/abc', 'cart', '/cart/abc'],
    ['payments/orders', 'payment', '/orders'],
    ['payments/config', 'payment', '/config'],
    ['admin/login', 'payment', '/admin/login'],
    ['admin/orders', 'payment', '/admin/orders'],
    ['orders', 'backend', '/api/orders'],
    ['contact', 'frontend', '/api/contact']
  ];

  for (const [name, serviceKey, upstreamPath] of expectations) {
    const [base, path] = target(name);
    assert.equal(base, api._test.SERVICES[serviceKey], `path "${name}" must hit ${serviceKey}`);
    assert.equal(path, upstreamPath, `path "${name}" must be forwarded unchanged`);
  }
});

test('nginx production config proxies /api/ to the gateway using Docker DNS', () => {
  const serverConfig = fs.readFileSync(require.resolve('../nginx/conf.d/00-default.conf'), 'utf8');
  const mainConfig = fs.readFileSync(require.resolve('../nginx/production.conf'), 'utf8');

  // The whole /api/ tree must land on the gateway, not on the frontend.
  const apiLocation = serverConfig.match(/location \/api\/ \{[\s\S]*?\n    \}/);
  assert.ok(apiLocation, 'nginx must define a location /api/ block');
  assert.match(apiLocation[0], /proxy_pass\s+http:\/\/api_gateway;/);
  assert.doesNotMatch(apiLocation[0], /frontend_app/, 'the /api/ location must never fall back to the frontend');

  // Upstreams must use service DNS names, never container IPs.
  assert.match(mainConfig, /upstream api_gateway\s*\{\s*server api:4600;/);
  assert.match(mainConfig, /upstream frontend_app\s*\{\s*server frontend:3000;/);
  assert.doesNotMatch(mainConfig, /server\s+\d{1,3}(\.\d{1,3}){3}:/);

  // Required functional paths must be covered by the gateway routing table.
  const { target } = api._test;
  for (const path of ['health', 'products', 'search', 'payments/orders', 'admin/orders']) {
    assert.ok(target(path).length === 2, `${path} must resolve to an upstream`);
  }
});

test('public contact section is mailto based and exposes no phone by default', async () => {
  const html = fs.readFileSync(require.resolve('../services/frontend/public/index.html'), 'utf8');
  const response = await request(frontend).get('/api/contact').expect(200);

  assert.match(html, /id="contact"/);
  assert.match(html, /class="primary contact-button"/);
  assert.match(html, /mailto:mostafaahmed862004@gmail\.com/);
  assert.match(html, /mostafaahmed862004@gmail\.com/);
  // No phone number is rendered unless PUBLIC_CONTACT_PHONE is configured.
  assert.doesNotMatch(html, /href="tel:/);

  assert.equal(response.body.email, 'mostafaahmed862004@gmail.com');
  assert.equal(response.body.phone, '');

  const serverSource = fs.readFileSync(require.resolve('../services/frontend/server'), 'utf8');
  assert.match(serverSource, /PUBLIC_CONTACT_PHONE/);
  const clientSource = fs.readFileSync(require.resolve('../services/frontend/public/app.js'), 'utf8');
  assert.match(clientSource, /contactPhone/);
  assert.match(clientSource, /contact:\{eyebrow/);
});

// ---------------------------------------------------------------------------
// Persistence (section 8): orders and receipts must survive `docker compose
// down` / `up -d`. The store is opt-in through PERSISTENCE_DRIVER + DATA_DIR so
// the rest of the suite stays side-effect free, which is why this test drives
// the adapter directly against a temporary directory.
// ---------------------------------------------------------------------------
test('payment store round-trips orders across a simulated restart', () => {
  const os = require('node:os');
  const path = require('node:path');
  const storeModule = require.resolve('../services/payment/src/store');
  const cached = require.cache[storeModule];
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ecommerce-store-'));
  const quiet = { info() {}, warn() {}, error() {} };
  const reload = () => { delete require.cache[storeModule]; return require(storeModule); };
  const emptyMaps = () => ({ orders: new Map(), notifications: new Map(), sessions: new Map() });

  const previousEnv = {
    PERSISTENCE_DRIVER: process.env.PERSISTENCE_DRIVER,
    DATA_DIR: process.env.DATA_DIR
  };
  const restoreEnv = (key, value) => { if (value === undefined) delete process.env[key]; else process.env[key] = value; };

  let first;
  try {
    process.env.PERSISTENCE_DRIVER = 'local';
    process.env.DATA_DIR = dir;

    // --- first "process": write an order -----------------------------------
    first = reload();
    assert.equal(first.enabled(), true, 'local driver + DATA_DIR must enable persistence');
    assert.equal(first.DRIVER, 'local');
    assert.equal(first.STORE_FILE, path.join(dir, 'payment-store.json'));

    const live = emptyMaps();
    const handle = first.attach(live, quiet);
    assert.equal(handle.enabled, true);

    const order = {
      orderId: 'order-round-trip',
      status: 'awaiting_payment',
      amountCents: 4899900,
      currency: 'EGP',
      items: [{ productId: '1', name: 'Laptop Pro', quantity: 1, unitPriceCents: 4899900 }],
      customer: { fullName: 'Persist Test', phone: '01000000000', shippingAddress: '1 Test Street', city: 'Cairo' },
      auditLog: [],
      createdAt: new Date().toISOString()
    };
    live.orders.set(order.orderId, order);
    live.notifications.set('note-1', { notificationId: 'note-1', orderId: order.orderId, status: 'awaiting_payment' });
    live.sessions.set('expired-session', { username: 'admin', csrfToken: 'x', expiresAt: Date.now() - 1000 });
    live.sessions.set('live-session', { username: 'admin', csrfToken: 'y', expiresAt: Date.now() + 600000 });

    assert.equal(handle.flush(), true, 'flush must write the file');
    assert.ok(fs.existsSync(first.STORE_FILE), 'store file must exist on disk');
    const onDisk = JSON.parse(fs.readFileSync(first.STORE_FILE, 'utf8'));
    assert.equal(onDisk.version, 1);
    assert.equal(onDisk.orders['order-round-trip'].amountCents, 4899900);
    // No tracking token may ever reach the file.
    assert.equal(JSON.stringify(onDisk).includes('trackingToken'), false);
    handle.stop();

    // --- second "process": restart -----------------------------------------
    const second = reload();
    const restored = emptyMaps();
    const result = second.hydrate(restored, quiet);

    assert.equal(result.loaded, true);
    assert.equal(result.orders, 1, 'the order must be restored');
    assert.equal(result.notifications, 1);
    assert.equal(result.sessions, 1, 'the expired session must NOT be restored');
    assert.deepEqual(restored.orders.get('order-round-trip'), order, 'order must round-trip unchanged');
    assert.ok(restored.sessions.has('live-session'));
    assert.equal(restored.sessions.has('expired-session'), false);

    // --- corrupt file: quarantine, do not crash ----------------------------
    fs.writeFileSync(second.STORE_FILE, '{ this is not json', 'utf8');
    const afterCorruption = emptyMaps();
    const corruptResult = second.hydrate(afterCorruption, quiet);
    assert.equal(corruptResult.loaded, false);
    assert.equal(corruptResult.reason, 'corrupt');
    assert.equal(afterCorruption.orders.size, 0, 'a corrupt store starts empty instead of throwing');
    const quarantined = fs.readdirSync(dir).filter(name => name.includes('.corrupt-'));
    assert.equal(quarantined.length, 1, 'the unreadable file must be preserved for recovery');

    // --- persistence is opt-in ---------------------------------------------
    delete process.env.DATA_DIR;
    const memoryOnly = reload();
    assert.equal(memoryOnly.enabled(), false, 'without DATA_DIR the service must stay stateless');
    const memoryMaps = emptyMaps();
    const memoryHandle = memoryOnly.attach(memoryMaps, quiet);
    assert.equal(memoryHandle.enabled, false);
    assert.equal(memoryHandle.flush(), false, 'memory mode must never write');
  } finally {
    restoreEnv('PERSISTENCE_DRIVER', previousEnv.PERSISTENCE_DRIVER);
    restoreEnv('DATA_DIR', previousEnv.DATA_DIR);
    delete require.cache[storeModule];
    if (cached) require.cache[storeModule] = cached;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
