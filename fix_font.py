with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# ThemeDataにfontFamilyを追加
old = "      useMaterial3: true,\n      brightness: Brightness.dark,"
new = "      useMaterial3: true,\n      brightness: Brightness.dark,\n      fontFamily: 'Roboto',"

content = content.replace(old, new)
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
