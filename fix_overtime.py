content = open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8').read()

old = """  Future<void> _onOvertime() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _OvertimeDialog(workerName: widget.workerName),
    );
    if (result != null && mounted) {
      Navigator.pop(context, {'action': 'overtime', ...result});
    }
  }"""

new = """  Future<void> _onOvertime() async {
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _OvertimeDialog(workerName: widget.workerName),
    );
    // 残業送信後はスライド画面に留まる（何もしない）
    if (mounted) setState(() {});
  }"""

content = content.replace(old, new)
open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8').write(content)
print('OK')
