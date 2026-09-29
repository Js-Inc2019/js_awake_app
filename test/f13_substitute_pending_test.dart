// ============================================================
// test/f13_substitute_pending_test.dart
//   便F13（事務が持ちかけた振替休日の同意待ちの見え方）を機械で固定する。
//   ボス裁定【Q109】＝１・【Q111】＝１（見本 v1）・【Q112】＝２（待ちの色＝橙）。
//
//   (a) P1  ホームの同意待ちの枠（pendingSubstituteRestDayId があるときだけ）
//   (b) P2  本日休みの _submit の分かれ（409 を符号を問わず成功にしない）
//   (c)     代休・振替の道の［振替休日を開く］（断りの窓・休む日の断り）
//   (d) P3  打刻の催促の窓の枠（窓は閉じない）
//   (e) K1〜K3・A4  カレンダーの輪と箱の行
//   (f)     月送りの ‹ › ↻ の押せる大きさと帯の高さ
//   (g)     getRestDayToday が pending_substitute_rest_day_id を読み分ける
//   (h)     読み直しの知らせ（鳴らす所と聞く所・二者比較）
//   (i)     状態の色（振替の待ちの色の置き場は1か所・値は今と同じ橙）
//   →再（2026-09-30・便F13続）: 名乗ったことを確かめる形に直し、次を足した:
//   (a) 本物のテーマ（AppTheme.dark）の下での P1 のボタンの形と素の OutlinedButton の二者比較・
//       P1 の枠の線・P1 の枠の上下の間
//   (c) 代休の断りの窓の［振替休日を開く］は最初の画面の上に1件だけ残す・登録の画面の断りの窓から
//       戻ると候補を引き直す
//   (h) 鳴らし漏れ（7か所）: 答えが返る前に画面や窓を閉じても通れば1回鳴る・閉じずに通っても1回だけ・
//       通らなければ鳴らない
//   (j) カレンダーの注意バー（振替の日付の失敗・［再試行］の大きさ）
//
// ★色は 16進の生の値で書く（前例 test/calendar_day_sheet_test.dart の★「色は 16進の生の値で書く」と
//   _kPending）。定数を import して比べると、定数の値が差し替わったときに気付けない。
// ★差し替え口は今ある形だけを使う（RestDayScreen などの service 引数・PunchScreen の reports・
//   compOffServiceFactory・package:http の runWithClient＋MockClient）。
// ★BE の形は便B17（js-office-api の 999cca0）の実物に合わせてここに直書きする。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' show min, max;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/core/theme/app_theme.dart';
import 'package:js_awake_app/screens/home_screen.dart'
    show CalendarTab, CalendarDaySheet, CalendarDayInfo;
import 'package:js_awake_app/screens/punch_screen.dart';
import 'package:js_awake_app/screens/rest_day_done_screen.dart';
import 'package:js_awake_app/screens/rest_day_screen.dart';
import 'package:js_awake_app/screens/substitute_change_screen.dart';
import 'package:js_awake_app/screens/substitute_detail_screen.dart';
import 'package:js_awake_app/screens/substitute_list_screen.dart'
    show substituteStateColor;
import 'package:js_awake_app/screens/substitute_register_screen.dart';
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';
import 'package:js_awake_app/utils/rest_day_refresh.dart';
import 'package:js_awake_app/widgets/comp_off_dialog.dart';
import 'package:js_awake_app/widgets/punch_remind_dialog.dart';

// ── 期待する色（16進の生の値。トークン名では書かない）──────────────
const int _kWait = 0xFFE0603A;      // 振替の待ち（同意待ち・事務の確認待ち）＝日報の未承認と同じ橙
const int _kError = 0xFFE05252;     // 成立できません
const int _kSuccess = 0xFF6FD6B4;   // 成立
const int _kSupport = 0xFF7B7567;   // 取消済み・［閉じる］（窓に［振替休日を開く］がある回）
const int _kAccent = 0xFF6FD6B4;    // 休みの輪・［振替休日を開く］（断りの窓）
const int _kBody = 0xFFEAE3D0;      // 本文色（P1 のボタンの字）

// ── BE の文（便B17 の services/substituteAgreement.js の pendingOnDateText の本人の文）──
String _selfText(String md) =>
    '$md は、事務から持ちかけられた振替休日の同意待ちです。休むときは、この振替に同意してください。'
    '振替にしないで休むときは、事務へご連絡ください。';

// 断りの本文（409 SUBSTITUTE_PENDING_ON_DATE・便B17 の pendingOnDateBody の形）。
Map<String, dynamic> _pendingBody({
  String id = 'rd-p',
  String restDate = '2026-11-11',
  String workDate = '2026-11-14',
  String md = '11月11日',
}) =>
    {
      'error': _selfText(md),
      'code': 'SUBSTITUTE_PENDING_ON_DATE',
      'rest_day_id': id,
      'rest_date': restDate,
      'paired_work_date': workDate,
    };

ApiResult<T> _pendingFailure<T>({String id = 'rd-p', String md = '11月11日'}) =>
    apiFailure<T>(
      statusCode: 409,
      errorMessage: _selfText(md),
      errorCode: 'SUBSTITUTE_PENDING_ON_DATE',
      errorDetails: _pendingBody(id: id, md: md),
    );

/// 差し替える口。★実 HTTP へ行かせず、何を何回叩いたかも数える。
class _Fake extends ReportsService {
  _Fake({
    this.pendingId,
    this.createResult,
    this.updateOk = true,
    this.candidatesBody,
    this.registerResult,
    this.rested = false,
    this.detailPending = true,
  }) : super.forTest();

  /// getRestDayToday の rested（便F13続・日報の入口の取り消しの検査で true）。
  final bool rested;

  /// getRestDay の pending_agreement（便F13続・変更の画面へ進む検査で false＝成立）。
  final bool detailPending;

  final String? pendingId;
  final ApiResult<RestDayMutation>? createResult;
  final bool updateOk;
  final Map<String, dynamic>? candidatesBody;
  final ApiResult<Map<String, dynamic>>? registerResult;

  int todayCalls = 0;
  int candidatesCalls = 0;
  final List<String> detailCalls = [];

  @override
  Future<ApiResult<RestDayToday>> getRestDayToday() async {
    todayCalls++;
    return apiSuccess<RestDayToday>(
      statusCode: 200,
      data: RestDayToday(
        rested: rested,
        reason: null,
        portion: 'full',
        pendingSubstituteRestDayId: pendingId,
      ),
    );
  }

  @override
  Future<ApiResult<RestDayMutation>> createRestDay({
    String? reason,
    String portion = 'full',
    String? restDate,
  }) async =>
      createResult ??
      apiSuccess<RestDayMutation>(
        statusCode: 201,
        data: const RestDayMutation(restDate: '2026-11-11', reason: null, cancelled: false),
      );

  @override
  Future<ApiResult<RestDayMutation>> updateRestDay(
          {String? reason, String portion = 'full'}) async =>
      updateOk
          ? apiSuccess<RestDayMutation>(
              statusCode: 200,
              data: RestDayMutation(restDate: '2026-11-11', reason: reason, cancelled: false))
          : apiFailure<RestDayMutation>(
              statusCode: 409,
              errorMessage: '代休と振替休日は、区分と理由を変えられません。',
              errorCode: 'PAIRED_REST_NOT_EDITABLE');

  @override
  Future<ApiResult<RestDayMutation>> deleteRestDay() async =>
      apiSuccess<RestDayMutation>(
        statusCode: 200,
        data: const RestDayMutation(restDate: '2026-11-11', reason: null, cancelled: true),
      );

