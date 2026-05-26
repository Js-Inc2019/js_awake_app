with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

old = "showJsSnackbar(context, '\u2705 $name\u306e\u5831\u544a\u3092\u9001\u4fe1\u3057\u307e\u3057\u305f');"
new = "showJsSnackbar(context, '\u2705 \u5831\u544a\u3092\u9001\u4fe1\u3057\u307e\u3057\u305f');"

content = content.replace(old, new)
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
