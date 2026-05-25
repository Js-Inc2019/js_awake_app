content = open('lib/main.dart', 'r', encoding='utf-8').read()
idx = content.find('_calculateRoutes')
print('found:', idx)
print(repr(content[idx:idx+300]))
