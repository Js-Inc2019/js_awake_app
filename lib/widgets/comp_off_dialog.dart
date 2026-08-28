// lib/widgets/comp_off_dialog.dart
// 「代休を取る」を、候補を出す → 選ばせる → 取る まで1本に閉じた受け皿。
//
// ★なぜ1本にするか:
//   入口は2つある（「本日休み」の画面と、「管理・履歴」のカレンダーで選んだ日）。
//   同じ操作を入口ごとに書くと、片方だけ直したときに「ある入口では候補が全部出て、
//   別の入口では先頭が既定になっている」といった食い違いが生まれる。
//   選ばせる部品と書く口はここ【ただ1つ】にする。
//   （lib/widgets/closing_period_dialog.dart を1本にしたのと同じ理由）
//
// ★休む日はここで決めない。入口から受け取る（restDate）。
//   ・「本日休み」の画面 … その画面が持っている日（既定は今日・先の日も選べる）
//   ・カレンダー         … 人がタップして選んだ日
//   同じ日付を2箇所で決めると、画面に出ている日と実際に送る日がずれる。
//
// ★BE の契約（js-office-api の routes/rest_days.js）:
//   GET  /rest-days/comp-off/available?as_of=YYYY-MM-DD
//        → { as_of, remaining_days, candidates[], undecided_notice }
//        ・期限切れと残0は BE が候補から外して返す（取れないものを勧めない）
//        ・並びは出勤日の古い順。★この順は「全部出す」ための順であって、
//          先頭を既定として押しつけるためのものではない（掟1）。
//   POST /rest-days/comp-off
//        → 201 { rest_day, taken_days, allocations, notice? }
//        ・notice は「選ばない」で取ったときだけ付く（掟2）。画面で書き写さない。
//        ・断り方は 400/409 で code と人の言葉の error が返る。言い換えず出す。
//
// ★見た目は FIELD の家風だけを使う（他アプリの配色・部品は持ち込まない）:
//   ・候補を選ばせるダイアログ … home_screen.dart の _openExtraDeclarationPicker
//       （AlertDialog surfaceCard・角丸14・title は textBody 16px＋
//         枠線1px の行＝アイコン＋太字ラベル＋薄い補足＋右向き山括弧＋
//         actions は「閉じる」1つ）と、その行部品 _DeclarationChoiceRow が手本。
//       lib/widgets/closing_period_dialog.dart の _ClosingChoiceRow も同じ形を写している。
//   ・区分（終日/午前休/午後休）のチップ … rest_day_screen.dart の _kPortions の
//       ChoiceChip（surfaceCard/outlineStrong・showCheckmark なし・解除不可）が手本。
//   ・理由を出す形 … home_screen.dart の _failView（error_outline 32＋
//       statusWarning 13px）を、ダイアログの中身として使う。
//   色は FieldTokens のみ（Color(0x 直書き・Colors.* は使わない）。

// visibleForTesting は material が再輸出しているのでここでは別に取り込まない。
import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../services/reports_service.dart';

/// 検査から実物の流れ（候補→選ばせる→取る）を通すための差し替え口。
///   ★なぜ要るか: FIELD には provider のような注入の仕組みが無く、画面は
///     Service を直接 new する。そのため widget 検査で実 HTTP を避けられない
///     （test/share_send_confirm_test.dart の冒頭が「lib/ に注入口を作らない限り
///       widget テストで実HTTPを避けられない」と書いているのがこの制約）。
///     選ばせる部品はここ1本しか無いので、差し替え口もここ1つで足りる。
///   ★本番の値は ReportsService.new。検査だけが差し替え、tearDown で戻すこと。
@visibleForTesting
ReportsService Function() compOffServiceFactory = ReportsService.new;

