import 'package:flutter/material.dart';

import '../core/report_send_texts.dart';
import '../core/theme/field_tokens.dart';
import '../utils/business_date.dart';
import '../utils/pending_view.dart';
import '../widgets/pending_report_parts.dart';

// 報告完了ビュー（日報のフォームの全画面＝home_screen.dart の _pushReportForm の中で出る）。
//   （元の説明「日報タブ index1 を占有」は、フォームを全画面へ移す前の作り＝便BM で今の作りに合わせた・見つけた事 (43)）
// S5b: 縦詰まり・見切れ・スクロール不能・スライド/タップ混在を解消するため全面改修。
//  ・全体を SingleChildScrollView 化（小画面でも必ず最後まで届く）
//  ・操作は全てタップ式カードに統一（旧 _SlideBtn / 円形 GestureDetector は廃止）
// ※ 旧・全画面版 AfterReportScreen は S5b で削除（呼び手ゼロの死蔵クラスだった）。
//
// N4（完了ビュー縮小）:
//  ・「🚗 次の現場へ移動」カードを全モードで撤去（showMoveToNextSite / onMoveToNextSite ごと削除）
//  ・「☀/🌙 シフト切替」カードも撤去（showShiftContinue / onShiftContinue ごと削除）
//  ・残るアクションは「⏰ 追加の申告」と主ボタン「今日はここまで」の2つだけ
//  ★2件目の作成に入る導線はホーム(punch_screen)へ一本化した（N5）。完了ビューは
//    「締める」か「追加で申告する」かの2択に絞る＝入口を2箇所に分けない。
//    リセット処理そのものは home_screen 側に _resetForNextReport として温存してある。
//
// A案作り直し（カード撤去）:
//  ・丸バッジ(_Badge)を廃止＝頭はテキストのみ。事実は文字で言う
//  ・「今日はここまで」を主ボタンへ昇格し、見出し直下＝最上部エリアに置く
//    （旧・末尾の案内文『今日はここまでなら、そのまま閉じてOK』はこれに置換）
//  ・塗り面（α0.08）を全廃。枠は暗枠1px のみ。区切りは1px線＋余白
//  ・色は意味だけ: 未送信の警告 = FieldTokens.statusWarning。続行3行は単色（textBody/textSupport）
//    ＝ FieldTokens.foremanBase(紫) / FieldTokens.accent の装飾用途は撤去した
//
// 便BK（見本 claude/field_report_fix_mock_v3.html の ⑮⑯⑰②・ボスの裁定【Q143】【Q144】【Q145】＝１）:
//  ・頭の字と3行目は「今日の分」の日報だけで決める（呼び手が sent と refusedMessage を今日の分から渡す）。
//  ・ほかの日の未送信と読み込めない日報は、「続けて報告」の後に「未送信日報」として並べる（受け付けなかった行と
//    読み込めない日報の行だけ「外す」）。「今すぐ再送する」は1つだけ（今日の分が未送信なら頭の下・送れていれば下）。
//  ・未送信の箱を読めなかった時は、頭の下に※（kPendingReadFailedNote）。
class AfterReportBody extends StatefulWidget {
  const AfterReportBody({
    super.key,
    required this.workerName,
    required this.sent,
    required this.shiftType,
    required this.onOvertime,
    this.onRetry,
    this.onClose,
    this.refusedMessage,
    this.pendingReadFailed = false,
    this.otherRows = const <PendingReportRow>[],
    this.unreadableCount = 0,
    this.unreadableUnknown = false,
    this.onRemoveRow,
    this.onRemoveUnreadable,
    this.bizDate,
    this.showOvertime = true,
    this.closeBusy = false,
  });
  // N4: アクションは「⏰追加の申告」と「今日はここまで」の2つだけ＝出し分けの引数を持たない。
  //   （旧 showMoveToNextSite / showShiftContinue / onMoveToNextSite / onShiftContinue は撤去）
  //   →再（2026-10-21・便BN・下調べの (D3)(Y1)）: 出し分けの引数 showOvertime（またいで送った印の時は見出し「続けて報告」と
  //   ［追加の申告］を出さない）と、［今日はここまで］の回る印の closeBusy を足した（アクションは今も2つだけ）。
  final String workerName;
  final bool sent;                       // 頭の字（便BK: 今日の分の未送信の日報が無いか＝lib/utils/pending_view.dart の pendingTodayRows）
  final String shiftType;                // 'day'|'night'（ヘッダのサブ行 _headerSubtitle に使う）
  final Future<void> Function() onOvertime;
  // 「今すぐ再送」。（元）sent==false の時だけ（頭の下）。
  //   →再（2026-10-14・便BK・見本 v3 の ⑮）: 今日の分が送れていて、ほかの日に送れる日報が在る時も（「未送信日報」の中）。
  final VoidCallback? onRetry;
  final VoidCallback? onClose;           // 主ボタン「今日はここまで」＝この画面を閉じる
  // 送り先が受け付けなかった時の、送り先の答えの字（便BJ・見本 v2 の ⑬・ボスの裁定【Q142】）。null＝通信の字のまま。
  //   在れば、sent==false の時の3行目を「提出できません（…）」にし、その下に※の行を足す。
  //   →再（2026-10-14・便BK・見本 v3 の ⑮）: 今日の分の日報の中で最初の受け付けなかった字（呼び手が渡す）。
  final String? refusedMessage;
  // 未送信の箱を読めなかったか（便BK・見本 v3 の ⑰②）。true の時、頭の下に kPendingReadFailedNote を出す。
  final bool pendingReadFailed;
  // 今日の分でない、今の人の未送信の日報（箱の並び・便BK・見本 v3 の ⑮）。「未送信日報」に並べる。
  final List<PendingReportRow> otherRows;
  // 読み込めない日報（便BK・見本 v3 の ⑯）。unreadableCount＝読めない行の数・unreadableUnknown＝読めない箱の元の字が在る。
  final int unreadableCount;
  final bool unreadableUnknown;
  // 「外す」を押した時（確かめの窓と、外した後の知らせは呼び手＝home_screen.dart が出す）。null＝「外す」を出さない。
  final Future<void> Function(PendingReportRow row)? onRemoveRow;
  final Future<void> Function()? onRemoveUnreadable;
  // 頭の日付の業務日（便BN・下調べの (D3)・見つけた事 (48)）。呼び手（home_screen.dart）が「出している印」の業務日を渡す。
  //   null の時は今の業務日（businessDateForShift(shiftType, 今)＝元の決め方）。
  final String? bizDate;
  // ［⏰ 追加の申告］と、その見出し「続けて報告」を出すか（便BN・(D3)(48)）。またいで送った印の時は false
  //   （休憩の短縮の日も残業の日報の時刻も今の業務日に当たるため＝前の業務日の申告は、業務日が替わった後の今と同じ道しか無い）。
  final bool showOvertime;
  // ［今日はここまで］から退勤を打っている間か（便BN・見つけた事 (50)・【Q156】＝１・下調べの (Y1)）。true の間、［今日はここまで］は
  //   回る印で押せない（ホームの［退勤］の打つ間と同じ姿）。ほかのボタンは今のまま押せる。既定 false＝今の呼び手は1文字も変わらない。
  final bool closeBusy;

