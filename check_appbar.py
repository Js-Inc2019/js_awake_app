content = open('lib/main.dart', 'r', encoding='utf-8').read()
# SharedWorkerFormのAppBar部分を探す
idx = content.find('screenTitle')
print(repr(content[idx:idx+400]))
