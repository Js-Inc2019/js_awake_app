with open('lib/screens/login_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

print('Sign Up:', 'Sign Up' in content)
print('Login:', 'Login' in content)
idx = content.find('Sign Up')
if idx >= 0:
    print(repr(content[idx-50:idx+50]))
