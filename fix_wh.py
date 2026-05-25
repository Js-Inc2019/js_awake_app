lines = open('lib/main.dart', 'r', encoding='utf-8').readlines()
result = []
skip = False
for line in lines:
    if "if (!widget.isBossMode) ...[" in line:
        skip = True
        continue
    if skip and "]," in line:
        skip = False
        continue
    if not skip:
        result.append(line)
open('lib/main.dart', 'w', encoding='utf-8').writelines(result)
print('OK')
