with open('lib/screens/login_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# 「認証」を「本人確認」に変更
content = content.replace('生体認証で登録', '指紋・顔で登録')
content = content.replace('生体認証が必要です', '指紋・顔認証が必要です')
content = content.replace('生体認証に失敗しました', '認識に失敗しました')
content = content.replace('本人確認のため生体認証を行ってください', '本人確認を行ってください')
content = content.replace('再試行', 'もう一度')

with open('lib/screens/login_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
