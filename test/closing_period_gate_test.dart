// ============================================================
// test/closing_period_gate_test.dart — 締め日で期間が2つある月の受け皿の検査
//
// 見ているのは「袋小路が開くか」の4点:
//   ① 候補2つ → 人が選ぶと、その締め日を付けて元の要求がやり直される
//   ② 未解決2か月 → 両方そろって初めてやり直す（1つ選んだだけでは送らない）
//   ③ やめると送らない（選びかけの値も残さない）
//   ④ 候補外・CLOSING_DATE_CONFLICT は BE の文言をそのまま出す（言い換えない）
//
// ★通信はしない。BE が返す 400 を http.Response として作り、実装と同じ
//   runApiCall に通す＝「本文から候補を読み取る」経路を素通りさせない。
//   応答の形は js-office-api の services/closingPeriodRequest.js に合わせて写す。
// ★期待する文言は実装から import せずここへ直書きする（実装を写すと何も検査しない）。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/config/constants.dart';
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/utils/session_lockout.dart';
import 'package:js_awake_app/widgets/closing_period_dialog.dart';

// ── BE の応答の写し ────────────────────────────────────────────

/// 1つの月を扱う口の 400（periods 付き）。
String _ambiguousOneMonthBody() => '{'
    '"error":"この月は締め日の変更により期間が2つあります。どちらの期間かを指定してください",'
    '"code":"AMBIGUOUS_CLOSING_PERIOD",'
    '"periods":['
    '{"start":"2026-02-21","end":"2026-03-21","closingDate":"2026-03-20"},'
    '{"start":"2026-03-01","end":"2026-04-01","closingDate":"2026-03-31"}'
    ']}';

/// 複数の月を扱う口の 400（unresolved 付き）。
String _ambiguousTwoMonthsBody() => '{'
    '"error":"締め日の変更により期間が2つある月があります（2026-03 / 2026-06）。",'
    '"code":"AMBIGUOUS_CLOSING_PERIOD",'
    '"unresolved":['
    '{"month":"2026-03","periods":['
    '{"start":"2026-02-21","end":"2026-03-21","closingDate":"2026-03-20"},'
    '{"start":"2026-03-01","end":"2026-04-01","closingDate":"2026-03-31"}]},'
    '{"month":"2026-06","periods":['
    '{"start":"2026-05-21","end":"2026-06-21","closingDate":"2026-06-20"},'
    '{"start":"2026-06-01","end":"2026-07-01","closingDate":"2026-06-30"}]}'
    ']}';

http.Response _res(int status, String body) {
  final req = http.Request('GET', Uri.parse('$kApiBaseUrl/reports?date=2026-03'));
  req.headers['Authorization'] = 'Bearer token-a';
  return http.Response(body, status,
      request: req,
      headers: const {'content-type': 'application/json; charset=utf-8'});
}

/// 実装と同じ経路（runApiCall）で ApiResult を作る。
Future<ApiResult<Map<String, dynamic>>> _call(http.Response res) =>
    runApiCall<Map<String, dynamic>>('Test', () async => res, apiJsonMap);

// ── 検査用の画面 ───────────────────────────────────────────────

/// 受け皿を1つ持ち、送るたびに「送った締め日」を記録するだけの画面。
class _Harness extends StatefulWidget {
  const _Harness({
    required this.gate,
    required this.months,
    required this.sent,
    required this.queue,
    this.asBar = false,
  });

  final ClosingPeriodGate gate;
  final List<String> months;

  /// 送信のたびに、そのとき載せた closing_dates を積む（長さ＝送信回数）。
  final List<List<String>> sent;

  /// 1回ぶんずつ返す応答。null なら 200（成功）。
  final List<http.Response?> queue;

