// ============================================================
// lib/widgets/punch_remind_dialog.dart
//   打刻のお知らせ（punch_remind_in / punch_remind_out）からの2択ダイアログ。
//
//   ★型とトークンは home_screen.dart:2564-2608 の _openExtraDeclarationPicker と
//     :2666-2719 の _DeclarationChoiceRow を踏襲した「同型・別実装」。
//     home_screen.dart 側は1バイトも変更していない。_DeclarationChoiceRow は
//     同ファイル内 private のため他所からは使えないが、共通化のためのリネームは
//     6800行ファイルの呼出2箇所（:2577 / :2584）にも波及するため持ち込まない。
//
//   ★FCM経路（画面外＝context を持たない fcm_service）から呼ばれるため、
//     context は PunchRemindDialogNavigator（home_screen.dart）経由で
//     「生きている画面の State」から渡される。
//     navigatorKey.currentContext は使わない（当リポジトリに実績が無いため）。
//
//   ★無言で閉じる経路をゼロにする: 2択・閉じるボタン・全ての API 応答の
//     いずれを通っても必ず onNotify で1件表示される。barrierDismissible は
//     false（背景タップという「何も出ない出口」を塞ぐ）。
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/js_colors.dart';
import '../main.dart' show showJsSnackbar;
import '../services/reports_service.dart';
import '../services/work_mode_service.dart';

/// 打刻のお知らせ通知からの入口。
///   side      : 'in' | 'out'      （出勤側 / 退勤側）
///   shiftType : 'day' | 'night'
///   bizDate   : 'YYYY-MM-DD'（業務日。BE が申告APIの work_date として必須にしている）
///
/// ダイアログを出す前に最新の打刻状態を照会し、該当 side が既に打刻済みなら
/// ダイアログを出さずに「すでに記録されています。」だけを見せる。
Future<void> showPunchRemindFlow(
  BuildContext context, {
  required String side,
  required String shiftType,
  required String bizDate,
}) async {
  // 不正値はここで倒す（BE へ想定外の値を投げない＝work_mode_service の流儀。
  // punch(:285) / breakRequest(:333) / fetchToday(:251) と同じ扱い）。
  final s     = side      == 'out'   ? 'out'   : 'in';
  final shift = shiftType == 'night' ? 'night' : 'day';

  // work_date は BE 必須。通知に業務日が無いときに「今日」を推測して代わりに
  // 送ると、黙って別の日を申告してしまう。日付は補完せず、原因と次の行動を
  // 伝えて終える（袋小路にしない）。
  if (bizDate.isEmpty) {
    debugPrint('punch_remind: biz_date が空のため申告できません side=$s shift=$shift');
    showJsSnackbar(context, '対象日を特定できませんでした。事務へご連絡ください。',
        isError: true);
    return;
  }

  // ── 最新の打刻状態を照会（work_mode_service.dart:243-275）──
  final today = await WorkModeService.instance.fetchToday(shiftType: shift);
  if (!context.mounted) return;

  if (today != null) {
    final done = s == 'in' ? today.punchedIn : today.punchedOut;
    if (done) {
      showJsSnackbar(context, 'すでに記録されています。');
      return;
    }
  }

  // today == null は「取得できなかった」であって「打刻済み」ではない
  // （work_mode_service.dart:267 の非200 と :271 の例外がどちらも null）。
  // ここで抑止すると電波が悪いときに打刻漏れ申告そのものができない＝袋小路に
  // なるため、ダイアログは出す。確認できていないことは注記1行で見せる。
  // 二重申告になっても BE が 200 already_declared / 409 ALREADY_PUNCHED で弾く。
  final unknownState = today == null;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PunchRemindDialog(
      side:         s,
      shiftType:    shift,
      workDate:     bizDate,
      unknownState: unknownState,
      // 通知は「背後の画面」の context で出す。ダイアログ自身の context は
      // pop 後に無効になるため使わない（home_screen.dart:2625-2628 と同流儀）。
      onNotify: (message, isError) {
        if (!context.mounted) return;
        showJsSnackbar(context, message, isError: isError);
      },
    ),
  );
}

