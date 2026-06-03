with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('depStation')
while idx >= 0:
    print(repr(content[idx-20:idx+100]))
    print('---')
    idx = content.find('depStation', idx+1)
