content = open('pubspec.yaml', 'r', encoding='utf-8').read()
if 'flutter_localizations' not in content:
    old = '  flutter:\n    sdk: flutter'
    new = '  flutter:\n    sdk: flutter\n  flutter_localizations:\n    sdk: flutter'
    content = content.replace(old, new)
    open('pubspec.yaml', 'w', encoding='utf-8').write(content)
    print('追加OK')
else:
    print('既に追加済み')