  @override
  Future<ApiResult<Map<String, dynamic>>> getRestDay(String id) async {
    detailCalls.add(id);
    return apiSuccess<Map<String, dynamic>>(
      statusCode: 200,
      data: {
        'rest_day': {
          'id': id,
          'rest_date': '2026-11-11',
          'paired_work_date': '2026-11-14',
          'pending_agreement': detailPending,
          'cancelled_at': null,
        },
        'events': const <Map<String, dynamic>>[],
      },
    );
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> getSubstituteWorkDateCandidates(
      String restDate) async {
    candidatesCalls++;
    // ★BE の本文を【取り込みの関数そのもの】に通してから画面へ渡す（前例 test/f7_decision_keys_test.dart）。
    return apiSuccess<Map<String, dynamic>>(
      statusCode: 200,
      data: ReportsService.substituteCandidatesFromBody(jsonEncode(candidatesBody ?? {})),
    );
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> registerSubstitute(
          String restDate, String pairedWorkDate,
          {bool priorAgreement = false}) async =>
      registerResult ??
      apiSuccess<Map<String, dynamic>>(
          statusCode: 201, data: const {'pending_agreement': false});

  @override
  Future<ApiResult<Map<String, dynamic>>> getMySubstitutes() async =>
      apiSuccess<Map<String, dynamic>>(
          statusCode: 200, data: const {'rows': [], 'truncated': false});
}

/// 選べる出勤する日が1日（11月14日（土））の候補の口の本文（便F13続）。
const Map<String, dynamic> _oneDayCandidates = {
  'rest_date': '2026-11-11',
  'rest_date_is_workday': true,
  'rest_date_reason_code': null,
  'rest_date_reason': null,
  'rest_date_pending_substitute_id': null,
  'holiday_def_configured': true,
  'days': [
    {'date': '2026-11-14', 'dow': 6, 'selectable': true, 'reason_code': null, 'reason': null},
  ],
};

/// 代休の口（compOffServiceFactory で差し替える）。
class _CompOffFake extends ReportsService {
  _CompOffFake() : super.forTest();

  @override
  Future<ApiResult<CompOffAvailable>> getCompOffAvailable({String? asOf}) async =>
      apiSuccess<CompOffAvailable>(
        statusCode: 200,
        data: CompOffAvailable(
          asOf: asOf,
          remainingDays: 1,
          candidates: const [
            CompOffCandidate(
                id: 'L1', sourceWorkDate: '2026-11-01', remainingDays: 1, expiresAt: null),
          ],
          undecidedNotice: null,
        ),
      );

  @override
  Future<ApiResult<CompOffTaken>> takeCompOff({
    required String restDate,
    String? sourceWorkDate,
    bool undecided = false,
    String portion = 'full',
  }) async =>
      _pendingFailure<CompOffTaken>();
}

Future<void> _pump(WidgetTester tester, Widget screen,
    {Size size = const Size(1200, 2600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

/// 本物のテーマ（AppTheme.dark）の下で立てる（便F13続・(a) の★）。
Future<void> _pumpThemed(WidgetTester tester, Widget screen,
    {Size size = const Size(1200, 2600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: screen));
  await tester.pumpAndSettle();
}

/// P1 の枠（左の線が3の Container）。
Finder _pendingBox() => find.ancestor(
    of: find.text('同意待ち'),
    matching: find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).border as Border?)?.left.width == 3));

Border _pendingBoxBorder(WidgetTester tester) =>
    (tester.widget<Container>(_pendingBox()).decoration as BoxDecoration).border! as Border;

/// 枠の線の外側（margin を含まない＝DecoratedBox）の位置。
Rect _pendingBoxRect(WidgetTester tester) => tester.getRect(
    find.descendant(of: _pendingBox(), matching: find.byType(DecoratedBox)).first);

/// その行の文の全部が見えているか（便F13続・K2 と K3）。
///   ★（元）RenderParagraph の didExceedMaxLines だけを見ていた＝maxLines を付けて切る作りなら赤だが、
///     maxLines を使わずに切る作り（softWrap: false・行の高さを1行分に固めて2行目を隠す）は通っていた。
///   →再（2026-09-30・便F13続）: 同じ文と同じ幅で折り返したときの高さ（行の数のぶん）を測り、
///     文の箱と、それを入れた行（Row）がその高さを持つことも見る。
void _expectWholeTextVisible(WidgetTester tester, Finder f) {
  final p = tester.renderObject<RenderParagraph>(
      find.descendant(of: f, matching: find.byType(RichText)));
  expect(p.didExceedMaxLines, isFalse, reason: '393 幅で切れている（maxLines）');
  final tp = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    locale: p.locale,
    strutStyle: p.strutStyle,
    textWidthBasis: p.textWidthBasis,
    textHeightBehavior: p.textHeightBehavior,
  )..layout(maxWidth: p.size.width);
  final lines = tp.computeLineMetrics().length;
  final need = tp.height;
  tp.dispose();
  final row = find.ancestor(of: f, matching: find.byType(Row)).first;
  // ignore: avoid_print
  print('「${p.text.toPlainText()}」: 折り返すと $lines 行・要る高さ $need・文の箱 ${p.size.height}・行 ${tester.getSize(row).height}');
  expect(p.size.height, greaterThanOrEqualTo(need - 0.01),
      reason: '文の全部（$lines 行）の高さで描いていない（1行に固めて切っている）');
  expect(tester.getSize(row).height, greaterThanOrEqualTo(need - 0.01),
      reason: '行の高さが文の全部（$lines 行）に足りない（2行目を隠している）');
}

/// 描いた物を記録する Canvas（便F13続・K1 の点線の輪）。★数えるのは丸と線だけ。ほかの描き方は何もしない。
class _RecordingCanvas implements Canvas {
  final List<({Offset center, double radius, PaintingStyle style, Color color})> circles = [];
  int paths = 0;

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add((center: c, radius: radius, style: paint.style, color: paint.color));

  @override
  void drawPath(Path path, Paint paint) => paths++;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => paths++;

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) =>
      paths++;

  @override
  void drawOval(Rect rect, Paint paint) => paths++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Color _textColorOf(WidgetTester tester, String text) {
  final rich = tester.widget<RichText>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)).first);
  return rich.text.style!.color!;
}

