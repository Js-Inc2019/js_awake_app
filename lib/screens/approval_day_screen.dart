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
import '../main.dart' show showJsSnackbar;
import '../services/auth_service.dart';
import '../services/work_mode_service.dart';
import 'home_screen.dart' show PendingApprovalCard;
import 'revision_inbox_screen.dart' show RevisionCard, ReportDetailSheet;
import 'revision_edit_screen.dart';

class ApprovalDayScreen extends StatefulWidget {
  const ApprovalDayScreen({
    super.key,
    required this.date,
    required this.reports,
    this.breakRequests = const [],
  });

  /// 対象日
  final DateTime date;

  /// その日の対象レポート（承認待ち＋差し戻しの両方を含む）
  final List<Map<String, dynamic>> reports;

  /// その日の休憩申請（pending のみ）。空なら休憩セクションは見出しごと出さない。
  /// 1件の形は BE の SELECT 列（routes/attendance.js:1641-1643）そのまま。
  final List<Map<String, dynamic>> breakRequests;

  @override
  State<ApprovalDayScreen> createState() => _ApprovalDayScreenState();
}

class _ApprovalDayScreenState extends State<ApprovalDayScreen> {
  static const _week = ['日', '月', '火', '水', '木', '金', '土'];

  /// 画面内で保持する対象。承認/修正依頼の成功後はここから消して即時反映する。
  late List<Map<String, dynamic>> _reports = List.of(widget.reports);

  /// 画面内で保持する休憩申請。承認/却下の成功後はここから消して即時反映する
  /// （日報側 _reports:42 と同じ流儀）。
  late List<Map<String, dynamic>> _breaks = List.of(widget.breakRequests);

  /// 休憩の決裁中フラグ（多重タップ防止）。日報側のカードは自前で sending を持つため独立。
  bool _breakBusy = false;

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
    if (_reports.isEmpty && _breaks.isEmpty && mounted) {
      Navigator.pop(context, true); // true = 呼び出し元は再読込する
    }
  }

  // 休憩申請の決裁。API は WorkModeService（work_mode_service.dart:328/347/352）。
  // 成功したらその場でカードを消し、日報と休憩が両方空になったら画面を閉じる。
  Future<void> _decideBreak(Map<String, dynamic> req, bool approve) async {
    if (_breakBusy) return;
    final id = req['id'] as String? ?? '';
    if (id.isEmpty) return;
    setState(() => _breakBusy = true);
    final svc = WorkModeService.instance;
    final res = approve
        ? await svc.approveBreakRequest(id)
        : await svc.rejectBreakRequest(id);
    if (!mounted) return;
    setState(() => _breakBusy = false);
    if (res.ok) {
      showJsSnackbar(context, approve ? '休憩申請を承認しました' : '休憩申請を却下しました');
      setState(() {
        _breaks = _breaks.where((b) => b['id'] != id).toList();
      });
      if (_reports.isEmpty && _breaks.isEmpty && mounted) {
        Navigator.pop(context, true);
      }
    } else {
      showJsSnackbar(
        context,
        res.errorMessage ?? '処理できませんでした（${res.statusCode}）',
        isError: true,
      );
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
          child: (pending.isEmpty && revision.isEmpty && _breaks.isEmpty)
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
                    // ── 休憩申請（0件なら見出しごと出さない）──
                    if (_breaks.isNotEmpty) ...[
                      if (pending.isNotEmpty || revision.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        // 区切りは1px線のみ（新しい色は使わない）
                        const Divider(
                            height: 1, thickness: 1, color: JsColors.divider),
                        const SizedBox(height: 16),
                      ],
                      const _SectionLabel('休憩申請'),
                      ..._breaks.map((b) => _BreakApprovalCard(
                            request: b,
                            busy: _breakBusy,
                            onApprove: () => _decideBreak(b, true),
                            onReject:  () => _decideBreak(b, false),
                          )),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 休憩申請カード（この画面専用・日報カードには一切触れていない）
// ─────────────────────────────────────────────
// 色は既存トークンのみ:
//   承認 = JsColors.success 塗り + JsPalette.onAccent 文字
//        （PendingApprovalCard の「承認」home_screen.dart:5070-5073 と同一様式）
//   却下 = JsColors.error の枠+文字（塗らない＝主従を色と枠で示す）
// ★minimumSize: Size(0, 44) を両方に明示する。
//   app_theme.dart:62(elevatedButtonTheme) / :72(outlinedButtonTheme) が
//   minimumSize: Size(double.infinity, 52) を課しており、Row の非 flex 子は
//   「幅＝無限」を要求して画面外へ逃げる（OFFICE 側で実際に発生した罠）。
//   PendingApprovalCard は Expanded(:4987/:5077) で包んで回避しているが、
//   ここでは内容幅のボタンにしたいので明示的に戻す。
class _BreakApprovalCard extends StatelessWidget {
  const _BreakApprovalCard({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final name    = request['person_name']           as String? ?? '不明';
    final minutes = request['break_override_min']    as int?    ?? 0;
    final reason  = request['break_override_reason'] as String? ?? '';
    final reqAt   = request['break_override_req_at'] as String? ?? '';
    final reqAtStr = reqAt.length >= 16
        ? reqAt.substring(0, 16).replaceFirst('T', ' ')
        : reqAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(
                  color: JsColors.offWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('申請休憩 $minutes分',
              style: const TextStyle(
                  color: JsColors.offWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('理由：$reason',
              style: const TextStyle(color: JsColors.offWhite, fontSize: 13)),
          const SizedBox(height: 4),
          Text(reqAtStr,
              style: const TextStyle(color: JsColors.silver, fontSize: 11)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: busy ? null : onReject,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  foregroundColor: JsColors.error,
                  side: const BorderSide(color: JsColors.error),
                ),
                child: const Text('却下'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: busy ? null : onApprove,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  backgroundColor: JsColors.success,
                  foregroundColor: JsPalette.onAccent,
                ),
                child: const Text('承認'),
              ),
            ],
          ),
        ],
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
