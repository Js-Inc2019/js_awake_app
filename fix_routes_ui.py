content = open('lib/main.dart', 'r', encoding='utf-8').read()

# TransportSelectorの後にルート表示を追加
old = """              const SizedBox(height: 16),

              if (_transport == TransportType.car) ...["""

new = """              const SizedBox(height: 8),

              // ルート情報表示
              if (_loadingRoutes)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: JsColors.gold)),
                    SizedBox(width: 8),
                    Text('\u30eb\u30fc\u30c8\u8a08\u7b97\u4e2d...', style: TextStyle(color: JsColors.silver, fontSize: 12)),
                  ]),
                ),

              if (!_loadingRoutes && _routeComparisons.isNotEmpty)
                Builder(builder: (context) {
                  final key = _transport.name;
                  final route = _routeComparisons[key];
                  if (route == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: JsColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: JsColors.gold.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(children: [
                          const Icon(Icons.straighten, color: JsColors.silver, size: 14),
                          const SizedBox(height: 2),
                          Text(route.distance,
                              style: const TextStyle(color: JsColors.offWhite,
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const Text('\u8ddd\u96e2', style: TextStyle(color: JsColors.silver, fontSize: 10)),
                        ]),
                        Container(width: 1, height: 36, color: JsColors.divider),
                        Column(children: [
                          const Icon(Icons.access_time, color: JsColors.silver, size: 14),
                          const SizedBox(height: 2),
                          Text(route.duration,
                              style: const TextStyle(color: JsColors.offWhite,
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const Text('\u6240\u8981\u6642\u9593', style: TextStyle(color: JsColors.silver, fontSize: 10)),
                        ]),
                        Container(width: 1, height: 36, color: JsColors.divider),
                        Column(children: [
                          const Icon(Icons.payments, color: JsColors.gold, size: 14),
                          const SizedBox(height: 2),
                          Text('\u00a5${route.cost}',
                              style: const TextStyle(color: JsColors.gold,
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const Text('\u6599\u91d1', style: TextStyle(color: JsColors.silver, fontSize: 10)),
                        ]),
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 8),

              if (_transport == TransportType.car) ...["""

content = content.replace(old, new)
open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK:', '_loadingRoutes' in content)
