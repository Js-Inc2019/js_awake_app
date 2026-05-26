with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('showJsSnackbar')
print(repr(content[idx+300:idx+600]))
