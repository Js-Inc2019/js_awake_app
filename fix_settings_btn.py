content = open('lib/main.dart', 'r', encoding='utf-8').read()

old = "tooltip: 'データ保持管理',"
new = """tooltip: '勤務設定',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const WorkSettingsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'データ保持管理',"""

content = content.replace(old, new)
open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK')
print('WorkSettingsScreen:', 'WorkSettingsScreen' in content)
