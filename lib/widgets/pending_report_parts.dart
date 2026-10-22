// lib/widgets/pending_report_parts.dart
// 「未送信日報」の行の部品（便BM・見本 claude/field_refused_today_mock_v1.html の ②・ボスの裁定【Q150】＝１）。
//
// ★何か：送った後の画面（lib/screens/after_report_screen.dart）の「未送信日報」と、ホームの要対応から開く「未送信日報」の画面
//   （lib/screens/pending_reports_screen.dart）が、同じ部品で行・「外す」・「今すぐ再送する」・※を出す。
// ★なぜ：同じ字と形を2つの画面に書き分けると、片方だけ直した時に割れる（便BJ の report_send_texts.dart と同じ考え）。
//   便BK で送った後の画面の中に作った行（_PendingRow）とカード（_ActionCard）を、形を変えずにここへ移した。
// ★通信しない・端末の保存を読まない（並べる物は呼び手が渡す）。
import 'package:flutter/material.dart';

import '../core/report_send_texts.dart';
import '../core/theme/field_tokens.dart';
import '../utils/pending_view.dart';

/// 未送信の箱を読めなかった時の※（送った後の画面の頭の下・「未送信日報」の画面の頭・字と形は1つ）。
const Widget kPendingReadFailedNoteView = Padding(
  padding: EdgeInsets.only(top: 6),
  child: Text(kPendingReadFailedNote,
      textAlign: TextAlign.center,
      style: TextStyle(color: FieldTokens.statusWarning, fontSize: 11.5)),
);

/// 窓の本文の下の同じ※（便BN・見つけた事 (46)・【Q155】＝１・見本 claude/field_read_failed_windows_mock_v1.html）。
///   字・色・大きさ・上の 6 は kPendingReadFailedNoteView と同じ。窓の本文が左寄せなので※も左寄せ。
///   使う窓＝2件目の窓（lib/screens/home_screen.dart の _confirmSecondReportIfNeeded）と本日休みの窓（lib/screens/punch_screen.dart の
///   _restDayGuard）。
const Widget kPendingReadFailedNoteDialogView = Padding(
  padding: EdgeInsets.only(top: 6),
  child: Text(kPendingReadFailedNote,
      textAlign: TextAlign.start,
      style: TextStyle(color: FieldTokens.statusWarning, fontSize: 11.5)),
);

/// 「今すぐ再送する」のカード（意味の色＝FieldTokens.statusWarning・字と形は1つ）。
Widget pendingRetryCard(VoidCallback? onRetry) => ReportActionCard(
      icon: Icons.refresh,
      title: '今すぐ再送する',
      subtitle: '保存済みの報告をもう一度送信',
      accent: FieldTokens.statusWarning,
      onTap: () => onRetry?.call(),
    );

