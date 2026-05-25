with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('_transport     = TransportType.train')
print(repr(content[idx-100:idx+200]))
