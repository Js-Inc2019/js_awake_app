content = open('lib/main.dart', 'r', encoding='utf-8').read()

# 職人モード（isBossMode=false）のときもアイコン表示
# actions: widget.isBossMode ? [...] : null を修正
old = "        actions: widget.isBossMode ? ["
new = """        actions: [
          if (!widget.isBossMode) ...[
            IconButton(
              icon: const Icon(Icons.work_history),
              tooltip: '\u52e4\u52d9\u30e2\u30fc\u30c9',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const WorkModeScreen())),
            ),
          ],
          if (widget.isBossMode) ...["""

content = content.replace(old, new)

# 末尾の ] : null を修正
old2 = "        ] : null,"
new2 = "          ],\n        ],"

content = content.replace(old2, new2)

open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK')
