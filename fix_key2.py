content = open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8').read()

old = """class _SlideButton extends StatefulWidget {
  const _SlideButton({
    required this.icon, required this.label, required this.subLabel,
    required this.color, required this.onSlide,
  });"""

new = """class _SlideButton extends StatefulWidget {
  const _SlideButton({
    super.key,
    required this.icon, required this.label, required this.subLabel,
    required this.color, required this.onSlide,
  });"""

content = content.replace(old, new)
open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8').write(content)
print('OK')
