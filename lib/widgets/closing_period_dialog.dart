// lib/widgets/closing_period_dialog.dart
// 「締め日を変えた月は期間が2つある」を人に選ばせて先へ通す、ただ1つの受け皿。
//
// ★なぜ1本にするか:
//   BE は締め日を変えた月に同名の期間が2つできると 400 AMBIGUOUS_CLOSING_PERIOD を
//   返す（js-office-api の services/closingPeriodRequest.js）。この 400 を読む受け手が
//   画面ごとに書かれると、同じ掟が入口によって効き方を変える（ある画面は選ばせ、
//   別の画面は 0 件のまま黙る）。読む・選ばせる・出す・送り直すの4つをここだけに置く。
//
// ★BE が 400 に載せてくる鍵（closingPeriodRequest.js の応答の節）:
//     periods    … その月の候補の期間一覧（1つの月を扱う口）
//     unresolved … [{ month, periods }] 未解決の月とその候補（複数の月を扱う口）
//     unused     … 指定したのにどの月の候補にも当たらなかった値
//   期間は { start, end, closingDate } の3つ。end は【含まない】ので表示には使わない。
//
// ★指定の送り方は closing_dates（複数・カンマ区切り）ただ1つにする。
//   BE は単数の closing_date も受けるが、こちら側が2つの送り方を持つと
//   「1つの月なら単数・複数月なら複数」という分岐が呼び手に生える。
//
// ★選んだ締め日は【月ごと】に持ち、その要求が触る月の分だけを送る。
//   まとめて送ると、3月を選んだあと4月を開いた瞬間に BE の resolveMonthPeriod が
//   「指定された締め日はこの月の候補にありません」（unused → CLOSING_DATE_NOT_IN_PERIOD）
//   で 400 を返し、別の袋小路になる。
//
// ★見た目は FIELD の家風に合わせる（他アプリの配色・部品は持ち込まない）:
//   ・候補を選ばせるダイアログ … home_screen.dart の _openExtraDeclarationPicker
//       （「追加の申告」種別選択）と、その行部品 _DeclarationChoiceRow が手本。
//       AlertDialog(surfaceCard・角丸14・title は textBody の 16px)＋
//       枠線 1px の行（アイコン＋太字ラベル＋薄い補足＋右向き山括弧）＋
//       actions は「閉じる」1つ（textSupport）。
//   ・全面に出す理由 … home_screen.dart の _failView（Center＋error_outline 32＋
//       statusWarning 13px＋OutlinedButton.icon）が手本。
//   ・1行で出す理由 … home_screen.dart の _breakFailBanner（surfaceCard の帯に
//       error_outline 14＋statusWarning 12px＋右端に操作の語）が手本。
//   ★どちらの形も FIELD に既にある。中身が入れ替わる場所は全面、
//     他の情報と並ぶ場所は1行、という使い分けも既存のまま。
import 'package:flutter/material.dart';

import '../core/closing_period_labels.dart';
import '../core/theme/field_tokens.dart';
import '../services/api_result.dart';

/// 締め日を指定したときにしか起きない 400 の code。
///   ★この受け皿が closing_dates を送ったから起きるものだけを並べる。
///     指定の有無に関係なく起きる既存の 400（NO_CLOSING_PERIOD 等）は触らない
///     ＝画面が従来から出している理由を横取りしない。
const Set<String> kClosingDateInputCodes = {
  'CLOSING_DATE_CONFLICT',
  'CLOSING_DATE_NOT_IN_PERIOD',
  'INVALID_CLOSING_DATE',
};

/// まだ期間が決まっていない月1つと、その候補。
class ClosingPeriodUnresolved {
  const ClosingPeriodUnresolved({required this.month, required this.periods});

  /// 'YYYY-MM'。1つの月しか扱わない口は応答に月が載らないため、候補の締め日から起こす。
  ///   ★起こせる根拠: BE の closingDatesInMonth はその月の1日〜末日の中の日しか
  ///     返さない＝候補の締め日が属する月＝その月。
  final String? month;

