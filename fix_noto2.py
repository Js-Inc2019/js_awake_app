with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# importを追加
if 'google_fonts' not in content:
    old = "import 'package:flutter/foundation.dart' show kIsWeb;"
    new = "import 'package:flutter/foundation.dart' show kIsWeb;\nimport 'package:google_fonts/google_fonts.dart';"
    content = content.replace(old, new)
    print('import追加')

# fontFamilyをNoto Sans JPに変更
old2 = "      fontFamily: 'Roboto',"
new2 = "      fontFamily: GoogleFonts.notoSansJp().fontFamily,"
content = content.replace(old2, new2)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
print('GoogleFonts:', 'GoogleFonts' in content)
