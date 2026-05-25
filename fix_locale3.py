with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

if 'GlobalMaterialLocalizations' not in content:
    old = "import 'package:google_fonts/google_fonts.dart';"
    new = """import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';"""
    content = content.replace(old, new)

    old2 = "      locale: const Locale('ja', 'JP'),"
    new2 = """      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      locale: const Locale('ja', 'JP'),"""
    content = content.replace(old2, new2)
    open('lib/main.dart', 'w', encoding='utf-8').write(content)
    print('OK')
