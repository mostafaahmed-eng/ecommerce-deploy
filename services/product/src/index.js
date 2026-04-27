const express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 4500;

app.use(cors());
app.use(express.json());

const products = [
  { id: 1, name: 'Laptop Pro', description: 'High-performance laptop', price: 1299.99, stock: 50, category: 'electronics' },
  { id: 2, name: 'Wireless Mouse', description: 'Ergonomic mouse', price: 29.99, stock: 200, category: 'accessories' },
  { id: 3, name: 'USB-C Hub', description: '7-in-1 hub', price: 49.99, stock: 150, category: 'accessories' },
  { id: 4, name: 'Monitor 27"', description: '4K Monitor', price: 399.99, stock: 75, category: 'electronics' },
  { id: 5, name: 'Keyboard', description: 'Mechanical keyboard', price: 89.99, stock: 120, category: 'accessories' }
];

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'product' }));

app.get('/products', (req, res) => {
  const { category, minPrice, maxPrice } = req.query;
  let filtered = [...products];
  if (category) filtered = filtered.filter(p => p.category === category);
  if (minPrice) filtered = filtered.filter(p => p.price >= parseFloat(minPrice));
  if (maxPrice) filtered = filtered.filter(p => p.price <= parseFloat(maxPrice));
  res.json({ products: filtered, total: filtered.length });
});

app.get('/products/:id', (req, res) => {
  const product = products.find(p => p.id === parseInt(req.params.id));
  if (!product) return res.status(404).json({ error: 'Not found' });
  res.json(product);
});

app.listen(PORT, () => console.log(`Product service on port ${PORT}`));