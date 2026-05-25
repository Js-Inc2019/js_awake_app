with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# 写真プレビューを枚数表示に変更
old = """              // 写真プレビュー
              if (widget.parkingPhotoPath != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(widget.parkingPhotoPath!),
                    height: 100, width: double.infinity, fit: BoxFit.cover),
                ),
                const Text('\u99d0\u8eca\u5834\u5199\u771f',
                    style: TextStyle(color: JsColors.silver, fontSize: 10)),
              ],
              if (widget.workPhotoPath != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(widget.workPhotoPath!),
                    height: 100, width: double.infinity, fit: BoxFit.cover),
                ),
                const Text('\u4f5c\u696d\u5199\u771f',
                    style: TextStyle(color: JsColors.silver, fontSize: 10)),
              ],"""

new = """              // 写真枚数表示
              Builder(builder: (context) {
                final photoCount = (widget.parkingPhotoPath != null ? 1 : 0)
                                 + (widget.workPhotoPath    != null ? 1 : 0);
                if (photoCount == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    const Icon(Icons.photo_camera, color: JsColors.gold, size: 14),
                    const SizedBox(width: 4),
                    Text('\u5199\u771f $photoCount\u679a\u6dfb\u4ed8',
                        style: const TextStyle(color: JsColors.gold, fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ]),
                );
              }),"""

content = content.replace(old, new)

with open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
