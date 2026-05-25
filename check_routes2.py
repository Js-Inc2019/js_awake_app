content = open('lib/main.dart', 'r', encoding='utf-8').read()
idx = content.find('_routeComparisons')
while idx >= 0:
    print(f'found at {idx}:', repr(content[idx:idx+80]))
    idx = content.find('_routeComparisons', idx+1)
