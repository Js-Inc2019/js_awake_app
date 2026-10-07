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
// →再（2026-10-07・便F8）: このファイルには、もう1枚の画面（3択の画面・見本 field_substitute_past_mock_v5
//   の B1・showWorkDateNoReport）と、A1・A2 から公開にした部品（PastDayFrame・PastDayDateRow・kPastDayNote・
//   ボタン3種）も在る。3択の画面は下の「3択の画面」の★を見ること。A1・A2 の字・色・並び・動きは変えていない。
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
import '../services/reports_service.dart';
// ★便F8: 尋ねる口の答えの読み方と「聞けなかった時」の出し方は、カレンダーの箱の入口と同じ1つ。
import '../widgets/day_request_entry.dart'
    show
        DayRequestEligibility,
        DayRequestEligibilityKind,
        DayRequestTrouble,
        readDayRequestEligibility;
import 'day_request_screen.dart' show DayRequestKind, DayRequestScreen;
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
        PastDayFrame(
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
        PastDayDateRow(label: '休む日', value: _dateText(widget.restDate)),
        const SizedBox(height: 6),
        PastDayDateRow(label: '出勤する日', value: _dateText(widget.pairedWorkDate)),
        const SizedBox(height: 16),

        const Text('事前に会社と取り決めていましたか？',
            style: TextStyle(
                color: FieldTokens.textBody,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        pastDayFilledButton('取り決めていた（登録する）',
            onPressed: () =>
                Navigator.of(context).pop(SubstitutePastDayChoice.agreed)),
        const SizedBox(height: 8),
        // ★画面を積まずに【同じ画面の中で】A2 へ切り替える（上の★）。
        pastDayOutlinedButton('取り決めていない',
            onPressed: () => setState(() => _refused = true)),

        const SizedBox(height: 12),
        const Text('※答えは記録に残り、事務へ知らせます。', style: kPastDayNote),
        const Text('※実際の取り扱いは、雇用契約書および就業規則の定めによります。',
            style: kPastDayNote),
      ];

  // ══════════ A2: 振替にはできないと伝える ══════════════════
  List<Widget> _refusedBody() => [
        const PastDayFrame(
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

        pastDayOutlinedButton('代休で取る',
            onPressed: () =>
                Navigator.of(context).pop(SubstitutePastDayChoice.compOff)),
        const SizedBox(height: 8),
        pastDayTextButton('日を選び直す',
            onPressed: () =>
                Navigator.of(context).pop(SubstitutePastDayChoice.pickAnother)),

        const SizedBox(height: 12),
        const Text('※代休は、休日に働いた後に休むしくみです（賃金の扱いが振替と異なります）。',
            style: kPastDayNote),
      ];
}

/// ※の字の形（A1・A2 の※）。
///   →再（2026-10-07・便F8）: 名前を公開にした（元 _note・値は1つも変えていない）。3択の画面・依頼と申告の
///   画面（lib/screens/day_request_screen.dart）・カレンダーの箱の入口（lib/widgets/day_request_entry.dart）の
///   ※も、この1つを使う（写しを作らない）。
const TextStyle kPastDayNote =
    TextStyle(color: FieldTokens.textSupport, fontSize: 12, height: 1.6);

/// 枠の中の本文の字の形（A1・A2 の本文と同じ値＝本文色 13・行の高さ 1.6）。
///   ★便F8 で足した。使うのは便F8 の枠（3択の画面と、カレンダーの箱の入口）だけ。
///     A1・A2 の本文は今のまま（その場に書いた字の形を1つも変えない）。
const TextStyle kPastDayFrameBody =
    TextStyle(color: FieldTokens.textBody, fontSize: 13, height: 1.6);

/// 左に太い線を引いた枠（A1・A2 で色と中身だけ変えて使い回す）。
///   →再（2026-10-07・便F8）: 名前を公開にした（元 _Frame）。見出し（heading・headingColor）を任意にした。
///   見出しが無い枠は、見出しの行とその下の 8 の間を出さない（3択の画面の出せない日＝見本 G2 と同じ形）。
///   見出しの在る枠（A1・A2・3択の出せる日・箱の入口の出せない日）は、今と1ピクセルも同じ。
class PastDayFrame extends StatelessWidget {
  const PastDayFrame({
    super.key,
    required this.lineColor,
    this.heading,
    this.headingColor,
    required this.body,
  });
  final Color lineColor;
  final String? heading;
  final Color? headingColor;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final h = heading;
    return Container(
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
          if (h != null) ...[
            Text(h,
                style: TextStyle(
                    // ★見出しの色は呼び手が渡す（今の2つの姿と同じ）。渡されなければ線の色。
                    color: headingColor ?? lineColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
          ],
          body,
        ],
      ),
    );
  }
}

/// 「休む日 M月D日（曜）」の1行（登録の画面の休む日の箱と同じ地の色）。
///   →再（2026-10-07・便F8）: 名前を公開にした（元 _DateRow・見た目は1つも変えていない）。
///   依頼と申告の画面の「対象の日」の箱もこれを使う（色も今のまま＝休日の色は付けない）。
class PastDayDateRow extends StatelessWidget {
  const PastDayDateRow({super.key, required this.label, required this.value});
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

// ── ボタン3種（便F8 で関数へ出した）──────────────────────────────
//   （元）A1・A2 の画面の中に直に書いてあった（塗りのボタン・枠のボタン・字のボタン）。
//   →再（2026-10-07・便F8）: 値を1つも変えずに、この3つの公開の関数へ出した。A1・A2・3択の画面・
//   依頼と申告の画面（lib/screens/day_request_screen.dart）が同じ物を使う（値の写しを作らない）。
//   ★onPressed が null なら押せない（塗りのボタンは、依頼と申告の画面で理由が空の間と送っている間）。

/// 高さ48の塗りのボタン（accent の塗り・角丸12・字15の太字）。
Widget pastDayFilledButton(String label, {required VoidCallback? onPressed}) =>
    SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: FieldTokens.accent,
          foregroundColor: FieldTokens.onAccent,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );

/// 高さ48の枠のボタン（本文色 1.5 の枠・角丸12・字15の太字）。
Widget pastDayOutlinedButton(String label, {required VoidCallback? onPressed}) =>
    SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: FieldTokens.textBody,
          side: const BorderSide(color: FieldTokens.textBody, width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );

/// 高さ44の字のボタン（補足の色）。押せる部品は 44pt 以上。
Widget pastDayTextButton(String label, {required VoidCallback? onPressed}) =>
    SizedBox(
      height: 44, // 押せる部品は 44pt 以上
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(minimumSize: Size.zero),
        child: Text(label,
            style: const TextStyle(color: FieldTokens.textSupport)),
      ),
    );

