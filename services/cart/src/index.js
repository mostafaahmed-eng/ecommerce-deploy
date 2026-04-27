const express = require('express');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 4300;

app.use(cors());
app.use(express.json());

const carts = new Map();

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'cart' }));

app.get('/cart/:userId', (req, res) => {
  const cart = carts.get(req.params.userId) || { items: [], total: 0 };
  res.json(cart);
});

app.post('/cart/:userId/items', (req, res) => {
  const { productId, name, price, quantity = 1 } = req.body;
  let cart = carts.get(req.params.userId) || { items: [], total: 0 };
  
  const existingItem = cart.items.find(item => item.productId === productId);
  if (existingItem) {
    existingItem.quantity += quantity;
  } else {
    cart.items.push({ itemId: uuidv4(), productId, name, price, quantity });
  }
  
  cart.total = cart.items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
  carts.set(req.params.userId, cart);
  
  res.json(cart);
});

app.delete('/cart/:userId/items/:itemId', (req, res) => {
  let cart = carts.get(req.params.userId);
  if (cart) {
    cart.items = cart.items.filter(item => item.itemId !== req.params.itemId);
    cart.total = cart.items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    carts.set(req.params.userId, cart);
  }
  res.json(cart || { items: [], total: 0 });
});

app.delete('/cart/:userId', (req, res) => {
  carts.delete(req.params.userId);
  res.json({ items: [], total: 0 });
});

app.listen(PORT, () => console.log(`Cart service on port ${PORT}`));