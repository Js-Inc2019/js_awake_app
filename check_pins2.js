const pool = require('./db/connection');
const bcrypt = require('bcryptjs');
require('dotenv').config();
(async () => {
  // 全ユーザーのPINハッシュと照合
  const r = await pool.query('SELECT user_id, name, role, pin_hash FROM users WHERE is_active = TRUE');
  const bcryptjs = require('bcryptjs');
  for (const u of r.rows) {
    if (u.pin_hash) {
      const match1234 = await bcrypt.compare('1234', u.pin_hash);
      const match9999 = await bcrypt.compare('9999', u.pin_hash);
      if (match1234 || match9999) {
        console.log(`${u.name} (${u.role}): PIN=${match1234 ? '1234' : '9999'}`);
      }
    }
  }
  process.exit(0);
})();
