lines = open('lib/main.dart', 'r', encoding='utf-8').readlines()

# import重複削除
seen = False
result = []
for line in lines:
    if line.strip() == "import 'screens/retention_screen.dart';":
        if not seen:
            result.append(line)
            seen = True
    else:
        result.append(line)

# RetentionScreen重複削除（2箇所目のボタンブロックを削除）
content = ''.join(result)

# 重複したボタンブロックを削除
import re
pattern = r"tooltip: 'データ保持管理',\n            onPressed: \(\) => Navigator\.push\(context,\n                MaterialPageRoute\(builder: \(_\) => const RetentionScreen\(\)\)\),\n          \),\n          IconButton\(\n            icon: const Icon\(Icons\.notifications_active\),\n            tooltip: 'データ保持管理',\n            onPressed: \(\) => Navigator\.push\(context,\n                MaterialPageRoute\(builder: \(_\) => const RetentionScreen\(\)\)\),\n          \),\n          IconButton\(\n            icon: const Icon\(Icons\.notifications_active\),\n            tooltip: '通知設定',"
replacement = "tooltip: 'データ保持管理',\n            onPressed: () => Navigator.push(context,\n                MaterialPageRoute(builder: (_) => const RetentionScreen())),\n          ),\n          IconButton(\n            icon: const Icon(Icons.notifications_active),\n            tooltip: '通知設定',"
content = re.sub(pattern, replacement, content)

open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK')
