with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('_gpsAddress')
print(repr(content[idx-20:idx+100]))
