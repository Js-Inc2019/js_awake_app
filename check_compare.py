with open('lib/services/routes_service.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('compareRoutes(')
while idx >= 0:
    print(repr(content[idx:idx+100]))
    print('---')
    idx = content.find('compareRoutes(', idx+1)
