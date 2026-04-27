const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const axios = require('axios');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:4000';

app.use(helmet());
app.use(cors());
app.use(compression());
app.use(morgan('combined'));
app.use(express.json());

app.get('/api/health', (req, res) => {
  res.json({ status: 'healthy', service: 'frontend', timestamp: new Date().toISOString() });
});

app.get('/api/products', async (req, res) => {
  try {
    const response = await axios.get(`${BACKEND_URL}/api/products`);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch products' });
  }
});

app.get('/api/search', async (req, res) => {
  try {
    const query = req.query.q || '';
    const response = await axios.get(`${process.env.SEARCH_URL || 'http://localhost:5000'}/search?q=${query}`);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: 'Search service unavailable' });
  }
});

app.get('/', (req, res) => {
  res.send(`<!DOCTYPE html>
<html><head><title>E-Commerce</title></head>
<body><h1>Welcome to E-Commerce Platform</h1>
<p>API: <a href="/api/health">Health Check</a></p>
<p>Products: <a href="/api/products">View Products</a></p></body></html>`);
});

app.listen(PORT, () => console.log(`Frontend on port ${PORT}`));