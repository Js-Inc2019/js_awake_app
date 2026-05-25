with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# SharedWorkerFormのAppBarに戻るボタン非表示
old = """      appBar: AppBar(
        title: Text(widget.screenTitle),
        actions: ["""

new = """      appBar: AppBar(
        title: Text(widget.screenTitle),
        automaticallyImplyLeading: false,
        actions: ["""

content = content.replace(old, new)
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
