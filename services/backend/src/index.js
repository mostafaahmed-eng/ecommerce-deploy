const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 4000;

app.use(helmet());
app.use(cors());
app.use(morgan('combined'));
app.use(express.json());

app.get('/api/health', (req, res) => {
  res.json({ status: 'healthy', service: 'backend-api', timestamp: new Date().toISOString() });
});

app.get('/api/ready', (req, res) => {
  res.json({ ready: true });
});

const products = [
  { id: 1, name: 'Laptop Pro', price: 1299.99, stock: 50, category: 'electronics' },
  { id: 2, name: 'Wireless Mouse', price: 29.99, stock: 200, category: 'accessories' },
  { id: 3, name: 'USB-C Hub', price: 49.99, stock: 150, category: 'accessories' },
  { id: 4, name: 'Monitor 27"', price: 399.99, stock: 75, category: 'electronics' },
  { id: 5, name: 'Mechanical Keyboard', price: 89.99, stock: 120, category: 'accessories' }
];

app.get('/api/products', (req, res) => {
  res.json({ products, total: products.length });
});

app.get('/api/products/:id', (req, res) => {
  const product = products.find(p => p.id === parseInt(req.params.id));
  if (!product) return res.status(404).json({ error: 'Product not found' });
  res.json(product);
});

app.post('/api/orders', (req, res) => {
  const { products } = req.body;
  if (!Array.isArray(products) || products.length === 0) {
    return res.status(400).json({ error: 'At least one product is required' });
  }
  res.json({ orderId: Date.now(), products, status: 'confirmed' });
});

if (require.main === module) {
  const server = app.listen(PORT, '0.0.0.0', () => console.log(`Backend API on port ${PORT}`));
  const shutdown = () => server.close(() => process.exit(0));
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

module.exports = app;
