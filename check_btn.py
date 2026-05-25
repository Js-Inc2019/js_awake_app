with open('lib/screens/login_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('ElevatedButton')
while idx >= 0:
    print(repr(content[idx:idx+150]))
    print('---')
    idx = content.find('ElevatedButton', idx+1)
