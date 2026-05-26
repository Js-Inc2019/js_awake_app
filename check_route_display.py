with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

idx = content.find('_RouteResultCard')
while idx >= 0:
    print(repr(content[idx-50:idx+100]))
    print('---')
    idx = content.find('_RouteResultCard', idx+1)
