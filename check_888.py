with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    lines = f.readlines()
for i in range(878, 905):
    print(f'{i+1}: {repr(lines[i])}')
