with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('_routeComparisons')
print('_routeComparisons found at:', idx)
idx2 = content.find('RouteCalculationResult')
print('RouteCalculationResult found at:', idx2)
