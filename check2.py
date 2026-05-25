lines = open('lib/main.dart', 'r', encoding='utf-8').readlines()
for i in range(1845, 1870):
    print(f'{i+1}: {repr(lines[i])}')
