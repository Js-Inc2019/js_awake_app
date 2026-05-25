content = open('lib/main.dart', 'r', encoding='utf-8').read()

# TransportTypeのキーをAPIキーにマッピング
old = """              if (!_loadingRoutes && _routeComparisons.isNotEmpty)
                Builder(builder: (context) {
                  final key = _transport.name;
                  final route = _routeComparisons[key];"""

new = """              if (!_loadingRoutes && _routeComparisons.isNotEmpty)
                Builder(builder: (context) {
                  // TransportType -> API key mapping
                  const keyMap = {
                    'train': 'transit',
                    'car':   'driving',
                    'bus':   'transit',
                    'bike':  'bicycling',
                    'walk':  'walking',
                    'other': 'driving',
                  };
                  final key = keyMap[_transport.name] ?? 'driving';
                  final route = _routeComparisons[key];"""

content = content.replace(old, new)
open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK')
