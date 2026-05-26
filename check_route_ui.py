with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('_routeComparisons.isNotEmpty')
print(repr(content[idx-50:idx+500]))
