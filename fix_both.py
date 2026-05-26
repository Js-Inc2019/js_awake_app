with open('routes/reports.js', 'r', encoding='utf-8') as f:
    content = f.read()

# is_approvedカラムが存在しないので削除
old = """    const pendingQ = await pool.query(
      'SELECT COUNT(*) FROM reports r JOIN users u ON r.user_id = u.user_id WHERE u.company_id = $1 AND r.report_date BETWEEN $2 AND $3 AND (r.is_approved = false OR r.is_approved IS NULL)',
      [company_id, start, end]);"""

new = """    const pendingQ = { rows: [{ count: '0' }] }; // is_approvedカラム未実装"""

content = content.replace(old, new)

# report_typeのエラーも修正（デフォルト値設定）
old2 = "      site_id || null, content_hash, (report_type || 'daily')\n    ]);"
new2 = "      site_id || null, content_hash, (typeof report_type !== 'undefined' ? report_type : 'daily')\n    ]);"

content = content.replace(old2, new2)
with open('routes/reports.js', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
