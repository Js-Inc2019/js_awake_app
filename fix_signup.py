with open('lib/screens/login_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

content = content.replace("'指紋・顔で登録'", "'Sign Up'")

with open('lib/screens/login_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK:', 'Sign Up' in content)
