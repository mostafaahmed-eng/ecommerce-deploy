const express = require('express');
const cors = require('cors');
const catalog = require('../data/products.json');
require('dotenv').config();
const app = express(), PORT = process.env.PORT || 4500;
const CATEGORIES = ['computers','mobile-devices','accessories','audio','storage','gaming','wearables','home-office','home-appliances'];
const labels = { computers:'Computers', 'mobile-devices':'Mobile Devices', accessories:'Accessories', audio:'Audio', storage:'Storage', gaming:'Gaming', wearables:'Wearables', 'home-office':'Home Office', 'home-appliances':'Home Appliances' };
app.use(cors()); app.use(express.json());
function invalid(res, message) { return res.status(400).json({ error: message }); }
function filtered(query) {
  const { category, q, minPrice, maxPrice, inStock, sort } = query;
  if (category && !CATEGORIES.includes(category)) throw new Error('Invalid category');
  if (minPrice !== undefined && (!/^\d+$/.test(minPrice) || Number(minPrice) < 0)) throw new Error('Invalid minimum price');
  if (maxPrice !== undefined && (!/^\d+$/.test(maxPrice) || Number(maxPrice) < 0)) throw new Error('Invalid maximum price');
  if (minPrice !== undefined && maxPrice !== undefined && Number(minPrice) > Number(maxPrice)) throw new Error('Minimum price cannot exceed maximum price');
  if (inStock !== undefined && !['true','false'].includes(inStock)) throw new Error('Invalid inStock value');
  if (sort && !['featured','price-asc','price-desc','name-asc'].includes(sort)) throw new Error('Invalid sort value');
  const text = (q || '').trim().toLowerCase(); let products = catalog.filter(product => (!category || product.category === category) && (!text || [product.name, product.description, labels[product.category]].join(' ').toLowerCase().includes(text)) && (minPrice === undefined || product.price >= Number(minPrice)) && (maxPrice === undefined || product.price <= Number(maxPrice)) && (inStock !== 'true' || (product.available && product.stock > 0)));
  if (sort === 'price-asc') products = products.sort((a,b) => a.price - b.price); if (sort === 'price-desc') products = products.sort((a,b) => b.price - a.price); if (sort === 'name-asc') products = products.sort((a,b) => a.name.localeCompare(b.name)); return products;
}
app.get('/health', (req,res) => res.json({ status:'healthy', service:'product', catalogSource:'local-canonical', products:catalog.length }));
app.get('/products', (req,res) => { try { const products = filtered(req.query); res.json({ products, total:products.length, filters:req.query }); } catch (error) { invalid(res,error.message); } });
app.get('/products/:id', (req,res) => { const product = catalog.find(item => item.id === req.params.id || item.slug === req.params.id); return product ? res.json(product) : res.status(404).json({ error:'Not found' }); });
app.get('/categories', (req,res) => res.json({ categories:CATEGORIES.map(key => ({ key, label:labels[key], total:catalog.filter(p=>p.category===key).length })) }));
if (require.main === module) { const server=app.listen(PORT,'0.0.0.0',()=>console.log(`Product service on port ${PORT}`)); const stop=()=>server.close(()=>process.exit(0)); process.on('SIGTERM',stop); process.on('SIGINT',stop); }
module.exports=app; module.exports.catalog=catalog;
