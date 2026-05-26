with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

content = content.replace('onReorderItem:', 'onReorder:')

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
