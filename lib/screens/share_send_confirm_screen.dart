// ============================================================
// lib/screens/share_send_confirm_screen.dart — 送信内容の確認（FIELD）
//
// 導線: 送信画面（share_send_screen.dart）で宛先まで決めた後の最終確認。
//
// ★業務仕様は OFFICE の完成形（js_office_admin_app 2028773 の
//   lib/screens/bundle_send_confirm_screen.dart）と同じ:
//     ・押す前に「誰へ・何件・どの期間・どの職人の・どの現場の・どの日報を」全部見せる
//     ・日報は【全件】並べる（抜粋しない・「n件ほか」で丸めない）
//     ・行タップで個別プレビュー（外せない＝確認した内容と送る内容がずれない）
//     ・「送信する」で true を返すだけ。API はここでは呼ばない（確認の責務のみ）
//   FIELD 側の違いは配色（FieldTokens = Asphalt Dawn）と、プレビューが
//   FIELD 既存の ReportDetailSheet（呼び手から関数で受け取る）である点だけ。
//
// ★宛先は「n社」で丸めずチップで全社ぶん出す。丸めると
//   「どこへ送るのか分からないまま押す」状態になる。
// ============================================================

import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';

class ShareSendConfirmScreen extends StatelessWidget {
  const ShareSendConfirmScreen({
    super.key,
    required this.reports,
    required this.receiverCompanyNames,
    required this.periodLabel,
    required this.workerSummary,
    required this.siteSummary,
    required this.includePhotos,
    required this.onPreview,
  });

  /// 送る日報（選択済みの全件）。
  final List<Map<String, dynamic>> reports;

  /// 宛先会社名（全社ぶん）。
  final List<String> receiverCompanyNames;

  /// 期間の見出し（'2026-06-10〜2026-06-20' 等・送信画面が組んだ1つの文言）。
  final String periodLabel;

  /// 職人・現場の条件の読み下し（'全員' / '3名を指定（田中・佐藤・鈴木）' 等）。
  final String workerSummary;
  final String siteSummary;

  /// 写真を含めて送るか。★受信側の見え方が変わる（含めない場合、受信側の
  /// 日報閲覧に「この束は写真を含めずに送られています」が出る）ので確認画面に出す。
  final bool includePhotos;

  /// 行タップのプレビュー。送信画面の共通シート（ReportDetailSheet）をそのまま使う
  /// ＝プレビューを2つ作らないために関数で受け取る。
  final void Function(Map<String, dynamic> report) onPreview;

  static String _weekdayJp(String ymd) {
    final d = DateTime.tryParse(ymd);
    if (d == null) return '';
    const w = ['月', '火', '水', '木', '金', '土', '日'];
    return w[d.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        title: const Text('送信内容の確認'),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: FieldTokens.surfaceCard,
            border: Border(top: BorderSide(color: FieldTokens.outline)),
          ),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: FieldTokens.textSupport,
                  side: const BorderSide(color: FieldTokens.outline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('戻る'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: receiverCompanyNames.isEmpty || reports.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.send, size: 18),
                label: const Text('送信する'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: FieldTokens.accent,
                  foregroundColor: FieldTokens.onAccent,
                  disabledBackgroundColor: FieldTokens.outlineStrong,
                  disabledForegroundColor: FieldTokens.textFaint,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // ── 宛先（全社ぶんチップで出す）──
          _sectionTitle('宛先', Icons.apartment),
          const SizedBox(height: 8),
          if (receiverCompanyNames.isEmpty)
            const Text('（宛先が選ばれていません）',
                style:
                    TextStyle(color: FieldTokens.statusError, fontSize: 13))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in receiverCompanyNames)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: FieldTokens.externalBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: FieldTokens.externalBlue),
                    ),
                    child: Text(name,
                        style: const TextStyle(
                            color: FieldTokens.textBody,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          const Text('※送信先は閲覧のみ可能です。',
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),

          const SizedBox(height: 20),
          // ── 送る内容の要約 ──
          _sectionTitle('送る内容', Icons.fact_check_outlined),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: FieldTokens.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FieldTokens.outline),
            ),
            child: Column(children: [
              _summaryRow('件数', '${reports.length}件'),
              _summaryRow('期間', periodLabel.isEmpty ? '（指定なし）' : periodLabel),
              _summaryRow('職人', workerSummary),
              _summaryRow('現場', siteSummary),
              _summaryRow('写真', includePhotos ? '含める' : '含めない'),
            ]),
          ),

          const SizedBox(height: 20),
          // ── 送る日報の全件一覧（行タップで個別プレビュー）──
          _sectionTitle('送る日報（${reports.length}件）',
              Icons.description_outlined),
          const SizedBox(height: 8),
          for (final r in reports) _reportRow(r),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) => Row(children: [
        Icon(icon, color: FieldTokens.accent, size: 18),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: FieldTokens.textBody,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      ]);

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 56,
            child: Text(label,
                style: const TextStyle(
                    color: FieldTokens.textSupport, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
      );

  Widget _reportRow(Map<String, dynamic> r) {
    final date = (r['report_date'] ?? '').toString();
    final wd = _weekdayJp(date);
    final worker = (r['worker_name'] ?? '').toString().trim();
    // 現場名は sitesマスタ正式名 > 職人入力 > 未設定 の順（日報一覧と同じ優先度）。
    final master = (r['master_site_name'] ?? '').toString().trim();
    final site = (r['site_name'] ?? '').toString().trim();
    final siteLabel =
        master.isNotEmpty ? master : (site.isNotEmpty ? site : '現場未設定');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FieldTokens.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        // 確認画面のプレビューは「見るだけ」＝選択を外す口は出さない
        //   （ここで外せると、確認した内容と送る内容がずれる）。
        onTap: () => onPreview(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(wd.isNotEmpty ? '$date（$wd）' : date,
                        style: const TextStyle(
                            color: FieldTokens.textBody,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(worker.isEmpty ? '不明' : worker,
                            style: const TextStyle(
                                color: FieldTokens.textSupport,
                                fontSize: 13)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(siteLabel,
                        style: const TextStyle(
                            color: FieldTokens.textSupport, fontSize: 11)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: FieldTokens.textSupport, size: 20),
          ]),
        ),
      ),
    );
  }
}
