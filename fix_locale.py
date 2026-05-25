with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# MaterialAppにlocaleを追加
old = "      theme: ThemeData("
new = """      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP'), Locale('en', 'US')],
      theme: ThemeData("""

content = content.replace(old, new)
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
