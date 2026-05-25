content = open('android/app/src/main/AndroidManifest.xml', 'r', encoding='utf-8').read()

old = '<uses-permission android:name="android.permission.INTERNET" />'
new = '''<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />'''

content = content.replace(old, new)
open('android/app/src/main/AndroidManifest.xml', 'w', encoding='utf-8').write(content)
print('OK')
