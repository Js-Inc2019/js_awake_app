// ============================================================
// test/substitute_register_test.dart
//   振替休日を【自分で登録する】道を機械で固定する（モック B1→B2→B3）。
//
// ★見る側は test/substitute_view_test.dart、既に在る振替への操作は
//   test/substitute_actions_test.dart の担当。この本は【新しく1件作る】道だけを見る。
//   本を分けたのは問いが違うため（家風＝新しい仕掛けには新しい本を立てる）。
//
// ★画面は立てる。差し替え口（任意の引数 service）が RestDayScreen にも
//   SubstituteRegisterScreen にも在るので、実 HTTP へ行かせずに押せる。
//   CalendarDaySheet は元から素の部品なので、そのまま立てて押せる。
//
// ★何を守るか（すべて二者比較。「出ない」だけで合格にしない）:
//   (1) 本日休みの画面に「振替で休む」が出て、押すと注意書きが出る
//       （対照：代休の入口と「休みを登録する」が今までどおり出る）
//   (2) 候補＝selectable が false の日は選べず、BE の reason がそのまま出る
//   (3) 出勤する日を選ぶまで「この内容で登録する」が押せない（onPressed が null）
//   (4) 選んで押すと、その休む日と出勤する日で登録が呼ばれる
//   (5) 断られたら BE の文がそのまま出て、閉じるまで消えない
//   (6) holiday_def_configured が false の回は、候補ではなく BE の断りが出る
//   (7) カレンダーの箱＝休みが無い日には出て、振替の日には出ない
//
// ★掟: 期待値（語・真偽・並び）はこのファイル内で組み立てる。実装の定数は import しない。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:js_awake_app/screens/home_screen.dart'
    show CalendarDayInfo, CalendarDaySheet;
import 'package:js_awake_app/screens/rest_day_screen.dart' show RestDayScreen;
import 'package:js_awake_app/screens/substitute_register_screen.dart'
    show SubstituteRegisterScreen;
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';

// ── 画面の実文言（lib の実文字列をここへ写した）──────────────────
// ★カレンダーの箱（home_screen）の文言。ここは今までどおり。
const String kActSubstitute = '振替で休む';
const String kActCompOff    = '代休で休む';
// ★本日休みの画面は、代休と振替を横に並べたときに種類名だけに変わった。
//   （半分の幅に「振替で休む（12月31日（水））」は1行に入らないため）
const String kRestSubstitute = '振替';
const String kRestCompOff    = '代休';
const String kRestAnotherDay = '別の日';
const String kSubmitLabel   = '休みを登録する';
const String kNoticeHead    = 'はじめにご確認ください';
const String kNoticeOk      = '確認しました';
const String kRegisterGo    = 'この内容で登録する';
const String kOpenSub       = '振替休日を開く';
const String kClose         = '閉じる';
const String kBand          = '同じ週の中で入れ替え';
const String kWorkHead      = '代わりに出勤する日';

/// BE の GET /rest-days/substitute/candidates が返す days[] の1つ。
Map<String, dynamic> _day({
  required String date,
  required int dow,
  bool selectable = true,
  String? reasonCode,
  String? reason,
}) => {
      'date': date,
      'dow': dow,
      'selectable': selectable,
      'reason_code': reasonCode,
      'reason': reason,
    };

/// 差し替える口。★実 HTTP へ行かせず、何を何で叩いたかを数える。
///   形は test/comp_off_flow_test.dart の _FakeSvc と同じ（super.forTest()）。
class _FakeSvc extends ReportsService {
  _FakeSvc({
    this.days = const [],
    this.holidayDefConfigured = true,
    this.restDateIsWorkday = true,
    this.candidatesFail,
    this.registerFail,
  }) : super.forTest();

  final List<Map<String, dynamic>> days;
  final bool holidayDefConfigured;
  final bool restDateIsWorkday;
  final String? candidatesFail;
  final String? registerFail;

  final List<String> candidateCalls = [];
  final List<Map<String, String>> registerCalls = [];

