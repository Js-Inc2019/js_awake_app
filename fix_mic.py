content = open('android/app/src/main/AndroidManifest.xml', 'r', encoding='utf-8').read()

old = '<uses-permission android:name="android.permission.CAMERA" />'
new = '''<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MICROPHONE" />'''

content = content.replace(old, new)
open('android/app/src/main/AndroidManifest.xml', 'w', encoding='utf-8').write(content)
print('OK')
