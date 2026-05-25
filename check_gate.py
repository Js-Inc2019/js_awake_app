content = open('lib/main.dart', 'r', encoding='utf-8').read()
idx = content.find('class GateScreen')
print(repr(content[idx:idx+800]))