void main() {
  // ══════════════════════════════════════════════════════════
  // (a) P1 ホームの同意待ちの枠
  // ══════════════════════════════════════════════════════════
  group('(a) P1 ホームの同意待ちの枠', () {
    setUp(() => SharedPreferences.setMockInitialValues(const {}));

    // ★UniqueKey＝同じ型を続けて立てても State を使い回さない（差し替えた口が効く）。
    Widget punch(_Fake f) => PunchScreen(
          key: UniqueKey(),
          reports: f,
          shiftType: 'day',
          onShiftTypeChanged: (_) {},
        );

    testWidgets('★pendingSubstituteRestDayId があるときだけ枠が出る・文は一字一句・本日休みは「本日休み」のまま',
        (tester) async {
      await _pump(tester, punch(_Fake()));
      expect(find.text('同意待ち'), findsNothing, reason: 'id が無いのに枠が出ている');

      await _pump(tester, punch(_Fake(pendingId: 'rd-9')));
      expect(find.text('同意待ち'), findsOneWidget);
      expect(find.text('今日は、事務から持ちかけられた振替休日の休む日です。'), findsOneWidget);
      expect(find.text('同意すると、今日は休みになります。'), findsOneWidget);
      expect(find.text('振替休日を開く'), findsOneWidget);
      expect(find.text('本日休み'), findsOneWidget, reason: '同意待ちの日に「登録済み」を出している');
      expect(find.textContaining('登録済み'), findsNothing);
      // 札の字は待ちの色（16進で照合）。
      expect(_textColorOf(tester, '同意待ち').toARGB32(), _kWait);
    });

    // ★（元）MaterialApp(home: …) の既定のテーマで測っていた。既定のテーマの OutlinedButton はもともと
    //   幅いっぱいにならないので、SubstituteOpenButton が幅を上書きしなくても通っていた。
    //   →再（2026-09-30・便F13続）: 本物のテーマ（lib/core/theme/app_theme.dart の AppTheme.dark・
    //   lib/main.dart の theme）の下で測る。職人アプリの検査で AppTheme を使うのはここが初めて。
    //   理由: テーマの OutlinedButton の既定（幅いっぱい・高さ52・字 accent）を SubstituteOpenButton が
    //   上書きすることを確かめるため。同じテーマの素の OutlinedButton が幅いっぱいになることも同じ検査で
    //   測る（二者比較＝上書きしない作りなら、P1 のボタンも幅いっぱいになって赤）。
    testWidgets('★ボタンは本物のテーマの下で高さ44・字は本文色・幅は字の幅（素の OutlinedButton は幅いっぱい）・押すとその id の1件が開く',
        (tester) async {
      final f = _Fake(pendingId: 'rd-9');
      await _pumpThemed(tester, punch(f));
      final btn = find.widgetWithText(OutlinedButton, '振替休日を開く');
      final size = tester.getSize(btn);
      // ignore: avoid_print
      print('P1 の［振替休日を開く］の大きさ（AppTheme.dark）: $size');
      expect(size.height, 44, reason: 'テーマの既定の高さ52のまま');
      expect(size.width, lessThan(600), reason: '幅いっぱい（テーマの既定）のまま');
      expect(_textColorOf(tester, '振替休日を開く').toARGB32(), _kBody,
          reason: '字がテーマの既定の accent のまま');

      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(find.byType(SubstituteDetailScreen), findsOneWidget);
      expect(f.detailCalls, ['rd-9']);

      // 対照: 同じテーマの素の OutlinedButton は幅いっぱい（1200）になる。
      await tester.pumpWidget(const SizedBox());
      await _pumpThemed(
          tester,
          Scaffold(
            body: Column(children: [
              OutlinedButton(onPressed: () {}, child: const Text('素')),
              Align(
                alignment: Alignment.centerLeft,
                child: SubstituteOpenButton(onPressed: () {}),
              ),
            ]),
          ));
      final plain = tester.getSize(find.widgetWithText(OutlinedButton, '素'));
      final open = tester.getSize(find.widgetWithText(OutlinedButton, '振替休日を開く'));
      // ignore: avoid_print
      print('AppTheme.dark の素の OutlinedButton: $plain ／ SubstituteOpenButton: $open');
      expect(plain.width, 1200, reason: 'テーマの既定が幅いっぱいでない（比べる相手になっていない）');
      expect(plain.height, 52);
      expect(open.width, lessThan(plain.width));
    });

    testWidgets('★枠の線は上・右・下が太さ1・左が3・色はどれも待ちの色', (tester) async {
      await _pumpThemed(tester, punch(_Fake(pendingId: 'rd-9')));
      final border = _pendingBoxBorder(tester);
      for (final s in [border.top, border.right, border.bottom]) {
        expect(s.width, 1);
        expect(s.color.toARGB32(), _kWait);
      }
      expect(border.left.width, 3);
      expect(border.left.color.toARGB32(), _kWait);
    });

    // ★見本 v1 の P1（.screen{gap:14px}）。（便F13続）
    testWidgets('★枠の上の間14・承認待ちの行が続く回は枠の下の間14・続かない回は次の塊まで28', (tester) async {
      Widget punchWith({required int approvals}) => PunchScreen(
            key: UniqueKey(),
            reports: _Fake(pendingId: 'rd-9'),
            shiftType: 'day',
            onShiftTypeChanged: (_) {},
            substituteCount: 1,
            pendingApprovalCount: approvals,
          );
      Finder rowOf(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_AttentionRow'));

      await _pumpThemed(tester, punchWith(approvals: 1));
      var box = _pendingBoxRect(tester);
      final above = tester.getRect(rowOf('振替休日'));
      final below = tester.getRect(rowOf('承認待ち'));
      // ignore: avoid_print
      print('P1 の枠: 上の間=${box.top - above.bottom} 下の間（承認待ちの行まで）=${below.top - box.bottom}');
      expect(box.top - above.bottom, 14);
      expect(below.top - box.bottom, 14);

      await tester.pumpWidget(const SizedBox());
      await _pumpThemed(tester, punchWith(approvals: 0));
      box = _pendingBoxRect(tester);
      final next = tester.getRect(find
          .byWidgetPredicate((w) => w.runtimeType.toString() == '_StatusSection')
          .first);
      // ignore: avoid_print
      print('P1 の枠: 続かない回の下の間（次の塊まで）=${next.top - box.bottom}');
      expect(next.top - box.bottom, 28);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (b) P2 本日休みの _submit
  // ══════════════════════════════════════════════════════════
  group('(b) P2 本日休みの _submit', () {
    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.text('休みを登録する'));
      await tester.pumpAndSettle();
    }

    testWidgets('★SUBSTITUTE_PENDING_ON_DATE → 断りの窓（題・BE の文・2つの押す物）で、完了の画面へ進まない',
        (tester) async {
      await _pump(tester,
          RestDayScreen(service: _Fake(createResult: _pendingFailure<RestDayMutation>())));
      await submit(tester);
      expect(find.byType(RestDayDoneScreen), findsNothing, reason: '断られたのに完了の画面へ進んだ');
      expect(find.text('休みを登録できませんでした'), findsOneWidget);
      expect(find.text(_selfText('11月11日')), findsOneWidget);
      expect(find.text('閉じる'), findsOneWidget);
      expect(find.text('振替休日を開く'), findsOneWidget);
      expect(_textColorOf(tester, '閉じる').toARGB32(), _kSupport);
      expect(_textColorOf(tester, '振替休日を開く').toARGB32(), _kAccent);
      for (final t in ['閉じる', '振替休日を開く']) {
        final s = tester.getSize(find.widgetWithText(TextButton, t));
        // ignore: avoid_print
        print('P2 の窓の［$t］の大きさ: $s');
        expect(s.height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('★［振替休日を開く］は窓と本日休みの画面を閉じてホームへ戻してから1件を開く', (tester) async {
      final f = _Fake(createResult: _pendingFailure<RestDayMutation>());
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => RestDayScreen(service: f))),
              child: const Text('ホーム'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ホーム'));
      await tester.pumpAndSettle();
      await submit(tester);
      await tester.tap(find.text('振替休日を開く'));
      await tester.pumpAndSettle();
      expect(find.byType(SubstituteDetailScreen), findsOneWidget);
      expect(find.byType(RestDayScreen), findsNothing, reason: '本日休みの画面が残っている');
      expect(f.detailCalls, ['rd-p']);
      // 1件の画面から戻るとホーム。
      Navigator.of(tester.element(find.byType(SubstituteDetailScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.text('ホーム'), findsOneWidget);
    });

    testWidgets('★ALREADY_RESTED → 完了の画面へ進まず、BE の文を snackbar に出す', (tester) async {
      await _pump(
          tester,
          RestDayScreen(
              service: _Fake(
                  createResult: apiFailure<RestDayMutation>(
                      statusCode: 409,
                      errorMessage: '本日は既に休みとして登録済みです',
                      errorCode: 'ALREADY_RESTED'))));
      await submit(tester);
      expect(find.byType(RestDayDoneScreen), findsNothing);
      expect(find.text('本日は既に休みとして登録済みです'), findsOneWidget);
    });

    testWidgets('★ほかの 409 → 完了の画面へ進まず snackbar（409 を符号を問わず成功にしない）', (tester) async {
      await _pump(
          tester,
          RestDayScreen(
              service: _Fake(
                  createResult: apiFailure<RestDayMutation>(
                      statusCode: 409, errorMessage: 'ほかの断り', errorCode: 'OTHER'))));
      await submit(tester);
      expect(find.byType(RestDayDoneScreen), findsNothing);
      expect(find.text('ほかの断り（409）'), findsOneWidget);
    });

    testWidgets('対照: ok → 完了の画面', (tester) async {
      await _pump(tester, RestDayScreen(service: _Fake()));
      await submit(tester);
      expect(find.byType(RestDayDoneScreen), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (c) 代休・振替の道
  // ══════════════════════════════════════════════════════════
  group('(c) 代休・振替の道', () {
    // ★（元）setUp が無く、前の group が入れた SharedPreferences の値に頼っていた。
    //   →再（2026-09-30・便F13続）: この group だけを走らせても通るよう、要る値を自分で入れる
    //   （1件の画面を差し替え口なしで開く道が、口の手前で auth_token を読むため）。
    setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'T'}));
    tearDown(() => compOffServiceFactory = ReportsService.new);

    testWidgets('★代休: SUBSTITUTE_PENDING_ON_DATE で断りの窓に［振替休日を開く］が出て、押すと1件が開く',
        (tester) async {
      compOffServiceFactory = _CompOffFake.new;
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showCompOffFlow(ctx, restDate: '2026-11-11'),
              child: const Text('代休'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('代休'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-11-01 の出勤'));
      await tester.pumpAndSettle();
      expect(find.text('代休を登録できませんでした'), findsOneWidget);
      expect(find.text(_selfText('11月11日')), findsOneWidget);
      expect(find.text('振替休日を開く'), findsOneWidget);
      await tester.tap(find.text('振替休日を開く'));
      await tester.pumpAndSettle();
      expect(find.byType(SubstituteDetailScreen), findsOneWidget);
    });

    testWidgets('★振替の登録: 候補の口の本文（rest_date_pending_substitute と id）を通すと、休む日の断りに［振替休日を開く］',
        (tester) async {
      final f = _Fake(candidatesBody: {
        'rest_date': '2026-11-11',
        'rest_date_is_workday': true,
        'rest_date_reason_code': 'rest_date_pending_substitute',
        'rest_date_reason': _selfText('11月11日'),
        'rest_date_pending_substitute_id': 'rd-7',
        'holiday_def_configured': true,
        'days': const [],
      });
      await _pump(tester, SubstituteRegisterScreen(restDate: '2026-11-11', service: f));
      expect(find.text(_selfText('11月11日')), findsOneWidget);
      final btn = find.widgetWithText(OutlinedButton, '振替休日を開く');
      expect(btn, findsOneWidget);
      final s = tester.getSize(btn);
      // ignore: avoid_print
      print('登録の画面の［振替休日を開く］の大きさ: $s');
      expect(s.height, greaterThanOrEqualTo(44));
      expect(f.candidatesCalls, 1);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(f.detailCalls, ['rd-7']);
      Navigator.of(tester.element(find.byType(SubstituteDetailScreen))).pop();
      await tester.pumpAndSettle();
      expect(f.candidatesCalls, 2, reason: '戻っても候補を引き直していない');
    });

    testWidgets('対照: ほかの休む日の断り（今週より前）には［振替休日を開く］が出ない', (tester) async {
      final f = _Fake(candidatesBody: {
        'rest_date': '2026-11-11',
        'rest_date_is_workday': true,
        'rest_date_reason_code': 'past_out_of_week',
        'rest_date_reason': '今週より前の日は選べません',
        'rest_date_pending_substitute_id': null,
        'holiday_def_configured': true,
        'days': const [],
      });
      await _pump(tester, SubstituteRegisterScreen(restDate: '2026-11-11', service: f));
      expect(find.text('今週より前の日は選べません'), findsOneWidget);
      expect(find.text('振替休日を開く'), findsNothing);
    });

    testWidgets('★振替の登録の断り（SUBSTITUTE_PENDING_ON_DATE）にも［振替休日を開く］', (tester) async {
      final f = _Fake(
        candidatesBody: {
          'rest_date': '2026-11-11',
          'rest_date_is_workday': true,
          'rest_date_reason_code': null,
          'rest_date_reason': null,
          'rest_date_pending_substitute_id': null,
          'holiday_def_configured': true,
          'days': const [
            {'date': '2026-11-14', 'dow': 6, 'selectable': true, 'reason_code': null, 'reason': null},
          ],
        },
        registerResult: _pendingFailure<Map<String, dynamic>>(),
      );
      await _pump(tester, SubstituteRegisterScreen(restDate: '2026-11-11', service: f));
      await tester.tap(find.text('11月14日（土）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この内容で登録する'));
      await tester.pumpAndSettle();
      expect(find.text('登録できませんでした'), findsOneWidget);
      expect(find.text('振替休日を開く'), findsOneWidget);
      await tester.tap(find.text('振替休日を開く'));
      await tester.pumpAndSettle();
      expect(f.detailCalls, ['rd-p']);
      // →再（2026-09-30・便F13続）: 戻ると候補を引き直す（休む日の断りの［振替休日を開く］と同じ）。
      expect(f.candidatesCalls, 1);
      Navigator.of(tester.element(find.byType(SubstituteDetailScreen))).pop();
      await tester.pumpAndSettle();
      expect(f.candidatesCalls, 2, reason: '断りの窓の［振替休日を開く］から戻っても候補を引き直していない');
    });

    testWidgets('対照: 登録の画面の断りの窓を［閉じる］で閉じた回は候補を引き直さない', (tester) async {
      final f = _Fake(
        candidatesBody: _oneDayCandidates,
        registerResult: _pendingFailure<Map<String, dynamic>>(),
      );
      await _pump(tester, SubstituteRegisterScreen(restDate: '2026-11-11', service: f));
      await tester.tap(find.text('11月14日（土）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この内容で登録する'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(f.candidatesCalls, 1);
    });

    // ★（便F13続・直すもの 7）代休の断りの窓の［振替休日を開く］は、本日休みの画面の断り（P2）と同じく、
    //   窓と積まれた画面を最初の画面まで閉じてから1件の画面を開く。
    Future<void> takeCompOffUntilDeny(WidgetTester tester) async {
      await tester.tap(find.text('2026-11-01 の出勤'));
      await tester.pumpAndSettle();
      expect(find.text('代休を登録できませんでした'), findsOneWidget);
    }

    Future<void> expectOnlyDetailOnFirst(WidgetTester tester, String firstText) async {
      expect(find.byType(SubstituteDetailScreen), findsOneWidget);
      final nav = Navigator.of(tester.element(find.byType(SubstituteDetailScreen)));
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.text(firstText), findsOneWidget, reason: '最初の画面に戻っていない');
      expect(Navigator.of(tester.element(find.text(firstText))).canPop(), isFalse,
          reason: '最初の画面の上に1件の画面のほかの画面が残っていた');
    }

    testWidgets('★代休の断りの窓の［振替休日を開く］: 本日休みの画面から来た回は、最初の画面の上に1件の画面だけが残る',
        (tester) async {
      compOffServiceFactory = _CompOffFake.new;
      final f = _Fake();
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => RestDayScreen(service: f))),
              child: const Text('ホーム'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ホーム'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('代休'));
      await tester.pumpAndSettle();
      await takeCompOffUntilDeny(tester);
      await tester.tap(find.text('振替休日を開く'));
      await tester.pumpAndSettle();
      expect(find.byType(RestDayScreen), findsNothing, reason: '本日休みの画面が残っている');
      await expectOnlyDetailOnFirst(tester, 'ホーム');
    });

    testWidgets('★代休の断りの窓の［振替休日を開く］: カレンダーから来た回も、最初の画面の上に1件の画面だけが残る',
        (tester) async {
      compOffServiceFactory = _CompOffFake.new;
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      MockClient c() => MockClient((req) async => http.Response('{}', 200,
          request: req, headers: {'content-type': 'application/json'}));
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CalendarTab())));
        await tester.pumpAndSettle();
        await tester.tap(find
            .ancestor(of: find.text('3'), matching: find.byType(GestureDetector))
            .first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('代休で休む'));
        await tester.pumpAndSettle();
        await takeCompOffUntilDeny(tester);
        await tester.tap(find.text('振替休日を開く'));
        await tester.pumpAndSettle();
        expect(find.byType(CalendarDaySheet), findsNothing, reason: '箱が残っている');
        expect(find.byType(SubstituteDetailScreen), findsOneWidget);
        Navigator.of(tester.element(find.byType(SubstituteDetailScreen))).pop();
        await tester.pumpAndSettle();
      }, c);
      expect(find.byType(CalendarTab), findsOneWidget);
      expect(Navigator.of(tester.element(find.byType(CalendarTab))).canPop(), isFalse,
          reason: '最初の画面の上に1件の画面のほかの画面が残っていた');
    });

    testWidgets('対照: 本日休みの断りの窓を［閉じる］で閉じた回は、本日休みの画面に残る', (tester) async {
      compOffServiceFactory = _CompOffFake.new;
      await _pump(tester, RestDayScreen(service: _Fake()));
      await tester.tap(find.text('代休'));
      await tester.pumpAndSettle();
      await takeCompOffUntilDeny(tester);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.byType(RestDayScreen), findsOneWidget);
      expect(find.byType(SubstituteDetailScreen), findsNothing);
    });

    testWidgets('対照: 今の断りの窓（onOpenSubstitute なし）は［閉じる］1つ・accent のまま', (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showSubstituteDeny(ctx, '題',
                  apiFailure<Map<String, dynamic>>(statusCode: 409, errorMessage: 'BE の文')),
              child: const Text('開く'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.text('閉じる'), findsOneWidget);
      expect(find.text('振替休日を開く'), findsNothing);
      expect(_textColorOf(tester, '閉じる').toARGB32(), _kAccent);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (d) P3 打刻の催促の窓
  // ══════════════════════════════════════════════════════════
  group('(d) P3 打刻の催促の窓', () {
    setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'T'}));

    testWidgets('★SUBSTITUTE_PENDING_ON_DATE → 窓の中に枠（BE の文と［振替休日を開く］）・窓は閉じない',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      MockClient client() => MockClient((req) async {
            if (req.method == 'POST' && req.url.path.endsWith('/rest-days')) {
              return http.Response(jsonEncode(_pendingBody()), 409,
                  request: req, headers: {'content-type': 'application/json'});
            }
            return http.Response('{}', 404,
                request: req, headers: {'content-type': 'application/json'});
          });
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => showPunchRemindFlow(ctx,
                    side: 'in', shiftType: 'day', bizDate: '2026-11-11'),
                child: const Text('催促'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('催促'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('本日休み'));
        await tester.pumpAndSettle();
      }, client);

      expect(find.text('出勤の打刻が確認できません'), findsOneWidget, reason: '窓を閉じた');
      expect(find.text(_selfText('11月11日')), findsWidgets);
      final btn = find.widgetWithText(OutlinedButton, '振替休日を開く');
      expect(btn, findsOneWidget);
      final s = tester.getSize(btn);
      // ignore: avoid_print
      print('P3 の枠の［振替休日を開く］の大きさ: $s');
      expect(s.height, greaterThanOrEqualTo(44));
      // 枠の線は待ちの色（16進で照合）。
      final boxes = tester.widgetList<Container>(find.ancestor(
          of: find.byType(SubstituteOpenButton), matching: find.byType(Container)));
      final border = boxes
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.border)
          .whereType<Border>()
          .first;
      expect(border.top.color.toARGB32(), _kWait);

      // →再（2026-09-30・便F13続）: 赤の字（_error・statusError）は出ていない（枠と赤の字を二重に出さない）。
      //   ★窓の中を見ていることを先に確かめる（見る所を外して空で通らないように）。
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(_selfText('11月11日'))),
          findsOneWidget);
      final reds = tester
          .widgetList<Text>(find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(Text)))
          .where((t) => t.style?.color?.toARGB32() == _kError)
          .map((t) => t.data)
          .toList();
      expect(reds, isEmpty, reason: '赤の字も出ている: $reds');

      // →再（2026-09-30・便F13続）: ［振替休日を開く］を押すと窓が閉じ、その id の1件の画面が開く。
      final ids = <String>[];
      MockClient detail() => MockClient((req) async {
            ids.add(req.url.path);
            return http.Response('{}', 200,
                request: req, headers: {'content-type': 'application/json'});
          });
      await http.runWithClient(() async {
        await tester.tap(btn);
        await tester.pumpAndSettle();
      }, detail);
      expect(find.text('出勤の打刻が確認できません'), findsNothing, reason: '窓が閉じていない');
      expect(find.byType(SubstituteDetailScreen), findsOneWidget);
      expect(tester.widget<SubstituteDetailScreen>(find.byType(SubstituteDetailScreen)).restDayId,
          'rd-p');
      expect(ids.where((p) => p.endsWith('/rest-days/rd-p')), isNotEmpty,
          reason: 'その id の1件を引いていない: $ids');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (e) K1〜K3・A4 カレンダー
  // ══════════════════════════════════════════════════════════
  group('(e) K1〜K3・A4 カレンダー', () {
    final now = DateTime.now();
    String ymd(int d) =>
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
    const w = ['日', '月', '火', '水', '木', '金', '土'];
    String mdw(int d) {
      final dt = DateTime(now.year, now.month, d);
      return '${dt.month}月${dt.day}日（${w[dt.weekday % 7]}）';
    }

    final restP = ymd(10), workP = ymd(13), restS = ymd(20), workS = ymd(22);
    // 半休の日（便F13続・K1 で同意待ちの点線の輪と半休の破線の輪を見分ける）。
    final restH = ymd(6);

    MockClient cal() => MockClient((req) async {
          final path = req.url.path;
          Object body = const {};
          if (path.endsWith('/rest-days/my/substitutes')) {
            body = {
              'rows': [
                {'id': 'rd-p', 'rest_date': restP, 'paired_work_date': workP,
                 'pending_agreement': true, 'action_needed': true},
                {'id': 'rd-s', 'rest_date': restS, 'paired_work_date': workS,
                 'pending_agreement': false, 'action_needed': false},
              ],
              'truncated': false,
            };
          } else if (path.endsWith('/rest-days/my')) {
            body = {
              'days': [
                {'id': 'rd-p', 'rest_date': restP, 'reason': 'substitute', 'portion': 'full',
                 'paired_work_date': workP, 'pending_agreement': true, 'settled': false},
                {'id': 'rd-s', 'rest_date': restS, 'reason': 'substitute', 'portion': 'full',
                 'paired_work_date': workS, 'pending_agreement': false, 'settled': true},
                {'id': 'rd-h', 'rest_date': restH, 'reason': null, 'portion': 'am_half',
                 'paired_work_date': null, 'pending_agreement': false, 'settled': false},
              ],
            };
          } else if (path.endsWith('/attendance/holidays/my')) {
            body = {'weekly': const {}, 'dates': {workP: 'legal', workS: 'legal'}};
          } else if (path.endsWith('/reports')) {
            body = {'reports': const []};
          }
          return http.Response(jsonEncode(body), 200,
              request: req, headers: {'content-type': 'application/json'});
        });

    setUp(() =>
        SharedPreferences.setMockInitialValues({'auth_token': 'T', 'company_id': 'C1'}));

    Future<void> pumpCal(WidgetTester tester) async {
      // ★393 幅の電話（test/one_screen_fit_test.dart の kPhoneW・kPhoneH）。
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CalendarTab())));
        await tester.pumpAndSettle();
      }, cal);
    }

    Finder paintedRings(String painter, int argb) => find.byWidgetPredicate((wd) =>
        wd is CustomPaint &&
        wd.painter != null &&
        wd.painter.runtimeType.toString() == painter &&
        ((wd.painter as dynamic).color as Color).toARGB32() == argb);
    Finder dashedRings(int argb) => paintedRings('_DashedRingPainter', argb);
    Finder dottedRings(int argb) => paintedRings('_DottedRingPainter', argb);
    Finder solidRings(int argb) => find.byWidgetPredicate((wd) =>
        wd is DecoratedBox &&
        wd.decoration is BoxDecoration &&
        (wd.decoration as BoxDecoration).shape == BoxShape.circle &&
        ((wd.decoration as BoxDecoration).border as Border?)?.top.color.toARGB32() == argb);

    Finder cellOf(int d) => find
        .ancestor(of: find.text('$d'), matching: find.byType(GestureDetector))
        .first;

    // ★（元）同意待ちの輪を _DashedRingPainter（半休と同じ破線）で見ていた＝名乗った「点線」を確かめていなかった。
    //   →再（2026-09-30・便F13続）: 同じ月に半休の日を足し、同意待ちは _DottedRingPainter（待ちの色）・
    //   半休は _DashedRingPainter（accent）で見分ける。さらに点線の輪を描いた物で確かめる
    //   （丸い点・直径 1.5・中心の間 3＝破線を描く painter なら赤）。描いた物は、painter の paint（公開）を
    //   描いた物を記録する Canvas（_RecordingCanvas）に描かせて数える。
    testWidgets('★K1: 同意待ちの休む日は待ちの色の点線の輪（丸い点・直径1.5・中心の間3）・半休は accent の破線・成立した休みは実線（MockClient で BE の形から通す）',
        (tester) async {
      await pumpCal(tester);
      expect(dottedRings(_kWait), findsOneWidget, reason: '同意待ちの休む日の点線の輪が無い');
      expect(find.descendant(of: cellOf(10), matching: dottedRings(_kWait)), findsOneWidget,
          reason: '点線の輪が10日の升目に無い');
      expect(find.descendant(of: cellOf(10), matching: dashedRings(_kWait)), findsNothing,
          reason: '同意待ちを破線（半休と同じ形）で描いている');
      expect(find.descendant(of: cellOf(10), matching: solidRings(_kAccent)), findsNothing,
          reason: '同意待ちを休みの輪で描いている');
      expect(find.descendant(of: cellOf(20), matching: solidRings(_kAccent)), findsOneWidget,
          reason: '成立した休みの実線の輪が無い');
      // 半休は accent の破線のまま（点線の輪ではない）。
      expect(find.descendant(of: cellOf(6), matching: dashedRings(_kAccent)), findsOneWidget,
          reason: '半休の破線の輪が無い');
      expect(find.descendant(of: cellOf(6), matching: dottedRings(_kAccent)), findsNothing);
      expect(dottedRings(_kAccent), findsNothing);

      // 点線の輪を描いた物で確かめる。
      final ring = find.descendant(of: cellOf(10), matching: dottedRings(_kWait));
      final painter = tester.widget<CustomPaint>(ring).painter!;
      final size = tester.getSize(ring);
      final rec = _RecordingCanvas();
      painter.paint(rec, size);
      // ignore: avoid_print
      print('K1 の点線の輪: 大きさ=$size 点=${rec.circles.length} 線=${rec.paths}');
      expect(rec.paths, 0, reason: '線（破線）を描いている');
      expect(rec.circles.length, greaterThan(10), reason: '丸い点で描いていない');
      for (final c in rec.circles) {
        expect(c.radius, 0.75, reason: '点の直径が 1.5 でない');
        expect(c.style, PaintingStyle.fill);
        expect(c.color.toARGB32(), _kWait);
      }
      // 中心の間は輪（楕円）に沿って 3。★点の位置は Path の計量（楕円は曲線を近似した長さ）で出るので、
      //   隣り合う点の直線の距離は 3 ちょうどにならない。そこで2つで見る:
      //   ・点の数＝同じ楕円の長さ÷3 の切り上げ（間が 3 なら数が決まる＝間 2 や 4 なら数が違って赤）
      //   ・隣り合う点の直線の距離は 3 の ±5% の中
      final len = (Path()..addOval(Offset.zero & size)).computeMetrics().first.length;
      final gaps = [
        for (var i = 0; i + 1 < rec.circles.length; i++)
          (rec.circles[i + 1].center - rec.circles[i].center).distance
      ];
      // ignore: avoid_print
      print('K1 の点線の輪: 楕円の長さ=$len 隣の距離 最小=${gaps.reduce(min)} 最大=${gaps.reduce(max)}');
      expect(rec.circles.length, (len / 3).ceil(), reason: '点の数が「長さ÷3」でない＝中心の間が 3 でない');
      for (var i = 0; i < gaps.length; i++) {
        expect(gaps[i], closeTo(3, 0.15), reason: '中心の間が 3 でない（$i と ${i + 1}: ${gaps[i]}）');
      }
      // 破線の painter で描くと線になる（対照＝同じ数え方で見分けられることの確かめ）。
      final halfRing = find.descendant(of: cellOf(6), matching: dashedRings(_kAccent));
      final rec2 = _RecordingCanvas();
      tester.widget<CustomPaint>(halfRing).painter!.paint(rec2, tester.getSize(halfRing));
      expect(rec2.circles, isEmpty);
      expect(rec2.paths, greaterThan(0));
    });

    Future<void> openDay(WidgetTester tester, int d) async {
      await http.runWithClient(() async {
        await tester.tap(cellOf(d));
        await tester.pumpAndSettle();
      }, cal);
    }

    double yOf(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

    testWidgets('★K2: 同意待ちの休む日の箱の行と並び・「代休で休む」「振替で休む」が無い・393 幅で切れない',
        (tester) async {
      await pumpCal(tester);
      await openDay(tester, 10);
      final sheet = find.byType(CalendarDaySheet);
      Finder inSheet(String t) => find.descendant(of: sheet, matching: find.text(t));
      final pending = inSheet('振替休日：同意待ち（同意すると、この日は休みになります）');
      final a4 = inSheet('出勤する日：${mdw(13)}と入れ替え');
      final rows = [
        inSheet('会社休み・自分の休み：なし'),
        pending,
        a4,
        inSheet('振替休日を開く'),
        inSheet('日報：なし'),
      ];
      for (final r in rows) {
        expect(r, findsOneWidget);
      }
      for (var i = 0; i + 1 < rows.length; i++) {
        expect(yOf(tester, rows[i]) < yOf(tester, rows[i + 1]), isTrue,
            reason: '並びが違う（$i と ${i + 1}）');
      }
      expect(inSheet('代休で休む'), findsNothing);
      expect(inSheet('振替で休む'), findsNothing);
      for (final f in [pending, a4]) {
        _expectWholeTextVisible(tester, f);
        expect(tester.getTopRight(f).dx, lessThanOrEqualTo(393));
      }
      // 印の色は待ちの色。
      final icon = tester.widget<Icon>(find.descendant(
          of: find.ancestor(of: pending, matching: find.byType(Row)).first,
          matching: find.byType(Icon)));
      expect(icon.color!.toARGB32(), _kWait);
    });

    testWidgets('★K3: 同意待ちの出勤する日の箱（会社休みの日）・「代休で休む」「振替で休む」は今までどおり・A4 は出さない',
        (tester) async {
      await pumpCal(tester);
      await openDay(tester, 13);
      final sheet = find.byType(CalendarDaySheet);
      Finder inSheet(String t) => find.descendant(of: sheet, matching: find.text(t));
      expect(inSheet('会社休み（法定休日）'), findsOneWidget);
      expect(inSheet('自分の休み：なし'), findsOneWidget);
      final pending = inSheet('振替休日：同意待ち（同意すると、この日は出勤する日になります）');
      expect(pending, findsOneWidget);
      expect(yOf(tester, inSheet('自分の休み：なし')) < yOf(tester, pending), isTrue);
      expect(inSheet('代休で休む'), findsOneWidget);
      expect(inSheet('振替で休む'), findsOneWidget);
      expect(inSheet('振替休日を開く'), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('と入れ替え')), findsNothing);
      _expectWholeTextVisible(tester, pending);
      // →再（2026-09-30・便F13続）: 行の印の色（待ちの色）も見る。
      final icon = tester.widget<Icon>(find.descendant(
          of: find.ancestor(of: pending, matching: find.byType(Row)).first,
          matching: find.byType(Icon)));
      expect(icon.color!.toARGB32(), _kWait);
    });

    testWidgets('★A4: 成立した振替の休む日の箱にも「出勤する日：…と入れ替え」', (tester) async {
      await pumpCal(tester);
      await openDay(tester, 20);
      final sheet = find.byType(CalendarDaySheet);
      expect(find.descendant(of: sheet, matching: find.text('自分の休み：終日休み（振替休日）')),
          findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('出勤する日：${mdw(22)}と入れ替え')),
          findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('同意待ち')), findsNothing);
    });

    // ★（元）名前は「同意待ちの休む日は休みに数えない」。この検査は CalendarDayInfo を手で組むだけで
    //   _dayInfoOf を通らない（数えないことは K1・K2 が MockClient から通して見ている）。
    //   →再（2026-09-30・便F13続）: 名前を中身（手で組んだ値の2つの行の文と hasAnyRest）に合わせた。
    test('手で組んだ CalendarDayInfo（同意待ちの休む日）: 同意待ちの行と A4 の行の文・hasAnyRest は false（_dayInfoOf は通らない）', () {
      final info = CalendarDayInfo(
        date: DateTime(2026, 11, 11),
        substitutePendingRest: true,
        substitutePairedWorkDate: '2026-11-14',
      );
      expect(info.hasAnyRest, isFalse, reason: '同意待ちを休みに数えている');
      expect(info.substitutePendingLine, '振替休日：同意待ち（同意すると、この日は休みになります）');
      expect(info.substitutePairLine, '出勤する日：11月14日（土）と入れ替え');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (f) 月送りの大きさと帯の高さ
  // ══════════════════════════════════════════════════════════
  group('(f) 月送りの ‹ › ↻', () {
    setUp(() =>
        SharedPreferences.setMockInitialValues({'auth_token': 'T', 'company_id': 'C1'}));

    testWidgets('★‹ › ↻ は高さ・幅とも44以上・帯の高さは直す前と同じ48', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CalendarTab())));
        await tester.pumpAndSettle();
      }, () => MockClient((req) async => http.Response('{}', 200,
          request: req, headers: {'content-type': 'application/json'})));
      // ★（元）tester.takeException(); で例外の中身を見ずに捨てていた。
      //   →再（2026-09-30・便F13続）: 捨てない。前例 test/future_date_limit_test.dart と同じく中身を出し、
      //   無いことを確かめる。
      final ex = tester.takeException();
      // ignore: avoid_print
      print('(f) CalendarTab を立てたときの例外: ${ex ?? 'なし'}');
      expect(ex, isNull, reason: 'CalendarTab を立てたときに例外が出た: $ex');
      final prev = find.widgetWithIcon(IconButton, Icons.chevron_left);
      final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
      final ref = find.widgetWithIcon(IconButton, Icons.refresh);
      final bar = find.ancestor(of: prev, matching: find.byType(Container)).first;
      // ignore: avoid_print
      print('‹=${tester.getSize(prev)} ›=${tester.getSize(next)} ↻=${tester.getSize(ref)} 帯=${tester.getSize(bar)}');
      for (final b in [prev, next, ref]) {
        expect(tester.getSize(b).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(b).width, greaterThanOrEqualTo(44));
      }
      // 直す前に測った帯の高さ（visualDensity compact の 40＋上下の余白4×2＝48）。
      expect(tester.getSize(bar).height, 48);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (g) getRestDayToday の読み分け
  // ══════════════════════════════════════════════════════════
  group('(g) getRestDayToday', () {
    setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'T'}));

    Future<RestDayToday?> read(Map<String, dynamic> body) => http.runWithClient(
          () async => (await ReportsService().getRestDayToday()).data,
          () => MockClient((req) async => http.Response(jsonEncode(body), 200,
              request: req, headers: {'content-type': 'application/json'})),
        );

    test('★キーあり → その id・rested は false のまま', () async {
      final t = await read({'rested': false, 'reason': null, 'portion': 'full',
          'pending_substitute_rest_day_id': 'rd-1'});
      expect(t!.pendingSubstituteRestDayId, 'rd-1');
      expect(t.rested, isFalse);
    });
    test('★null → null', () async {
      final t = await read({'rested': true, 'reason': 'substitute', 'portion': 'full',
          'pending_substitute_rest_day_id': null});
      expect(t!.pendingSubstituteRestDayId, isNull);
      expect(t.rested, isTrue);
    });
    test('★キー無し（便B17 より前の BE）→ null と同じ', () async {
      final t = await read({'rested': false, 'reason': null, 'portion': 'full'});
      expect(t!.pendingSubstituteRestDayId, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (h) 読み直しの知らせ
  // ══════════════════════════════════════════════════════════
  group('(h) 読み直しの知らせ', () {
    testWidgets('★知らせが鳴るとホーム（PunchScreen）が getRestDayToday をもう一度引く・鳴らない回は引かない',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      final f = _Fake();
      await _pump(tester, PunchScreen(reports: f, shiftType: 'day', onShiftTypeChanged: (_) {}));
      final base = f.todayCalls;
      await tester.pumpAndSettle();
      expect(f.todayCalls, base, reason: '鳴らしていないのに引いた');
      RestDayRefresh.ring();
      await tester.pumpAndSettle();
      expect(f.todayCalls, base + 1);
    });

    testWidgets('★PunchScreen に渡す要求の数が進むと getRestDayToday をもう一度引く（進まない回は引かない）',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      final f = _Fake();
      Widget punch(int n) => MaterialApp(
          home: PunchScreen(
              reports: f, shiftType: 'day', onShiftTypeChanged: (_) {}, restStatusRequestId: n));
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(punch(0));
      await tester.pumpAndSettle();
      final base = f.todayCalls;
      await tester.pumpWidget(punch(0));
      await tester.pumpAndSettle();
      expect(f.todayCalls, base, reason: '数が同じなのに引いた');
      await tester.pumpWidget(punch(1));
      await tester.pumpAndSettle();
      expect(f.todayCalls, base + 1);
    });

    testWidgets('★知らせが鳴るとカレンダーが /rest-days/my と /rest-days/my/substitutes をもう一度引く',
        (tester) async {
      SharedPreferences.setMockInitialValues({'auth_token': 'T', 'company_id': 'C1'});
      final counts = <String, int>{};
      MockClient c() => MockClient((req) async {
            counts[req.url.path] = (counts[req.url.path] ?? 0) + 1;
            return http.Response('{}', 200,
                request: req, headers: {'content-type': 'application/json'});
          });
      int my() => counts.entries
          .where((e) => e.key.endsWith('/rest-days/my'))
          .fold(0, (s, e) => s + e.value);
      int subs() => counts.entries
          .where((e) => e.key.endsWith('/rest-days/my/substitutes'))
          .fold(0, (s, e) => s + e.value);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CalendarTab())));
        await tester.pumpAndSettle();
      }, c);
      expect(subs(), 1, reason: '画面に入ったときに振替の地図を2回引いている');
      final m0 = my(), s0 = subs();
      await http.runWithClient(() async {
        await tester.pumpAndSettle();
      }, c);
      expect(my(), m0, reason: '鳴らしていないのに引いた');
      expect(subs(), s0);
      await http.runWithClient(() async {
        RestDayRefresh.ring();
        await tester.pumpAndSettle();
      }, c);
      expect(my(), m0 + 1);
      expect(subs(), s0 + 1);
    });

    testWidgets('★本日休みの変更（updateRestDay が通ったとき）と取り消しで鳴る・通らない回は鳴らない', (tester) async {
      var rung = 0;
      void l() => rung++;
      RestDayRefresh.changes.addListener(l);
      addTearDown(() => RestDayRefresh.changes.removeListener(l));

      await _pump(tester,
          RestDayScreen(key: UniqueKey(), editMode: true, service: _Fake(updateOk: false)));
      await tester.tap(find.text('変更を保存'));
      await tester.pumpAndSettle();
      expect(rung, 0, reason: '通っていないのに鳴らした');

      await _pump(tester, RestDayScreen(key: UniqueKey(), editMode: true, service: _Fake()));
      await tester.tap(find.text('変更を保存'));
      await tester.pumpAndSettle();
      expect(rung, 1, reason: '変更が通ったのに鳴らない');

      // ★変更が通ると完了の画面に差し替わる（pushReplacement）ので、木を一度空にしてから立て直す。
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, RestDayScreen(key: UniqueKey(), editMode: true, service: _Fake()));
      await tester.tap(find.text('休みを取り消す'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消する'));
      await tester.pumpAndSettle();
      expect(rung, 2, reason: '取り消しが通ったのに鳴らない');
    });

    testWidgets('★1件の画面で同意が通ると鳴る', (tester) async {
      var rung = 0;
      void l() => rung++;
      RestDayRefresh.changes.addListener(l);
      addTearDown(() => RestDayRefresh.changes.removeListener(l));
      await _pump(tester, SubstituteDetailScreen(restDayId: 'rd-1', service: _AgreeFake()));
      await tester.tap(find.text('この振替に同意する'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認しました'));
      await tester.pumpAndSettle();
      expect(rung, 1);
    });

    // ════ 鳴らし漏れ（便F13続・直すもの 2）══════════════════════════
    // ★7か所（1件の画面の _run・登録の画面の _register と _askPriorAgreement の「取り決めていた」・
    //   打刻の催促の窓の _restDay・代休の showCompOffFlow・ホームの日報の入口の deleteRestDay・
    //   変更の画面の _confirm）のそれぞれで、次の3つを見る（二者比較）:
    //     ・答えが返る前に画面（窓）を閉じ、その後で通った答えが返る → 1回鳴る
    //     ・閉じずに通った → 1回だけ鳴る
    //     ・答えが返る前に閉じ、通らなかった → 鳴らない
    // ★答えを返す時は Completer で決める（今ある差し替え口の形の中＝_HoldFake・_CompOffHoldFake・
    //   打刻の催促の窓は MockClient の中で待つ）。
    const scenarios = [
      (close: true, ok: true, want: 1),
      (close: false, ok: true, want: 1),
      (close: true, ok: false, want: 0),
    ];

    Future<void> pumpHome(WidgetTester tester, Widget Function() screen) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(ctx)
                  .push(MaterialPageRoute(builder: (_) => screen())),
              child: const Text('ホーム'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ホーム'));
      await tester.pumpAndSettle();
    }

    Future<void> popTop(WidgetTester tester, Finder inTop) async {
      Navigator.of(tester.element(inTop.first)).pop();
      await tester.pumpAndSettle();
      expect(inTop, findsNothing, reason: '閉じていない');
    }

    /// 1つの場所の3つの回を走らせる。step は「通信を出すところまで進め、close なら閉じ、
    /// 答えを返す関数」を返す。
    Future<void> runSite(
      WidgetTester tester,
      String name,
      Future<void Function(bool ok)> Function(bool close) step,
    ) async {
      var rung = 0;
      void l() => rung++;
      RestDayRefresh.changes.addListener(l);
      addTearDown(() => RestDayRefresh.changes.removeListener(l));
      for (final s in scenarios) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final answer = await step(s.close);
        final before = rung;
        answer(s.ok);
        await tester.pumpAndSettle();
        // ignore: avoid_print
        print('$name: 閉じる=${s.close} 通る=${s.ok} → 鳴った ${rung - before} 回');
        expect(rung - before, s.want,
            reason: '$name（閉じる=${s.close}・通る=${s.ok}）');
      }
    }

    testWidgets('★1件の画面の _run（同意）', (tester) async {
      await runSite(tester, '1件の画面の _run', (close) async {
        final f = _HoldFake();
        await pumpHome(tester, () => SubstituteDetailScreen(restDayId: 'rd-1', service: f));
        await tester.tap(find.text('この振替に同意する'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('確認しました'));
        await tester.pumpAndSettle();
        if (close) await popTop(tester, find.byType(SubstituteDetailScreen));
        return (ok) => f.hold.complete(ok ? _okMap() : _ngMap());
      });
    });

    testWidgets('★登録の画面の _register', (tester) async {
      await runSite(tester, '登録の画面の _register', (close) async {
        final f = _HoldFake(candidatesBody: _oneDayCandidates);
        await pumpHome(tester,
            () => SubstituteRegisterScreen(restDate: '2026-11-11', service: f));
        await tester.tap(find.text('11月14日（土）'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('この内容で登録する'));
        await tester.pumpAndSettle();
        if (close) await popTop(tester, find.byType(SubstituteRegisterScreen));
        return (ok) => f.hold.complete(ok ? _okMap() : _ngMap());
      });
    });

    testWidgets('★登録の画面の _askPriorAgreement（取り決めていた）', (tester) async {
      await runSite(tester, '登録の画面の _askPriorAgreement', (close) async {
        final f = _HoldFake(
          candidatesBody: _oneDayCandidates,
          firstRegister: apiFailure<Map<String, dynamic>>(
            statusCode: 409,
            errorMessage: '過去の日が入っています',
            errorCode: 'SUBSTITUTE_PRIOR_AGREEMENT_REQUIRED',
            errorDetails: const {'past_dates': ['2026-11-11']},
          ),
        );
        await pumpHome(tester,
            () => SubstituteRegisterScreen(restDate: '2026-11-11', service: f));
        await tester.tap(find.text('11月14日（土）'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('この内容で登録する'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取り決めていた（登録する）'));
        await tester.pumpAndSettle();
        expect(f.registerCalls, 2, reason: '取り決めていたで出し直していない');
        if (close) await popTop(tester, find.byType(SubstituteRegisterScreen));
        return (ok) => f.hold.complete(ok ? _okMap() : _ngMap());
      });
    });

    testWidgets('★変更の画面の _confirm（休む日の変更の申し出）', (tester) async {
      await runSite(tester, '変更の画面の _confirm', (close) async {
        final f = _HoldFake();
        await pumpHome(tester, () => SubstituteChangeScreen(restDayId: 'rd-1', service: f));
        await tester.tap(find.text('11月12日（木）'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('変更は一度きりであることを確認しました'));
        await tester.tap(find.text('この変更を自分の意思で申し出ます'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('申請する'));
        await tester.pumpAndSettle();
        if (close) await popTop(tester, find.byType(SubstituteChangeScreen));
        return (ok) => f.hold.complete(ok ? _okMap() : _ngMap());
      });
    });

    testWidgets('★1件の画面 → 変更の画面で申し出が通って戻っても1回だけ（_openChange では鳴らさない）',
        (tester) async {
      var rung = 0;
      void l() => rung++;
      RestDayRefresh.changes.addListener(l);
      addTearDown(() => RestDayRefresh.changes.removeListener(l));
      final f = _HoldFake(detailPending: false);
      await pumpHome(tester, () => SubstituteDetailScreen(restDayId: 'rd-1', service: f));
      await tester.tap(find.text('休む日を変える'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認しました'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('11月12日（木）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('変更は一度きりであることを確認しました'));
      await tester.tap(find.text('この変更を自分の意思で申し出ます'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('申請する'));
      await tester.pumpAndSettle();
      final loads = f.detailCalls.length;
      f.hold.complete(_okMap());
      await tester.pumpAndSettle();
      expect(find.byType(SubstituteChangeScreen), findsNothing);
      expect(find.byType(SubstituteDetailScreen), findsOneWidget);
      expect(f.detailCalls.length, loads + 1, reason: '1件の画面が戻って読み直していない');
      expect(rung, 1, reason: '同じ申し出で2回鳴った（または鳴らない）');
    });

    testWidgets('★代休の showCompOffFlow', (tester) async {
      addTearDown(() => compOffServiceFactory = ReportsService.new);
      await runSite(tester, '代休の showCompOffFlow', (close) async {
        final fake = _CompOffHoldFake();
        compOffServiceFactory = () => fake;
        await pumpHome(
            tester,
            () => Builder(
                  builder: (ctx) => Scaffold(
                    body: TextButton(
                      onPressed: () => showCompOffFlow(ctx, restDate: '2026-11-11'),
                      child: const Text('呼び手'),
                    ),
                  ),
                ));
        await tester.tap(find.text('呼び手'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2026-11-01 の出勤'));
        await tester.pumpAndSettle();
        if (close) await popTop(tester, find.text('呼び手'));
        return (ok) => fake.hold.complete(ok
            ? apiSuccess<CompOffTaken>(
                statusCode: 201,
                data: const CompOffTaken(
                    restDate: '2026-11-11',
                    pairedWorkDate: '2026-11-01',
                    pairedUndecided: false,
                    takenDays: 1,
                    notice: null))
            : apiFailure<CompOffTaken>(
                statusCode: 409, errorMessage: 'ほかの断り', errorCode: 'OTHER'));
      });
    });

    testWidgets('★ホームの日報の入口の deleteRestDay（休みを取り消して続行）', (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      await runSite(tester, '日報の入口の deleteRestDay', (close) async {
        final f = _HoldFake(rested: true);
        await pumpHome(
            tester,
            () => PunchScreen(
                  reports: f,
                  shiftType: 'day',
                  onShiftTypeChanged: (_) {},
                  onNavigateToReport: () {},
                ));
        await tester.tap(find.text('日報を報告'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('休みを取り消して続行'));
        await tester.pumpAndSettle();
        if (close) await popTop(tester, find.byType(PunchScreen));
        return (ok) => f.holdMutation.complete(ok
            ? apiSuccess<RestDayMutation>(
                statusCode: 200,
                data: const RestDayMutation(
                    restDate: '2026-11-11', reason: null, cancelled: true))
            : apiFailure<RestDayMutation>(
                statusCode: 409, errorMessage: 'ほかの断り', errorCode: 'OTHER'));
      });
    });

    // ★打刻の催促の窓は、送る間は［閉じる］が押せず外を押しても閉じない（barrierDismissible: false）ので、
    //   Navigator の pop で閉じる。★口は ReportsService() を直に作る（差し替え口が無い）ので、
    //   MockClient の中で答えを待つ。★答えを返す前に、口の時間切れ（15秒）より時計を進めない
    //   （窓は送る間 LinearProgressIndicator が回るので pumpAndSettle を使わず、pump で少しずつ進める）。
    testWidgets('★打刻の催促の窓の _restDay（本日休み）', (tester) async {
      SharedPreferences.setMockInitialValues({'auth_token': 'T'});
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var rung = 0;
      void l() => rung++;
      RestDayRefresh.changes.addListener(l);
      addTearDown(() => RestDayRefresh.changes.removeListener(l));

      for (final s in scenarios) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final gate = Completer<bool>();
        MockClient c() => MockClient((req) async {
              if (req.method == 'POST' && req.url.path.endsWith('/rest-days')) {
                final ok = await gate.future;
                return ok
                    ? http.Response(
                        jsonEncode({'rest_date': '2026-11-11', 'reason': null}), 201,
                        request: req, headers: {'content-type': 'application/json'})
                    : http.Response(
                        jsonEncode({'error': 'ほかの断り', 'code': 'OTHER'}), 409,
                        request: req, headers: {'content-type': 'application/json'});
              }
              return http.Response('{}', 404,
                  request: req, headers: {'content-type': 'application/json'});
            });
        final before = rung;
        await http.runWithClient(() async {
          await tester.pumpWidget(MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: TextButton(
                  onPressed: () => showPunchRemindFlow(ctx,
                      side: 'in', shiftType: 'day', bizDate: '2026-11-11'),
                  child: const Text('催促'),
                ),
              ),
            ),
          ));
          await tester.tap(find.text('催促'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('本日休み'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          if (s.close) {
            Navigator.of(tester.element(find.text('出勤の打刻が確認できません'))).pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.text('出勤の打刻が確認できません'), findsNothing, reason: '窓が閉じていない');
          }
          expect(rung, before, reason: '答えが返る前に鳴った');
          gate.complete(s.ok);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pumpAndSettle();
        }, c);
        // ignore: avoid_print
        print('打刻の催促の窓の _restDay: 閉じる=${s.close} 通る=${s.ok} → 鳴った ${rung - before} 回');
        expect(rung - before, s.want, reason: '打刻の催促の窓（閉じる=${s.close}・通る=${s.ok}）');
      }
    });
  });

  // ══════════════════════════════════════════════════════════
  // (i) 状態の色
  // ══════════════════════════════════════════════════════════
  group('(i) 状態の色', () {
    test('★一覧: 同意待ちは待ちの色（今と同じ橙）・成立できません・成立は今の色のまま', () {
      expect(substituteStateColor({'pending_agreement': true}).toARGB32(), _kWait);
      expect(substituteStateColor({'change_blocked': true}).toARGB32(), _kError);
      expect(substituteStateColor(const {}).toARGB32(), _kSuccess);
    });

    Future<Color> labelColor(WidgetTester tester, Map<String, dynamic> rd, String label) async {
      await _pump(tester,
          SubstituteDetailScreen(key: UniqueKey(), restDayId: 'x', service: _DetailFake(rd)));
      return _textColorOf(tester, label);
    }

    testWidgets('★1件の画面: 同意待ち・事務の確認待ちは待ちの色・成立できません・成立・取消済みは今の色',
        (tester) async {
      expect((await labelColor(tester, {'pending_agreement': true, 'cancelled_at': null}, '同意待ち'))
          .toARGB32(), _kWait);
      expect((await labelColor(tester,
              {'change_requested_rest_date': '2026-11-19', 'cancelled_at': null}, '事務の確認待ち'))
          .toARGB32(), _kWait);
      expect((await labelColor(tester, {'change_blocked': true, 'cancelled_at': null}, '成立できません'))
          .toARGB32(), _kError);
      expect((await labelColor(tester, {'cancelled_at': null}, '成立')).toARGB32(), _kSuccess);
      expect((await labelColor(tester, {'cancelled_at': '2026-11-01T00:00:00Z'}, '取消済み'))
          .toARGB32(), _kSupport);
    });

    testWidgets('★K2 の印も同じ待ちの色（P1 の札は (a)・P3 の枠は (d)・K1 の輪は (e) で同じ 16進）',
        (tester) async {
      await _pump(
          tester,
          Scaffold(
            body: CalendarDaySheet(
              maxHeight: 800,
              info: CalendarDayInfo(
                  date: DateTime(2026, 11, 11), substitutePendingRest: true),
            ),
          ));
      final icon = tester.widget<Icon>(find.descendant(
          of: find
              .ancestor(
                  of: find.text('振替休日：同意待ち（同意すると、この日は休みになります）'),
                  matching: find.byType(Row))
              .first,
          matching: find.byType(Icon)));
      expect(icon.color!.toARGB32(), _kWait);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (j) カレンダーの注意バー（便F13続・直すもの 5）
  // ══════════════════════════════════════════════════════════
  group('(j) カレンダーの注意バー', () {
    setUp(() =>
        SharedPreferences.setMockInitialValues({'auth_token': 'T', 'company_id': 'C1'}));

    // 振替の日付の口（/rest-days/my/substitutes）だけを失敗させるか選べる口。引いた回数も数える。
    Future<({int Function() subs})> pumpCal(WidgetTester tester, {required bool failSubs}) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var n = 0;
      MockClient c() => MockClient((req) async {
            if (req.url.path.endsWith('/rest-days/my/substitutes')) {
              n++;
              if (failSubs) {
                return http.Response(jsonEncode({'error': 'サーバーエラー', 'code': 'SERVER_ERROR'}), 500,
                    request: req, headers: {'content-type': 'application/json'});
              }
            }
            return http.Response('{}', 200,
                request: req, headers: {'content-type': 'application/json'});
          });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CalendarTab())));
        await tester.pumpAndSettle();
      }, c);
      return (subs: () => n);
    }

    testWidgets('★振替の日付の口だけが失敗した回は「振替休日を取得できませんでした」と［再試行］・押すと振替の日付の口をもう一度引く',
        (tester) async {
      final r = await pumpCal(tester, failSubs: true);
      expect(find.text('振替休日を取得できませんでした'), findsOneWidget, reason: '振替の日付の失敗が黙っている');
      final retry = find.ancestor(of: find.text('再試行'), matching: find.byType(GestureDetector)).first;
      final s = tester.getSize(retry);
      final bar = find
          .ancestor(of: find.text('振替休日を取得できませんでした'), matching: find.byType(Container))
          .first;
      // ignore: avoid_print
      print('注意バーの［再試行］の大きさ: $s ／ 注意バーの高さ: ${tester.getSize(bar).height}');
      expect(s.height, greaterThanOrEqualTo(44));
      expect(s.width, greaterThanOrEqualTo(44));
      expect(tester.getSize(bar).height, 44, reason: '注意バーの高さが［再試行］の44にそろっていない');
      expect(r.subs(), 1);
    });

    testWidgets('★［再試行］を押すと振替の日付の口をもう一度引く（引く回数）', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var n = 0;
      var fail = true;
      MockClient c() => MockClient((req) async {
            if (req.url.path.endsWith('/rest-days/my/substitutes')) {
              n++;
              if (fail) {
                return http.Response(jsonEncode({'error': 'サーバーエラー', 'code': 'SERVER_ERROR'}), 500,
                    request: req, headers: {'content-type': 'application/json'});
              }
            }
            return http.Response('{}', 200,
                request: req, headers: {'content-type': 'application/json'});
          });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CalendarTab())));
        await tester.pumpAndSettle();
        expect(n, 1);
        expect(find.text('振替休日を取得できませんでした'), findsOneWidget);
        await tester.tap(find.text('再試行'));
        await tester.pumpAndSettle();
        expect(n, 2, reason: '［再試行］で振替の日付の口を引き直していない');
        expect(find.text('振替休日を取得できませんでした'), findsOneWidget, reason: 'まだ失敗しているのに注意バーが消えた');
        // 次は通る → 注意バーが消える（旗を下ろす）。今の地図は失敗の間も消していない。
        fail = false;
        await tester.tap(find.text('再試行'));
        await tester.pumpAndSettle();
        expect(n, 3);
        expect(find.textContaining('を取得できませんでした'), findsNothing, reason: '通ったのに注意バーが残った');
      }, c);
    });

    testWidgets('対照: 成功の回は注意バーが出ない', (tester) async {
      final r = await pumpCal(tester, failSubs: false);
      expect(r.subs(), 1);
      expect(find.textContaining('を取得できませんでした'), findsNothing);
      expect(find.text('再試行'), findsNothing);
    });
  });
}

/// 答えを返す時を検査が決める口（便F13続・(h) の鳴らし漏れ）。★今ある差し替え口（service 引数・
///   PunchScreen の reports）の形のまま、_Fake を継いで返りを Completer にするだけ。
class _HoldFake extends _Fake {
  _HoldFake({
    super.candidatesBody,
    super.rested,
    super.detailPending,
    this.firstRegister,
  });

  /// 1回目の登録だけ返す答え（過去の日の問い＝_askPriorAgreement へ進むため）。null なら1回目から待つ。
  final ApiResult<Map<String, dynamic>>? firstRegister;
  int registerCalls = 0;

  final hold = Completer<ApiResult<Map<String, dynamic>>>();
  final holdMutation = Completer<ApiResult<RestDayMutation>>();

  @override
  Future<ApiResult<Map<String, dynamic>>> agreeSubstitute(String id) => hold.future;

  @override
  Future<ApiResult<Map<String, dynamic>>> registerSubstitute(
      String restDate, String pairedWorkDate,
      {bool priorAgreement = false}) {
    registerCalls++;
    if (firstRegister != null && registerCalls == 1) return Future.value(firstRegister!);
    return hold.future;
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> getChangeCandidates(String id) async =>
      apiSuccess<Map<String, dynamic>>(statusCode: 200, data: {
        'rest_day_id': id,
        'current_rest_date': '2026-11-11',
        'paired_work_date': '2026-11-14',
        'holiday_def_configured': true,
        'days': [
          {'date': '2026-11-12', 'dow': 4, 'selectable': true, 'reason_code': null,
           'reason': null, 'deadline': '2026-11-10'},
        ],
      });

  @override
  Future<ApiResult<Map<String, dynamic>>> requestSubstituteChange(String id, String newDate) =>
      hold.future;

  @override
  Future<ApiResult<RestDayMutation>> deleteRestDay() => holdMutation.future;
}

/// 代休の口で、取る答えを検査が決める（便F13続・(h)）。
class _CompOffHoldFake extends _CompOffFake {
  final hold = Completer<ApiResult<CompOffTaken>>();

  @override
  Future<ApiResult<CompOffTaken>> takeCompOff({
    required String restDate,
    String? sourceWorkDate,
    bool undecided = false,
    String portion = 'full',
  }) =>
      hold.future;
}

ApiResult<Map<String, dynamic>> _okMap() =>
    apiSuccess<Map<String, dynamic>>(statusCode: 200, data: const {});
ApiResult<Map<String, dynamic>> _ngMap() => apiFailure<Map<String, dynamic>>(
    statusCode: 409, errorMessage: 'ほかの断り', errorCode: 'OTHER');

/// 同意が通る1件の口（(h) の1件の画面）。
class _AgreeFake extends ReportsService {
  _AgreeFake() : super.forTest();

  @override
  Future<ApiResult<Map<String, dynamic>>> getRestDay(String id) async =>
      apiSuccess<Map<String, dynamic>>(statusCode: 200, data: {
        'rest_day': {'id': id, 'pending_agreement': true, 'cancelled_at': null,
            'rest_date': '2026-11-11', 'paired_work_date': '2026-11-14'},
        'events': const <Map<String, dynamic>>[],
      });

  @override
  Future<ApiResult<Map<String, dynamic>>> agreeSubstitute(String id) async =>
      apiSuccess<Map<String, dynamic>>(statusCode: 200, data: const {});
}

/// 1件の画面の状態を決める口（(i)）。
class _DetailFake extends ReportsService {
  _DetailFake(this.rd) : super.forTest();
  final Map<String, dynamic> rd;

  @override
  Future<ApiResult<Map<String, dynamic>>> getRestDay(String id) async =>
      apiSuccess<Map<String, dynamic>>(statusCode: 200, data: {
        'rest_day': {'id': id, 'rest_date': '2026-11-11', 'paired_work_date': '2026-11-14', ...rd},
        'events': const <Map<String, dynamic>>[],
      });
}
