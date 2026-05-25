with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('Future<void> _submit()')
print(repr(content[idx+1400:idx+1800]))
