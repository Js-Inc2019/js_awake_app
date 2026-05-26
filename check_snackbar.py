with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('showJsSnackbar')
print('定義:', idx)
print(repr(content[idx:idx+300]))
