with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('transportLabel')
print(repr(content[idx-50:idx+300]))