  @override
  State<AfterReportBody> createState() => _AfterReportBodyState();
}

class _AfterReportBodyState extends State<AfterReportBody> {
  // ヘッダのサブ行「🌙夜勤 7/22分を送信しました」。
  // 業務日は送信時と同じ物差し（businessDateForShift）で出す＝黙って日付を変えない。
  //   →再（2026-10-14・便BK・検分 a260 の N5）: 「☀日勤 M/D分」の組み方は lib/core/report_send_texts.dart の pendingRowTitle の
  //   1本（「未送信日報」の行の題と同じ・出る字は元と同じ）。
  //   →再（2026-10-21・便BN・(D3)）: 業務日は呼び手が渡した物（出している印の日）。渡さない時は今の業務日。
  String get _headerSubtitle =>
      '${pendingRowTitle(widget.shiftType, widget.bizDate ?? businessDateForShift(widget.shiftType, businessNow()))}を送信しました';

  bool get _hasUnreadable => widget.unreadableCount > 0 || widget.unreadableUnknown;

  // 「未送信日報」に並べる物が在るか。
  bool get _hasPendingSection => widget.otherRows.isNotEmpty || _hasUnreadable;

  // 送った後の画面の※（未送信の箱を読めなかった時・頭の下）。
  //   便BM: 字と形は「未送信日報」の画面の頭の※と1つ（lib/widgets/pending_report_parts.dart の kPendingReadFailedNoteView）。
  Widget get _readFailedNote => kPendingReadFailedNoteView;

