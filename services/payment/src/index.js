const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const { v4: uuidv4 } = require('uuid');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 4200;

app.use(helmet());
app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'payment', timestamp: new Date().toISOString() });
});

app.post('/process', (req, res) => {
  const { orderId, amount, method } = req.body;
  if (!orderId || !amount) {
    return res.status(400).json({ success: false, error: 'Missing required fields' });
  }
  const transactionId = uuidv4();
  res.json({
    success: true,
    transactionId,
    orderId,
    amount,
    status: 'completed'
  });
});

app.post('/refund', (req, res) => {
  const { transactionId, amount } = req.body;
  res.json({ success: true, refundId: uuidv4(), transactionId, amount, status: 'refunded' });
});

app.listen(PORT, () => console.log(`Payment service on port ${PORT}`));