  /// 候補の期間（start / end / closingDate）。
  final List<Map<String, dynamic>> periods;

  String get monthText => closingMonthText(month);
}

/// 400 から読み取った「締め日が決まっていない」事情。
class ClosingPeriodIssue {
  const ClosingPeriodIssue({
    this.choices = const [],
    this.message,
    this.staleMonths = const [],
  });

  /// 選ばせられる候補。空なら選ばせようがない。
  final List<ClosingPeriodUnresolved> choices;

  /// 画面に出す理由。BE の文言をそのまま入れる（言い換えない）。
  final String? message;

  /// 送った締め日が使われなかった月（次の要求から外す）。
  final List<String> staleMonths;

  bool get isEmpty => choices.isEmpty && message == null;
}

/// ApiResult から「締め日が決まっていない」を読む唯一の関数。
///   ★code は ApiResult.errorCode を先に見る。無ければ本文（errorDetails）から拾う。
///     BE は口によって鍵の名前が違う（大半は code、経費の口だけ error_code）ため、
///     読む場所を1つにして両方を見る。FIELD が現に叩く口はすべて code だが、
///     読み方を1箇所に閉じておけば口が増えても同じ掟のままで済む。
ClosingPeriodIssue readClosingIssue(
  ApiResult<Object?> res, {
  List<String> sentMonths = const [],
}) {
  if (res.ok) return const ClosingPeriodIssue();
  final body = res.errorDetails;
  final code = res.errorCode ??
      (body?['code'] as String?) ??
      (body?['error_code'] as String?);
  if (code == null) return const ClosingPeriodIssue();
  final text = res.errorMessage;

  if (code == 'AMBIGUOUS_CLOSING_PERIOD') {
    final list = _unresolvedOf(body);
    if (list.isNotEmpty) return ClosingPeriodIssue(choices: list, message: text);
    // 候補が載っていない曖昧＝選ばせようがない。黙らずに BE の文言を出す。
    return ClosingPeriodIssue(message: text ?? kClosingUnresolvedFallback);
  }
  if (kClosingDateInputCodes.contains(code)) {
    // 候補外・同じ月に2つ指定 など。言い換えず BE の文言をそのまま出す。
    // ★あわせて、この要求で送った締め日は捨てる。残したままだと同じ 400 が
    //   出続けて選び直す道が無くなる（袋小路をもう1つ作らない）。
    return ClosingPeriodIssue(
      message: text ?? kClosingUnresolvedFallback,
      staleMonths: sentMonths,
    );
  }
  return const ClosingPeriodIssue();
}

List<ClosingPeriodUnresolved> _unresolvedOf(Map<String, dynamic>? body) {
  if (body == null) return const [];
  final many = body['unresolved'];
  if (many is List) {
    final out = <ClosingPeriodUnresolved>[];
    for (final e in many.whereType<Map>()) {
      final ps = _periodsOf(e['periods']);
      if (ps.length < 2) continue; // 選ばせる意味のない候補は出さない
      out.add(ClosingPeriodUnresolved(
        month: (e['month'] as String?) ?? _monthOfPeriods(ps),
        periods: ps,
      ));
    }
    return out;
  }
  final ps = _periodsOf(body['periods']);
  if (ps.length < 2) return const [];
  return [ClosingPeriodUnresolved(month: _monthOfPeriods(ps), periods: ps)];
}

List<Map<String, dynamic>> _periodsOf(Object? v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((p) => (p['closingDate'] as String?)?.length == 10)
      .toList();
}

String? _monthOfPeriods(List<Map<String, dynamic>> ps) {
  final d = ps.first['closingDate'] as String?;
  return (d == null || d.length < 7) ? null : d.substring(0, 7);
}

