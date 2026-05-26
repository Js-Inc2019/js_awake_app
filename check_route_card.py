with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    lines = f.readlines()

for i in range(1853, 1920):
    print(f'{i+1}: {repr(lines[i])}')
