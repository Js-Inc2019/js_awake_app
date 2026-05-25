with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('_submitting = false')
while idx >= 0:
    print(f'{idx}:', repr(content[idx-50:idx+100]))
    idx = content.find('_submitting = false', idx+1)
