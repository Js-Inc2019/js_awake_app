with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('class _SlideBtnState')
print(repr(content[idx:idx+200]))
