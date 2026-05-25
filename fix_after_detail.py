with open('lib/screens/after_report_screen.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# コンストラクタにreport情報追加
old = """class AfterReportScreen extends StatefulWidget {
  const AfterReportScreen({
    super.key,
    required this.workerName,
    required this.reportTime,
  });
  final String workerName;
  final String reportTime;"""

new = """class AfterReportScreen extends StatefulWidget {
  const AfterReportScreen({
    super.key,
    required this.workerName,
    required this.reportTime,
    this.gpsAddress = '',
    this.transport = '',
    this.workContent = '',
    this.reportType = 'daily',
  });
  final String workerName;
  final String reportTime;
  final String gpsAddress;
  final String transport;
  final String workContent;
  final String reportType;"""

content = content.replace(old, new)

# 送信完了画面に詳細表示追加
old2 = """              const Text('次の行動を選択',
                  style: TextStyle(color: JsColors.silver, fontSize: 14)),"""

new2 = """              // 送信詳細
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: JsColors.gunmetal,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: JsColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('\u9001\u4fe1\u5185\u5bb9',
                        style: TextStyle(color: JsColors.silver, fontSize: 11)),
                    const SizedBox(height: 8),
                    if (widget.gpsAddress.isNotEmpty)
                      Row(children: [
                        const Icon(Icons.location_on, color: JsColors.gold, size: 14),
                        const SizedBox(width: 4),
                        Expanded(child: Text(widget.gpsAddress,
                            style: const TextStyle(color: JsColors.offWhite, fontSize: 12),
                            maxLines: 2)),
                      ]),
                    if (widget.transport.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.directions, color: JsColors.silver, size: 14),
                        const SizedBox(width: 4),
                        Text(widget.transport,
                            style: const TextStyle(color: JsColors.offWhite, fontSize: 12)),
                      ]),
                    ],
                    if (widget.workContent.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.construction, color: JsColors.silver, size: 14),
                        const SizedBox(width: 4),
                        Expanded(child: Text(widget.workContent,
                            style: const TextStyle(color: JsColors.offWhite, fontSize: 12),
                            maxLines: 3)),
                      ]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('\u6b21\u306e\u884c\u52d5\u3092\u9078\u629e',
                  style: TextStyle(color: JsColors.silver, fontSize: 14)),"""

content = content.replace(old2, new2)

with open('lib/screens/after_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
