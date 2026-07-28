// lib/screens/approval_day_screen.dart
// 承認タブ ▸ 日付一覧の行タップで開く「その日の報告」画面。
//
// ★この画面は器であり、カードの中身は既存実体をそのまま呼ぶ:
//     承認待ち = PendingApprovalCard   (home_screen.dart:4407)
//     差し戻し = RevisionCard          (revision_inbox_screen.dart:213)
//   承認/修正依頼の判定式・API 呼び出し・確認ダイアログは一切ここに持たない
//   （すべて PendingApprovalCard の内部にあり、1文字も変更していない）。
//
// 抽出条件は ReviewTab（呼び出し元）と同一の式を使う:
//     承認待ち = is_sent==true && approved!=true && revision_requested!=true
//     差し戻し = revision_requested==true
import 'package:flutter/material.dart';

import '../core/theme/js_colors.dart';
import '../services/auth_service.dart';
import 'home_screen.dart' show PendingApprovalCard;
import 'revision_inbox_screen.dart' show RevisionCard, ReportDetailSheet;
import 'revision_edit_screen.dart';

class ApprovalDayScreen extends StatefulWidget {
  const ApprovalDayScreen({
    super.key,
    required this.date,
    required this.reports,
  });

  /// 対象日
  final DateTime date;

  /// その日の対象レポート（承認待ち＋差し戻しの両方を含む）
  final List<Map<String, dynamic>> reports;

  @override
  State<ApprovalDayScreen> createState() => _ApprovalDayScreenState();
}

class _ApprovalDayScreenState extends State<ApprovalDayScreen> {
  static const _week = ['日', '月', '火', '水', '木', '金', '土'];

  /// 画面内で保持する対象。承認/修正依頼の成功後はここから消して即時反映する。
  late List<Map<String, dynamic>> _reports = List.of(widget.reports);

  /// 本人判定用（RevisionCard の編集/閲覧分岐は revision_inbox_screen.dart:131-135 と同じ流儀）。
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _loadMyUserId();
  }

  Future<void> _loadMyUserId() async {
    final uid = await AuthService().getUserId();
    if (!mounted) return;
    setState(() => _myUserId = uid);
  }

  // 抽出条件（ReviewTab と同一）
  bool _isPending(Map<String, dynamic> r) =>
      r['is_sent'] == true &&
      r['approved'] != true &&
      r['revision_requested'] != true;
  bool _isRevision(Map<String, dynamic> r) => r['revision_requested'] == true;

  // 承認/修正依頼の成功後: この画面から対象を外し、呼び出し元にも再読込を促す。
  // （旧 _ReviewTab._reloadBoth 相当＝両方を最新化する挙動を維持）
  void _onActionSuccess(Map<String, dynamic> handled) {
    final id = handled['report_id'];
    setState(() {
      _reports = _reports.where((r) => r['report_id'] != id).toList();
    });
    if (_reports.isEmpty && mounted) {
      Navigator.pop(context, true); // true = 呼び出し元は再読込する
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.date;
    final pending  = _reports.where(_isPending).toList();
    final revision = _reports.where(_isRevision).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, true); // 戻るときは常に呼び出し元へ再読込を促す
      },
      child: Scaffold(
        backgroundColor: JsColors.black,
        appBar: AppBar(
          backgroundColor: JsColors.black,
          iconTheme: const IconThemeData(color: JsPalette.brand),
          title: Text(
            '${d.month}月${d.day}日（${_week[d.weekday % 7]}）の報告',
            style: const TextStyle(
                color: JsPalette.brand,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
        ),
        body: SafeArea(
          child: (pending.isEmpty && revision.isEmpty)
              ? const Center(
                  child: Text('対応が必要な報告はありません',
                      style: TextStyle(color: JsColors.silver, fontSize: 13)),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (pending.isNotEmpty) ...[
                      const _SectionLabel('承認待ち'),
                      ...pending.map((r) => PendingApprovalCard(
                            report: r,
                            onActionSuccess: () => _onActionSuccess(r),
                          )),
                    ],
                    if (revision.isNotEmpty) ...[
                      if (pending.isNotEmpty) const SizedBox(height: 8),
                      const _SectionLabel('差し戻し'),
                      ...revision.map((rev) {
                        // 本人判定は revision_inbox_screen.dart:134-135 と同一の式。
                        final isMine =
                            _myUserId != null && rev['user_id'] == _myUserId;
                        return RevisionCard(
                          revision: rev,
                          isMine: isMine,
                          onResubmit: () async {
                            if (!isMine) {
                              // 本人以外 → 読み取り専用の詳細（呼び出し元と同じ挙動）。
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: JsColors.gunmetal,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16)),
                                ),
                                builder: (_) => ReportDetailSheet(report: rev),
                              );
                              return;
                            }
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RevisionEditScreen(revision: rev),
                              ),
                            );
                            if (result == true) _onActionSuccess(rev);
                          },
                        );
                      }),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

// 区分の小見出し（新しい色は使わない）
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: const TextStyle(
                color: JsColors.silver,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      );
}