class _PunchRemindDialog extends StatefulWidget {
  const _PunchRemindDialog({
    required this.side,
    required this.shiftType,
    required this.workDate,
    required this.unknownState,
    required this.onNotify,
  });

  final String side;         // 'in' | 'out'
  final String shiftType;    // 'day' | 'night'
  final String workDate;     // 'YYYY-MM-DD'
  final bool   unknownState; // fetchToday が null だった＝打刻状態が不明
  final void Function(String message, bool isError) onNotify;

  @override
  State<_PunchRemindDialog> createState() => _PunchRemindDialogState();
}

class _PunchRemindDialogState extends State<_PunchRemindDialog> {
  // 多重送信ガード。home_screen.dart:2745 / :2754 の _ShortBreakSheetState と同型。
  bool _submitting = false;
  String? _error;   // ダイアログ内エラー（snackbar だけだと最前面に隠れるため両方に出す）

  bool get _isOut => widget.side == 'out';

  String get _shiftLabel => widget.shiftType == 'night' ? '🌙夜勤' : '☀日勤';

  // ── 打刻漏れの申告 ────────────────────────────────────────────
  Future<void> _declare() async {
    if (_submitting) return;
    setState(() { _error = null; _submitting = true; });
    final r = await WorkModeService.instance.declareForgotPunch(
      side:      widget.side,
      shiftType: widget.shiftType,
      workDate:  widget.workDate,
    );
    if (!mounted) return;
    if (r.ok) {
      // 201=受理 / 200=二度目。どちらも成功として閉じる（袋小路にしない）。
      Navigator.of(context).pop();
      widget.onNotify(
        r.alreadyDeclared
            ? 'すでに申告済みです。'
            : '打刻漏れを申告しました。事務が確認します。',
        false,
      );
      return;
    }
    // 409 ALREADY_PUNCHED は「もう記録されている」＝目的は満たされているので閉じる。
    if (r.statusCode == 409 && r.errorCode == 'ALREADY_PUNCHED') {
      Navigator.of(context).pop();
      widget.onNotify('すでに記録されています。', false);
      return;
    }
    _fail(_declareMessage(r.statusCode, r.errorCode));
  }

  // 非200の文言。判定は BE の statusCode + code だけで行い、FE で意味を作らない。
  String _declareMessage(int statusCode, String? code) {
    if (statusCode == 0) return '通信に失敗しました。';
    if (statusCode == 403 && code == 'ATTENDANCE_EMPLOYEE_ONLY') {
      return 'この機能は社員のみご利用いただけます。事務へご確認ください。';
    }
    if (statusCode == 400 && code == 'INVALID_WORK_DATE') {
      // ベル一覧に残った古いお知らせを開いた場合もここに来る。
      return '申告できる期間を過ぎています。事務へご連絡ください。';
    }
    // 400 その他（INVALID_SIDE / INVALID_SHIFT_TYPE）およびそれ以外の非200。
    return '申告を送信できませんでした。';
  }

