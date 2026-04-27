const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const axios = require('axios');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 4600;

app.use(helmet());
app.use(cors());
app.use(express.json());

const SERVICES = {
  frontend: process.env.FRONTEND_URL || 'http://localhost:3000',
  backend: process.env.BACKEND_URL || 'http://localhost:4000',
  payment: process.env.PAYMENT_URL || 'http://localhost:4200',
  search: process.env.SEARCH_URL || 'http://localhost:5000',
  cart: process.env.CART_URL || 'http://localhost:4300',
  product: process.env.PRODUCT_URL || 'http://localhost:4500'
};

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'api-gateway', timestamp: new Date().toISOString() });
});

app.get('/api/*', async (req, res) => {
  const path = req.path.replace('/api/', '');
  try {
    const response = await axios.get(`${SERVICES.backend}/api/${path}`, { timeout: 5000 });
    res.json(response.data);
  } catch (error) {
    res.status(502).json({ error: 'Backend service unavailable' });
  }
});

app.post('/api/*', async (req, res) => {
  const path = req.path.replace('/api/', '');
  try {
    const response = await axios.post(`${SERVICES.backend}/api/${path}`, req.body, { timeout: 5000 });
    res.json(response.data);
  } catch (error) {
    res.status(502).json({ error: 'Backend service unavailable' });
  }
});

app.listen(PORT, () => console.log(`API Gateway on port ${PORT}`));