// ════════════════════════════════════════════════════════════
// 3択の画面（便F8・見本 field_substitute_past_mock_v5 の B1・ボス裁定【Q89】）
//
// ★登録の画面（substitute_register_screen.dart）の候補で、BE が reason_code に no_report
//   （「この日の日報がありません」）を付けた行を押すと開く。過去の日か・会社の休みの日かを
//   端末で数えない（BE が no_report を付けた行だけが入口）。
// ★開いたら尋ねる口に type=attendance_fix とその日で1回だけ聞き、答えを3つに分ける
//   （分け方は lib/widgets/day_request_entry.dart の readDayRequestEligibility ただ1本＝
//   カレンダーの箱の入口と同じ物を呼ぶ）。
//   ・出せる日 … 見出しの在る枠＋「出勤の修正を依頼する」「代休で取る」「日を選び直す」
//   ・出せない日 … 見出しの無い枠に BE の文だけ＋「代休で取る」「日を選び直す」
//     （押せるのに断られるボタン「出勤の修正を依頼する」は置かない）
//   ・聞けなかった時 … 理由＋「もう一度」（3つのボタンは出さない＝戻る矢印で登録の画面へ戻れる）
// ★答えを返すだけ。代休の受け皿（showCompOffFlow）を呼ぶのは登録の画面の1か所のまま
//   （事前の取り決めの画面の「代休で取る」と同じ1つの道へ寄せる）。
// ════════════════════════════════════════════════════════════

/// 3択の画面が返す答え。★戻る（何も決めずに閉じる）は null。
enum WorkDateNoReportChoice {
  /// 出勤の修正依頼を送れた … 呼び手は候補を引き直す。
  requested,
  /// 「代休で取る」… 呼び手が代休の流れを開く。
  compOff,
  /// 「日を選び直す」… 呼び手が選んだ日を消して登録の画面に残る。
  pickAnother,
}

