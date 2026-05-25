import re

with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# _onOvertimeを修正：送信後にボタンを非表示
old = """  final _overtimeKey = GlobalKey();
  int _overtimeResetCount = 0;

  Future<void> _onOvertime() async {
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _OvertimeDialog(workerName: widget.workerName),
    );
    // ダイアログ閉じたらスライドをリセット
    if (mounted) setState(() => _overtimeResetCount++);
  }"""

new = """  bool _overtimeDone = false;

  Future<void> _onOvertime() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _OvertimeDialog(workerName: widget.workerName),
    );
    // 送信完了したら非表示
    if (mounted && result == true) setState(() => _overtimeDone = true);
  }"""

content = content.replace(old, new)

# 残業ボタンを丸ボタンに変更＋送信後非表示
old2 = """              // 残業ボタン（最上段）
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

new2 = """              // 残業ボタン（最上段・丸ボタン）
              if (!_overtimeDone)
                GestureDetector(
                  onTap: _processing ? null : _onOvertime,
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: JsColors.warning,
                      boxShadow: [BoxShadow(
                        color: JsColors.warning.withValues(alpha: 0.4),
                        blurRadius: 16, spreadRadius: 2,
                      )],
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.more_time, color: Colors.white, size: 32),
                        SizedBox(height: 4),
                        Text('\u6b8b\u696d',
                            style: TextStyle(color: Colors.white,
                                fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),"""

content = content.replace(old2, new2)

with open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK:', '_overtimeDone' in content)
