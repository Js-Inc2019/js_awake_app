content = open('lib/main.dart', 'r', encoding='utf-8').read()
idx = content.find('Icons.work_history')
print('found at:', idx)
print(repr(content[idx-150:idx+150]))
