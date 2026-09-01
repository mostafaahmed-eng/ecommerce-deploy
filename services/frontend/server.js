const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const axios = require('axios');
const crypto = require('crypto');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:4000';

app.use((req, res, next) => {
  res.locals.cspNonce = crypto.randomBytes(16).toString('base64');
  next();
});
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", (req, res) => `'nonce-${res.locals.cspNonce}'`],
      styleSrc: ["'self'", (req, res) => `'nonce-${res.locals.cspNonce}'`],
      imgSrc: ["'self'", 'data:'],
      connectSrc: ["'self'"],
      objectSrc: ["'none'"],
      baseUri: ["'self'"],
      frameAncestors: ["'none'"]
    }
  }
}));
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
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Northstar Market</title>
<style nonce="${res.locals.cspNonce}">
:root{color-scheme:dark;--ink:#eef2ff;--muted:#9aa5bd;--line:#273249;--card:#121a2a;--blue:#6ea8fe;--mint:#5eead4}
*{box-sizing:border-box}body{margin:0;background:#080d18;color:var(--ink);font-family:Inter,ui-sans-serif,system-ui,sans-serif}
body:before{content:"";position:fixed;inset:0;background:radial-gradient(circle at 80% 10%,#15376088,transparent 32%),radial-gradient(circle at 10% 45%,#173c3588,transparent 28%);pointer-events:none}
header,main,footer{position:relative}.nav{max-width:1180px;margin:auto;padding:24px;display:flex;align-items:center;justify-content:space-between}.brand{font-weight:800;letter-spacing:-.04em}.brand span{color:var(--mint)}
.status{display:flex;align-items:center;gap:8px;color:var(--muted);font-size:14px}.dot{width:8px;height:8px;border-radius:50%;background:#f59e0b}.dot.ok{background:#22c55e;box-shadow:0 0 14px #22c55e}
.hero{max-width:1180px;margin:58px auto 44px;padding:0 24px}.eyebrow{color:var(--mint);font-size:13px;font-weight:800;letter-spacing:.16em;text-transform:uppercase}.hero h1{font-size:clamp(42px,7vw,82px);line-height:.98;letter-spacing:-.065em;max-width:850px;margin:15px 0 22px}.hero p{color:var(--muted);font-size:18px;line-height:1.7;max-width:650px}
.toolbar{max-width:1180px;margin:auto;padding:0 24px 24px;display:flex;gap:12px}.toolbar input{flex:1;border:1px solid var(--line);background:#0d1422;color:var(--ink);padding:15px 18px;border-radius:13px;font:inherit;outline:none}.toolbar input:focus{border-color:var(--blue)}button{border:0;border-radius:13px;padding:0 22px;background:var(--ink);color:#0a1020;font-weight:800;cursor:pointer}
.products{max-width:1180px;margin:auto;padding:0 24px 80px;display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px}.card{background:linear-gradient(155deg,#151f32dd,#0d1422dd);border:1px solid var(--line);border-radius:20px;padding:22px;min-height:210px;display:flex;flex-direction:column;transition:.2s}.card:hover{transform:translateY(-4px);border-color:#47618b}.category{color:var(--blue);font-size:12px;text-transform:uppercase;letter-spacing:.12em}.card h2{font-size:20px;margin:16px 0 8px}.card p{color:var(--muted);margin:0}.price{margin-top:auto!important;padding-top:28px;color:var(--mint)!important;font-size:22px;font-weight:800}.empty{grid-column:1/-1;color:var(--muted);padding:40px 0}footer{border-top:1px solid var(--line);color:var(--muted);padding:28px;text-align:center;font-size:13px}@media(max-width:600px){.toolbar{flex-direction:column}.toolbar button{height:48px}.hero{margin-top:30px}}
</style></head><body>
<header><nav class="nav"><div class="brand">NORTHSTAR<span>•</span></div><div class="status"><i class="dot" id="dot"></i><span id="status">Checking platform</span></div></nav></header>
<main><section class="hero"><div class="eyebrow">Cloud-native commerce demo</div><h1>Modern products.<br>Reliable delivery.</h1><p>A containerized microservices showcase deployed through an automated AWS pipeline.</p></section>
<section class="toolbar"><input id="search" type="search" placeholder="Search the catalog" aria-label="Search products"><button id="searchButton">Search</button></section><section class="products" id="products"><div class="empty">Loading catalog…</div></section><section class="toolbar" style="display:block"><h2>Cart <span id="cartCount">0</span></h2><p id="cartNote" class="empty">Add products, then complete your order with a manual Vodafone Cash transfer.</p><button id="checkout">Complete Order and Pay with Vodafone Cash<br><span lang="ar" dir="rtl">إتمام الطلب والدفع بفودافون كاش</span></button><form id="checkoutForm" hidden><input id="fullName" placeholder="Full name" required><input id="phone" placeholder="Phone number" required><input id="email" placeholder="Email (optional)"><input id="address" placeholder="Shipping address" required><input id="city" placeholder="City" required><button>Place manual-payment order</button></form><div id="orderResult" class="empty"></div></section></main>
<footer>Portfolio demonstration · Payments are simulated · Built for observable, repeatable deployments</footer>
<script nonce="${res.locals.cspNonce}">
const list=document.getElementById('products');
let cart=[];function updateCart(){document.getElementById('cartCount').textContent=cart.reduce((n,i)=>n+i.quantity,0);document.getElementById('cartNote').textContent=cart.length?cart.map(i=>i.name+' × '+i.quantity).join(' · '):'Add products, then complete your order with a manual Vodafone Cash transfer.'}function add(id,name){let item=cart.find(i=>i.productId===id);if(item)item.quantity++;else cart.push({productId:id,name,quantity:1});updateCart()}function render(items){list.innerHTML=items.length?items.map(p=>'<article class="card"><span class="category">'+(p.category||'product')+'</span><h2>'+p.name+'</h2><p>'+(p.description||'Curated for the demo catalog.')+'</p><p class="price">$'+Number(p.price).toFixed(2)+'</p><button onclick="add(\''+p.id+'\',\''+p.name.replace(/'/g,'')+'\')">Add to cart</button></article>').join(''):'<div class="empty">No matching products found.</div>'}
async function load(){try{const r=await fetch('/api/products');const d=await r.json();render(d.products||[])}catch(e){list.innerHTML='<div class="empty">Catalog is temporarily unavailable.</div>'}}
async function search(){const q=document.getElementById('search').value.trim();if(!q)return load();list.innerHTML='<div class="empty">Searching…</div>';try{const r=await fetch('/api/search?q='+encodeURIComponent(q));const d=await r.json();render(d.results||[])}catch(e){list.innerHTML='<div class="empty">Search is temporarily unavailable.</div>'}}
fetch('/api/health').then(r=>r.ok?r.json():Promise.reject()).then(()=>{document.getElementById('dot').classList.add('ok');document.getElementById('status').textContent='All systems operational'}).catch(()=>document.getElementById('status').textContent='Service unavailable');
document.getElementById('searchButton').addEventListener('click',search);document.getElementById('search').addEventListener('keydown',e=>{if(e.key==='Enter')search()});load();
document.getElementById('checkout').onclick=()=>{if(!cart.length)return alert('Your cart is empty.');document.getElementById('checkoutForm').hidden=false};document.getElementById('checkoutForm').onsubmit=async e=>{e.preventDefault();let r=await fetch('/api/payments/orders',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({fullName:fullName.value,phone:phone.value,email:email.value,shippingAddress:address.value,city:city.value,items:cart})});let d=await r.json();orderResult.textContent=r.ok?'Order '+d.orderId+' created. Transfer EGP '+(d.amountCents/100).toFixed(2)+' to Vodafone Cash '+d.vodafoneCashNumber+'. Save this tracking token (shown only once): '+d.trackingToken+'. Uploading a receipt does not confirm payment automatically.':d.error};
</script></body></html>`);
});

if (require.main === module) {
  const server = app.listen(PORT, '0.0.0.0', () => console.log(`Frontend on port ${PORT}`));
  const shutdown = () => server.close(() => process.exit(0));
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

module.exports = app;
