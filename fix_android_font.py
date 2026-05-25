content = open('android/app/src/main/AndroidManifest.xml', 'r', encoding='utf-8').read()

old = '        android:label="js_awake_app"'
new = '        android:label="js_awake_app"\n        android:fontFamily="@font/noto_sans_jp"'

content = content.replace(old, new)
open('android/app/src/main/AndroidManifest.xml', 'w', encoding='utf-8').write(content)
print('OK')
