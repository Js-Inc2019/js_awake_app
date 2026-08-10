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

import '../core/theme/field_tokens.dart';
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

  /// その日の休憩申告。空なら休憩セクションは見出しごと出さない。
  /// 1件の形は BE の SELECT 列（routes/attendance.js:1760-1765）そのまま。
  final List<Map<String, dynamic>> breakRequests;

  @override
  State<ApprovalDayScreen> createState() => _ApprovalDayScreenState();
}

class _ApprovalDayScreenState extends State<ApprovalDayScreen> {
  static const _week = ['日', '月', '火', '水', '木', '金', '土'];

  /// 画面内で保持する対象。承認/修正依頼の成功後はここから消して即時反映する。
  late List<Map<String, dynamic>> _reports = List.of(widget.reports);

  /// 画面内で保持する休憩申告。修正の成功後は分数だけを差し替えて即時反映する
  /// （申告制では行そのものは消えない＝承認制の「消して終わり」とは挙動が違う）。
  late List<Map<String, dynamic>> _breaks = List.of(widget.breakRequests);

  /// 休憩の修正中フラグ（多重タップ防止）。日報側のカードは自前で sending を持つため独立。
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

  // 休憩申告の修正。API は WorkModeService.amendBreakRequest（work_mode_service.dart:353）。
  // 申告制では「承認/却下」は無く、事実と違う申告を管理側が直す＝行は消えない。
  // 成功したら詳細ダイアログを閉じ → 手元の行の分数を更新して表示へ即反映する。
  // ★順序が重要: 先にダイアログを閉じないと、後続の pop がダイアログを閉じるだけになる。
  // ★一覧の再取得は呼び出し元が行う。この画面は戻り時に必ず PopScope(:295-300) が
  //   Navigator.pop(context, true) を投げ、ReviewTab がそれを受けて _load() し直す。
  Future<void> _amendBreak(Map<String, dynamic> req, int minutes,
      {BuildContext? dialogCtx}) async {
    if (_breakBusy) return;
    final id = req['id'] as String? ?? '';
    if (id.isEmpty) return;
    setState(() => _breakBusy = true);
    final res = await WorkModeService().amendBreakRequest(id, minutes);
    if (!mounted) return;
    setState(() => _breakBusy = false);
    if (res.ok) {
      if (dialogCtx != null && dialogCtx.mounted) Navigator.pop(dialogCtx);
      if (!mounted) return;
      showJsSnackbar(context, '休憩を$minutes分に修正しました');
      setState(() {
        _breaks = _breaks
            .map((b) => b['id'] == id
                ? {...b, 'break_override_min': minutes}
                : b)
            .toList();
      });
    } else {
      showJsSnackbar(
        context,
        res.errorMessage ?? '処理できませんでした（${res.statusCode}）',
        isError: true,
      );
    }
  }

