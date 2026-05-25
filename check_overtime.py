content = open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8').read()
idx = content.find('残業')
print(repr(content[idx-100:idx+300]))
