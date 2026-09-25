const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const http = require('http');
const https = require('https');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 4600;
const SERVICES = { frontend: process.env.FRONTEND_URL || 'http://localhost:3000', backend: process.env.BACKEND_URL || 'http://localhost:4000', payment: process.env.PAYMENT_URL || 'http://localhost:4200', search: process.env.SEARCH_URL || 'http://localhost:5000', cart: process.env.CART_URL || 'http://localhost:4300', product: process.env.PRODUCT_URL || 'http://localhost:4500' };
const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || '';
app.use(helmet()); app.use(cors({ credentials: true, origin(origin, done) { if (!origin || (PUBLIC_BASE_URL && origin === PUBLIC_BASE_URL)) return done(null, true); return done(new Error('Origin is not allowed')); } }));
app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'api-gateway' }));
function target(name) { if (name === 'contact') return [SERVICES.frontend, '/api/contact']; if (name.startsWith('products')) return [SERVICES.product, `/${name}`]; if (name.startsWith('categories')) return [SERVICES.product, `/${name}`]; if (name.startsWith('search')) return [SERVICES.search, `/${name}`]; if (name.startsWith('cart')) return [SERVICES.cart, `/${name}`]; if (name.startsWith('payments')) return [SERVICES.payment, `/${name.replace(/^payments\/?/, '')}`]; if (name.startsWith('admin')) return [SERVICES.payment, `/${name}`]; return [SERVICES.backend, `/api/${name}`]; }
app.all('/api/*', (req, res) => { const name = req.path.replace(/^\/api\//, ''), [base, servicePath] = target(name), url = new URL(base), transport = url.protocol === 'https:' ? https : http, query = req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : ''; const upstream = transport.request({ hostname: url.hostname, port: url.port, method: req.method, path: servicePath + query, headers: { ...req.headers, host: url.host, 'x-forwarded-for': req.ip } }, response => { res.status(response.statusCode); for (const [key, value] of Object.entries(response.headers)) if (value !== undefined) res.setHeader(key, value); response.pipe(res); }); upstream.on('error', () => !res.headersSent && res.status(502).json({ error: 'Backend service unavailable' })); req.pipe(upstream); });
if (require.main === module) { const server = app.listen(PORT, '0.0.0.0', () => console.log(`API gateway on port ${PORT}`)); const stop = () => server.close(() => process.exit(0)); process.on('SIGTERM', stop); process.on('SIGINT', stop); }
module.exports = app;
module.exports._test = { target, SERVICES };
