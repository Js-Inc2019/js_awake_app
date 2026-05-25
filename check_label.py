with open('lib/screens/login_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find("label: const Text(")
while idx >= 0:
    print(repr(content[idx:idx+80]))
    print('---')
    idx = content.find("label: const Text(", idx+1)
