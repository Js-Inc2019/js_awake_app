import re

with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# _SlideButtonの残業部分をElevatedButtonに置換
old = """              _SlideButton(
                key: ValueKey(_overtimeResetCount),
                icon: Icons.more_time, label: '\u6b8b\u696d',
                subLabel: '\u6b8b\u696d\u6642\u9593\u30fb\u5185\u5bb9\u3092\u5831\u544a\u3059\u308b',
                color: JsColors.warning,
                onSlide: _processing ? null : _onOvertime,
              ),"""

new = """              SizedBox(
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

if old in content:
    content = content.replace(old, new)
    print('置換成功')
else:
    print('見つからない。現在のスライドボタン部分:')
    idx = content.find('more_time')
    print(repr(content[idx-200:idx+200]))

with open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