  // ── 本日休みの登録（reports_service.dart:299 createRestDay を再利用）──────
  //   reason は指定しない・portion は既定の 'full'。
  //   rest_date はサーバが JST 業務日で確定するため FE からは送らない。
  Future<void> _restDay() async {
    if (_submitting) return;
    setState(() { _error = null; _submitting = true; });
    final res = await ReportsService().createRestDay();
    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.of(context).pop();
      widget.onNotify('本日休みを登録しました。', false);
      return;
    }
    final statusCode = res['statusCode'] as int?;
    // 409 ALREADY_RESTED は「もう休みで登録されている」＝目的は満たされている。
    if (statusCode == 409 && res['code'] == 'ALREADY_RESTED') {
      Navigator.of(context).pop();
      widget.onNotify('すでに休みで登録されています。', false);
      return;
    }
    // createRestDay は例外時に statusCode を積まない（reports_service.dart:323）。
    // ＝ statusCode 欠落は通信失敗として扱う。
    _fail(statusCode == null ? '通信に失敗しました。' : '本日休みを登録できませんでした。');
  }

  // ── 勤務継続中（APIは呼ばない）────────────────────────────────────
  //   選択の結果として「今どう扱われるか」と「次に取るべき行動」を返す。
  void _keepWorking() {
    if (_submitting) return;
    Navigator.of(context).pop();
    widget.onNotify('勤務中として扱います。退勤時に打刻してください。', false);
  }

  // ── 閉じる（何もしない・何も表示しない）──────────────────────────
  //   本人が閉じた操作に結果表示は不要（ダイアログが消えること自体が返事）。
  //   「無言で閉じる経路ゼロ」は失敗を隠さないための条項であり、本人の取消には
  //   適用しない。あとから申告できることは下部の※注記(:274-276)で示している。
  void _close() {
    if (_submitting) return;
    Navigator.of(context).pop();
  }

  // 失敗は非ブロック: ダイアログは開いたまま残し、理由をその場と snackbar の
  // 両方に出す（home_screen.dart:2775-2779 と同流儀）。
  void _fail(String msg) {
    setState(() { _submitting = false; _error = msg; });
    widget.onNotify(msg, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: JsFormTokens.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      // タイトルは FCM通知の title（BE services/punchRemind.js:32,39）と同一文言。
      // 同じ事実を2つの言い方で持たない（二重真実の禁止）。
      title: Text(
        _isOut ? '退勤の打刻が確認できません' : '出勤の打刻が確認できません',
        style: const TextStyle(color: JsFormTokens.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$_shiftLabel ${widget.workDate} 分',
                style: const TextStyle(
                    color: JsFormTokens.textMuted, fontSize: 11)),
            const SizedBox(height: 12),
            if (_isOut) ...[
              _PunchRemindChoiceRow(
                icon:  Icons.assignment_late_outlined,
                label: '打刻漏れ（退勤済み）',
                note:  '事務が確認して記録します',
                onTap: _submitting ? null : _declare,
              ),
              const SizedBox(height: 10),
              _PunchRemindChoiceRow(
                icon:  Icons.work_history_outlined,
                label: '勤務継続中',
                note:  'まだ勤務中（記録しません）',
                onTap: _submitting ? null : _keepWorking,
              ),
            ] else ...[
              _PunchRemindChoiceRow(
                icon:  Icons.assignment_late_outlined,
                label: '打刻漏れ（出勤済み）',
                note:  '事務が確認して記録します',
                onTap: _submitting ? null : _declare,
              ),
              const SizedBox(height: 10),
              _PunchRemindChoiceRow(
                icon:  Icons.hotel_outlined,
                label: '本日休み',
                note:  '本日は休みとして登録します',
                onTap: _submitting ? null : _restDay,
              ),
            ],
            if (widget.unknownState) ...[
              const SizedBox(height: 12),
              const Text('最新の打刻状態を確認できませんでした',
                  style: TextStyle(
                      color: JsFormTokens.accentAlert, fontSize: 11)),
            ],
            // 閉じても袋小路にならないことを示す常設の補足。
            // 上の注記と同じ体裁（fontSize 11）で、色だけ通常の補足色にする
            // （警告ではないため accentAlert は使わない）。
            const SizedBox(height: 12),
            const Text('※あとから通知一覧でも申告できます',
                style: TextStyle(
                    color: JsFormTokens.textMuted, fontSize: 11)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: JsColors.error, fontSize: 12)),
            ],
            if (_submitting) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                minHeight: 2,
                color: JsColors.accent,
                backgroundColor: Colors.transparent,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : _close,
          child: const Text('閉じる',
              style: TextStyle(color: JsFormTokens.textSub)),
        ),
      ],
    );
  }
}

// 2択の選択肢1行。暗枠1px・塗りなし。
// home_screen.dart:2666-2719 の _DeclarationChoiceRow と同型（トークン・寸法とも同じ）。
// 唯一の差: onTap を nullable にして送信中は押せなくしている（多重送信ガード）。
class _PunchRemindChoiceRow extends StatelessWidget {
  const _PunchRemindChoiceRow({
    required this.icon,
    required this.label,
    required this.note,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: JsFormTokens.chipBorder),
            ),
            child: Row(
              children: [
                Icon(icon, color: JsFormTokens.textSub, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: JsFormTokens.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(note,
                          style: const TextStyle(
                              color: JsFormTokens.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: JsFormTokens.textSub, size: 18),
              ],
            ),
          ),
        ),
      );
}
