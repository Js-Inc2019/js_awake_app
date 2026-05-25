with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('useMaterial3')
print(repr(content[idx:idx+200]))
