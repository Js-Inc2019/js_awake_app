with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# バスは別表示（暫定でtransitデータを流用しつつバスと明示）
old = """  @override
  Widget build(BuildContext context) {
    if (selectedTransport == TransportType.train || selectedTransport == TransportType.bus) {
      return _buildTransit();"""

new = """  @override
  Widget build(BuildContext context) {
    if (selectedTransport == TransportType.train) {
      return _buildTransit(label: '\u96fb\u8eca');
    } else if (selectedTransport == TransportType.bus) {
      return _buildTransit(label: '\u30d0\u30b9');"""

content = content.replace(old, new)

# _buildTransitにlabelパラメータ追加
old2 = "  Widget _buildTransit() {"
new2 = "  Widget _buildTransit({String label = '\u96fb\u8eca'}) {"

content = content.replace(old2, new2)

# アイコンとラベルを変更
old3 = "          const Icon(Icons.train, color: JsColors.gold, size: 16),"
new3 = "          Icon(label == '\u30d0\u30b9' ? Icons.directions_bus : Icons.train, color: JsColors.gold, size: 16),"

content = content.replace(old3, new3)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