  /// 1行の帯（カレンダー用）で出すか。既定は全面の理由。
  final bool asBar;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    widget.gate.beginRound();
    await widget.gate.send<Map<String, dynamic>>(
      months: widget.months,
      run: (dates) {
        widget.sent.add(List<String>.from(dates));
        final res = widget.queue.isEmpty ? null : widget.queue.removeAt(0);
        return _call(res ?? _res(200, '{"ok":true}'));
      },
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: widget.gate.isPending
            ? (widget.asBar
                ? ClosingPeriodBar(gate: widget.gate, onResolved: _load)
                : ClosingPeriodNotice(gate: widget.gate, onResolved: _load))
            : Text('取得できました（送信${widget.sent.length}回）'),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'token-a'});
    resetLockoutGuardForTest();
  });

  group('締め日の受け皿：400 の本文の読み取り', () {
    test('ApiResult が本文をそのまま運ぶ（候補が捨てられない）', () async {
      final r = await _call(_res(400, _ambiguousOneMonthBody()));
      expect(r.ok, isFalse);
      expect(r.statusCode, 400);
      expect(r.errorCode, 'AMBIGUOUS_CLOSING_PERIOD');
      expect(r.errorDetails, isNotNull,
          reason: '400 の本文が運ばれていない＝候補一覧が読めない');
      expect((r.errorDetails!['periods'] as List).length, 2);

      final issue = readClosingIssue(r);
      expect(issue.choices.length, 1);
      expect(issue.choices.first.periods.length, 2);
      // 月は応答に載らない口なので、候補の締め日から起こす。
      expect(issue.choices.first.month, '2026-03');
    });

    test('締め日と関係ない 400 は引き取らない（画面の従来の出し方を横取りしない）',
        () async {
      final r = await _call(
          _res(400, '{"error":"month は YYYY-MM 形式です","code":"INVALID_MONTH"}'));
      expect(readClosingIssue(r).isEmpty, isTrue);
    });

    test('成功した応答からは何も引き取らない', () async {
      final r = await _call(_res(200, '{"ok":true}'));
      expect(readClosingIssue(r).isEmpty, isTrue);
    });
  });

  group('締め日の受け皿：選ばせてやり直す', () {
    testWidgets('① 候補2つ → 選ぶと締め日を付けて再送される', (tester) async {
      final gate = ClosingPeriodGate();
      final sent = <List<String>>[];
      final queue = <http.Response?>[_res(400, _ambiguousOneMonthBody())];

      await tester.pumpWidget(_Harness(
          gate: gate, months: const ['2026-03'], sent: sent, queue: queue));
      await tester.pumpAndSettle();

      // 1回目は締め日を付けずに送っている。
      expect(sent.length, 1);
      expect(sent.first, isEmpty);

      // 押される前から理由が画面に出ている（0件で黙らない）。
      expect(find.textContaining('2026年3月分'), findsOneWidget);
      expect(find.textContaining('期間が2つあります'), findsOneWidget);

      await tester.tap(find.text('期間を選ぶ'));
      await tester.pumpAndSettle();

      // 候補は幅と締め日の両方で見分けられる形で出る。
      expect(find.text('2/21〜3/20'), findsOneWidget);
      expect(find.text('3/1〜3/31'), findsOneWidget);
      expect(find.text('締め日 2026年3月31日'), findsOneWidget);

      await tester.tap(find.text('3/1〜3/31'));
      await tester.pumpAndSettle();

      // 選んだ締め日を付けて、元の要求がやり直された。
      expect(sent.length, 2);
      expect(sent[1], ['2026-03-31']);
      expect(gate.isPending, isFalse);
      expect(find.text('取得できました（送信2回）'), findsOneWidget);
    });

    testWidgets('② 未解決2か月 → 両方そろって初めて再送される', (tester) async {
      final gate = ClosingPeriodGate();
      final sent = <List<String>>[];
      final queue = <http.Response?>[_res(400, _ambiguousTwoMonthsBody())];

      await tester.pumpWidget(_Harness(
          gate: gate,
          months: const ['2026-03', '2026-06'],
          sent: sent,
          queue: queue));
      await tester.pumpAndSettle();

      // 未解決の月は両方とも理由に出る（どの月が決まっていないか分かる）。
      expect(find.textContaining('2026年3月分 / 2026年6月分'), findsOneWidget);

      await tester.tap(find.text('期間を選ぶ'));
      await tester.pumpAndSettle();

      // 1か月目。
      expect(find.textContaining('2026年3月分は期間が2つあります'), findsOneWidget);
      await tester.tap(find.text('2/21〜3/20'));
      await tester.pumpAndSettle();

      // ★ここで送ってはいけない（1つずつ小出しにしない）。
      expect(sent.length, 1);

      // 2か月目が続けて出る。
      expect(find.textContaining('2026年6月分は期間が2つあります'), findsOneWidget);
      await tester.tap(find.text('5/21〜6/20'));
      await tester.pumpAndSettle();

      // 両方そろって初めて再送。2か月ぶんの締め日が載る。
      expect(sent.length, 2);
      expect(sent[1], ['2026-03-20', '2026-06-20']);
    });

    testWidgets('② 途中でやめたら、選びかけの月も残さない', (tester) async {
      final gate = ClosingPeriodGate();
      final sent = <List<String>>[];
      final queue = <http.Response?>[_res(400, _ambiguousTwoMonthsBody())];

      await tester.pumpWidget(_Harness(
          gate: gate,
          months: const ['2026-03', '2026-06'],
          sent: sent,
          queue: queue));
      await tester.pumpAndSettle();

      await tester.tap(find.text('期間を選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2/21〜3/20')); // 1か月目だけ選ぶ
      await tester.pumpAndSettle();
      await tester.tap(find.text('閉じる')); // 2か月目でやめる
      await tester.pumpAndSettle();

      expect(sent.length, 1, reason: 'やめたのに再送している');
      expect(gate.chosenFor('2026-03'), isNull,
          reason: '選びかけの1か月目が残っている（次に別の月と混ざる）');
      expect(gate.isPending, isTrue, reason: '理由が消えて画面が黙っている');
    });

    testWidgets('③ やめると再送しない（理由は画面に残る）', (tester) async {
      final gate = ClosingPeriodGate();
      final sent = <List<String>>[];
      final queue = <http.Response?>[_res(400, _ambiguousOneMonthBody())];

      await tester.pumpWidget(_Harness(
          gate: gate, months: const ['2026-03'], sent: sent, queue: queue));
      await tester.pumpAndSettle();

      await tester.tap(find.text('期間を選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();

      expect(sent.length, 1, reason: 'やめたのに再送している');
      expect(gate.isPending, isTrue);
      expect(find.text('期間を選ぶ'), findsOneWidget, reason: '選び直す道が消えている');
    });

    testWidgets('④ 候補外の 400 は BE の文言をそのまま出す', (tester) async {
      final gate = ClosingPeriodGate();
      final sent = <List<String>>[];
      final queue = <http.Response?>[
        _res(
            400,
            '{"error":"指定された締め日はこの月の候補にありません。候補の中から選んでください",'
                '"code":"CLOSING_DATE_NOT_IN_PERIOD"}'),
      ];

      await tester.pumpWidget(_Harness(
          gate: gate, months: const ['2026-03'], sent: sent, queue: queue));
      await tester.pumpAndSettle();

      expect(
          find.text('指定された締め日はこの月の候補にありません。候補の中から選んでください'),
          findsOneWidget);
      // 選ばせる候補が無いので「期間を選ぶ」は出さない。
      expect(find.text('期間を選ぶ'), findsNothing);
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('④ CLOSING_DATE_CONFLICT の 400 も BE の文言をそのまま出す',
        (tester) async {
      final gate = ClosingPeriodGate();
      final sent = <List<String>>[];
      final queue = <http.Response?>[
        _res(
            400,
            '{"error":"同じ月の締め日を2つ以上指定しています。月ごとに1つだけ指定してください",'
                '"code":"CLOSING_DATE_CONFLICT"}'),
      ];

      await tester.pumpWidget(_Harness(
          gate: gate, months: const ['2026-03'], sent: sent, queue: queue));
      await tester.pumpAndSettle();

      expect(
          find.text('同じ月の締め日を2つ以上指定しています。月ごとに1つだけ指定してください'),
          findsOneWidget);
      expect(find.text('期間を選ぶ'), findsNothing);
    });

    testWidgets('使われなかった締め日は捨てる（同じ400が出続ける袋小路を作らない）',
        (tester) async {
      final gate = ClosingPeriodGate();
      final sent = <List<String>>[];
      final queue = <http.Response?>[
        _res(400, _ambiguousOneMonthBody()), // 1回目: 選ばせる
        _res(
            400,
            '{"error":"指定された締め日に当たる期間がありません。候補の中から選んでください",'
                '"code":"CLOSING_DATE_NOT_IN_PERIOD"}'), // 2回目: 当たらない
        null, // 3回目: 素で成功する
      ];

      await tester.pumpWidget(_Harness(
          gate: gate, months: const ['2026-03'], sent: sent, queue: queue));
      await tester.pumpAndSettle();

      await tester.tap(find.text('期間を選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3/1〜3/31'));
      await tester.pumpAndSettle();

      expect(sent[1], ['2026-03-31']);
      // 当たらなかった締め日は捨てられている。
      expect(gate.chosenFor('2026-03'), isNull);

      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      // 3回目は締め日を付けずに送り直す＝押しても直らない道にならない。
      expect(sent.length, 3);
      expect(sent[2], isEmpty);
      expect(gate.isPending, isFalse);
    });

    testWidgets('選んだ締め日は月ごとに持ち、別の月の要求には載せない', (tester) async {
      final gate = ClosingPeriodGate();
      final sent = <List<String>>[];
      final queue = <http.Response?>[_res(400, _ambiguousOneMonthBody())];

      await tester.pumpWidget(_Harness(
          gate: gate, months: const ['2026-03'], sent: sent, queue: queue));
      await tester.pumpAndSettle();
      await tester.tap(find.text('期間を選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2/21〜3/20'));
      await tester.pumpAndSettle();

      expect(gate.chosenFor('2026-03'), '2026-03-20');

      // 別の月を要求すると、3月の締め日は載らない
      // （載せると BE が CLOSING_DATE_NOT_IN_PERIOD を返して別の袋小路になる）。
      final other = <List<String>>[];
      await gate.send<Map<String, dynamic>>(
        months: const ['2026-04'],
        run: (dates) {
          other.add(List<String>.from(dates));
          return _call(_res(200, '{"ok":true}'));
        },
      );
      expect(other.single, isEmpty);
    });

    testWidgets('1周で2本を並行に投げても、先に見つかった理由が消えない', (tester) async {
      // カレンダーは日報と自分の休みを同時に投げる。後から来た「何も無い結果」で
      // 先に見つかった事情が消えると、画面が黙る。
      final gate = ClosingPeriodGate();
      gate.beginRound();
      final a = gate.send<Map<String, dynamic>>(
        months: const ['2026-03'],
        run: (_) => _call(_res(400, _ambiguousOneMonthBody())),
      );
      final b = gate.send<Map<String, dynamic>>(
        months: const ['2026-03'],
        run: (_) => _call(_res(200, '{"ok":true}')),
      );
      await a;
      await b;
      expect(gate.isPending, isTrue);
      expect(gate.canChoose, isTrue);
    });

    testWidgets('カレンダー用の1行の帯からも同じ受け皿で選べる', (tester) async {
      final gate = ClosingPeriodGate();
      final sent = <List<String>>[];
      final queue = <http.Response?>[_res(400, _ambiguousOneMonthBody())];

      await tester.pumpWidget(_Harness(
          gate: gate,
          months: const ['2026-03'],
          sent: sent,
          queue: queue,
          asBar: true));
      await tester.pumpAndSettle();

      expect(find.textContaining('2026年3月分'), findsOneWidget);
      await tester.tap(find.text('期間を選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2/21〜3/20'));
      await tester.pumpAndSettle();

      expect(sent.length, 2);
      expect(sent[1], ['2026-03-20']);
    });
  });
}
