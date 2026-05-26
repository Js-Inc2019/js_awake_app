with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    lines = f.readlines()

for i in range(1428, 1440):
    print(f'{i+1}: {repr(lines[i])}')
