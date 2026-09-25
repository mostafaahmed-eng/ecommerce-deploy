const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const axios = require('axios');
const crypto = require('crypto');
const path = require('path');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:4000';
const API_URL = process.env.API_URL || 'http://localhost:4600';

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
app.use('/assets', express.static(path.join(__dirname, 'public/assets'), { fallthrough: false, maxAge: '7d' }));
app.use(express.static(path.join(__dirname, 'public'), { index: 'index.html', maxAge: '1h' }));

app.get('/api/health', (req, res) => {
  res.json({ status: 'healthy', service: 'frontend', timestamp: new Date().toISOString() });
});

app.get('/api/products', async (req, res) => {
  try {
    const response = await axios.get(`${process.env.PRODUCT_URL || 'http://localhost:4500'}/products`, { params: req.query, timeout: 3000 });
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

// In ECS the ALB reaches this frontend container directly. Keep customer
// payment, receipt, cart, and admin requests on the same-origin public path
// by streaming them to the internal API gateway (including multipart uploads).
function proxyApi(req, res) {
  const upstreamUrl = new URL(API_URL);
  const transport = upstreamUrl.protocol === 'https:' ? require('https') : require('http');
  const upstream = transport.request({
    hostname: upstreamUrl.hostname,
    port: upstreamUrl.port,
    method: req.method,
    path: req.originalUrl,
    headers: { ...req.headers, host: upstreamUrl.host, 'x-forwarded-for': req.ip }
  }, response => {
    res.status(response.statusCode);
    for (const [name, value] of Object.entries(response.headers)) if (value !== undefined) res.setHeader(name, value);
    response.pipe(res);
  });
  upstream.on('error', () => !res.headersSent && res.status(502).json({ error: 'API gateway unavailable' }));
  req.pipe(upstream);
}

app.use(['/api/payments', '/api/admin', '/api/cart'], proxyApi);

app.get('/admin', (req, res) => {
  res.send(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Northstar Admin</title><style nonce="${res.locals.cspNonce}">body{margin:0;background:#080d18;color:#eef2ff;font:16px system-ui;max-width:1100px;padding:24px;margin:auto}input,select,button{padding:10px;margin:4px;border-radius:7px;border:1px solid #334155}button{background:#5eead4;color:#082f49;font-weight:700}table{width:100%;border-collapse:collapse;margin-top:18px}td,th{padding:10px;border-bottom:1px solid #334155;text-align:left}.panel{background:#121a2a;padding:16px;border-radius:12px;margin:15px 0}.hidden{display:none}.stats{display:flex;flex-wrap:wrap;gap:10px}.stats span{background:#1e293b;padding:12px;border-radius:8px}</style></head><body><h1>Order review</h1><section id="login" class="panel"><h2>Secure sign in</h2><input id="username" placeholder="Username" autocomplete="username"><input id="password" type="password" placeholder="Password" autocomplete="current-password"><button id="signIn">Sign in</button><p id="loginMessage"></p></section><main id="dashboard" class="hidden"><button id="logout">Sign out</button><section class="panel"><input id="query" placeholder="Order ID or phone"><select id="statusFilter"><option value="">All statuses</option><option>awaiting_payment</option><option>receipt_submitted</option><option>paid</option><option>payment_rejected</option><option>cancelled</option></select><button id="reload">Refresh</button><div class="stats" id="stats"></div></section><section class="panel"><p id="message"></p><table><thead><tr><th>Order</th><th>Customer</th><th>Amount</th><th>Status</th><th>Action</th></tr></thead><tbody id="orders"></tbody></table></section><section id="detail" class="panel hidden"></section></main><script nonce="${res.locals.cspNonce}">let csrf='';const api=(p,o={})=>fetch('/api/admin'+p,{credentials:'same-origin',headers:{'content-type':'application/json','x-csrf-token':csrf,...(o.headers||{})},...o});async function load(){let r=await api('/orders?q='+encodeURIComponent(query.value)+'&status='+encodeURIComponent(statusFilter.value)),d=await r.json();if(!r.ok){message.textContent=d.error;return}stats.innerHTML=Object.entries(d.counts).map(([k,v])=>'<span>'+k+': '+v+'</span>').join('');orders.innerHTML=d.orders.map(o=>'<tr><td>'+o.orderId+'</td><td>'+o.customer.fullName+'</td><td>EGP '+(o.amountCents/100).toFixed(2)+'</td><td>'+o.status+'</td><td><button data-id="'+o.orderId+'">Review</button></td></tr>').join('')||'<tr><td colspan="5">No orders found</td></tr>';document.querySelectorAll('[data-id]').forEach(b=>b.onclick=()=>details(b.dataset.id))}async function details(id){let r=await api('/orders/'+id),o=await r.json();detail.classList.remove('hidden');detail.innerHTML='<h2>'+o.orderId+'</h2><p>'+o.customer.fullName+' · '+o.customer.phone+'</p><p>'+o.items.map(i=>i.name+' × '+i.quantity+' — EGP '+(i.unitPriceCents*i.quantity/100).toFixed(2)).join('<br>')+'</p><p>Status: '+o.status+'</p><button id="approve">Approve</button><button id="reject">Reject</button><button id="cancel">Cancel</button><pre>'+JSON.stringify(o.auditLog,null,2)+'</pre>';approve.onclick=()=>change(id,'approve');reject.onclick=()=>change(id,'reject');cancel.onclick=()=>change(id,'cancel')}async function change(id,action){let reason='';if(action!=='approve'){reason=prompt('Reason required:')||'';if(!reason)return}if(!confirm('Confirm status change?'))return;let r=await api('/orders/'+id+'/'+action,{method:'POST',body:JSON.stringify({reason})}),d=await r.json();message.textContent=r.ok?'Order updated':d.error;load()}signIn.onclick=async()=>{let r=await api('/login',{method:'POST',body:JSON.stringify({username:username.value,password:password.value})}),d=await r.json();if(!r.ok){loginMessage.textContent=d.error;return}csrf=d.csrfToken;login.classList.add('hidden');dashboard.classList.remove('hidden');load()};logout.onclick=async()=>{await api('/logout',{method:'POST'});location.reload()};reload.onclick=load;</script></body></html>`);
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
<section class="toolbar"><input id="search" type="search" placeholder="Search products" aria-label="Search products"><select id="category"><option value="">All Categories</option><option value="computers">Computers</option><option value="mobile-devices">Mobile Devices</option><option value="accessories">Accessories</option><option value="audio">Audio</option><option value="storage">Storage</option><option value="gaming">Gaming</option><option value="wearables">Wearables</option><option value="home-office">Home Office</option><option value="home-appliances">Home Appliances</option></select><select id="sort"><option value="featured">Featured</option><option value="price-asc">Price: low to high</option><option value="price-desc">Price: high to low</option><option value="name-asc">Name: A to Z</option></select><input id="minPrice" type="number" min="0" placeholder="Min EGP"><input id="maxPrice" type="number" min="0" placeholder="Max EGP"><label><input id="inStock" type="checkbox"> In stock only</label><button id="searchButton">Apply filters</button><button id="clearFilters">Clear</button></section><p class="toolbar" id="resultCount"></p><section class="products" id="products"><div class="empty">Loading catalog…</div></section><section class="toolbar" style="display:block"><h2>Cart <span id="cartCount">0</span></h2><p id="cartNote" class="empty">Add products, then complete your order with a manual Vodafone Cash transfer.</p><button id="checkout">Complete Order and Pay with Vodafone Cash<br><span lang="ar" dir="rtl">إتمام الطلب والدفع بفودافون كاش</span></button><form id="checkoutForm" hidden><input id="fullName" placeholder="Full name" required><input id="phone" placeholder="Phone number" required><input id="email" placeholder="Email (optional)"><input id="address" placeholder="Shipping address" required><input id="city" placeholder="City" required><button>Place manual-payment order</button></form><div id="orderResult" class="empty"></div></section></main>
<footer>Portfolio demonstration · Payments are simulated · Built for observable, repeatable deployments</footer>
<script nonce="${res.locals.cspNonce}">
const list=document.getElementById('products');
let cart=JSON.parse(localStorage.getItem('northstar-cart')||'[]');const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));function updateCart(){localStorage.setItem('northstar-cart',JSON.stringify(cart));document.getElementById('cartCount').textContent=cart.reduce((n,i)=>n+i.quantity,0);document.getElementById('cartNote').textContent=cart.length?cart.map(i=>esc(i.name)+' × '+i.quantity).join(' · '):'Add products, then complete your order with a manual Vodafone Cash transfer.'}function add(id,name,stock){let item=cart.find(i=>i.productId===id);if(item&&item.quantity>=stock)return;if(item)item.quantity++;else cart.push({productId:id,name,quantity:1,stock});updateCart()}function render(items){resultCount.textContent=items.length+' products found';list.innerHTML=items.length?items.map((p,i)=>'<article class="card"><img src="'+esc(p.image)+'" alt="'+esc(p.name)+'" width="320" height="200" loading="'+(i>3?'lazy':'eager')+'" onerror="this.style.display=\'none\'" style="width:100%;aspect-ratio:16/10;object-fit:cover"><span class="category">'+esc(p.category)+'</span><h2>'+esc(p.name)+'</h2><p>'+esc(p.description)+'</p><p class="price">EGP '+Number(p.price).toLocaleString()+'</p><p>'+((p.available&&p.stock>0)?p.stock+' in stock':'Unavailable')+'</p><button class="add" data-id="'+esc(p.id)+'" '+(!(p.available&&p.stock>0)?'disabled':'')+'>Add to cart</button></article>').join(''):'<div class="empty">No products match these filters.</div>';document.querySelectorAll('.add').forEach((b,index)=>b.onclick=()=>add(items[index].id,items[index].name,items[index].stock))}
async function load(){list.innerHTML='<div class="empty">Loading catalog…</div>';const qs=new URLSearchParams();if(search.value.trim())qs.set('q',search.value.trim());if(category.value)qs.set('category',category.value);if(sort.value)qs.set('sort',sort.value);if(minPrice.value)qs.set('minPrice',minPrice.value);if(maxPrice.value)qs.set('maxPrice',maxPrice.value);if(inStock.checked)qs.set('inStock','true');try{const r=await fetch('/api/products?'+qs);const d=await r.json();if(!r.ok)throw Error(d.error);render(d.products||[])}catch(e){list.innerHTML='<div class="empty">Catalog is temporarily unavailable.</div>'}}
async function search(){load()}
fetch('/api/health').then(r=>r.ok?r.json():Promise.reject()).then(()=>{document.getElementById('dot').classList.add('ok');document.getElementById('status').textContent='All systems operational'}).catch(()=>document.getElementById('status').textContent='Service unavailable');
document.getElementById('searchButton').addEventListener('click',search);document.getElementById('search').addEventListener('keydown',e=>{if(e.key==='Enter')search()});clearFilters.onclick=()=>{search.value='';category.value='';sort.value='featured';minPrice.value='';maxPrice.value='';inStock.checked=false;load()};updateCart();load();
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
