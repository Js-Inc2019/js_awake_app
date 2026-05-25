content = open('pubspec.yaml', 'r', encoding='utf-8').read()
# fontsセクション削除
import re
content = re.sub(r'  fonts:\n    - family: NotoSansJP\n      fonts:\n        - asset: assets/fonts/NotoSansJP-Regular\.otf\n', '', content)
open('pubspec.yaml', 'w', encoding='utf-8').write(content)
print('OK')
