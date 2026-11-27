'use strict';

const PRODUCTS = [
  { id: 'p1', name: 'Mechanical Keyboard', price: 89.9 },
  { id: 'p2', name: 'Wireless Mouse', price: 39.5 },
  { id: 'p3', name: 'USB-C Hub', price: 54.0 },
  { id: 'p4', name: '27" Monitor', price: 279.0 },
];

const COUPONS = {
  SAVE10: { type: 'percent', value: 10, expires: '2099-12-31' },
  WELCOME5: { type: 'fixed', value: 5, expires: '2099-12-31' },
  BLACKFRIDAY20: { type: 'percent', value: 20, expires: '2020-11-30' }, // expirado
};

class ValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const round2 = (n) => Math.round(n * 100) / 100;

function applyCoupon(code, subtotal) {
  if (!code) return 0;
  const coupon = COUPONS[String(code).toUpperCase()];
  if (!coupon) throw new ValidationError('coupon_invalid', 'Coupon does not exist');
  const discount = coupon.type === 'percent' ? (subtotal * coupon.value) / 100 : coupon.value;
  return Math.min(round2(discount), subtotal);
}

function price(items, couponCode) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new ValidationError('empty_cart', 'Cart must contain at least one item');
  }
  let subtotal = 0;
  for (const item of items) {
    const product = PRODUCTS.find((p) => p.id === item.id);
    if (!product) throw new ValidationError('unknown_product', `Unknown product ${item.id}`);
    if (!Number.isInteger(item.qty) || item.qty < 1 || item.qty > 10) {
      throw new ValidationError('invalid_quantity', 'qty must be an integer between 1 and 10');
    }
    subtotal += product.price * item.qty;
  }
  subtotal = round2(subtotal);
  const discount = applyCoupon(couponCode, subtotal);
  return { subtotal, discount, total: round2(subtotal - discount) };
}

module.exports = { PRODUCTS, COUPONS, ValidationError, price, applyCoupon };
