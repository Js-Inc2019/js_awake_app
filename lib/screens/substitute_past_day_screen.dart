// ============================================================
// lib/screens/substitute_past_day_screen.dart
//   振替に【過去の日】が入っていたときに、事前の取り決めを尋ねる画面（モックの A1・A2）。
//
// ★なぜ要るか: 本番 v609 で、過去の日を含む振替は「事前に会社と取り決めていた」の
//   答え（本文の prior_agreement: true）が無いと BE が断るようになった。
//   答える道が無いと、職人は「…取り決めていた場合に限り登録できます」で行き止まりになる。
//
// ★A1 と A2 は【1枚の画面の2つの姿】。別の画面にしない ─ 「取り決めていない」は
//   答えの続きであって別の用事ではなく、画面を積むと戻るの意味が2通りになる。
//
// ★どの日が過去かを端末で数えない。使うのは BE の 409
//   SUBSTITUTE_PRIOR_AGREEMENT_REQUIRED の本文に載った past_dates ただ1つ
//   （BE が数えた過去の日の配列・[休む日, 出勤する日] の順・'YYYY-MM-DD'）。
//   ここで「今日より前か」を数えると、今日の物差しが端末と BE の2箇所に並ぶ。
//   ★どちらのラベル（休む日／出勤する日）かは、登録しようとした2つの日と
//     突き合わせて決めるだけ（これは数えることではなく照合）。
//
// ★曜日も端末で数えない。候補の口が返した days[] の dow をそのまま使う
//   （2つの日は必ずその週の7日に入っている）。曜日の文字の並び kWeekdayJa は
//   このファイルが唯一の持ち主で、substitute_register_screen.dart の候補の行も
//   これを使う（写しを作らない）。
//
// 色は FieldTokens のみ（直書き禁止・新しい色を作らない）。
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import 'substitute_list_screen.dart' show jpMonthDay;

/// 曜日の文字の並び（0=日..6=土）。★このファイルが唯一の持ち主。
///   候補の口の dow をそのまま添字にする（端末で曜日を数え直さない）。
const List<String> kWeekdayJa = ['日', '月', '火', '水', '木', '金', '土'];

/// この画面が返す答え。★戻る（何も決めずに閉じる）は null。
enum SubstitutePastDayChoice {
  /// 「取り決めていた（登録する）」… 呼び手が prior_agreement: true で出し直す。
  agreed,
  /// 「代休で取る」… 呼び手が代休の流れを開く。
  compOff,
  /// 「日を選び直す」… 呼び手が選んだ日を消して登録の画面に残る。
  pickAnother,
}

/// A1 を開く。返り＝上の3つのどれか／戻るなら null。
///
/// [restDate]・[pairedWorkDate] 登録しようとした2つの日（'YYYY-MM-DD'）。
/// [pastDates] BE が数えた過去の日（409 の本文の past_dates をそのまま）。
/// [dowOf] 日付 → 曜日の添字（候補の口の days[] から呼び手が作る）。
Future<SubstitutePastDayChoice?> showSubstitutePastDay(
  BuildContext context, {
  required String restDate,
  required String pairedWorkDate,
  required List<String> pastDates,
  required Map<String, int> dowOf,
}) =>
    Navigator.of(context).push<SubstitutePastDayChoice>(MaterialPageRoute(
      builder: (_) => SubstitutePastDayScreen(
        restDate: restDate,
        pairedWorkDate: pairedWorkDate,
        pastDates: pastDates,
        dowOf: dowOf,
      ),
    ));

class SubstitutePastDayScreen extends StatefulWidget {
  const SubstitutePastDayScreen({
    super.key,
    required this.restDate,
    required this.pairedWorkDate,
    required this.pastDates,
    required this.dowOf,
  });

  final String restDate;
  final String pairedWorkDate;
  final List<String> pastDates;
  final Map<String, int> dowOf;

  @override
  State<SubstitutePastDayScreen> createState() =>
      _SubstitutePastDayScreenState();
}

class _SubstitutePastDayScreenState extends State<SubstitutePastDayScreen> {
  /// false=A1（尋ねる姿）／true=A2（振替にはできないと伝える姿）。
  bool _refused = false;

  // ── 日付の言葉 ──────────────────────────────────────────
  //   'YYYY-MM-DD' → 'M月D日（曜）'。★M月D日は jpMonthDay ただ1本。
  //     曜日は候補の口の dow だけを使い、分からなければ付けない（作らない）。
  String _dateText(String ymd) {
    final d = widget.dowOf[ymd];
    final dow = (d != null && d >= 0 && d < 7) ? '（${kWeekdayJa[d]}）' : '';
    return '${jpMonthDay(ymd)}$dow';
  }

  /// その日が「休む日」か「出勤する日」か。★登録しようとした2つの日との照合だけ。
  String _labelOf(String ymd) =>
      ymd == widget.restDate ? '休む日' : '出勤する日';

