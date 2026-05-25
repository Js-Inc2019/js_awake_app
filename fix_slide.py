content = open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8').read()

# スライドボタンのStateにリセット機能追加
old = """  void _onDragEnd(DragEndDetails d) {
    if (!_slid) setState(() => _dragX = 0);
  }"""

new = """  void _onDragEnd(DragEndDetails d) {
    // 完了してなければ戻す
    if (!_slid) setState(() => _dragX = 0);
    // 残業など非同期処理後もリセット
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _dragX = 0; _slid = false; });
    });
  }"""

content = content.replace(old, new)

# ドラッグ中に途中で止まらないように閾値を上げる
old2 = "      if (_dragX >= _maxDrag * 0.85 && !_slid) {"
new2 = "      if (_dragX >= _maxDrag * 0.95 && !_slid) {"

content = content.replace(old2, new2)
open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8').write(content)
print('OK')
