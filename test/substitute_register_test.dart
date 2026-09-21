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
// ★代休の受け皿の差し替え口（test/comp_off_flow_test.dart と同じ使い方）。
import 'package:js_awake_app/widgets/comp_off_dialog.dart'
    show compOffServiceFactory;

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
    this.restDateReasonCode,
    this.restDateReason,
    this.registerFailCode,
    this.registerFailPastDates,
    this.failOnlyWithoutPriorAgreement = false,
  }) : super.forTest();

  final List<Map<String, dynamic>> days;
  final bool holidayDefConfigured;
  final bool restDateIsWorkday;
  final String? candidatesFail;
  final String? registerFail;
  // ★休む日そのものが断られる回（BE が応答の頭に載せる2つ）。
  final String? restDateReasonCode;
  final String? restDateReason;
  // ★断りの符号と past_dates（BE が数えた過去の日）。
  final String? registerFailCode;
  final List<String>? registerFailPastDates;
  // ★prior_agreement を付けて出し直したときだけ通す（1回目は断る）。
  final bool failOnlyWithoutPriorAgreement;

  final List<String> candidateCalls = [];
  final List<Map<String, String>> registerCalls = [];
  /// 送った body そのもの（キーが有るか無いかを数で見るため）。
  final List<Map<String, dynamic>> registerBodies = [];

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
        'rest_date_reason_code': restDateReasonCode,
        'rest_date_reason': restDateReason,
        'holiday_def_configured': holidayDefConfigured,
        'days': days,
      },
    );
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> registerSubstitute(
      String restDate, String pairedWorkDate,
      {bool priorAgreement = false}) async {
    registerCalls.add({'rest_date': restDate, 'work_date': pairedWorkDate});
    // ★送る形そのものを数える。実装の組み立て（substituteRegisterBody）を
    //   通して記録するので、キーが入る／入らないをここで作り直さない。
    registerBodies.add(ReportsService.substituteRegisterBody(
        restDate, pairedWorkDate, priorAgreement: priorAgreement));
    // ★出し直し（prior_agreement: true）だけ通す回。
    if (failOnlyWithoutPriorAgreement && priorAgreement) {
      return apiSuccess<Map<String, dynamic>>(
          statusCode: 201, data: const {'pending_agreement': false});
    }
    return registerFail == null
        ? apiSuccess<Map<String, dynamic>>(
            statusCode: 201,
            data: const {'pending_agreement': false})
        : apiFailure<Map<String, dynamic>>(
            statusCode: 409,
            errorMessage: registerFail,
            errorCode: registerFailCode ?? 'X',
            errorDetails: registerFailPastDates == null
                ? null
                : {'past_dates': registerFailPastDates});
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

  // ══════════════════════════════════════════════════════════
  // (8) 過去の日が入っていた回（モック A1・A2）
  //   ★どの日が過去かは端末で数えない。BE の 409
  //     SUBSTITUTE_PRIOR_AGREEMENT_REQUIRED と本文の past_dates だけで動く。
  //   ★期待値（符号・文言）はこの本の中に直書きする（掟F-3）。
  // ══════════════════════════════════════════════════════════
  group('(8) 過去の日が入っていた回', () {
    const restDate = '2026-06-13'; // 土（dow 6）… 休む日
    const workDate = '2026-06-07'; // 日（dow 0）… 出勤する日
    const kAgreed   = '取り決めていた（登録する）';
    const kNotAgreed= '取り決めていない';
    const kCompOff  = '代休で取る';
    const kPickAgain= '日を選び直す';
    const kAskHead  = '過去の日が入っています';
    const kRefuseHead = '振替休日にはできません';
    const kAsk      = '事前に会社と取り決めていましたか？';
    const kPriorDeny = '過去の日を含む振替は、事前に会社と取り決めていた場合に限り登録できます';

    // 画面を【押して】ここまで来る道具。選んでから「この内容で登録する」を押す。
    //   ★閉じたときの返りは [popped] へ後から入る（押した時点ではまだ閉じていないので、
    //     ここで受け取って返すと必ず null になる）。呼び手はタップを済ませてから読む。
    Future<void> pushAndRegister(
        WidgetTester tester, _FakeSvc api, List<bool?> popped) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) => ElevatedButton(
          onPressed: () async {
            popped.add(await Navigator.of(ctx).push<bool>(MaterialPageRoute(
              builder: (_) => SubstituteRegisterScreen(
                  restDate: restDate, service: api))));
          },
          child: const Text('開く'),
        )),
      ));
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6月7日（日）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kRegisterGo));
      await tester.pumpAndSettle();
    }

    _FakeSvc priorRequired({List<String>? pastDates, bool passOnRetry = false}) =>
        _FakeSvc(
          days: _week(),
          registerFail: kPriorDeny,
          registerFailCode: 'SUBSTITUTE_PRIOR_AGREEMENT_REQUIRED',
          registerFailPastDates: pastDates ?? const [workDate],
          failOnlyWithoutPriorAgreement: passOnRetry,
        );

    testWidgets('★送る形: priorAgreement なしはキー自体が無い／true なら入る',
        (tester) async {
      final without =
          ReportsService.substituteRegisterBody(restDate, workDate);
      final with_ = ReportsService.substituteRegisterBody(restDate, workDate,
          priorAgreement: true);
      expect(without.containsKey('prior_agreement'), isFalse,
          reason: '答えていない回にキーを送っている（送る形が変わっている）');
      expect(without, {'rest_date': restDate, 'paired_work_date': workDate});
      expect(with_['prior_agreement'], isTrue);
      expect(with_.keys.toList(),
          ['rest_date', 'paired_work_date', 'prior_agreement']);
    });

    testWidgets('★409 で A1 が出る（文に「出勤する日 M月D日（曜）」が入る）',
        (tester) async {
      final api = priorRequired();
      await pushAndRegister(tester, api, <bool?>[]);

      expect(find.text(kAskHead), findsOneWidget, reason: 'A1 が出ていない');
      expect(find.text(kAsk), findsOneWidget);
      expect(find.text(kAgreed), findsOneWidget);
      expect(find.text(kNotAgreed), findsOneWidget);
      // ★過去の日は past_dates のぶんだけ・ラベルつきで出る。
      expect(find.textContaining('出勤する日 6月7日（日）'), findsWidgets,
          reason: '過去の日が BE の past_dates どおりに出ていない');
      expect(find.textContaining('休む日 6月13日（土）は過去'), findsNothing,
          reason: '過去でない休む日まで過去として並べている');
    });

    testWidgets('★2つのときは「休む日 …と出勤する日 …」の順で並ぶ', (tester) async {
      final api = priorRequired(pastDates: const [restDate, workDate]);
      await pushAndRegister(tester, api, <bool?>[]);

      final span = tester.widget<Text>(find.byWidgetPredicate((w) =>
          w is Text && (w.textSpan?.toPlainText() ?? '').contains('は過去の日です')));
      final plain = span.textSpan!.toPlainText();
      expect(plain.startsWith('休む日 6月13日（土）と出勤する日 6月7日（日）は過去の日です。'),
          isTrue, reason: '並びかラベルが違う: $plain');
    });

    testWidgets('★「取り決めていた（登録する）」→ 2回目が prior_agreement: true で送られ、通れば閉じる',
        (tester) async {
      final api = priorRequired(passOnRetry: true);
      final popped = <bool?>[];
      await pushAndRegister(tester, api, popped);
      expect(api.registerBodies.length, 1, reason: '1回目が送られていない');

      await tester.tap(find.text(kAgreed));
      await tester.pumpAndSettle();

      expect(api.registerBodies.length, 2, reason: '出し直していない');
      expect(api.registerBodies[0].containsKey('prior_agreement'), isFalse,
          reason: '1回目に答えを付けている');
      expect(api.registerBodies[1]['prior_agreement'], isTrue,
          reason: '2回目に答えが付いていない');
      expect(api.registerBodies[1]['rest_date'], restDate);
      expect(api.registerBodies[1]['paired_work_date'], workDate,
          reason: '出し直しで日が変わっている');
      expect(popped, [true], reason: '通ったのに画面が true で閉じていない');
    });

    testWidgets('★「取り決めていない」→ A2 に切り替わる（A1 の問いは消える）',
        (tester) async {
      final api = priorRequired();
      await pushAndRegister(tester, api, <bool?>[]);

      await tester.tap(find.text(kNotAgreed));
      await tester.pumpAndSettle();

      expect(find.text(kRefuseHead), findsOneWidget, reason: 'A2 になっていない');
      expect(find.text(kCompOff), findsOneWidget);
      expect(find.text(kPickAgain), findsOneWidget);
      expect(find.text(kAsk), findsNothing, reason: 'A1 の問いが残っている');
    });

    testWidgets('★A2「日を選び直す」→ 登録の画面に戻り、選んだ日が消えている',
        (tester) async {
      final api = priorRequired();
      await pushAndRegister(tester, api, <bool?>[]);
      await tester.tap(find.text(kNotAgreed));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kPickAgain));
      await tester.pumpAndSettle();

      expect(find.text(kWorkHead), findsOneWidget, reason: '登録の画面に戻っていない');
      final go = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, kRegisterGo));
      expect(go.onPressed, isNull, reason: '選んだ日が消えていない（押せたまま）');
      expect(api.registerBodies.length, 1, reason: '勝手に出し直している');
    });

    testWidgets('★A2「代休で取る」→ 代休の流れが呼ばれる（差し替えで確かめる）',
        (tester) async {
      final compOff = _FakeCompOffSvc();
      compOffServiceFactory = () => compOff;
      addTearDown(() => compOffServiceFactory = ReportsService.new);

      final api = priorRequired();
      await pushAndRegister(tester, api, <bool?>[]);
      await tester.tap(find.text(kNotAgreed));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCompOff));
      await tester.pumpAndSettle();

      expect(compOff.availableCalls, [restDate],
          reason: '代休の流れが、この休む日で呼ばれていない');
    });

    testWidgets('★対照: ほかの 409 では A1 が出ず、今までどおりの断りの箱',
        (tester) async {
      final api = _FakeSvc(
        days: _week(),
        registerFail: '6月7日の日報がありません',
        registerFailCode: 'SUBSTITUTE_WORK_DATE_NO_REPORT',
      );
      await pushAndRegister(tester, api, <bool?>[]);

      expect(find.text(kAskHead), findsNothing, reason: 'A1 を出している');
      expect(find.text('登録できませんでした'), findsOneWidget,
          reason: '今までどおりの断りの箱が出ていない');
      expect(find.text('6月7日の日報がありません'), findsOneWidget,
          reason: 'BE の文をそのまま出していない');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (9) 休む日そのものが断られている回（応答の頭の2つ）
  // ══════════════════════════════════════════════════════════
  group('(9) 休む日そのものが断られている回', () {
    testWidgets('★rest_date_reason_code があれば候補も登録のボタンも出さず、BE の文を出す',
        (tester) async {
      const reason = '今週より前の日は選べません';
      await _pump(
        tester,
        SubstituteRegisterScreen(
          restDate: '2026-06-13',
          service: _FakeSvc(
            days: _week(),
            restDateReasonCode: 'past_out_of_week',
            restDateReason: reason,
          ),
        ),
      );

      expect(find.text(reason), findsOneWidget, reason: 'BE の文が出ていない');
      expect(find.text(kRegisterGo), findsNothing,
          reason: '登録のボタンを出している（どの日を選んでも断られる）');
      expect(find.text(kWorkHead), findsNothing, reason: '候補を並べている');
      expect(find.text('6月7日（日）'), findsNothing);
      // ★休む日の行は今までどおり出す（何の話かが分かるように）。
      expect(find.text('休む日'), findsOneWidget);
      expect(find.text('6月13日（土）'), findsNothing,
          reason: '休む日の行に曜日を付けている（今までは M月D日 だけ）');
      expect(find.text('6月13日'), findsOneWidget);
    });

    testWidgets('★対照: null なら今までどおり候補も登録のボタンも出る', (tester) async {
      await _pump(
        tester,
        SubstituteRegisterScreen(
            restDate: '2026-06-13', service: _FakeSvc(days: _week())),
      );
      expect(find.text(kRegisterGo), findsOneWidget);
      expect(find.text(kWorkHead), findsOneWidget);
      expect(find.text('6月7日（日）'), findsOneWidget);
    });
  });
}

/// 代休の受け皿（showCompOffFlow）の差し替え。★呼ばれたことだけを数える。
///   取れなかった道で止める（この本が見たいのは「呼ばれたか」であって代休の中身ではない）。
class _FakeCompOffSvc extends ReportsService {
  _FakeCompOffSvc() : super.forTest();
  final List<String> availableCalls = [];

  @override
  Future<ApiResult<CompOffAvailable>> getCompOffAvailable({String? asOf}) async {
    availableCalls.add(asOf ?? '');
    return apiFailure<CompOffAvailable>(
        statusCode: 0, errorMessage: 'サーバーに接続できませんでした');
  }
}
