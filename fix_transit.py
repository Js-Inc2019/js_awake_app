content = open('lib/main.dart', 'r', encoding='utf-8').read()

old = """                          Text(route.fare != null
                              ? '\u00a5${route.fare}'
                              : route.estimatedGasCost != null
                                  ? '\u00a5${route.estimatedGasCost}'
                                  : '-',"""

new = """                          Text(route.fare != null && route.fare!.isNotEmpty
                              ? '\u00a5${route.fare}'
                              : route.estimatedGasCost != null
                                  ? '\u30ac\u30bd\u30ea\u30f3\u4ee3\u00a5${route.estimatedGasCost}'
                                  : '-',"""

content = content.replace(old, new)

# transitでもrouteがnullでも距離・時間は表示
old2 = "                  if (route == null) return const SizedBox.shrink();"
new2 = """                  if (route == null) {
                    // ルートデータ未取得時は再計算を促す
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: JsColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: JsColors.divider),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline, color: JsColors.silver, size: 14),
                        SizedBox(width: 8),
                        Text('\u4ea4\u901a\u624b\u6bb5\u3092\u9078\u629e\u3059\u308b\u3068\u30eb\u30fc\u30c8\u3092\u53d6\u5f97\u3057\u307e\u3059',
                            style: TextStyle(color: JsColors.silver, fontSize: 12)),
                      ]),
                    );
                  }"""

content = content.replace(old2, new2)
open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK')
