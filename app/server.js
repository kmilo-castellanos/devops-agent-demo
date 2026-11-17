'use strict';

const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { PRODUCTS, ValidationError, price } = require('./src/pricing');

const PORT = process.env.PORT || 3000;
const orders = new Map(); // en memoria: usar 1 replica en la demo
const INDEX = fs.readFileSync(path.join(__dirname, 'public', 'index.html'));

function send(res, status, body) {
  const isBuf = Buffer.isBuffer(body);
  res.writeHead(status, { 'Content-Type': isBuf ? 'text/html; charset=utf-8' : 'application/json' });
  res.end(isBuf ? body : JSON.stringify(body));
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 1e5) req.destroy();
    });
    req.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch {
        reject(new ValidationError('bad_json', 'Invalid JSON body'));
      }
    });
  });
}

async function handle(req, res) {
  const url = new URL(req.url, 'http://x');
  const { pathname } = url;
  const m = req.method;

  if (m === 'GET' && pathname === '/') return send(res, 200, INDEX);
  if (m === 'GET' && pathname === '/healthz') return send(res, 200, { status: 'ok' });
  if (m === 'GET' && pathname === '/version') return send(res, 200, { sha: process.env.GIT_SHA || 'dev' });
  if (m === 'GET' && pathname === '/api/products') return send(res, 200, PRODUCTS);

  if (m === 'POST' && pathname === '/api/cart/price') {
    const { items, coupon } = await readJson(req);
    return send(res, 200, price(items, coupon));
  }

  if (m === 'POST' && pathname === '/api/orders') {
    const { items, coupon, email } = await readJson(req);
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      throw new ValidationError('invalid_email', 'A valid email is required');
    }
    const totals = price(items, coupon);
    const order = { id: crypto.randomUUID(), email, items, coupon: coupon || null, ...totals, status: 'CREATED' };
    if (orders.size >= 100) orders.delete(orders.keys().next().value);
    orders.set(order.id, order);
    return send(res, 201, order);
  }

  const match = pathname.match(/^\/api\/orders\/([\w-]+)$/);
  if (match) {
    const order = orders.get(match[1]);
    if (!order) return send(res, 404, { error: 'order_not_found' });
    if (m === 'GET') return send(res, 200, order);
    if (m === 'DELETE') {
      orders.delete(match[1]);
      return send(res, 204, {});
    }
  }

  return send(res, 404, { error: 'not_found' });
}

http
  .createServer((req, res) => {
    handle(req, res).catch((err) => {
      if (err instanceof ValidationError) return send(res, 400, { error: err.code, message: err.message });
      console.error(err);
      send(res, 500, { error: 'internal_error' });
    });
  })
  .listen(PORT, () => console.log(`shop listening on :${PORT}`));
