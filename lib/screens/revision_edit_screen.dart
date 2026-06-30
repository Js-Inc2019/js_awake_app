import 'package:flutter/material.dart';
import '../main.dart' show JsColors;

/// 差戻しされた日報を職人が修正する専用画面（バッチ2）。
/// パイロット版：差戻し理由(boss_note)と現状表示のみ。
/// フィールド編集・写真・PUT/resubmit送信は後続ステップで追加する。
class RevisionEditScreen extends StatefulWidget {
  const RevisionEditScreen({super.key, required this.revision});
  final Map<String, dynamic> revision;

  @override
  State<RevisionEditScreen> createState() => _RevisionEditScreenState();
}

class _RevisionEditScreenState extends State<RevisionEditScreen> {
  @override
  Widget build(BuildContext context) {
    final r = widget.revision;
    final reportDate = (r['report_date'] as String?)?.trim() ?? '';
    final workContent = (r['work_content'] as String?)?.trim() ?? '';
    final bossNote = (r['boss_note'] as String?)?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('日報の修正'),
        backgroundColor: JsColors.gunmetal,
        foregroundColor: JsColors.offWhite,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (bossNote.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: JsColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JsColors.gold),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.feedback_outlined, color: JsColors.gold, size: 18),
                      SizedBox(width: 6),
                      Text('事務からの修正依頼',
                          style: TextStyle(color: JsColors.gold, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(bossNote,
                      style: const TextStyle(color: JsColors.offWhite, fontSize: 14, height: 1.5)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (reportDate.isNotEmpty) ...[
            const Text('対象日', style: TextStyle(color: JsColors.silver, fontSize: 12)),
            const SizedBox(height: 4),
            Text(reportDate, style: const TextStyle(color: JsColors.offWhite, fontSize: 15)),
            const SizedBox(height: 16),
          ],
          const Text('現在の作業内容', style: TextStyle(color: JsColors.silver, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JsColors.gunmetal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JsColors.divider),
            ),
            child: Text(workContent.isEmpty ? '（未入力）' : workContent,
                style: const TextStyle(color: JsColors.offWhite, fontSize: 14)),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JsColors.gunmetal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JsColors.divider),
            ),
            child: Row(
              children: const [
                Icon(Icons.construction, color: JsColors.silver, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('編集して再提出する機能は次の更新で追加されます。',
                      style: TextStyle(color: JsColors.silver, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
