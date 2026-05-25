with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('Future<void> _submit()')
print(repr(content[idx+800:idx+1400]))
