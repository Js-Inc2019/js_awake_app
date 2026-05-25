content = open('lib/main.dart', 'r', encoding='utf-8').read()

old = """                        Column(children: [
                          const Icon(Icons.payments, color: JsColors.gold, size: 14),
                          const SizedBox(height: 2),
                          Text('\u00a5${route.cost}',
                              style: const TextStyle(color: JsColors.gold,
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const Text('\u6599\u91d1', style: TextStyle(color: JsColors.silver, fontSize: 10)),
                        ]),"""

new = """                        Column(children: [
                          const Icon(Icons.payments, color: JsColors.gold, size: 14),
                          const SizedBox(height: 2),
                          Text(route.fare != null
                              ? '\u00a5${route.fare}'
                              : route.estimatedGasCost != null
                                  ? '\u00a5${route.estimatedGasCost}'
                                  : '-',
                              style: const TextStyle(color: JsColors.gold,
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const Text('\u6599\u91d1', style: TextStyle(color: JsColors.silver, fontSize: 10)),
                        ]),"""

content = content.replace(old, new)
open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK')
