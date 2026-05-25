content = open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig').read()

# overtimeボタン部分確認
idx = content.find('overtime')
while idx >= 0:
    print(f'{idx}:', repr(content[idx:idx+100]))
    idx = content.find('overtime', idx+1)
    if idx > 5000:
        break
