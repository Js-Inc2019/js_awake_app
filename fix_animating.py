with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

old = """class _SlideBtnState extends State<_SlideBtn> {
  double _offset = 0;
  bool _done = false;
  static const double _max = 220.0;

  bool _animating = false;"""

new = """class _SlideBtnState extends State<_SlideBtn> {
  double _offset = 0;
  bool _done = false;
  bool _animating = false;
  static const double _max = 220.0;"""

if old in content:
    content = content.replace(old, new)
    print('OK')
else:
    # _animatingがないから追加
    old2 = """class _SlideBtnState extends State<_SlideBtn> {
  double _offset = 0;
  bool _done = false;
  static const double _max = 220.0;"""
    new2 = """class _SlideBtnState extends State<_SlideBtn> {
  double _offset = 0;
  bool _done = false;
  bool _animating = false;
  static const double _max = 220.0;"""
    content = content.replace(old2, new2)
    print('OK2')

with open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
