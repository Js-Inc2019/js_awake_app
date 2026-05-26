with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if '_RouteResultCard' in line or '_routeComparisons' in line or '_loadingRoutes' in line:
        print(f'{i+1}: {repr(line.strip())}')
