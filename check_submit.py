with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('Future<void> _submit()')
print(repr(content[idx:idx+600]))
