with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# _routeComparisons の型を変更
old = "  Map<String, RouteCalculationResult> _routeComparisons = {};"
new = "  Map<String, dynamic> _routeComparisons = {};"

content = content.replace(old, new)

# _calculateRoutes でcompareRoutesV2を使う
old2 = """    final routes = await RoutesService().compareRoutes(
      origin:      homeAddr,
      destination: _gpsAddress,
      authToken:   token,
    );
    if (mounted) setState(() {
      _routeComparisons = routes;
      _loadingRoutes    = false;
    });"""

new2 = """    final routes = await RoutesService().compareRoutesV2(
      origin:      homeAddr,
      destination: _gpsAddress,
      authToken:   token,
    );
    if (mounted) setState(() {
      _routeComparisons = routes;
      _loadingRoutes    = false;
    });"""

if old2 in content:
    content = content.replace(old2, new2)
    print('compareRoutesV2 OK')
else:
    print('compareRoutes not found')
    idx = content.find('compareRoutes')
    print(repr(content[idx-20:idx+200]))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('main.dart OK')