/// 「未送信日報」の行の並び（行・読み込めない日報の行・「今すぐ再送する」・※）。
///   rows＝並べる今の人の日報（呼び手の並び）・canRemove＝その行が外せるか（受け付けなかった行で、今日の分でない物＝呼び手が決める）。
///   「外す」は canRemove が true で onRemoveRow が在る行だけ（読み込めない日報の行は onRemoveUnreadable が在る時）。
///   retry＝「今すぐ再送する」（null＝出さない）・refusedNote＝「※会社のご担当者にご確認ください。」を出すか（呼び手が決める）。
///   ※の並び：会社の※（refusedNote）→ 外した※（外せる行が在る時）→ 読み込めない※（読み込めない日報が在る時）。
List<Widget> pendingRowsSection({
  required List<PendingReportRow> rows,
  required bool Function(PendingReportRow r) canRemove,
  required int unreadableCount,
  required bool unreadableUnknown,
  Future<void> Function(PendingReportRow row)? onRemoveRow,
  Future<void> Function()? onRemoveUnreadable,
  Widget? retry,
  required bool refusedNote,
}) {
  final hasUnreadable = unreadableCount > 0 || unreadableUnknown;
  final removable = rows.any(canRemove);
  return [
    for (final r in rows) ...[
      PendingRowCard(
        title: pendingRowTitle(r.shiftType, r.businessDate),
        subtitle: r.refusedMessage != null
            ? refusedReportText(r.refusedMessage!)
            : kPendingNetworkText,
        subtitleColor: FieldTokens.statusWarning,
        // 「外す」は外せる行だけ（通信で送れていない行は、送り直しで届く・今日の分は外さない＝【Q150】の ④ 案１）。
        onRemove: canRemove(r) && onRemoveRow != null ? () => onRemoveRow(r) : null,
      ),
      const SizedBox(height: 8),
    ],
    if (hasUnreadable) ...[
      PendingRowCard(
        title: unreadableRowTitle(unreadableCount, unknown: unreadableUnknown),
        subtitle: kUnreadableRowText,
        subtitleColor: FieldTokens.textSupport,
        onRemove: onRemoveUnreadable,
      ),
      const SizedBox(height: 8),
    ],
    if (retry != null) ...[
      retry,
      const SizedBox(height: 8),
    ],
    // ※は枠の外（textSupport・11.5）。
    if (refusedNote) ...[
      const SizedBox(height: 4),
      const Text(kRefusedReportNote,
          style: TextStyle(color: FieldTokens.textSupport, fontSize: 11.5)),
    ],
    if (removable) ...[
      const SizedBox(height: 2),
      const Text(kRemovedReportNote,
          style: TextStyle(color: FieldTokens.textSupport, fontSize: 11.5)),
    ],
    if (hasUnreadable) ...[
      SizedBox(height: refusedNote || removable ? 2 : 4),
      const Text(kUnreadableReportNote,
          style: TextStyle(color: FieldTokens.textSupport, fontSize: 11.5)),
    ],
  ];
}

// 「未送信日報」の1行（便BK・見本 v3 の ⑮⑯）。枠は暗枠1px（ReportActionCard と同じ）・題 14 太字・下の字 11。
//   「外す」は高さ 44・幅 64 以上（触れる大きさの決まり）・枠 textSupport 1px・字 textBody 13 太字。onRemove＝null なら出さない。
//   便BM: 送った後の画面の中の _PendingRow を、形を変えずにここへ移した。
class PendingRowCard extends StatelessWidget {
  const PendingRowCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    this.onRemove,
  });
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FieldTokens.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: FieldTokens.textBody,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: subtitleColor, fontSize: 11)),
              ],
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: onRemove,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: FieldTokens.textBody,
                side: const BorderSide(color: FieldTokens.textSupport),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              child: const Text(kRemovePendingLabel),
            ),
          ],
        ],
      ),
    );
  }
}

// 次の行動の1行。A案で塗り面（旧: 背景α0.08 + 枠α0.4 + 行ごとの色）を撤去した。
//   ・面は透明。枠は暗枠1px = FieldTokens.outline(= FieldTokens.outline #2E333A)
//     ＝ home_screen.dart の二次様式 _StepBackButton と同一トークン
//   ・アイコン/サブ/シェブロンは単色 FieldTokens.textSupport、タイトルのみ FieldTokens.textBody
//   ・accent は「未送信の再送行」だけが渡す意味色。null のときは単色に落ちる。
//   便BM: 送った後の画面の中の _ActionCard を、形を変えずにここへ移した（「未送信日報」の画面の「今すぐ再送する」も同じカード）。
class ReportActionCard extends StatelessWidget {
  const ReportActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent,
    this.subtitleMaxLines = 1,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? accent;
  // サブ行の行数。既定 1 ＝従来の描画そのまま（再送の行は不変）。
  // 「追加の申告」行だけが 2 を渡す＝長い注記が見切れるのを防ぐ。
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    // 単色統一。accent が来た行だけ意味色（warning）で塗り分ける。
    final sub   = accent ?? FieldTokens.textSupport;
    final head  = accent ?? FieldTokens.textBody;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,                                   // 行全面がタップ領域
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            // 塗り面なし（透明）。枠のみで領域を示す。
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: FieldTokens.outline),
          ),
          child: Row(
            children: [
              Icon(icon, color: sub, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: head,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: subtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: sub, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: sub, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
