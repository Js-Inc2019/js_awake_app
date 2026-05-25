content = open('lib/main.dart', 'r', encoding='utf-8').read()
idx = content.find('AppBar(\n        title: Text(widget.screenTitle)')
print('found at:', idx)
if idx >= 0:
    print(repr(content[idx:idx+500]))
