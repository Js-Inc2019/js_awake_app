with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# スライド判定を下げて素早く反応、戻りは素早く
old = """  void _onEnd(DragEndDetails _) {
    if (_done) return;
    if (_offset > _max * 0.6) {
      setState(() { _done = true; _offset = _max; _animating = true; });
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 300), widget.onSlide);
    } else {
      setState(() { _offset = 0; _animating = true; });
    }
  }"""

new = """  void _onEnd(DragEndDetails d) {
    if (_done) return;
    // 速度か距離で判定
    final velocity = d.primaryVelocity ?? 0;
    if (_offset > _max * 0.45 || velocity > 800) {
      setState(() { _done = true; _offset = _max; _animating = true; });
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 200), widget.onSlide);
    } else {
      setState(() { _offset = 0; _animating = true; });
    }
  }"""

content = content.replace(old, new)

# アニメーション時間を短く
old2 = "duration: _animating ? const Duration(milliseconds: 200) : Duration.zero,"
new2 = "duration: _animating ? const Duration(milliseconds: 120) : Duration.zero,"

content = content.replace(old2, new2)

with open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('slide OK')