/// 画面が1つ持つ受け皿。送る・抱える・選ばせる、の3つだけを受け持つ。
///
/// どの画面でも同じ3手:
///   ① 送る    … `final res = await _closing.send(months: [m],
///                    run: (dates) => Service().foo(month: m, closingDates: dates));`
///   ② 見る    … `if (_closing.isPending) { 理由を出す }`
///   ③ 選ばせる… ClosingPeriodNotice / ClosingPeriodBar のボタンが choose() を呼び、
///                選び終えたら onResolved（＝画面の読み込み直し）が走る。
class ClosingPeriodGate {
  /// 月（'YYYY-MM'）→ 人が選んだ締め日（'YYYY-MM-DD'）。
  final Map<String, String> _byMonth = <String, String>{};
  ClosingPeriodIssue _issue = const ClosingPeriodIssue();

  /// まだ期間が決まっていない＝画面は理由を出す（0件や空で黙らない）。
  bool get isPending => !_issue.isEmpty;

  /// 選ばせられる（候補がある）か。false のときは理由を出すだけ。
  bool get canChoose => _issue.choices.isNotEmpty;

  /// 画面に出す理由。候補があるときは月名と候補の数を必ず添える。
  String get noticeText {
    if (_issue.choices.isNotEmpty) {
      return closingAmbiguousNotice(
        _issue.choices.map((u) => u.monthText).toList(),
        _issue.choices.first.periods.length,
      );
    }
    return _issue.message ?? kClosingUnresolvedFallback;
  }

  /// 検査用の覗き窓。いまこの月に対して選ばれている締め日。
  String? chosenFor(String month) => _byMonth[month];

  /// 読み込みの1周を始める（抱えている事情を捨てる）。
  ///   ★各画面の読み込みメソッドの先頭で必ず1回呼ぶ。ここで捨てないと、
  ///     締め日の設定が直ったあとも古い理由が画面に残り続ける。
  ///   ★捨てるのは「事情」だけで、人が選んだ締め日は残す（選び直させない）。
  ///   ★send の中で捨てないのは、1周で複数本を【並行に】投げる画面があるため。
  ///     送る前に一斉に捨てる形だと、後から始まった1本が、先に見つかった事情を
  ///     消してしまう（実際に日報と休憩を同時に投げる画面がある）。
  void beginRound() {
    _issue = const ClosingPeriodIssue();
  }

  /// 1本送る。締め日由来の 400 だったら抱え込み、そうでなければ何も起きない。
  ///   [months] … この要求が触る月（'YYYY-MM'）。ここに載っている月の締め日だけを送る。
  ///   [run]    … 送る締め日を受け取って実際に通信する処理。
  ///   ★1周で何本呼んでもよい。先に見つかった事情を、後から来た「何も無い結果」で
  ///     上書きしない（＝並行に投げても結果が実行順で変わらない）。
  Future<ApiResult<T>> send<T>({
    required List<String> months,
    required Future<ApiResult<T>> Function(List<String> closingDates) run,
  }) async {
    final dates = <String>[];
    for (final m in months) {
      final d = _byMonth[m];
      if (d != null && !dates.contains(d)) dates.add(d);
    }
    final res = await run(List<String>.unmodifiable(dates));
    final issue = readClosingIssue(res, sentMonths: months);
    for (final m in issue.staleMonths) {
      _byMonth.remove(m);
    }
    if (!issue.isEmpty && _issue.isEmpty) _issue = issue;
    return res;
  }

  /// 未解決の月ぶんを順に選ばせる。
  ///   ・1つでもやめたら false（＝再送しない。選びかけの値も残さない）
  ///   ・全部そろって初めて true（＝呼び手はここで読み込み直す）
  Future<bool> choose(BuildContext context) async {
    final list = _issue.choices;
    if (list.isEmpty) return false;
    final picked = <String, String>{};
    for (final u in list) {
      if (!context.mounted) return false;
      final one = await _askOne(context, u);
      if (one == null || one.length < 7) return false; // やめる道
      picked[u.month ?? one.substring(0, 7)] = one;
    }
    _byMonth.addAll(picked);
    _issue = const ClosingPeriodIssue();
    return true;
  }

