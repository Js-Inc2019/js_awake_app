with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# textThemeにもNoto Sans JPを適用
old = "      fontFamily: GoogleFonts.notoSansJp().fontFamily,"
new = """      fontFamily: GoogleFonts.notoSansJp().fontFamily,
      textTheme: GoogleFonts.notoSansJpTextTheme(
        ThemeData.dark().textTheme,
      ),"""

content = content.replace(old, new)
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