/// 区分3値（既定=終日）。rest_day_screen.dart の _kPortions と同じ並び・同じラベル。
///   ★同じ語を2つの表で持たないため、値の対応（BEキー↔表示）はここでも
///     「BEキー → 日本語」の1方向だけにする。
const List<Map<String, String>> _kCompOffPortions = [
  {'key': 'full',    'label': '終日'},
  {'key': 'am_half', 'label': '午前休'},
  {'key': 'pm_half', 'label': '午後休'},
];

/// 候補が1件も無いときに出す事実と手掛かり。
///   ★BE の文言の写しではない。BE の一覧の口は「そもそも無い」と「期限切れで無い」を
///     区別せず、候補が空としか言わない（区別できるのは取ろうとしたときの code だけで、
///     その NO_COMP_OFF の文も両方を1文で言っている）。
///     区別できないものを区別したふりをしないため、ここは観測した事実
///     （この日に取れる代休が0件）と、期限という手掛かりだけを出す。
const String _kNoCompOffTitle = '取れる代休がありません';
const String _kNoCompOffBody  = '休日に出勤したぶんの代休が、この日には残っていません。\n'
    '（代休は期限を過ぎると取れなくなります）';

/// 代休を取る一連。取れたら true（呼び手は一覧を読み直す）。
///
/// [restDate] 休む日 'YYYY-MM-DD'。★入口が持つ値をそのまま渡すこと。
Future<bool> showCompOffFlow(BuildContext context, {required String restDate}) async {
  final svc = compOffServiceFactory();

  // ① 今取れる代休を引く。★as_of は休む日。今日ではない。
  //   「登録した日には期限内だが、休む日には切れている」を通してしまわないため
  //   （BE も休む日で判定する）。
  final avail = await svc.getCompOffAvailable(asOf: restDate);
  if (!context.mounted) return false;

  if (!avail.ok) {
    // 取得そのものが失敗。★黙って空にしない。BE の言い分をそのまま出す。
    await _showReason(context, '代休を確認できませんでした',
        avail.errorMessage ?? 'サーバーに接続できませんでした');
    return false;
  }

  final data = avail.data!;
  if (data.candidates.isEmpty) {
    await _showReason(context, _kNoCompOffTitle, _kNoCompOffBody);
    return false;
  }

  // ② 選ばせる。候補は全部出す（先頭を既定にしない・並べ替えない）。
  final picked = await _askCompOff(context, restDate: restDate, data: data);
  if (picked == null || !context.mounted) return false;   // 閉じる＝何もしない

  // ③ 取る。
  final res = await svc.takeCompOff(
    restDate: restDate,
    sourceWorkDate: picked.sourceWorkDate,   // 「選ばない」なら null
    undecided: picked.undecided,
    portion: picked.portion,
  );
  if (!context.mounted) return false;

  if (!res.ok) {
    // 期限切れ・残不足・同じ日に既に休み など。★BE の文言をそのまま出す。
    await _showReason(context, '代休を登録できませんでした',
        res.errorMessage ?? '登録に失敗しました');
    return false;
  }

  // ④ 「選ばない」で取ったときは BE が付けてきた注意をそのまま出す（掟2）。
  //   画面に文を書き写さない＝FIELD と OFFICE で別の文が出るのを防ぐ。
  final notice = res.data?.notice;
  await _showReason(
    context,
    '代休を登録しました',
    notice ?? '$restDate を代休として登録しました。',
    warning: false,
  );
  return true;
}

/// 選ばれた内容（対の出勤日 か 「選ばない」＋区分）。
class _CompOffChoice {
  const _CompOffChoice({this.sourceWorkDate, required this.undecided, required this.portion});
  final String? sourceWorkDate;
  final bool undecided;
  final String portion;
}