  //   便BM: 「今すぐ再送する」のカードは「未送信日報」の画面と1つ（同じ本の pendingRetryCard）。
  Widget get _retryCard => pendingRetryCard(widget.onRetry);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 頭の表示は sent（下の →再）で出し分け ──
            //    （元）分岐条件・文言はA案でも1文字も変えていない。丸バッジだけを外した。
            //    →再（2026-10-14・便BJ）: sent は「今の人の未送信の数が 0 か」（見本 v1 の ①案A）。3行目は、送り先が
            //    受け付けなかった時だけ替わる（見本 v2 の ⑬・下の refusedMessage）。
            if (widget.sent) ...[
              const Text('報告完了',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: FieldTokens.textBody, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(_headerSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
              if (widget.pendingReadFailed) _readFailedNote,   // ⑰②（報告完了の時）
            ] else ...[
              const Text('未送信（再送待ち）',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: FieldTokens.textBody, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('${widget.workerName}さんの報告は保存されました',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
              const SizedBox(height: 10),
              // 元: いつも通信の字（送り先が受け付けなかった時も「通信状況により…」のままで、事実と違った）。
              // →再（2026-10-14・便BJ・見本 v2 の ⑬・【Q142】）: 受け付けなかった時だけ、送り先の答えの字と※を出す。
              //   →再（2026-10-14・便BK・検分 a260 の N6）: 頭の字は kPendingNetworkText から組む（「未送信日報」の行の字と1本・
              //   出る字は元と同じ）。
              if (widget.refusedMessage == null)
                const Text(
                  '$kPendingNetworkText。電波の良い場所で自動再送されます。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: FieldTokens.statusWarning, fontSize: 12),
                )
              else ...[
                Text(
                  refusedReportText(widget.refusedMessage!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FieldTokens.statusWarning, fontSize: 12),
                ),
                const SizedBox(height: 4),
                const Text(
                  kRefusedReportNote,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: FieldTokens.textSupport, fontSize: 12),
                ),
              ],
              if (widget.pendingReadFailed) _readFailedNote,   // ⑰②（未送信の時）
              const SizedBox(height: 12),
              // 再送は続行3行と同じ新様式。ただし文字/アイコンは warning のまま
              //（＝「まだ送れていない」という意味を色で持つ唯一の行）。機能は現行のまま。
              //   →再（2026-10-14・便BK・見本 v3 の ⑮）: 組み方は _retryCard の1本（「未送信日報」の中に出す時と同じ）。
              _retryCard,
            ],

            const SizedBox(height: 24),

            // ── 主ボタン「今日はここまで」（見出しブロック直下＝最上部エリア）──
            //    旧UIでは末尾の小さな案内文でしかなく、閉じる導線がAppBarの戻る矢印しか
            //    無かった。最も多い行動を最上部の主ボタンへ昇格する。
            _PrimaryOutlineButton(
              label: '今日はここまで',
              onTap: () => widget.onClose?.call(),
              busy: widget.closeBusy,
            ),

            // 便BN (D3)(48): またいで送った印の時は、区切りと「続けて報告」と［⏰ 追加の申告］を出さない（中身の無い見出しを残さない）。
            if (widget.showOvertime) ...[
            const SizedBox(height: 24),
            // 区切りは1px線＋余白のみ（カード・塗り面は使わない）
            const Divider(height: 1, thickness: 1, color: FieldTokens.outline),
            const SizedBox(height: 20),

            const Text('続けて報告',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
            const SizedBox(height: 12),

            // ⏰ 追加の申告（残業／休憩の短縮。ラッチなし＝何度でも申告できる）
            //    絵文字・アイコン・onTap（既存 onOvertime）は据え置き。呼び先の
            //    home_screen 側で種別を選ばせる1段を挟むだけ＝ここは入口の名前だけを変える。
            //    サブ行は既存3行で唯一2行に渡るため subtitleMaxLines: 2 を渡す
            //    （既定は 1 のまま＝下の2行の描画は1ピクセルも変わらない）。
            ReportActionCard(
              icon: Icons.more_time,
              title: '⏰  追加の申告',
              subtitle: '※残業や休憩の短縮を、あとから申告できます',
              subtitleMaxLines: 2,
              onTap: () => widget.onOvertime(),
            ),
            ],
            // N4: 「🚗 次の現場へ移動」「☀/🌙 シフト切替」の2カードは撤去した。
            //   2件目の作成に入る導線はホーム(punch_screen)へ一本化（N5）。

            // ── 未送信日報（便BK・見本 v3 の ⑮⑯）：ほかの日の未送信と、読み込めない日報 ──
            if (_hasPendingSection) ..._pendingSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _pendingSection() {
    final rows = widget.otherRows;
    final refused = rows.any((r) => r.refusedMessage != null);
    final known = rows.length + widget.unreadableCount;
    return [
      const SizedBox(height: 24),
      const Divider(height: 1, thickness: 1, color: FieldTokens.outline),
      const SizedBox(height: 20),
      // 見出し（字の形は「続けて報告」と同じ）＋件数。
      //   便BM: 未送信の箱を読めなかった時も「件数不明」（数の決まりは pendingCountLabel の1本＝ホームの要対応の行と同じ）。
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          const Text(kPendingSectionLabel,
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          const SizedBox(width: 8),
          Text(
              pendingSectionCountLabel(known,
                  unknown: widget.unreadableUnknown, readFailed: widget.pendingReadFailed),
              style: const TextStyle(
                  color: FieldTokens.statusWarning,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
      const SizedBox(height: 12),
      // 行・読み込めない日報の行・「今すぐ再送する」・※は、「未送信日報」の画面と同じ部品（便BM・lib/widgets/pending_report_parts.dart）。
      ...pendingRowsSection(
        rows: rows,
        // 「外す」は受け付けなかった行だけ（通信で送れていない行は、送り直しで届く）。
        canRemove: (r) => r.refusedMessage != null,
        unreadableCount: widget.unreadableCount,
        unreadableUnknown: widget.unreadableUnknown,
        onRemoveRow: widget.onRemoveRow,
        onRemoveUnreadable: widget.onRemoveUnreadable,
        // 「今すぐ再送する」は1つだけ：今日の分が送れていて、ほかの日に送れる日報（読み込めない物でない）が在る時はここ。
        retry: widget.sent && rows.isNotEmpty ? _retryCard : null,
        // 「※会社のご担当者にご確認ください。」は、頭の下に同じ※が出ている時（今日の分が受け付けられなかった時）は出さない
        //   （1つの画面に同じ字を2回出さない・検分 a260 の N2）。
        refusedNote: refused && (widget.sent || widget.refusedMessage == null),
      ),
    ];
  }
}

/// 「外す」を押した時の確かめの窓（便BK・見本 v3 の ⑮⑯）。形と色は「今日の報告を締めますか？」（home_screen.dart の
///   _onCloseToday）と同じ AlertDialog。本文は2つの段（line1＝「端末から外し、送信しません。」＋写真・line2＝出し直しの道）。
///   返り＝「外す」を押した時だけ true（「キャンセル」・外を押して閉じた時は false）。
Future<bool> confirmRemovePendingDialog(
  BuildContext context, {
  required String title,
  required String line1,
  required String line2,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: FieldTokens.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(title,
          style: const TextStyle(color: FieldTokens.textBody, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line1,
              style: const TextStyle(color: FieldTokens.textSupport, height: 1.6)),
          const SizedBox(height: 12),
          Text(line2,
              style: const TextStyle(color: FieldTokens.textSupport, height: 1.6)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('キャンセル',
              style: TextStyle(color: FieldTokens.textSupport)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(kRemovePendingLabel,
              style: TextStyle(color: FieldTokens.statusWarning)),
        ),
      ],
    ),
  );
  return ok == true;
}

// 主ボタン「今日はここまで」。生成り枠1.5px＋同色文字・塗りなし・高さ56・角丸10。
// 色は FieldTokens.textBody(#EAE3D0)。field_tokens.dart の同トークンの doc が
// 「生成り抜きボタンの枠1.5px＋文字にも使う」と明記しており、
// home_screen.dart が同じ width:1.5 で使っている既存様式に揃えた。
//   →再（2026-10-21・便BN・(Y1)）: busy の間は回る印で押せない（ホームの［退勤］の打つ間＝punch_screen.dart の _PunchPrimaryButton と
//   同じ姿＝枠は textFaint の 1.5・回る印 20×20・textFaint・太さ 2.5）。
class _PrimaryOutlineButton extends StatelessWidget {
  const _PrimaryOutlineButton({required this.label, required this.onTap, this.busy = false});
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: busy ? FieldTokens.textFaint : FieldTokens.textBody, width: 1.5),
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: FieldTokens.textFaint, strokeWidth: 2.5),
                    )
                  : Text(label,
                      style: const TextStyle(
                          color: FieldTokens.textBody,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      );
}
