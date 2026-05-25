with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# NotoSansJPをgoogle_fontsに戻す
content = content.replace(
    "      fontFamily: 'NotoSansJP',",
    "      fontFamily: GoogleFonts.notoSansJp().fontFamily,"
)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK:', 'GoogleFonts' in content)
