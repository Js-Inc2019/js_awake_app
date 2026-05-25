with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

content = content.replace(
    "      fontFamily: GoogleFonts.notoSansJp().fontFamily,",
    "      fontFamily: 'NotoSansJP',"
)
content = content.replace(
    "      textTheme: GoogleFonts.notoSansJpTextTheme(\n        ThemeData.dark().textTheme,\n      ),",
    ""
)
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
