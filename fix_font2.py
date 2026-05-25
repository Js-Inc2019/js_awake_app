content = open('pubspec.yaml', 'r', encoding='utf-8').read()

# fontsセクション追加
if 'NotoSansJP' not in content:
    old = '\nflutter:\n'
    new = '\nflutter:\n  fonts:\n    - family: NotoSansJP\n      fonts:\n        - asset: assets/fonts/NotoSansJP-Regular.otf\n'
    content = content.replace(old, new, 1)
    open('pubspec.yaml', 'w', encoding='utf-8').write(content)
    print('OK')
else:
    print('既に追加済み')
