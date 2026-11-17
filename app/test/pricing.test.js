'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { price } = require('../src/pricing');

// Estos tests cubren el camino feliz. A propósito NO cubren cupones expirados:
// la regresión de la demo pasa el CI unitario y solo la detecta el release testing.

test('subtotal without coupon', () => {
  assert.deepStrictEqual(price([{ id: 'p2', qty: 2 }]), { subtotal: 79, discount: 0, total: 79 });
});

test('SAVE10 applies 10% discount', () => {
  assert.deepStrictEqual(price([{ id: 'p4', qty: 1 }], 'SAVE10'), { subtotal: 279, discount: 27.9, total: 251.1 });
});

test('rejects empty cart', () => {
  assert.throws(() => price([]), { code: 'empty_cart' });
});
