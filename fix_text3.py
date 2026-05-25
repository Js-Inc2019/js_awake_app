with open('lib/screens/login_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

content = content.replace('登録する', 'Sign Up')
content = content.replace('ログイン', 'Login')
content = content.replace('指紋・顔認証が必要です', 'Login')
content = content.replace('もう一度', 'Retry')
content = content.replace('再試行', 'Retry')

with open('lib/screens/login_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
