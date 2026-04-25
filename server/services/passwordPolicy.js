const MIN_LEN = 10;
const COMMON = new Set([
  'password', 'password123', '12345678', '123456789', '1234567890',
  'qwerty123', 'admin123', 'admin1234', 'user1234', 'letmein123',
  'welcome123', 'changeme', 'iloveyou', 'monkey123', 'dragon123'
]);

/**
 * Validate password strength.
 * Rules:
 *   - min 10 characters
 *   - must contain at least 3 of: lowercase, uppercase, digit, symbol
 *   - not in common-password list
 *   - not equal to username (case-insensitive)
 */
function validateStrong(password, username) {
  if (typeof password !== 'string') return { ok: false, message: 'Password tidak valid.' };
  if (password.length < MIN_LEN) return { ok: false, message: `Password minimal ${MIN_LEN} karakter.` };
  if (password.length > 200) return { ok: false, message: 'Password terlalu panjang (max 200).' };
  if (username && password.toLowerCase().includes(String(username).toLowerCase())) {
    return { ok: false, message: 'Password tidak boleh mengandung username.' };
  }
  if (COMMON.has(password.toLowerCase())) {
    return { ok: false, message: 'Password terlalu umum/lemah, pilih yang lebih unik.' };
  }
  let score = 0;
  if (/[a-z]/.test(password)) score++;
  if (/[A-Z]/.test(password)) score++;
  if (/[0-9]/.test(password)) score++;
  if (/[^a-zA-Z0-9]/.test(password)) score++;
  if (score < 3) {
    return { ok: false, message: 'Password harus campuran 3 dari 4: huruf kecil, huruf besar, angka, simbol.' };
  }
  return { ok: true };
}

/** Less strict: used when checking user's own change (still 8 char min for non-strong). */
function isDefaultPassword(plain) {
  return ['admin123', 'user1234', 'changeme', 'password', '12345678'].includes(plain);
}

module.exports = { validateStrong, isDefaultPassword, MIN_LEN };
