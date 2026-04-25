const crypto = require('crypto');

const COOKIE_NAME = 'devplatform.csrf';
const HEADER_NAME = 'x-csrf-token';

/**
 * Double-submit cookie CSRF protection.
 *
 * Issuance: every GET response sets a non-HttpOnly cookie with a random token.
 * Verification: every state-changing request (POST/PUT/PATCH/DELETE) must include
 * the same token in either the `X-CSRF-Token` header or `_csrf` body field.
 *
 * Combined with SameSite=Lax cookies, this protects against cross-origin form
 * submissions and link-based CSRF.
 *
 * Login/logout endpoints are exempt because the user has no session yet to compare
 * against — the rate limiter and password check protect those instead.
 */
function csrfMiddleware(opts = {}) {
  const exempt = new Set(opts.exempt || []);

  return function (req, res, next) {
    // Issue/refresh cookie on safe methods
    if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') {
      let token = req.cookies ? req.cookies[COOKIE_NAME] : parseCookie(req.headers.cookie, COOKIE_NAME);
      if (!token) {
        token = crypto.randomBytes(24).toString('hex');
        res.setHeader('Set-Cookie',
          `${COOKIE_NAME}=${token}; Path=/; SameSite=Lax; Max-Age=${8 * 60 * 60}` +
          (opts.secure ? '; Secure' : ''));
      }
      res.locals.csrfToken = token;
      return next();
    }

    // Skip exempt paths (login, etc)
    if (exempt.has(req.path)) return next();

    // Verify token on state-changing requests
    const cookieToken = parseCookie(req.headers.cookie, COOKIE_NAME);
    const sentToken = req.headers[HEADER_NAME] || (req.body && req.body._csrf);

    if (!cookieToken || !sentToken || !timingSafeEq(cookieToken, sentToken)) {
      return res.status(403).json({
        success: false,
        error: 'csrf_invalid',
        message: 'Sesi keamanan tidak valid. Silakan refresh halaman.'
      });
    }
    next();
  };
}

function parseCookie(cookieHeader, name) {
  if (!cookieHeader) return null;
  const parts = cookieHeader.split(';');
  for (const p of parts) {
    const [k, v] = p.trim().split('=');
    if (k === name) return v;
  }
  return null;
}

function timingSafeEq(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) return false;
  return crypto.timingSafeEqual(ab, bb);
}

/** Endpoint to fetch current CSRF token (for SPA/JS calls). */
function csrfTokenEndpoint(req, res) {
  let token = parseCookie(req.headers.cookie, COOKIE_NAME);
  if (!token) {
    token = crypto.randomBytes(24).toString('hex');
    res.setHeader('Set-Cookie', `${COOKIE_NAME}=${token}; Path=/; SameSite=Lax; Max-Age=${8 * 60 * 60}`);
  }
  res.json({ csrfToken: token });
}

module.exports = { csrfMiddleware, csrfTokenEndpoint, COOKIE_NAME, HEADER_NAME };
