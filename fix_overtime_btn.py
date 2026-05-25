content = open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8').read()

old = """              _SlideButton(
                key: ValueKey(_overtimeResetCount),
                icon: Icons.more_time, label: '残業',
                subLabel: '残業時間・内容を報告する',
                color: JsColors.warning,
                onSlide: _processing ? null : _onOvertime,
              ),
              const SizedBox(height: 12),
              _SlideButton(
                icon: Icons.directions_car, label: '現場移動',
                subLabel: 'GPS再取得して新しい報告へ',
                color: JsColors.gold,
                onSlide: _processing ? null : _onMove,
              ),
              const SizedBox(height: 12),
              _SlideButton(
                icon: Icons.nights_stay, label: '夜勤継続',
                subLabel: 'そのまま勤務を継続する',
                color: const Color(0xFF5C6BC0),
                onSlide: _processing ? null : _onNightShift,
              ),"""

new = """              // 残業ボタン（最上段・通常ボタン）
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _processing ? null : _onOvertime,
                  icon: const Icon(Icons.more_time),
                  label: const Text('残業報告'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JsColors.warning,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SlideButton(
                icon: Icons.directions_car, label: '現場移動',
                subLabel: 'GPS再取得して新しい報告へ',
                color: JsColors.gold,
                onSlide: _processing ? null : _onMove,
              ),
              const SizedBox(height: 12),
              _SlideButton(
                icon: Icons.nights_stay, label: '夜勤継続',
                subLabel: 'そのまま勤務を継続する',
                color: const Color(0xFF5C6BC0),
                onSlide: _processing ? null : _onNightShift,
              ),"""

content = content.replace(old, new)
open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8').write(content)
print('OK')
