const express = require('express');
const cors = require('cors');
const Fuse = require('fuse.js');
const axios = require('axios');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

const products = [
  { id: 1, name: 'Laptop Pro', description: 'High-performance laptop', price: 1299.99, category: 'electronics' },
  { id: 2, name: 'Wireless Mouse', description: 'Ergonomic wireless mouse', price: 29.99, category: 'accessories' },
  { id: 3, name: 'USB-C Hub', description: '7-in-1 USB-C hub', price: 49.99, category: 'accessories' },
  { id: 4, name: 'Monitor 27"', description: '4K IPS Monitor', price: 399.99, category: 'electronics' },
  { id: 5, name: 'Mechanical Keyboard', description: 'RGB mechanical keyboard', price: 89.99, category: 'accessories' },
  { id: 6, name: 'Webcam HD', description: '1080p webcam', price: 59.99, category: 'electronics' },
  { id: 7, name: 'Desk Lamp', description: 'LED desk lamp', price: 34.99, category: 'office' },
  { id: 8, name: 'Office Chair', description: 'Ergonomic office chair', price: 249.99, category: 'furniture' },
  { id: 9, name: 'Standing Desk', description: 'Adjustable standing desk', price: 449.99, category: 'furniture' },
  { id: 10, name: 'Headphones', description: 'Noise-canceling headphones', price: 199.99, category: 'electronics' }
];

const loadProducts = async () => {
  const PRODUCT_URL = process.env.PRODUCT_URL;
  if (!PRODUCT_URL) return products;
  try {
    const response = await axios.get(`${PRODUCT_URL}/products`, { timeout: 2000 });
    return response.data.products || products;
  } catch (error) {
    console.error('Product service unavailable; using demo search index');
    return products;
  }
};

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'search', indexedProducts: products.length });
});

app.get('/search', async (req, res) => {
  const { q } = req.query;
  if (!q) return res.status(400).json({ error: 'Query required' });
  const catalog = await loadProducts();
  const fuse = new Fuse(catalog, { keys: ['name', 'description', 'tags'], threshold: 0.4 });
  const results = fuse.search(q).map(r => r.item);
  res.json({ query: q, results, total: results.length });
});

app.get('/categories', async (req, res) => {
  const catalog = await loadProducts();
  const categories = [...new Set(catalog.map(p => p.category))];
  res.json({ categories });
});

if (require.main === module) {
  const server = app.listen(PORT, '0.0.0.0', () => console.log(`Search service on port ${PORT}`));
  const shutdown = () => server.close(() => process.exit(0));
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

module.exports = app;