  /// 月1つぶんの候補を選ばせる。戻りは選ばれた締め日（'YYYY-MM-DD'）。
  /// ★見た目は home_screen の _openExtraDeclarationPicker と同じ形。
  Future<String?> _askOne(BuildContext context, ClosingPeriodUnresolved u) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(kClosingAmbiguousTitle,
            style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // どの月の話なのかを必ず出す（複数の月を続けて聞くので取り違えないため）。
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${u.monthText}は期間が${u.periods.length}つあります',
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 12)),
              ),
              const SizedBox(height: 10),
              for (final p in u.periods) ...[
                _ClosingChoiceRow(
                  // 幅だけでは取り違えるので締め日そのものも出す。
                  label: closingPeriodRangeText(p),
                  note: closingPeriodClosingText(p),
                  onTap: () => Navigator.pop(ctx, p['closingDate'] as String?),
                ),
                const SizedBox(height: 10),
              ],
            ],
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
    );
  }
}

/// 候補1行。home_screen の _DeclarationChoiceRow と同じ形
/// （枠線1px・塗りなし・最低56px・アイコン＋太字ラベル＋薄い補足＋山括弧）。
class _ClosingChoiceRow extends StatelessWidget {
  const _ClosingChoiceRow({
    required this.label,
    required this.note,
    required this.onTap,
  });

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
                const Icon(Icons.date_range,
                    color: FieldTokens.textSupport, size: 20),
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

/// 中身が入れ替わる場所に出す全面の理由。home_screen の _failView と同じ形。
///   ★候補が無いとき（BE の文言だけのとき）はボタンを「再試行」にする。
///     そのとき受け皿は使われなかった締め日を既に捨てているので、
///     押せば次はやり直せる＝押しても直らない道にはならない。
class ClosingPeriodNotice extends StatelessWidget {
  const ClosingPeriodNotice({
    super.key,
    required this.gate,
    required this.onResolved,
  });

  final ClosingPeriodGate gate;

  /// 全部の月を選び終えたとき／再試行が押されたときに呼ばれる。
  final VoidCallback onResolved;

  @override
  Widget build(BuildContext context) {
    final choosing = gate.canChoose;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: FieldTokens.statusWarning, size: 32),
            const SizedBox(height: 8),
            Text(gate.noticeText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: FieldTokens.statusWarning, fontSize: 13)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                if (!choosing) {
                  onResolved();
                  return;
                }
                if (await gate.choose(context)) onResolved();
              },
              icon: Icon(choosing ? Icons.date_range : Icons.refresh, size: 16),
              label: Text(choosing ? kClosingChooseAction : '再試行'),
              style: OutlinedButton.styleFrom(
                foregroundColor: FieldTokens.textBody,
                side: const BorderSide(color: FieldTokens.textBody, width: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 他の情報と並ぶ場所に出す1行の理由。home_screen の _breakFailBanner と同じ形。
class ClosingPeriodBar extends StatelessWidget {
  const ClosingPeriodBar({
    super.key,
    required this.gate,
    required this.onResolved,
  });

  final ClosingPeriodGate gate;
  final VoidCallback onResolved;

  @override
  Widget build(BuildContext context) {
    final choosing = gate.canChoose;
    return GestureDetector(
      onTap: () async {
        if (!choosing) {
          onResolved();
          return;
        }
        if (await gate.choose(context)) onResolved();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: FieldTokens.surfaceCard,
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                color: FieldTokens.statusWarning, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(gate.noticeText,
                  style: const TextStyle(
                      color: FieldTokens.statusWarning, fontSize: 12)),
            ),
            Text(choosing ? kClosingChooseAction : '再試行',
                style: const TextStyle(
                    color: FieldTokens.statusWarning,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