/// 候補を全部出して選ばせる。★見た目は _openExtraDeclarationPicker と同じ形。
Future<_CompOffChoice?> _askCompOff(
  BuildContext context, {
  required String restDate,
  required CompOffAvailable data,
}) {
  // 区分はダイアログの中で選べる（既定=終日）。★選んだ区分は行をタップした
  //   瞬間の値をそのまま使う＝「どの区分で取ったか」を2箇所で持たない。
  String portion = 'full';

  return showDialog<_CompOffChoice>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('代休で休む',
            style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // どの日を休むのかを必ず出す（入口が持っている日をそのまま見せる）。
                Text('$restDate を休みます',
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 12)),
                const SizedBox(height: 12),

                // 区分（rest_day_screen と同じチップ・解除不可）
                const Text('区分',
                    style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _kCompOffPortions.map((p) {
                    final selected = portion == p['key'];
                    return ChoiceChip(
                      label: Text(p['label']!),
                      selected: selected,
                      showCheckmark: false,
                      backgroundColor: FieldTokens.surfaceCard,
                      selectedColor: FieldTokens.outlineStrong,
                      side: BorderSide(
                          color: selected
                              ? FieldTokens.outlineStrong
                              : FieldTokens.outline),
                      labelStyle: TextStyle(
                        color: selected ? FieldTokens.textBody : FieldTokens.textSupport,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) => setLocal(() => portion = p['key']!),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // 対になる出勤日（掟1: 候補が複数なら全部出す・順番で勝手に決めない）
                Text('どの出勤日のぶんの代休かを選んでください（残り ${_days(data.remainingDays)}日）',
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 12)),
                const SizedBox(height: 10),
                for (final c in data.candidates) ...[
                  _CompOffChoiceRow(
                    icon: Icons.event_available_outlined,
                    label: '${c.sourceWorkDate} の出勤',
                    note: '残り ${_days(c.remainingDays)}日'
                        '${c.expiresAt != null ? ' ／ 期限 ${c.expiresAt}' : ''}',
                    onTap: () => Navigator.pop(
                        ctx,
                        _CompOffChoice(
                            sourceWorkDate: c.sourceWorkDate,
                            undecided: false,
                            portion: portion)),
                  ),
                  const SizedBox(height: 10),
                ],

                // 掟2: 「選択しない」も選べる。
                _CompOffChoiceRow(
                  icon: Icons.help_outline,
                  label: '選ばない',
                  note: 'どの出勤日のぶんかを決めずに休む',
                  onTap: () => Navigator.pop(
                      ctx,
                      _CompOffChoice(
                          sourceWorkDate: null, undecided: true, portion: portion)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
        ],
      ),
    ),
  );
}

/// 0.5 → '0.5' / 1.0 → '1' （小数が要らないときに .0 を出さない）
String _days(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// 理由を出す（閉じるまで消えない）。★流れて消えるスナックバーにしない。
///   ダイアログの流れの中で出すので、同じ形の AlertDialog を使う。
///   中身は home_screen.dart の _failView と同じ（error_outline＋statusWarning）。
Future<void> _showReason(BuildContext context, String title, String body,
    {bool warning = true}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: FieldTokens.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(title,
          style: const TextStyle(color: FieldTokens.textBody, fontSize: 16)),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warning ? Icons.error_outline : Icons.check_circle_outline,
              color: warning ? FieldTokens.statusWarning : FieldTokens.accent,
              size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(body,
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 13)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('閉じる',
              style: TextStyle(color: FieldTokens.textSupport)),
        ),
      ],
    ),
  );
}

/// 候補1行。home_screen の _DeclarationChoiceRow と同じ形
/// （枠線1px・塗りなし・最低56px・アイコン＋太字ラベル＋薄い補足＋山括弧）。
class _CompOffChoiceRow extends StatelessWidget {
  const _CompOffChoiceRow({
    required this.icon,
    required this.label,
    required this.note,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String note;
  final VoidCallback onTap;

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
              border: Border.all(color: FieldTokens.outline),
            ),
            child: Row(
              children: [
                Icon(icon, color: FieldTokens.textSupport, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: FieldTokens.textBody,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(note,
                          style: const TextStyle(
                              color: FieldTokens.textFaint, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: FieldTokens.textSupport, size: 18),
              ],
            ),
          ),
        ),
      );
}
