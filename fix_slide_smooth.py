with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# ドラッグ中はアニメーションなし、終了時だけアニメーション
old = """  void _onUpdate(DragUpdateDetails d) {
    if (_done) return;
    setState(() => _offset = (_offset + d.delta.dx).clamp(0.0, _max));
  }
  void _onEnd(DragEndDetails _) {
    if (_done) return;
    if (_offset > _max * 0.6) {
      setState(() { _done = true; _offset = _max; });
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 300), widget.onSlide);
    } else {
      setState(() => _offset = 0);
    }
  }"""

new = """  bool _animating = false;

  void _onUpdate(DragUpdateDetails d) {
    if (_done) return;
    setState(() {
      _animating = false;
      _offset = (_offset + d.delta.dx).clamp(0.0, _max);
    });
  }
  void _onEnd(DragEndDetails _) {
    if (_done) return;
    if (_offset > _max * 0.6) {
      setState(() { _done = true; _offset = _max; _animating = true; });
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 300), widget.onSlide);
    } else {
      setState(() { _offset = 0; _animating = true; });
    }
  }"""

content = content.replace(old, new)

# アニメーション時間をドラッグ中は0msに
old2 = """            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),"""

new2 = """            child: AnimatedContainer(
              duration: _animating ? const Duration(milliseconds: 200) : Duration.zero,"""

content = content.replace(old2, new2)

with open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