/// 3択の画面を開く。返り＝上の3つのどれか／戻るなら null。
///
/// [workDate] 押した行の日（'YYYY-MM-DD'・休む日ではない）。
/// [dateText] その日の「M月D日（曜）」（曜日は候補の口の dow・呼び手が字で渡す）。
/// [permitUntilText] 依頼の画面の※の期限「M月D日（曜）」（候補の口の days[] の最後の日・呼び手が字で渡す）。
/// [service] 口の差し替え（検査だけが渡す）。既定は null＝ReportsService()。
Future<WorkDateNoReportChoice?> showWorkDateNoReport(
  BuildContext context, {
  required String workDate,
  required String dateText,
  required String permitUntilText,
  ReportsService? service,
}) =>
    Navigator.of(context).push<WorkDateNoReportChoice>(MaterialPageRoute(
      builder: (_) => WorkDateNoReportScreen(
        workDate: workDate,
        dateText: dateText,
        permitUntilText: permitUntilText,
        service: service,
      ),
    ));

class WorkDateNoReportScreen extends StatefulWidget {
  const WorkDateNoReportScreen({
    super.key,
    required this.workDate,
    required this.dateText,
    required this.permitUntilText,
    this.service,
  });

  final String workDate;
  final String dateText;
  final String permitUntilText;
  final ReportsService? service;

  @override
  State<WorkDateNoReportScreen> createState() => _WorkDateNoReportScreenState();
}

class _WorkDateNoReportScreenState extends State<WorkDateNoReportScreen> {
  late final ReportsService _api = widget.service ?? ReportsService();

  bool _loading = true;
  DayRequestEligibility? _answer;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  // 尋ねる口に1回聞く（「もう一度」も同じこの1本）。
  Future<void> _ask() async {
    setState(() => _loading = true);
    final res =
        await _api.getDayRequestEligibility('attendance_fix', widget.workDate);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _answer = readDayRequestEligibility(res);
    });
  }

  // 「出勤の修正を依頼する」→ 依頼の画面。送れたら（true）この画面も閉じて登録の画面へ戻る。
  Future<void> _openRequest() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => DayRequestScreen(
        kind: DayRequestKind.attendanceFix,
        workDate: widget.workDate,
        dateText: widget.dateText,
        permitUntilText: widget.permitUntilText,
        service: widget.service,
      ),
    ));
    if (sent == true && mounted) {
      Navigator.of(context).pop(WorkDateNoReportChoice.requested);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: FieldTokens.bgBase,
        // ★器は A1・A2 と同じ（AppBar の地・字・影なし／余白は左右16・上下12）。
        appBar: AppBar(
          backgroundColor: FieldTokens.surfaceCard,
          foregroundColor: FieldTokens.textBody,
          elevation: 0,
          title: const Text('振替で休む'),
        ),
        // ★聞いている間のくるくるは、今の候補の画面と同じ形（画面の中央）。
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  children: _bodyOf(_answer),
                ),
              ),
      );

  List<Widget> _bodyOf(DayRequestEligibility? a) {
    if (a == null || a.kind == DayRequestEligibilityKind.unknown) {
      return [
        DayRequestTrouble(
          text: a?.text ?? '依頼できるかを確かめられませんでした',
          onRetry: _ask,
        ),
      ];
    }
    final allowed = a.kind == DayRequestEligibilityKind.allowed;
    return [
      if (allowed)
        PastDayFrame(
          lineColor: FieldTokens.brand,
          heading: 'この日の日報がありません',
          headingColor: FieldTokens.brand,
          body: Text.rich(
            TextSpan(
              style: kPastDayFrameBody,
              children: [
                TextSpan(
                    text: widget.dateText,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const TextSpan(
                  text: ' を出勤する日に選ぶには、その日の日報が必要です。'
                      '後から日報を出すには、事務の許可が要ります。',
                ),
              ],
            ),
          ),
        )
      else
        // ★出せない日は見出しを出さない（見本 G2 と同じ形）。候補が古いままの時に、
        //   「この日の日報がありません」と BE の文（例「すでに出勤の修正を依頼しています…」）が食い違わない。
        PastDayFrame(
          lineColor: FieldTokens.brand,
          body: Text(a.text ?? '', style: kPastDayFrameBody),
        ),
      const SizedBox(height: 16),
      if (allowed) ...[
        pastDayOutlinedButton('出勤の修正を依頼する', onPressed: _openRequest),
        const SizedBox(height: 8),
      ],
      pastDayOutlinedButton('代休で取る',
          onPressed: () =>
              Navigator.of(context).pop(WorkDateNoReportChoice.compOff)),
      const SizedBox(height: 8),
      pastDayTextButton('日を選び直す',
          onPressed: () =>
              Navigator.of(context).pop(WorkDateNoReportChoice.pickAnother)),
    ];
  }
}
