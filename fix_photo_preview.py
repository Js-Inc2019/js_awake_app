with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# コンストラクタに写真パス追加
old = """    this.reportType = 'daily',
  });
  final String workerName;
  final String reportTime;
  final String gpsAddress;
  final String transport;
  final String workContent;
  final String reportType;"""

new = """    this.reportType = 'daily',
    this.parkingPhotoPath,
    this.workPhotoPath,
  });
  final String workerName;
  final String reportTime;
  final String gpsAddress;
  final String transport;
  final String workContent;
  final String reportType;
  final String? parkingPhotoPath;
  final String? workPhotoPath;"""

content = content.replace(old, new)

# 詳細表示に写真追加
old2 = """                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('\u6b21\u306e\u884c\u52d5\u3092\u9078\u629e',"""

new2 = """                  ],
                ),
              ),
              // 写真プレビュー
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
              ],
              const SizedBox(height: 20),
              const Text('\u6b21\u306e\u884c\u52d5\u3092\u9078\u629e',"""

content = content.replace(old2, new2)

# dart:ioのimport確認
if "import 'dart:io'" not in content:
    content = "import 'dart:io';\n" + content

with open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
