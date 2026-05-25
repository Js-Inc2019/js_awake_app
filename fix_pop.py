with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

old = """    if (mounted) Navigator.pop(context, {
      'overtime_start': _fmtTime(_start),
      'overtime_end':   _fmtTime(_end),
      'content':        _contentCtrl.text.trim(),
    });"""

new = "    if (mounted) Navigator.pop(context, true);"

content = content.replace(old, new)

with open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK:', 'Navigator.pop(context, true)' in content)
