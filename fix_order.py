import re

with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# ボタンの順番を変更（残業を最上段に）
old = """              _SlideButton(
                icon: Icons.directions_car, label: '\u73fe\u5834\u79fb\u52d5',
                subLabel: 'GPS\u518d\u53d6\u5f97\u3057\u3066\u65b0\u3057\u3044\u5831\u544a\u3078',
                color: JsColors.gold,
                onSlide: _processing ? null : _onMove,
              ),
              const SizedBox(height: 12),
              _SlideButton(
                icon: Icons.nights_stay, label: '\u591c\u52e4\u7d99\u7d9a',
                subLabel: '\u305d\u306e\u307e\u307e\u52e4\u52d9\u3092\u7d99\u7d9a\u3059\u308b',
                color: const Color(0xFF5C6BC0),
                onSlide: _processing ? null : _onNightShift,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _processing ? null : _onOvertime,
                  icon: const Icon(Icons.more_time),
                  label: const Text('\u6b8b\u696d\u5831\u544a'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JsColors.warning,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),"""

new = """              // 残業ボタン（最上段）
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _processing ? null : _onOvertime,
                  icon: const Icon(Icons.more_time),
                  label: const Text('\u6b8b\u696d\u5831\u544a'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JsColors.warning,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _SlideButton(
                icon: Icons.directions_car, label: '\u73fe\u5834\u79fb\u52d5',
                subLabel: 'GPS\u518d\u53d6\u5f97\u3057\u3066\u65b0\u3057\u3044\u5831\u544a\u3078',
                color: JsColors.gold,
                onSlide: _processing ? null : _onMove,
              ),
              const SizedBox(height: 12),
              _SlideButton(
                icon: Icons.nights_stay, label: '\u591c\u52e4\u7d99\u7d9a',
                subLabel: '\u305d\u306e\u307e\u307e\u52e4\u52d9\u3092\u7d99\u7d9a\u3059\u308b',
                color: const Color(0xFF5C6BC0),
                onSlide: _processing ? null : _onNightShift,
              ),"""

if old in content:
    content = content.replace(old, new)
    print('順番変更成功')
else:
    print('見つからない')
    idx = content.find('directions_car')
    print(repr(content[idx-50:idx+200]))

with open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
