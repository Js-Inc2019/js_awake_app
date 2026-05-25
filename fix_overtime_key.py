content = open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8').read()

old = """  Future<void> _onOvertime() async {
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _OvertimeDialog(workerName: widget.workerName),
    );
    // 残業送信後はスライド画面に留まる（何もしない）
    if (mounted) setState(() {});
  }"""

new = """  final _overtimeKey = GlobalKey();
  int _overtimeResetCount = 0;

  Future<void> _onOvertime() async {
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _OvertimeDialog(workerName: widget.workerName),
    );
    // ダイアログ閉じたらスライドをリセット
    if (mounted) setState(() => _overtimeResetCount++);
  }"""

content = content.replace(old, new)

# スライドボタンにkeyを追加してリセット
old2 = """              _SlideButton(
                icon: Icons.more_time, label: '残業',
                subLabel: '残業時間・内容を報告する',
                color: JsColors.warning,
                onSlide: _processing ? null : _onOvertime,
              ),"""

new2 = """              _SlideButton(
                key: ValueKey(_overtimeResetCount),
                icon: Icons.more_time, label: '残業',
                subLabel: '残業時間・内容を報告する',
                color: JsColors.warning,
                onSlide: _processing ? null : _onOvertime,
              ),"""

content = content.replace(old2, new2)
open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8').write(content)
print('OK')
