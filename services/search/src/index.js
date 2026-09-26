const express=require('express');
const cors=require('cors');
const axios=require('axios');
require('dotenv').config();
const app=express(), PORT=process.env.PORT||5000, PRODUCT_URL=()=>process.env.PRODUCT_URL||'http://localhost:4500';
app.use(cors()); app.use(express.json());
async function products(params={}) { const response=await axios.get(`${PRODUCT_URL()}/products`,{params,timeout:3000}); return response.data; }
app.get('/health',async(req,res)=>{try{const data=await products();res.json({status:'healthy',service:'search',indexedProducts:data.total});}catch{res.json({status:'healthy',service:'search',indexedProducts:0});}});
app.get('/search',async(req,res)=>{const q=String(req.query.q||'').trim();if(!q)return res.status(400).json({error:'Query required'});try{const data=await products({q});res.json({query:q,results:data.products,total:data.total});}catch{return res.status(503).json({error:'Search service unavailable'});}});
app.get('/categories',async(req,res)=>{try{const response=await axios.get(`${PRODUCT_URL()}/categories`,{timeout:3000});res.json(response.data);}catch{return res.status(503).json({error:'Category service unavailable'});}});
if(require.main===module){const server=app.listen(PORT,'0.0.0.0',()=>console.log(`Search service on port ${PORT}`));const stop=()=>server.close(()=>process.exit(0));process.on('SIGTERM',stop);process.on('SIGINT',stop);}
module.exports=app;
