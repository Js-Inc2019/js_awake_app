// lib/screens/pending_reports_screen.dart
// 「未送信日報」の画面（便BM・見本 claude/field_refused_today_mock_v1.html の ②・ボスの裁定【Q150】＝１）。
//
// ★何か：ホームの要対応の「未送信日報」の行（lib/screens/punch_screen.dart）から開く。今の人の未送信の日報（今日の分・
//   ほかの日の分・もう一方の勤務の分）と、読み込めない日報を並べる。行・「外す」・「今すぐ再送する」・※の字と形は、
//   送った後の画面の「未送信日報」と同じ部品（lib/widgets/pending_report_parts.dart）。
// ★並び：今日の分の行を上に、ほかの日の行をその下に（見本 ② の並び・どちらの中も箱の並び）。
// ★「外す」：今日の分の行には付けない（④ 案１＝会社が直せば届く日報を消さない・その日に届いた日報がほかに在る日は出し直す道が
//   無い恐れ＝見つけた事 (44)）。ほかの日の行は受け付けなかった行だけ・読み込めない日報の行は付ける（送った後の画面と同じ）。
// ★姿は ReportStore.instance.pendingView を聞く（届けば減り、0件で「未送信日報はありません」）。開いた時に1回読み直す
//   （refreshPendingCount・投げない）。読めなかった時は頭に※（前に読めた時の行は出したまま・「ありません」とは言わない）。
// ★外す・今すぐ再送の口は呼び手（lib/screens/home_screen.dart のシェル）が渡す＝送った後の画面と同じ口
//   （窓と知らせを2つに書き分けない）。
import 'package:flutter/material.dart';

import '../core/report_send_texts.dart';
import '../core/theme/field_tokens.dart';
import '../main.dart' show ReportStore;
import '../utils/pending_view.dart';
import '../widgets/pending_report_parts.dart';

class PendingReportsScreen extends StatefulWidget {
  const PendingReportsScreen({
    super.key,
    required this.shiftType,
    required this.onRemoveRow,
    required this.onRemoveUnreadable,
    required this.onRetry,
  });

  /// 今日の分を分ける勤務の種類（'day'|'night'・ホームの勤務区分＝シェルの _shiftType）。
  final String shiftType;

  /// 「外す」を押した時（確かめの窓と、外した後の知らせは呼び手が出す）。
  final Future<void> Function(PendingReportRow row) onRemoveRow;
  final Future<void> Function() onRemoveUnreadable;

  /// 「今すぐ再送する」を押した時（送り直しと、残りの数の知らせは呼び手が出す）。
  final Future<void> Function() onRetry;

  @override
  State<PendingReportsScreen> createState() => _PendingReportsScreenState();
}

class _PendingReportsScreenState extends State<PendingReportsScreen> {
  @override
  void initState() {
    super.initState();
    // 開いた時の箱の姿に合わせる（★投げない＝読めなかった時は readFailed が立ち、頭に※が出る）。
    ReportStore.instance.refreshPendingCount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(kPendingSectionLabel)),
      body: ValueListenableBuilder<PendingView>(
        valueListenable: ReportStore.instance.pendingView,
        builder: (_, view, __) {
          final now = DateTime.now();
          final today = pendingTodayRows(view, shiftType: widget.shiftType, now: now);
          final others = pendingOtherRows(view, shiftType: widget.shiftType, now: now);
          final todayIds = {for (final r in today) r.id};
          final rows = [...today, ...others];
          // 全部届いた・全部外した時（読めた時だけ＝読めなかった時に「ありません」と言わない）。
          if (rows.isEmpty && !view.hasUnreadable && !view.readFailed) return _emptyView();
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (view.readFailed) ...[
                    kPendingReadFailedNoteView,
                    const SizedBox(height: 12),
                  ],
                  ...pendingRowsSection(
                    rows: rows,
                    canRemove: (r) => r.refusedMessage != null && !todayIds.contains(r.id),
                    unreadableCount: view.unreadableRows,
                    unreadableUnknown: view.unreadableBoxes > 0,
                    onRemoveRow: widget.onRemoveRow,
                    onRemoveUnreadable: widget.onRemoveUnreadable,
                    // 「今すぐ再送する」は今の人の日報が1つでも在る時（1つだけ・読み込めない日報は送れない）。
                    retry: rows.isNotEmpty ? pendingRetryCard(() => widget.onRetry()) : null,
                    refusedNote: rows.any((r) => r.refusedMessage != null),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 前例＝差し戻しの画面の _emptyView（lib/screens/revision_inbox_screen.dart・絵と字の形も同じ）。
  Widget _emptyView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, color: FieldTokens.textSupport, size: 64),
          SizedBox(height: 16),
          Text(kPendingEmptyText,
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 16)),
        ],
      ),
    );
  }
}
