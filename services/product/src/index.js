const express = require('express');
const cors = require('cors');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, ScanCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 4500;
const PRODUCTS_TABLE = process.env.PRODUCTS_TABLE;
const dynamodb = PRODUCTS_TABLE
  ? DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } })
  : null;

app.use(cors());
app.use(express.json());

const products = [
  { id: 1, name: 'Laptop Pro', description: 'High-performance laptop', price: 1299.99, stock: 50, category: 'electronics' },
  { id: 2, name: 'Wireless Mouse', description: 'Ergonomic mouse', price: 29.99, stock: 200, category: 'accessories' },
  { id: 3, name: 'USB-C Hub', description: '7-in-1 hub', price: 49.99, stock: 150, category: 'accessories' },
  { id: 4, name: 'Monitor 27"', description: '4K Monitor', price: 399.99, stock: 75, category: 'electronics' },
  { id: 5, name: 'Keyboard', description: 'Mechanical keyboard', price: 89.99, stock: 120, category: 'accessories' }
];

const loadProducts = async () => {
  if (!dynamodb) return products;
  const response = await dynamodb.send(new ScanCommand({ TableName: PRODUCTS_TABLE }));
  return (response.Items || []).sort((a, b) => String(a.id).localeCompare(String(b.id), undefined, { numeric: true }));
};

const loadProduct = async (id) => {
  if (!dynamodb) return products.find((product) => product.id === Number(id));
  const response = await dynamodb.send(new GetCommand({ TableName: PRODUCTS_TABLE, Key: { id: String(id) } }));
  return response.Item;
};

app.get('/health', (req, res) => res.json({
  status: 'healthy',
  service: 'product',
  catalogSource: PRODUCTS_TABLE ? 'dynamodb' : 'embedded-demo'
}));

app.get('/products', async (req, res) => {
  try {
    const { category, minPrice, maxPrice } = req.query;
    let filtered = await loadProducts();
    if (category) filtered = filtered.filter(p => p.category === category);
    if (minPrice) filtered = filtered.filter(p => Number(p.price) >= Number(minPrice));
    if (maxPrice) filtered = filtered.filter(p => Number(p.price) <= Number(maxPrice));
    res.json({ products: filtered, total: filtered.length });
  } catch (error) {
    console.error('Failed to load product catalog', error);
    res.status(503).json({ error: 'Product catalog unavailable' });
  }
});

app.get('/products/:id', async (req, res) => {
  try {
    const product = await loadProduct(req.params.id);
    if (!product) return res.status(404).json({ error: 'Not found' });
    res.json(product);
  } catch (error) {
    console.error('Failed to load product', error);
    res.status(503).json({ error: 'Product catalog unavailable' });
  }
});

if (require.main === module) {
  const server = app.listen(PORT, '0.0.0.0', () => console.log(`Product service on port ${PORT}`));
  const shutdown = () => server.close(() => process.exit(0));
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

module.exports = app;