  // 分チップの中央ダイアログ。決定した分数を返す（キャンセル/背景タップは null）。
  Future<int?> _pickBreakMinutes(BuildContext ctx, int current) {
    const presets = [0, 15, 30, 45, 60];
    int selected = presets.contains(current) ? current : presets.first;
    return showDialog<int>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          backgroundColor: FieldTokens.surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('休憩を修正',
              style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((m) {
                final on = selected == m;
                return GestureDetector(
                  onTap: () => setLocal(() => selected = m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: on ? FieldTokens.accent : FieldTokens.outline),
                    ),
                    child: Text('$m 分',
                        style: TextStyle(
                          color: on ? FieldTokens.accent : FieldTokens.textSupport,
                          fontSize: 13,
                          fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                        )),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('キャンセル',
                  style: TextStyle(color: FieldTokens.textSupport)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, selected),
              child: const Text('決定',
                  style: TextStyle(color: FieldTokens.accent)),
            ),
          ],
        ),
      ),
    );
  }

  // ── 一覧の行データ ───────────────────────────────────────────
  // 種別と元データだけを持つ。並びは現行踏襲: 承認待ち → 差し戻し → 休憩。
  // 0件の種別は要素が出ないため自然に消える（見出しを持たないので空セクションも出ない）。
  List<({String kind, Map<String, dynamic> data})> _entries() {
    final pending  = _reports.where(_isPending).toList();
    final revision = _reports.where(_isRevision).toList();
    return [
      ...pending .map((r) => (kind: 'pending',  data: r)),
      ...revision.map((r) => (kind: 'revision', data: r)),
      ..._breaks .map((b) => (kind: 'break',    data: b)),
    ];
  }

  // 氏名。日報は worker_name（home_screen.dart:3353 / monthly_history_screen.dart:315 と同じキー）、
  // 休憩は person_name（BE routes/attendance.js:1643 の `p.name AS person_name`）。
  // 空・欠落時の文言は既存の home_screen.dart:3353 に合わせる。
  static String _nameOf(String kind, Map<String, dynamic> m) {
    final raw = kind == 'break'
        ? (m['person_name'] as String? ?? '')
        : (m['worker_name'] as String? ?? '');
    return raw.trim().isEmpty ? '(氏名不明)' : raw.trim();
  }

  // 1行 = 左:氏名（主役） / 右:種別テキスト。カードは使わない。
  Widget _row(({String kind, Map<String, dynamic> data}) e) {
    final String label;
    final Color  labelColor;
    if (e.kind == 'pending') {
      label = '承認待ち';
      labelColor = FieldTokens.statusWarning;
    } else if (e.kind == 'revision') {
      label = '差戻し';
      labelColor = FieldTokens.statusError;
    } else {
      final min = e.data['break_override_min'] as int? ?? 0;
      label = '休憩 $min分';
      labelColor = FieldTokens.textSupport;
    }

    return InkWell(
      onTap: () => _openDetailDialog(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(_nameOf(e.kind, e.data),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: labelColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: FieldTokens.textSupport, size: 18),
          ],
        ),
      ),
    );
  }

  // ── 行タップで開く中央ダイアログ ──────────────────────────────
  // 中身は既存の PendingApprovalCard / RevisionCard / 休憩詳細をそのまま置く。
  // カード内部・判定式・API 呼び出し・確認ダイアログ（OriginConfirmDialog /
  // _SiteLinkGateDialog / RevisionReasonDialog）には一切触れていない。
  // それらはこのダイアログの上に重ねて開く（Flutter のネストで問題ない）。
  Future<void> _openDetailDialog(
      ({String kind, Map<String, dynamic> data}) e) async {
    final d = widget.date;
    final name = _nameOf(e.kind, e.data);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) => Dialog(
        backgroundColor: FieldTokens.surfaceCard,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 誰の・いつ の小見出し（どの人の詳細か迷わないため）
              Text('$name　${d.month}/${d.day}（${_week[d.weekday % 7]}）',
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12)),
              const SizedBox(height: 10),
              if (e.kind == 'pending')
                PendingApprovalCard(
                  report: e.data,
                  // 成功時: ダイアログを閉じてから行を除去（既存 _onActionSuccess を再利用）
                  onActionSuccess: () {
                    if (dctx.mounted) Navigator.pop(dctx);
                    _onActionSuccess(e.data);
                  },
                )
              else if (e.kind == 'revision')
                _revisionCardIn(dctx, e.data)
              else
                StatefulBuilder(
                  builder: (_, setLocal) => _BreakDeclarationCard(
                    request: e.data,
                    busy: _breakBusy,
                    onAmend: () async {
                      setLocal(() {});
                      final current =
                          e.data['break_override_min'] as int? ?? 0;
                      final picked = await _pickBreakMinutes(dctx, current);
                      if (picked == null || !dctx.mounted) return;
                      await _amendBreak(e.data, picked, dialogCtx: dctx);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 差し戻しカード。本人判定・再提出/閲覧の分岐は
  // revision_inbox_screen.dart:134-135 と同一の式で、旧実装から1文字も変えていない。
  Widget _revisionCardIn(BuildContext dctx, Map<String, dynamic> rev) {
    final isMine = _myUserId != null && rev['user_id'] == _myUserId;
    return RevisionCard(
      revision: rev,
      isMine: isMine,
      onResubmit: () async {
        if (!isMine) {
          // 本人以外 → 読み取り専用の詳細（呼び出し元と同じ挙動）。
          showModalBottomSheet(
            context: dctx,
            backgroundColor: FieldTokens.surfaceCard,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (_) => ReportDetailSheet(report: rev),
          );
          return;
        }
        final result = await Navigator.push(
          dctx,
          MaterialPageRoute(
            builder: (_) => RevisionEditScreen(revision: rev),
          ),
        );
        if (result == true) {
          if (dctx.mounted) Navigator.pop(dctx);
          _onActionSuccess(rev);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.date;
    final entries = _entries();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, true); // 戻るときは常に呼び出し元へ再読込を促す
      },
      child: Scaffold(
        backgroundColor: FieldTokens.bgBase,
        appBar: AppBar(
          backgroundColor: FieldTokens.bgBase,
          iconTheme: const IconThemeData(color: FieldTokens.brand),
          title: Text(
            '${d.month}月${d.day}日（${_week[d.weekday % 7]}）の報告',
            style: const TextStyle(
                color: FieldTokens.brand,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
        ),
        // 本体は「氏名の行リスト」。カード・塗り面は使わず、
        // 行間は1px区切り（FieldTokens.outline）＋余白のみ。
        body: SafeArea(
          child: entries.isEmpty
              ? const Center(
                  child: Text('対応が必要な報告はありません',
                      style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(
                      height: 1, thickness: 1, color: FieldTokens.outline),
                  itemBuilder: (_, i) => _row(entries[i]),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 休憩申告カード（この画面専用・日報カードには一切触れていない）
// ─────────────────────────────────────────────
// 申告制のため中身は「確認表示」＝氏名 / 申告◯分 / 理由 / 申告日時。
// 操作は「修正」1個だけ（承認・却下は BE から撤去済み＝出さない）。
// 様式は二次＝OutlinedButton（塗らない・枠と文字で示す）。
// ★minimumSize: Size(0, 44) を明示する。
//   app_theme.dart:62(elevatedButtonTheme) / :72(outlinedButtonTheme) が
//   minimumSize: Size(double.infinity, 52) を課しており、Row の非 flex 子は
//   「幅＝無限」を要求して画面外へ逃げる（OFFICE 側で実際に発生した罠）。
//   PendingApprovalCard は Expanded(:4987/:5077) で包んで回避しているが、
//   ここでは内容幅のボタンにしたいので明示的に戻す。
class _BreakDeclarationCard extends StatelessWidget {
  const _BreakDeclarationCard({
    required this.request,
    required this.busy,
    required this.onAmend,
  });

  final Map<String, dynamic> request;
  final bool busy;
  final VoidCallback onAmend;

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
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(
                  color: FieldTokens.textBody,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('申告休憩 $minutes分',
              style: const TextStyle(
                  color: FieldTokens.textBody,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('理由：$reason',
              style: const TextStyle(color: FieldTokens.textBody, fontSize: 13)),
          const SizedBox(height: 4),
          Text('申告日時：$reqAtStr',
              style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: busy ? null : onAmend,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  foregroundColor: FieldTokens.textBody,
                  side: const BorderSide(color: FieldTokens.outline),
                ),
                child: const Text('修正'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ★ 旧 _SectionLabel（区分の小見出し）は撤去した。
//   種別の表示は各行の右側テキスト（承認待ち / 差戻し / 休憩◯分・_row:216-241）が担うため、
//   見出しは二重の記号になる。0件の種別は行が出ないので空セクションも生じない。
