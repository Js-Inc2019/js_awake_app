with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

old = """await _routesService.compareRoutes(
      origin: homeAddr,
      destination: _gpsAddress,
      authToken: token,
    );"""

new = """await _routesService.compareRoutesV2(
      origin: homeAddr,
      destination: _gpsAddress,
      authToken: token,
    );"""

if old in content:
    content = content.replace(old, new)
    print('OK')
else:
    idx = content.find('compareRoutes')
    print('見つからない')
    print(repr(content[idx-50:idx+200]))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
