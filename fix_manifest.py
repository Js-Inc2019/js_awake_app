content = open('android/app/src/main/AndroidManifest.xml', 'r', encoding='utf-8').read()

# xmlns重複修正
content = content.replace(
    'xmlns:android="http://schemas.android.com/apk/res/android"> xmlns:android="http://schemas.android.com/apk/res/android">',
    'xmlns:android="http://schemas.android.com/apk/res/android">'
)

# `n を改行に修正
content = content.replace(
    '<uses-permission android:name="android.permission.INTERNET" />`n<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    '<uses-permission android:name="android.permission.INTERNET" />\n<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />'
)

open('android/app/src/main/AndroidManifest.xml', 'w', encoding='utf-8').write(content)
print('OK')