  // ── A1 の本文（日付だけ太字）────────────────────────────
  //   「{休む日 M月D日（曜）}と{出勤する日 M月D日（曜）}は過去の日です。…」
  //   ★並びは past_dates の並びそのまま（BE が [休む日, 出勤する日] の順で返す）。
  List<InlineSpan> _pastDatesSpans() {
    const bold = TextStyle(fontWeight: FontWeight.bold);
    final out = <InlineSpan>[];
    for (var i = 0; i < widget.pastDates.length; i += 1) {
      if (i > 0) out.add(const TextSpan(text: 'と'));
      final ymd = widget.pastDates[i];
      out.add(TextSpan(text: '${_labelOf(ymd)} '));
      out.add(TextSpan(text: _dateText(ymd), style: bold));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: FieldTokens.bgBase,
        appBar: AppBar(
          backgroundColor: FieldTokens.surfaceCard,
          foregroundColor: FieldTokens.textBody,
          elevation: 0,
          title: const Text('振替で休む'),
        ),
        // ★戻る（AppBar の矢印・端末の戻る）は何も返さずに閉じる＝呼び手は
        //   登録の画面にそのまま残る（null が「何も決めていない」の印）。
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: _refused ? _refusedBody() : _askBody(),
          ),
        ),
      );

  // ══════════ A1: 事前の取り決めを尋ねる ══════════════════════
  List<Widget> _askBody() => [
        _Frame(
          lineColor: FieldTokens.brand,
          heading: '過去の日が入っています',
          headingColor: FieldTokens.brand,
          body: Text.rich(
            TextSpan(
              style: const TextStyle(
                  color: FieldTokens.textBody, fontSize: 13, height: 1.6),
              children: [
                ..._pastDatesSpans(),
                const TextSpan(
                  text: 'は過去の日です。振替休日は前もって入れ替えるしくみのため、'
                      '事前に会社と取り決めていた場合に限り登録できます。',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 登録しようとしている2つの日（どちらが休む日かを取り違えないため）。
        _DateRow(label: '休む日', value: _dateText(widget.restDate)),
        const SizedBox(height: 6),
        _DateRow(label: '出勤する日', value: _dateText(widget.pairedWorkDate)),
        const SizedBox(height: 16),

        const Text('事前に会社と取り決めていましたか？',
            style: TextStyle(
                color: FieldTokens.textBody,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(SubstitutePastDayChoice.agreed),
            style: ElevatedButton.styleFrom(
              backgroundColor: FieldTokens.accent,
              foregroundColor: FieldTokens.onAccent,
              elevation: 0,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('取り決めていた（登録する）',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            // ★画面を積まずに【同じ画面の中で】A2 へ切り替える（上の★）。
            onPressed: () => setState(() => _refused = true),
            style: OutlinedButton.styleFrom(
              foregroundColor: FieldTokens.textBody,
              side: const BorderSide(color: FieldTokens.textBody, width: 1.5),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('取り決めていない',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),

        const SizedBox(height: 12),
        const Text('※答えは記録に残り、事務へ知らせます。', style: _note),
        const Text('※実際の取り扱いは、雇用契約書および就業規則の定めによります。',
            style: _note),
      ];

  // ══════════ A2: 振替にはできないと伝える ══════════════════
  List<Widget> _refusedBody() => [
        const _Frame(
          lineColor: FieldTokens.statusError,
          heading: '振替休日にはできません',
          headingColor: FieldTokens.statusError,
          body: Text.rich(
            TextSpan(
              style: TextStyle(
                  color: FieldTokens.textBody, fontSize: 13, height: 1.6),
              children: [
                TextSpan(text: '事前の取り決めが無い入れ替えは、振替休日になりません。'
                    '休日に働いた分は'),
                TextSpan(text: '代休', style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: 'で取れます。'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: () =>
                Navigator.of(context).pop(SubstitutePastDayChoice.compOff),
            style: OutlinedButton.styleFrom(
              foregroundColor: FieldTokens.textBody,
              side: const BorderSide(color: FieldTokens.textBody, width: 1.5),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('代休で取る',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44, // 押せる部品は 44pt 以上
          child: TextButton(
            onPressed: () =>
                Navigator.of(context).pop(SubstitutePastDayChoice.pickAnother),
            style: TextButton.styleFrom(minimumSize: Size.zero),
            child: const Text('日を選び直す',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
        ),

        const SizedBox(height: 12),
        const Text('※代休は、休日に働いた後に休むしくみです（賃金の扱いが振替と異なります）。',
            style: _note),
      ];
}

const TextStyle _note =
    TextStyle(color: FieldTokens.textSupport, fontSize: 12, height: 1.6);

/// 左に太い線を引いた枠（A1・A2 で色と中身だけ変えて使い回す）。
class _Frame extends StatelessWidget {
  const _Frame({
    required this.lineColor,
    required this.heading,
    required this.headingColor,
    required this.body,
  });
  final Color lineColor;
  final String heading;
  final Color headingColor;
  final Widget body;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: lineColor, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading,
                style: TextStyle(
                    color: headingColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            body,
          ],
        ),
      );
}

/// 「休む日 M月D日（曜）」の1行（登録の画面の休む日の箱と同じ地の色）。
class _DateRow extends StatelessWidget {
  const _DateRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(label,
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12)),
            ),
            Text(value,
                style: const TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