  @override
  Future<ApiResult<Map<String, dynamic>>> getSubstituteWorkDateCandidates(
      String restDate) async {
    candidateCalls.add(restDate);
    if (candidatesFail != null) {
      return apiFailure<Map<String, dynamic>>(
          statusCode: 0, errorMessage: candidatesFail);
    }
    return apiSuccess<Map<String, dynamic>>(
      statusCode: 200,
      data: {
        'rest_date': restDate,
        'rest_date_is_workday': restDateIsWorkday,
        'holiday_def_configured': holidayDefConfigured,
        'days': days,
      },
    );
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> registerSubstitute(
      String restDate, String pairedWorkDate) async {
    registerCalls.add({'rest_date': restDate, 'work_date': pairedWorkDate});
    return registerFail == null
        ? apiSuccess<Map<String, dynamic>>(
            statusCode: 201,
            data: const {'pending_agreement': false})
        : apiFailure<Map<String, dynamic>>(
            statusCode: 409, errorMessage: registerFail, errorCode: 'X');
  }
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

/// 候補の7日ぶん（選べる日2つ・選べない日2つ）。
List<Map<String, dynamic>> _week() => [
      _day(date: '2026-06-07', dow: 0),
      _day(date: '2026-06-08', dow: 1,
          selectable: false, reasonCode: 'not_holiday',
          reason: '会社の休みの日ではありません'),
      _day(date: '2026-06-13', dow: 6,
          selectable: false, reasonCode: 'same_as_rest_date',
          reason: '休む日と同じ日です'),
      _day(date: '2026-06-14', dow: 0),
    ];

void main() {
  // ══════════════════════════════════════════════════════════
  // (1) 本日休みの画面（モック B1）
  // ══════════════════════════════════════════════════════════
  group('(1) 本日休みの画面の入口', () {
    testWidgets('★「振替で休む」が出る（対照: 代休の入口と「休みを登録する」も今までどおり出る）',
        (tester) async {
      await _pump(tester, RestDayScreen(service: _FakeSvc()));

      expect(find.widgetWithText(OutlinedButton, kRestSubstitute),
          findsOneWidget, reason: '振替の入口が無い');
      // ★対照: 既にあった入口を1つも壊していない。
      expect(find.widgetWithText(OutlinedButton, kRestCompOff), findsOneWidget,
          reason: '代休の入口が消えている');
      expect(find.text(kSubmitLabel), findsOneWidget,
          reason: '本体の「休みを登録する」が消えている');
      expect(find.text('代休・振替'), findsOneWidget, reason: '小見出しが無い');
      // 「別の日」は代休と振替で1つずつ＝2つ。
      expect(find.text(kRestAnotherDay), findsNWidgets(2),
          reason: '振替側の「別の日」が無い／代休側が消えている');
    });

    testWidgets('★押すと注意書き（B2）が出る（対照: 押す前は出ていない）',
        (tester) async {
      await _pump(tester, RestDayScreen(service: _FakeSvc(days: _week())));

      expect(find.text(kNoticeHead), findsNothing,
          reason: '押していないのに注意書きが出ている');
      await tester.tap(find.text(kRestSubstitute));
      await tester.pumpAndSettle();
      expect(find.text(kNoticeHead), findsOneWidget, reason: '注意書きが出ない');
      expect(find.text(kNoticeOk), findsOneWidget);
    });

    testWidgets('★注意書きで「確認しました」を押すと、その休む日で候補が引かれる',
        (tester) async {
      final api = _FakeSvc(days: _week());
      await _pump(tester, RestDayScreen(service: api));

      await tester.tap(find.text(kRestSubstitute));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kNoticeOk));
      await tester.pumpAndSettle();

      expect(api.candidateCalls.length, 1,
          reason: '候補の口をちょうど1回叩いていない');
      // ★既定の休む日は今日。端末の今日を写して突き合わせる（実装の関数は呼ばない）。
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}'
          '-${now.day.toString().padLeft(2, '0')}';
      expect(api.candidateCalls.first, today,
          reason: '既定の休む日が今日になっていない');
      expect(find.text(kWorkHead), findsOneWidget, reason: 'B3 へ進んでいない');
    });

    testWidgets('★対: 注意書きで「やめる」を押すと候補を1回も引かない', (tester) async {
      final api = _FakeSvc(days: _week());
      await _pump(tester, RestDayScreen(service: api));

      await tester.tap(find.text(kRestSubstitute));
      await tester.pumpAndSettle();
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();

      expect(api.candidateCalls, isEmpty, reason: 'やめたのに口を叩いている');
      expect(find.text(kWorkHead), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (2)〜(6) 出勤する日を選ぶ画面（モック B3）
  // ══════════════════════════════════════════════════════════
  group('(2) 出勤する日の候補', () {
    testWidgets('★selectable が false の日は BE の reason がそのまま出る'
        '（対照: 選べる日には理由が付かない）', (tester) async {
      final api = _FakeSvc(days: _week());
      await _pump(tester,
          SubstituteRegisterScreen(restDate: '2026-06-13', service: api));

      expect(find.text('会社の休みの日ではありません'), findsOneWidget,
          reason: 'BE の理由が出ていない（端末で言い換えている）');
      expect(find.text('休む日と同じ日です'), findsOneWidget);
      // ★対照: 選べる日はそのまま並び、理由の文が付かない。
      expect(find.text('6月7日（日）'), findsOneWidget);
      expect(find.text('6月14日（日）'), findsOneWidget);
      // 上の「休む日」と帯と小見出しも出る。
      expect(find.text('休む日'), findsOneWidget);
      expect(find.text(kBand), findsOneWidget);
      expect(find.text(kWorkHead), findsOneWidget);
    });

    testWidgets('★※2行がそのまま出る（週の両端は days[] の最初と最後から）',
        (tester) async {
      await _pump(
          tester,
          SubstituteRegisterScreen(
              restDate: '2026-06-13', service: _FakeSvc(days: _week())));

      expect(
          find.text('※同じ週（6月7日〜6月14日）の会社休みの日から選びます。'),
          findsOneWidget, reason: '1行目が原文どおりでない／両端が違う');
      expect(find.text('※出勤する日を決めないと登録できません。'), findsOneWidget);
    });

    testWidgets('★対照: days[] の両端が変われば※の日付も変わる（端末で週を数えていない）',
        (tester) async {
      final api = _FakeSvc(days: [
        _day(date: '2026-07-05', dow: 0),
        _day(date: '2026-07-11', dow: 6),
      ]);
      await _pump(tester,
          SubstituteRegisterScreen(restDate: '2026-07-08', service: api));

      expect(
          find.text('※同じ週（7月5日〜7月11日）の会社休みの日から選びます。'),
          findsOneWidget, reason: '両端を変えても文が変わらない＝決め打ちになっている');
    });
  });

  group('(3)(4) 選ぶまで押せない／選ぶとその内容で登録される', () {
    bool goEnabled(WidgetTester tester) =>
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, kRegisterGo))
            .onPressed !=
        null;

    testWidgets('★出勤する日を選ぶまで押せない → 選ぶと押せて、その内容で登録が呼ばれる',
        (tester) async {
      final api = _FakeSvc(days: _week());
      await _pump(tester,
          SubstituteRegisterScreen(restDate: '2026-06-13', service: api));

      expect(goEnabled(tester), isFalse,
          reason: '何も選ばずに押せてしまう（見た目だけ灰色にしている）');
      expect(api.registerCalls, isEmpty);

      // ★選べない日を押しても押せるようにならない。
      await tester.tap(find.text('6月8日（月）'));
      await tester.pumpAndSettle();
      expect(goEnabled(tester), isFalse, reason: '選べない日で選べたことにしている');

      // ★選べる日を押すと押せるようになる（対照）。
      await tester.tap(find.text('6月7日（日）'));
      await tester.pumpAndSettle();
      expect(goEnabled(tester), isTrue, reason: '選んでも押せない');

      await tester.tap(find.text(kRegisterGo));
      await tester.pumpAndSettle();
      expect(api.registerCalls, [
        {'rest_date': '2026-06-13', 'work_date': '2026-06-07'}
      ], reason: 'その休む日と出勤する日で登録していない');
    });

    testWidgets('★選び直すと、あとから選んだ日で登録される', (tester) async {
      final api = _FakeSvc(days: _week());
      await _pump(tester,
          SubstituteRegisterScreen(restDate: '2026-06-13', service: api));

      await tester.tap(find.text('6月7日（日）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6月14日（日）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kRegisterGo));
      await tester.pumpAndSettle();

      expect(api.registerCalls, [
        {'rest_date': '2026-06-13', 'work_date': '2026-06-14'}
      ], reason: '先に選んだ日で送っている');
    });
  });

  group('(5)(6) 断りの出し方', () {
    testWidgets('★登録が断られたら BE の文がそのまま出て、閉じるまで消えない',
        (tester) async {
      const beText = 'その日はすでに休みが入っています';
      final api = _FakeSvc(days: _week(), registerFail: beText);
      await _pump(tester,
          SubstituteRegisterScreen(restDate: '2026-06-13', service: api));

      await tester.tap(find.text('6月7日（日）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kRegisterGo));
      await tester.pumpAndSettle();

      expect(find.text(beText), findsOneWidget, reason: 'BE の文が出ていない');
      expect(find.text(kClose), findsOneWidget, reason: '閉じる道が無い');
      await tester.pump(const Duration(seconds: 6));
      expect(find.text(beText), findsOneWidget, reason: '時間で消えている');
      expect(find.text('X'), findsNothing, reason: '英字の code を出している');
    });

    testWidgets('★会社の休みの日が未設定の回は、候補を並べず BE の断りを出す',
        (tester) async {
      const beText = '会社の休みの日が設定されていません。事務にご確認ください';
      final api = _FakeSvc(
        holidayDefConfigured: false,
        days: [
          _day(date: '2026-06-07', dow: 0,
              selectable: false,
              reasonCode: 'holiday_def_not_configured', reason: beText),
        ],
      );
      await _pump(tester,
          SubstituteRegisterScreen(restDate: '2026-06-13', service: api));

      expect(find.text(beText), findsOneWidget, reason: 'BE の断りを出していない');
      expect(find.text('もう一度'), findsOneWidget, reason: '袋小路になっている');
      expect(find.text(kWorkHead), findsNothing, reason: '選べない候補を並べている');
      expect(find.text(kRegisterGo), findsNothing);
    });

    testWidgets('★対照: 休む日が会社の休みの日でも、端末は先回りして閉じない'
        '（断るのは口の仕事）', (tester) async {
      // rest_date_is_workday=false でも候補は出し、登録の道も開いたままにする。
      final api = _FakeSvc(days: _week(), restDateIsWorkday: false);
      await _pump(tester,
          SubstituteRegisterScreen(restDate: '2026-06-13', service: api));

      expect(find.text(kWorkHead), findsOneWidget,
          reason: '端末が先回りして候補を閉じている');
      await tester.tap(find.text('6月7日（日）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kRegisterGo));
      await tester.pumpAndSettle();
      expect(api.registerCalls.length, 1,
          reason: '端末が先回りして弾いている（断るのは BE の仕事）');
    });

    testWidgets('★対: 候補が取れなかった回は理由と「もう一度」が出る', (tester) async {
      const beText = 'サーバーに接続できません: 検査';
      await _pump(
          tester,
          SubstituteRegisterScreen(
              restDate: '2026-06-13',
              service: _FakeSvc(candidatesFail: beText)));
      expect(find.text(beText), findsOneWidget);
      expect(find.text('もう一度'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (7) カレンダーの箱
  // ══════════════════════════════════════════════════════════
  group('(7) カレンダーの箱の入口', () {
    Widget sheet({
      String? restPortion,
      String? restReason,
      String? substituteId,
      VoidCallback? onCompOff,
      VoidCallback? onSubstitute,
      VoidCallback? onOpenSubstitute,
    }) =>
        Scaffold(
          body: CalendarDaySheet(
            info: CalendarDayInfo(
              date: DateTime(2026, 6, 10),
              restPortion: restPortion,
              restReason: restReason,
            ),
            maxHeight: 900,
            onCompOff: onCompOff,
            substituteId: substituteId,
            onOpenSubstitute: onOpenSubstitute,
            onSubstitute: onSubstitute,
          ),
        );

    testWidgets('★休みが無い日の箱には「振替で休む」が出て、押すと呼ばれる',
        (tester) async {
      var tapped = 0;
      await _pump(tester, sheet(onSubstitute: () => tapped++));

      expect(find.text(kActSubstitute), findsOneWidget);
      await tester.tap(find.text(kActSubstitute));
      await tester.pumpAndSettle();
      expect(tapped, 1, reason: '押しても何も起きないボタンになっている');
    });

    testWidgets('★対照: 振替の日の箱には出ず、「振替休日を開く」が出る',
        (tester) async {
      await _pump(
          tester,
          sheet(
            restPortion: 'full',
            restReason: 'substitute',
            substituteId: 'rd_1',
            onOpenSubstitute: () {},
            onSubstitute: () {},
          ));

      expect(find.text(kActSubstitute), findsNothing,
          reason: '既に休みが在る日に、必ず断られる入口を出している');
      expect(find.text(kOpenSub), findsOneWidget,
          reason: '既に在る振替を見る道が無い');
    });

    testWidgets('★対照: 代休の入口の出方は今までどおり（振替と同じ条件で並ぶ）',
        (tester) async {
      await _pump(tester, sheet(onCompOff: () {}, onSubstitute: () {}));
      expect(find.text(kActCompOff), findsOneWidget,
          reason: '代休の入口が消えている');
      expect(find.text(kActSubstitute), findsOneWidget);

      // ★対: 休みが在る日には代休も振替も出ない（同じ条件で並んでいる）。
      await _pump(tester,
          sheet(restPortion: 'full', onCompOff: () {}, onSubstitute: () {}));
      expect(find.text(kActCompOff), findsNothing);
      expect(find.text(kActSubstitute), findsNothing);
    });
  });
}
