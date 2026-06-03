with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find("if (t.depStation.isNotEmpty || t.arrStation.isNotEmpty)")
print(repr(content[idx-20:idx+200]))
