// ============================================================
// test/f8_day_request_test.dart
//   便F8＝出勤した日の日報を出し忘れた職人が、事務に「後から日報を出す許可」を頼む入口
//   （見本 field_substitute_past_mock_v5 の A3・B1・B2・D1・D2・D3・ボス裁定【Q89】）を機械で固定する。
//
// ★何を守るか（すべて二者比較。「出ない」だけで合格にしない）:
//   (i)    口3本（尋ねる口・出勤の修正依頼・日報漏れの申告）の道・引数・本文・答え・断り
//   (ii)   振替の登録の候補で no_report の行だけが押せる行になる（ほかの行は今のまま）・※の1行
//   (iii)  3択の画面（出せる日／出せない日／聞けなかった時）と、押した後の道
//   (iv)   依頼と申告の画面の字・押せる条件・送る本文・知らせ・断りの窓・二度押し
//   (v)    箱に入口を出す日の決まり・自分の日報の数え方・入口を組み立てる関数
//   (vi)   カレンダーの箱の入口（出せる日／出せない日／聞けなかった時・押した後の道）
//   (vii)  入口を渡さない箱は今のまま・置き場・見出しの字
//   (viii) 押せる物の高さ 44 以上（本物のテーマ）
//   (ix)   尋ねる口の答えの読み方（readDayRequestEligibility）
//   (x)    ソースの字（箱を開く所の差し込み・時計を読まない）
//
// ★掟: 期待値（語・色・並び）はこのファイル内で組み立てる。実装の定数は import しない。
//   字は一字一句・色は16進の生の値。時計を読まない（今日は検査が字で渡す）。
// ★画面には口の差し替え（ReportsService.forTest() を継いだ偽物）を渡す
//   （test/substitute_register_test.dart と同じ形）。口そのものは package:http の
//   runWithClient＋MockClient で、実 HTTP へ行かせずに道と本文を見る。
// ★検査の名前の頭の番号（(i-1) ほか）は、ログの赤い行からどの検査かを機械で読むための物。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/core/theme/app_theme.dart';
import 'package:js_awake_app/screens/day_request_screen.dart'
    show DayRequestKind, DayRequestScreen;
import 'package:js_awake_app/screens/home_screen.dart'
    show CalendarDayInfo, CalendarDaySheet, showCalendarDaySheet;
import 'package:js_awake_app/screens/monthly_history_screen.dart'
    show JsReportTile;
import 'package:js_awake_app/screens/substitute_past_day_screen.dart'
    show WorkDateNoReportScreen;
import 'package:js_awake_app/screens/substitute_register_screen.dart'
    show SubstituteRegisterScreen;
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';
import 'package:js_awake_app/widgets/comp_off_dialog.dart'
    show compOffServiceFactory;
import 'package:js_awake_app/widgets/day_request_entry.dart'
    show
        DayRequestEligibilityKind,
        DayRequestEntry,
        dayRequestEntryOrNull,
        ownLiveReportCount,
        readDayRequestEligibility,
        shouldOfferDayRequestEntry;

// ── 色（lib/core/theme/field_tokens.dart の値を16進の生の値で写した）──────
const int _kBrand = 0xFFD9C08A;
const int _kTextBody = 0xFFEAE3D0;
const int _kTextFaint = 0xFF635F55;

// ── 今日（検査が字で渡す・時計を読まない）────────────────────────────
const String _kToday = '2026-10-07';
const String _kRestDate = '2026-10-07';

// ── BE の文（js-office-api の services/dayRequests.js・routes/attendance.js・
//    routes/rest_days.js の実文字列を写したもの）──────────────────────────
const String _kNoReport = 'この日の日報がありません';
const String _kUnapproved = 'この日の日報は未承認です';
const String _kNotHoliday = '会社の休みの日ではありません';
const String _kAlreadyFix = 'すでに出勤の修正を依頼しています（事務の確認待ち）';
const String _kOutOfClosing = 'いまの締め期間より前の日は申告できません。事務へ直接ご相談ください。';
const String _kEmployeeOnly = '依頼・申告の確認は従業員のみ利用できます';
const String _kServerError = 'サーバーエラー';

// ── 画面の字（指示の字をそのまま写した）──────────────────────────────
const String _kHeadNoReport = 'この日の日報がありません';
const String _kBtnFix = '出勤の修正を依頼する';
const String _kBtnCompOff = '代休で取る';
const String _kBtnPickAgain = '日を選び直す';
const String _kRetry = 'もう一度';
const String _kCannotAskFix = '依頼できるかを確かめられませんでした';
const String _kCannotAskMissing = '申告できるかを確かめられませんでした';
const String _kBtnDeclare = '日報漏れを申告する';
const String _kNoteDeclare = '※この日の日報を後から出すには、事務の許可が要ります。';
const String _kHeadCannotDeclare = '申告できません';
const String _kNotePast = '※過去の日を選べるのは、今日が入っている週の中だけです。';
const String _kNoteRegister = '※出勤する日を決めないと登録できません。';
const String _kDenyDefault = 'できませんでした。時間をおいて、もう一度お試しください。';
const String _kNetError = '通信エラーが発生しました';

// ── 候補の口（GET /rest-days/substitute/candidates）の days[] ─────────────
Map<String, dynamic> _day(String date, int dow,
        {String? code, String? reason}) =>
    {
      'date': date,
      'dow': dow,
      'selectable': code == null,
      'reason_code': code,
      'reason': reason,
    };

/// 2026-10-04（日）〜10-10（土）。★no_report の行（10-06）の dow は、わざと実の曜日（火＝2）と
///   違う 3（水）にする＝端末で曜日を数えていないことを見る。
List<Map<String, dynamic>> _week() => [
      _day('2026-10-04', 0),
      _day('2026-10-05', 1, code: 'not_holiday', reason: _kNotHoliday),
      _day('2026-10-06', 3, code: 'no_report', reason: _kNoReport),
      _day('2026-10-07', 3, code: 'same_as_rest_date', reason: '休む日と同じ日です'),
      _day('2026-10-08', 4, code: 'report_unapproved', reason: _kUnapproved),
      _day('2026-10-09', 5, code: 'not_holiday', reason: _kNotHoliday),
      _day('2026-10-10', 6),
    ];

// 候補の行の字（M月D日（曜）・曜日は上の dow のまま）。
const String _kRowSelectable = '10月4日（日）';
const String _kRowNotHoliday = '10月5日（月）';
const String _kRowNoReport = '10月6日（水）';
const String _kRowUnapproved = '10月8日（木）';
const String _kWeekLast = '10月10日（土）';

// ── 尋ねる口の答え（BE の8つのキーの形）──────────────────────────────
Map<String, dynamic> _answer(String type, String workDate,
        {required Object? canDeclare, String? code, String? reason}) =>
    {
      'type': type,
      'work_date': workDate,
      'can_declare': canDeclare,
      'code': code,
      'reason': reason,
      'permit_until': null,
      'request_id': code == 'ALREADY_REQUESTED' ? 'cq-1' : null,
      'confirm_type': code == 'ALREADY_REQUESTED' ? 'attendance_fix' : null,
    };

ApiResult<Map<String, dynamic>> _ok(Map<String, dynamic> d) =>
    apiSuccess<Map<String, dynamic>>(statusCode: 200, data: d);

ApiResult<Map<String, dynamic>> _fail(int status, String? msg, {String? code}) =>
    apiFailure<Map<String, dynamic>>(
        statusCode: status, errorMessage: msg, errorCode: code);

ApiResult<Map<String, dynamic>> _fixAllowed() =>
    _ok(_answer('attendance_fix', '2026-10-06', canDeclare: true));
ApiResult<Map<String, dynamic>> _fixDenied() => _ok(_answer(
    'attendance_fix', '2026-10-06',
    canDeclare: false, code: 'ALREADY_REQUESTED', reason: _kAlreadyFix));

/// 差し替える口。★実 HTTP へ行かせず、何を何で叩いたかを数える。
class _Fake extends ReportsService {
  _Fake({List<Map<String, dynamic>>? days, List<ApiResult<Map<String, dynamic>>>? elig})
      : days = days ?? _week(),
        elig = elig ?? [_fixAllowed()],
        super.forTest();

  final List<Map<String, dynamic>> days;
  final List<ApiResult<Map<String, dynamic>>> elig;
  ApiResult<Map<String, dynamic>>? sendResult;
  Completer<void>? eligHold;
  Completer<void>? sendHold;
  Completer<void>? registerHold;

  final List<String> candidateCalls = [];
  final List<String> eligCalls = [];      // 'type|work_date'
  final List<String> sendKinds = [];      // 'fix' / 'missing'
  final List<String> sentDates = [];
  final List<String> sentReasons = [];    // 画面が口へ渡した字（そのまま）
  int registerCalls = 0;

  @override
  Future<ApiResult<Map<String, dynamic>>> getSubstituteWorkDateCandidates(
      String restDate) async {
    candidateCalls.add(restDate);
    return apiSuccess<Map<String, dynamic>>(statusCode: 200, data: {
      'rest_date': restDate,
      'rest_date_is_workday': true,
      'rest_date_reason_code': null,
      'rest_date_reason': null,
      'rest_date_pending_substitute_id': null,
      'holiday_def_configured': true,
      'days': days,
    });
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> registerSubstitute(
      String restDate, String pairedWorkDate,
      {bool priorAgreement = false}) async {
    registerCalls++;
    final h = registerHold;
    if (h != null) await h.future;
    return apiFailure<Map<String, dynamic>>(
        statusCode: 409, errorMessage: '登録の断り', errorCode: 'X');
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> getDayRequestEligibility(
      String type, String workDate) async {
    eligCalls.add('$type|$workDate');
    final i = eligCalls.length - 1;
    final h = eligHold;
    if (h != null) await h.future;
    return elig[i < elig.length ? i : elig.length - 1];
  }

  Future<ApiResult<Map<String, dynamic>>> _send(
      String kind, String workDate, String reasonText) async {
    sendKinds.add(kind);
    sentDates.add(workDate);
    sentReasons.add(reasonText);
    final h = sendHold;
    if (h != null) await h.future;
    return sendResult ??
        apiSuccess<Map<String, dynamic>>(
            statusCode: 201, data: const {'declared': true, 'id': 'cq-9'});
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> requestAttendanceFix(
          String workDate, String reasonText) =>
      _send('fix', workDate, reasonText);

  @override
  Future<ApiResult<Map<String, dynamic>>> declareReportMissing(
          String workDate, String reasonText) =>
      _send('missing', workDate, reasonText);
}

/// 代休の受け皿の差し替え（test/comp_off_flow_test.dart と同じ使い方）。
class _CompFake extends ReportsService {
  _CompFake() : super.forTest();
  final List<String?> askedAsOf = [];

  @override
  Future<ApiResult<CompOffAvailable>> getCompOffAvailable({String? asOf}) async {
    askedAsOf.add(asOf);
    return apiSuccess<CompOffAvailable>(
      statusCode: 200,
      data: const CompOffAvailable(
          asOf: null, remainingDays: 0, candidates: [], undecidedNotice: null),
    );
  }
}

// ── 立て方 ──────────────────────────────────────────────────────────
Future<void> _pump(WidgetTester tester, Widget home,
    {ThemeData? theme, Size size = const Size(1200, 3000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // ★1つの検査で2回立てる時に、前の木の State（入口が聞いた答え）を持ち越さない。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(theme: theme, home: home));
  await tester.pumpAndSettle();
}

Widget _register(_Fake api) =>
    SubstituteRegisterScreen(restDate: _kRestDate, service: api);

/// 押した結果を受け取れる土台（画面を積んで、閉じた時の返りを残す）。
class _Host {
  Object? result;
  bool closed = false;
  Widget build(Widget Function() screen) => Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(ctx)
                    .push<Object?>(MaterialPageRoute(builder: (_) => screen()));
                closed = true;
              },
              child: const Text('ひらく'),
            ),
          ),
        ),
      );
}

// ── 探し方 ──────────────────────────────────────────────────────────
/// 候補の1行の器（行の間 4 の Container）。
Finder _rowOf(String dateText) => find
    .ancestor(
        of: find.text(dateText),
        matching: find.byWidgetPredicate((w) =>
            w is Container && w.margin == const EdgeInsets.only(bottom: 4)))
    .first;

double _opacityOf(WidgetTester tester, String dateText) => tester
    .widget<Opacity>(find
        .ancestor(of: find.text(dateText), matching: find.byType(Opacity))
        .first)
    .opacity;

Border? _borderOf(WidgetTester tester, String dateText) =>
    (tester.widget<Container>(_rowOf(dateText)).decoration as BoxDecoration)
        .border as Border?;

int? _textColor(WidgetTester tester, Finder f) =>
    tester.widget<Text>(f).style?.color?.toARGB32();

Finder _in(Type screen, Finder f) =>
    find.descendant(of: find.byType(screen), matching: f);

/// RichText の葉の字と、その字の太さ・色（親から受け継いだ形を重ねて）。
List<(String, FontWeight?, int?)> _spansOf(InlineSpan root) {
  final out = <(String, FontWeight?, int?)>[];
  void walk(InlineSpan s, TextStyle inherited) {
    final st = inherited.merge(s.style);
    if (s is TextSpan) {
      final t = s.text;
      if (t != null && t.isNotEmpty) out.add((t, st.fontWeight, st.color?.toARGB32()));
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c, st);
      }
    }
  }

  walk(root, const TextStyle());
  return out;
}

Finder _rich(String plain) => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText() == plain);

/// 行コメントを落としたソース（差し込みをコメントアウトしただけで通らないように）。
String _codeOnly(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 箱の日（CalendarDayInfo）と入口を組み立てて立てる。
Future<void> _pumpSheet(WidgetTester tester, CalendarDayInfo info, Widget? entry,
    {ThemeData? theme}) async {
  await _pump(
    tester,
    Scaffold(
      body: CalendarDaySheet(info: info, maxHeight: 2000, dayRequestEntry: entry),
    ),
    theme: theme,
  );
}

Widget? _entryFor(_Fake api, String workDate,
        {String today = _kToday,
        int own = 0,
        bool rest = false,
        bool pending = false,
        String dateText = '10月3日（土）'}) =>
    dayRequestEntryOrNull(
      workDate: workDate,
      today: today,
      ownReportCount: own,
      hasOwnRest: rest,
      substitutePendingRest: pending,
      dateText: dateText,
      service: api,
    );

ApiResult<Map<String, dynamic>> _missingAllowed() =>
    _ok(_answer('report_missing', '2026-10-03', canDeclare: true));

// BE の日報の行（test/calendar_day_sheet_test.dart の _row と同じ形に user_id を足した）。
Map<String, dynamic> _report(String id, String userId) => <String, dynamic>{
      'report_id': id,
      'report_date': '2026-10-03',
      'user_id': userId,
      'worker_name': '職人太郎',
      'site_name': '現場A',
      'work_content': '配線',
      'approved': false,
      'revision_requested': false,
      'status': 'open',
    };

void main() {
  // ══════════════════════════════════════════════════════════
  // (i) 口3本
  // ══════════════════════════════════════════════════════════
  group('(i) 口3本', () {
    setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'T'}));

    Future<(http.Request, ApiResult<Map<String, dynamic>>)> call(
        Future<ApiResult<Map<String, dynamic>>> Function(ReportsService) run,
        int status,
        Object body) async {
      late http.Request seen;
      final res = await http.runWithClient(
        () => run(ReportsService.forTest()),
        () => MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode(body), status,
              request: req,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      return (seen, res);
    }

    test('(i-1) 尋ねる口: GET・道・引数 type と work_date・8つのキーが BE の値のまま（null も null）',
        () async {
      final be = <String, dynamic>{
        'type': 'attendance_fix',
        'work_date': '2026-10-06',
        'can_declare': false,
        'code': 'ALREADY_REQUESTED',
        'reason': _kAlreadyFix,
        'permit_until': null,
        'request_id': 'cq-1',
        'confirm_type': 'attendance_fix',
      };
      final (req, res) = await call(
          (s) => s.getDayRequestEligibility('attendance_fix', '2026-10-06'), 200, be);
      expect(req.method, 'GET');
      expect(req.url.path.endsWith('/attendance/day-requests/eligibility'), isTrue,
          reason: '道が違う: ${req.url.path}');
      expect(req.url.queryParameters,
          {'type': 'attendance_fix', 'work_date': '2026-10-06'});
      expect(res.ok, isTrue);
      expect(res.data, be, reason: '8つのキーが BE の値のまま返っていない');
      expect(res.data!.keys.length, 8);

      // ★対照: 出せる日（ほかの5つは null）も、null のまま返る。
      final be2 = <String, dynamic>{
        'type': 'report_missing',
        'work_date': '2026-10-03',
        'can_declare': true,
        'code': null,
        'reason': null,
        'permit_until': null,
        'request_id': null,
        'confirm_type': null,
      };
      final (req2, res2) = await call(
          (s) => s.getDayRequestEligibility('report_missing', '2026-10-03'), 200, be2);
      expect(req2.url.queryParameters,
          {'type': 'report_missing', 'work_date': '2026-10-03'});
      expect(res2.data, be2);
      expect(res2.data!.containsKey('permit_until'), isTrue);
    });

    for (final (no, name, path, run) in <(String, String, String,
        Future<ApiResult<Map<String, dynamic>>> Function(ReportsService))>[
      ('(i-2)', '出勤の修正依頼の口', '/attendance/attendance-fix-request',
          (s) => s.requestAttendanceFix('2026-10-06', '  片付けで出勤  ')),
      ('(i-3)', '日報漏れの申告の口', '/attendance/report-missing-declare',
          (s) => s.declareReportMissing('2026-10-06', '  片付けで出勤  ')),
    ]) {
      test('$no $name: POST・道・本文のキーは work_date と reason_text の2つだけ（理由は前後の空白を除く）・201 も 200 も通る',
          () async {
        final (req, res) =
            await call(run, 201, const {'declared': true, 'id': 'cq-9'});
        expect(req.method, 'POST');
        expect(req.url.path.endsWith(path), isTrue, reason: '道が違う: ${req.url.path}');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body, {'work_date': '2026-10-06', 'reason_text': '片付けで出勤'});
        expect(body.keys.toSet(), {'work_date', 'reason_text'});
        expect(res.ok, isTrue);
        expect(res.statusCode, 201);

        // ★対照: 200（もう積まれている）も通った答え。statusCode で見分けられる。
        final (_, res200) =
            await call(run, 200, const {'already_declared': true, 'id': 'cq-9'});
        expect(res200.ok, isTrue);
        expect(res200.statusCode, 200);
        expect(res200.data, {'already_declared': true, 'id': 'cq-9'});
      });
    }

    test('(i-4) 断り 409 { error, code }: errorMessage が error・errorCode が code と1字も同じ（3本とも）',
        () async {
      const be = {'error': _kAlreadyFix, 'code': 'ALREADY_REQUESTED'};
      for (final run in <Future<ApiResult<Map<String, dynamic>>> Function(ReportsService)>[
        (s) => s.getDayRequestEligibility('attendance_fix', '2026-10-06'),
        (s) => s.requestAttendanceFix('2026-10-06', '理由'),
        (s) => s.declareReportMissing('2026-10-06', '理由'),
      ]) {
        final (_, res) = await call(run, 409, be);
        expect(res.ok, isFalse);
        expect(res.statusCode, 409);
        expect(res.errorMessage, _kAlreadyFix);
        expect(res.errorCode, 'ALREADY_REQUESTED');
      }
    });
  });

  // ══════════════════════════════════════════════════════════
  // (ii) 候補の行と※
  // ══════════════════════════════════════════════════════════
  group('(ii) 候補の行', () {
    testWidgets('(ii-1) no_report の行: 薄くない・日付の字は選べる行と同じ色・枠と理由と chevron が brand・押すと3択が開き1回だけ聞く',
        (tester) async {
      final api = _Fake();
      await _pump(tester, _register(api));

      expect(_opacityOf(tester, _kRowNoReport), 1.0);
      expect(_textColor(tester, find.text(_kRowNoReport)),
          _textColor(tester, find.text(_kRowSelectable)),
          reason: '日付の字の色が選べる行と違う');
      expect(_textColor(tester, find.text(_kRowNoReport)), _kTextBody);
      final b = _borderOf(tester, _kRowNoReport)!;
      expect(b.top.color.toARGB32(), _kBrand);
      expect(b.top.width, 1.0);
      expect(_textColor(tester, find.text(_kNoReport)), _kBrand);
      final chev = find.descendant(
          of: _rowOf(_kRowNoReport), matching: find.byIcon(Icons.chevron_right));
      expect(chev, findsOneWidget);
      expect(tester.widget<Icon>(chev).color!.toARGB32(), _kBrand);
      // ★対照: not_holiday の行は今のまま（薄い・枠なし・理由は textFaint）。
      expect(_opacityOf(tester, _kRowNotHoliday), 0.55);
      expect(_borderOf(tester, _kRowNotHoliday), isNull);

      await tester.tap(find.text(_kRowNoReport));
      await tester.pumpAndSettle();
      expect(find.byType(WorkDateNoReportScreen), findsOneWidget);
      expect(api.eligCalls, ['attendance_fix|2026-10-06']);
    });

    testWidgets('(ii-1) 登録を送っている間は no_report の行を押せない（尋ねる口は0回）', (tester) async {
      final api = _Fake()..registerHold = Completer<void>();
      await _pump(tester, _register(api));
      await tester.tap(find.text(_kRowSelectable));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この内容で登録する'));
      await tester.pump();
      expect(api.registerCalls, 1);

      await tester.tap(find.text(_kRowNoReport), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(WorkDateNoReportScreen), findsNothing);
      expect(api.eligCalls, isEmpty);

      api.registerHold!.complete();
      await tester.pumpAndSettle();
      // ★対照: 送り終わったら押せる。
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_kRowNoReport));
      await tester.pumpAndSettle();
      expect(find.byType(WorkDateNoReportScreen), findsOneWidget);
      expect(api.eligCalls.length, 1);
    });

    testWidgets('(ii-2) report_unapproved と not_holiday の行: 押しても何も開かない・薄い・chevron が無い',
        (tester) async {
      final api = _Fake();
      await _pump(tester, _register(api));
      for (final row in [_kRowUnapproved, _kRowNotHoliday]) {
        expect(_opacityOf(tester, row), 0.55, reason: '$row が薄くない');
        expect(
            find.descendant(of: _rowOf(row), matching: find.byIcon(Icons.chevron_right)),
            findsNothing);
        expect(_borderOf(tester, row), isNull);
        expect(_textColor(tester, find.text(row)), _kTextFaint);
        await tester.tap(find.text(row));
        await tester.pumpAndSettle();
        expect(find.byType(WorkDateNoReportScreen), findsNothing,
            reason: '$row を押すと3択が開いた');
      }
      expect(_textColor(tester, find.text(_kUnapproved)), _kTextFaint);
      expect(api.eligCalls, isEmpty);
    });

    testWidgets('(ii-3) 選べる行: 押すと選ばれる・3択は開かない', (tester) async {
      final api = _Fake();
      await _pump(tester, _register(api));
      expect(find.byIcon(Icons.check), findsNothing);
      await tester.tap(find.text(_kRowSelectable));
      await tester.pumpAndSettle();
      expect(
          find.descendant(of: _rowOf(_kRowSelectable), matching: find.byIcon(Icons.check)),
          findsOneWidget);
      expect(find.byType(WorkDateNoReportScreen), findsNothing);
      expect(api.eligCalls, isEmpty);
    });

    testWidgets('(ii-4) 候補の下の※: 過去の日の1行が週の※の下・登録の※の上に出る', (tester) async {
      await _pump(tester, _register(_Fake()));
      final week = tester.getRect(find.text('※同じ週（10月4日〜10月10日）の会社休みの日から選びます。'));
      final past = tester.getRect(find.text(_kNotePast));
      final reg = tester.getRect(find.text(_kNoteRegister));
      expect(week.top < past.top, isTrue, reason: '過去の日の※が週の※より上');
      expect(past.top < reg.top, isTrue, reason: '過去の日の※が登録の※より下');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (iii) 3択の画面
  // ══════════════════════════════════════════════════════════
  group('(iii) 3択の画面', () {
    Future<void> open3(WidgetTester tester, _Fake api) async {
      await _pump(tester, _register(api));
      await tester.tap(find.text(_kRowNoReport));
      await tester.pumpAndSettle();
    }

    testWidgets('(iii-1) 出せる日: 見出し・本文（日付だけ太字・dow は候補の口のまま）・3つのボタンの字と並び・聞いている間はくるくる',
        (tester) async {
      final api = _Fake()..eligHold = Completer<void>();
      await _pump(tester, _register(api));
      await tester.tap(find.text(_kRowNoReport));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_in(WorkDateNoReportScreen, find.byType(CircularProgressIndicator)),
          findsOneWidget, reason: '聞いている間のくるくるが無い');
      expect(_in(WorkDateNoReportScreen, find.text(_kBtnFix)), findsNothing);
      api.eligHold!.complete();
      await tester.pumpAndSettle();
      expect(_in(WorkDateNoReportScreen, find.byType(CircularProgressIndicator)),
          findsNothing);

      expect(find.text('振替で休む'), findsOneWidget);
      expect(_in(WorkDateNoReportScreen, find.text(_kHeadNoReport)), findsOneWidget);
      const body = '10月6日（水） を出勤する日に選ぶには、その日の日報が必要です。'
          '後から日報を出すには、事務の許可が要ります。';
      final rich = _rich(body);
      expect(rich, findsOneWidget, reason: '本文が1字も同じでない（または曜日を端末で数えている）');
      final spans = _spansOf(tester.widget<RichText>(rich).text);
      final bold = spans.where((s) => s.$2 == FontWeight.bold).map((s) => s.$1).toList();
      expect(bold, ['10月6日（水）'], reason: '太字が日付だけでない');

      final a = tester.getRect(find.text(_kBtnFix));
      final c = tester.getRect(find.text(_kBtnCompOff));
      final p = tester.getRect(find.text(_kBtnPickAgain));
      expect(a.top < c.top && c.top < p.top, isTrue, reason: '並びが違う');
      expect(find.widgetWithText(OutlinedButton, _kBtnFix), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, _kBtnCompOff), findsOneWidget);
      expect(find.widgetWithText(TextButton, _kBtnPickAgain), findsOneWidget);
    });

    testWidgets('(iii-2) 出せない日（ALREADY_REQUESTED）: 枠の文が BE の文のまま・見出しと依頼のボタンが無い・代休と選び直しは在る',
        (tester) async {
      final api = _Fake(elig: [_fixDenied()]);
      await open3(tester, api);
      expect(_in(WorkDateNoReportScreen, find.text(_kAlreadyFix)), findsOneWidget);
      expect(_in(WorkDateNoReportScreen, find.text(_kHeadNoReport)), findsNothing);
      expect(find.text(_kBtnFix), findsNothing);
      expect(find.text(_kBtnCompOff), findsOneWidget);
      expect(find.text(_kBtnPickAgain), findsOneWidget);
      expect(find.text(_kRetry), findsNothing);
    });

    testWidgets('(iii-3) 聞けなかった時: 符号つきの失敗はその文・届かなかった失敗は決めた字（例外の字は出ない）・もう一度で聞き直す',
        (tester) async {
      // 符号つきの失敗（500・SERVER_ERROR）。
      final api = _Fake(elig: [_fail(500, _kServerError, code: 'SERVER_ERROR')]);
      await open3(tester, api);
      expect(_in(WorkDateNoReportScreen, find.text(_kServerError)), findsOneWidget);
      expect(find.text(_kCannotAskFix), findsNothing);
      expect(find.text(_kRetry), findsOneWidget);
      for (final t in [_kBtnFix, _kBtnCompOff, _kBtnPickAgain]) {
        expect(find.text(t), findsNothing, reason: '聞けなかった時に「$t」が出ている');
      }
    });

    testWidgets('(iii-3) 聞けなかった時（サーバまで届かなかった）→ もう一度 → 通れば3択', (tester) async {
      final api = _Fake(elig: [
        _fail(0, 'サーバーに接続できません: SocketException: boom'),
        _fixAllowed(),
      ]);
      await open3(tester, api);
      expect(_in(WorkDateNoReportScreen, find.text(_kCannotAskFix)), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.textContaining('サーバーに接続できません'), findsNothing);
      expect(find.text(_kBtnFix), findsNothing);
      expect(find.text(_kBtnCompOff), findsNothing);

      await tester.tap(find.text(_kRetry));
      await tester.pumpAndSettle();
      expect(api.eligCalls.length, 2, reason: 'もう一度で聞き直していない');
      expect(find.text(_kBtnFix), findsOneWidget);
      expect(find.text(_kBtnCompOff), findsOneWidget);
      expect(find.text(_kBtnPickAgain), findsOneWidget);
      expect(find.text(_kRetry), findsNothing);
    });

    testWidgets('(iii-4) 代休で取る: 登録の画面が代休の窓を開く（休む日が渡る）', (tester) async {
      final comp = _CompFake();
      compOffServiceFactory = () => comp;
      addTearDown(() => compOffServiceFactory = ReportsService.new);
      final api = _Fake();
      await open3(tester, api);
      await tester.tap(find.text(_kBtnCompOff));
      await tester.pumpAndSettle();
      expect(comp.askedAsOf, [_kRestDate], reason: '代休の窓に休む日が渡っていない');
      expect(find.text('取れる代休がありません'), findsOneWidget);
      expect(find.byType(WorkDateNoReportScreen), findsNothing);
    });

    testWidgets('(iii-5) 日を選び直す: 登録の画面に戻り選んでいた日が消える／対照: 戻る矢印では残る',
        (tester) async {
      final api = _Fake();
      await _pump(tester, _register(api));
      Finder checkIn() => find.descendant(
          of: _rowOf(_kRowSelectable), matching: find.byIcon(Icons.check));

      // 対照: 戻る（矢印）。
      await tester.tap(find.text(_kRowSelectable));
      await tester.pumpAndSettle();
      expect(checkIn(), findsOneWidget);
      await tester.tap(find.text(_kRowNoReport));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(WorkDateNoReportScreen), findsNothing);
      expect(checkIn(), findsOneWidget, reason: '戻る矢印で選んでいた日が消えた');

      // 日を選び直す。
      await tester.tap(find.text(_kRowNoReport));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_kBtnPickAgain));
      await tester.pumpAndSettle();
      expect(find.byType(WorkDateNoReportScreen), findsNothing);
      expect(find.byType(SubstituteRegisterScreen), findsOneWidget);
      expect(checkIn(), findsNothing, reason: '日を選び直すで選んでいた日が消えない');
      expect(api.candidateCalls.length, 1, reason: '選び直しで候補を引き直している');
    });

    testWidgets('(iii-6) 出勤の修正を依頼する: 依頼の画面（対象の日は押した日・期限は days[] の最後）→ 送ると押した日が渡り、登録の画面へ戻って候補を引き直す',
        (tester) async {
      final api = _Fake();
      await open3(tester, api);
      await tester.tap(find.text(_kBtnFix));
      await tester.pumpAndSettle();
      expect(find.byType(DayRequestScreen), findsOneWidget);
      expect(_in(DayRequestScreen, find.text(_kRowNoReport)), findsOneWidget,
          reason: '対象の日が押した日でない');
      expect(_in(DayRequestScreen, find.text('10月7日（水）')), findsNothing,
          reason: '対象の日に休む日が出ている');
      expect(
          _rich('※事務が許可すると、この日の日報を $_kWeekLast'
              'まで出せるようになります。'),
          findsOneWidget,
          reason: '※の期限が days[] の最後の日でない');

      await tester.enterText(find.byType(TextField), '現場の片付け');
      await tester.pump();
      await tester.tap(find.text('依頼を送る'));
      await tester.pumpAndSettle();
      expect(api.sendKinds, ['fix']);
      expect(api.sentDates, ['2026-10-06']);
      expect(find.byType(DayRequestScreen), findsNothing);
      expect(find.byType(WorkDateNoReportScreen), findsNothing);
      expect(find.byType(SubstituteRegisterScreen), findsOneWidget);
      expect(api.candidateCalls.length, 2, reason: '戻った後に候補を引き直していない');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (iv) 依頼と申告の画面
  // ══════════════════════════════════════════════════════════
  group('(iv) 依頼と申告の画面', () {
    DayRequestScreen screenOf(_Fake api, DayRequestKind kind) => DayRequestScreen(
          kind: kind,
          workDate: '2026-10-06',
          dateText: _kRowNoReport,
          permitUntilText: kind == DayRequestKind.attendanceFix ? _kWeekLast : null,
          service: api,
        );

    // 種類ごとの字（指示の字をそのまま）。
    const fix = (
      kind: DayRequestKind.attendanceFix,
      title: '出勤の修正依頼',
      fixed: 'この日に出勤していましたが、日報を出していませんでした。'
          '振替休日の出勤する日にするため、この日の日報を出す許可をお願いします。',
      hint: '例：現場の片付けで出勤。日報を出し忘れた',
      button: '依頼を送る',
      note1: '※事務が許可すると、この日の日報を 10月10日（土）まで出せるようになります。',
      note2: '※日報が事務に承認されるまで、この日を出勤する日には選べません。',
      done: '出勤の修正を依頼しました。事務が確認します。',
      already: 'すでに依頼済みです。',
      denyTitle: '依頼できませんでした',
      sendKind: 'fix',
    );
    const missing = (
      kind: DayRequestKind.reportMissing,
      title: '日報漏れの申告',
      fixed: 'この日に出勤していましたが、日報を出していませんでした。'
          'この日の日報を出す許可をお願いします。',
      hint: '例：現場で電池が切れて日報を出せなかった',
      button: '申告を送る',
      note1: '※事務が許可すると、この日の日報をこの締め期間の最終日まで出せるようになります。',
      note2: '※出した日報は、事務の承認で確定します。',
      done: '日報漏れを申告しました。事務が確認します。',
      already: 'すでに申告済みです。',
      denyTitle: '申告できませんでした',
      sendKind: 'missing',
    );

    ElevatedButton sendBtn(WidgetTester tester, String label) =>
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, label));

    for (final (no, w) in [('(iv-1)', fix), ('(iv-2)', missing)]) {
      testWidgets('$no ${w.title}: 題・対象の日・固定の文・理由（必須）・例・ボタン・※の2行が1字も同じ',
          (tester) async {
        await _pump(tester, screenOf(_Fake(), w.kind));
        expect(find.descendant(of: find.byType(AppBar), matching: find.text(w.title)),
            findsOneWidget);
        expect(find.text('対象の日'), findsOneWidget);
        expect(find.text(_kRowNoReport), findsOneWidget);
        expect(find.text(w.fixed), findsOneWidget);
        expect(find.text('理由（必須）'), findsOneWidget);
        expect(find.text(w.hint), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, w.button), findsOneWidget);
        expect(_rich(w.note1), findsOneWidget, reason: '※1行目が1字も同じでない');
        expect(find.text(w.note2), findsOneWidget);
        // 並び: 対象の日 → 固定の文 → 理由（必須）→ 欄 → ボタン → ※。
        final ys = [
          tester.getRect(find.text('対象の日')).top,
          tester.getRect(find.text(w.fixed)).top,
          tester.getRect(find.text('理由（必須）')).top,
          tester.getRect(find.byType(TextField)).top,
          tester.getRect(find.widgetWithText(ElevatedButton, w.button)).top,
          tester.getRect(_rich(w.note1)).top,
          tester.getRect(find.text(w.note2)).top,
        ];
        for (var i = 1; i < ys.length; i++) {
          expect(ys[i - 1] < ys[i], isTrue, reason: '並びが違う（$i 番目）');
        }
        if (w.kind == DayRequestKind.attendanceFix) {
          final spans = _spansOf(tester.widget<RichText>(_rich(w.note1)).text);
          final bold = spans.where((s) => s.$2 == FontWeight.bold).toList();
          expect(bold.map((s) => s.$1).toList(), [_kWeekLast], reason: '太字が日付だけでない');
          expect(bold.single.$3, _kTextBody, reason: '期限の日付の色が本文色でない');
        }
      });
    }

    testWidgets('(iv-3) 理由が空・半角の空白だけ・全角の空白だけの間は押せない（口は0回）・字を入れると押せる',
        (tester) async {
      final api = _Fake();
      await _pump(tester, screenOf(api, DayRequestKind.attendanceFix));
      expect(sendBtn(tester, '依頼を送る').onPressed, isNull, reason: '空で押せる');
      for (final t in ['   ', '　　']) {
        await tester.enterText(find.byType(TextField), t);
        await tester.pump();
        expect(sendBtn(tester, '依頼を送る').onPressed, isNull, reason: '「$t」で押せる');
        await tester.tap(find.text('依頼を送る'), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      expect(api.sendKinds, isEmpty);
      await tester.enterText(find.byType(TextField), '片付け');
      await tester.pump();
      expect(sendBtn(tester, '依頼を送る').onPressed, isNotNull, reason: '字を入れても押せない');
    });

    for (final w in [fix, missing]) {
      testWidgets('(iv-4) ${w.title}: 送る本文は work_date と前後の空白を除いた reason_text・201 は「…しました」で閉じて true',
          (tester) async {
        final api = _Fake();
        final host = _Host();
        await _pump(tester, host.build(() => screenOf(api, w.kind)));
        await tester.tap(find.text('ひらく'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '  現場の片付け  ');
        await tester.pump();
        await tester.tap(find.text(w.button));
        await tester.pumpAndSettle();
        expect(api.sendKinds, [w.sendKind]);
        expect(api.sentDates, ['2026-10-06']);
        expect(ReportsService.dayRequestBody(api.sentDates.single, api.sentReasons.single),
            {'work_date': '2026-10-06', 'reason_text': '現場の片付け'});
        expect(find.text(w.done), findsOneWidget);
        expect(find.byType(DayRequestScreen), findsNothing);
        expect(host.closed, isTrue);
        expect(host.result, true);
      });

      testWidgets('(iv-5) ${w.title}: 200（もう積まれている）は「${w.already}」で閉じて true', (tester) async {
        final api = _Fake()
          ..sendResult = apiSuccess<Map<String, dynamic>>(
              statusCode: 200, data: const {'already_declared': true, 'id': 'cq-9'});
        final host = _Host();
        await _pump(tester, host.build(() => screenOf(api, w.kind)));
        await tester.tap(find.text('ひらく'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '片付け');
        await tester.pump();
        await tester.tap(find.text(w.button));
        await tester.pumpAndSettle();
        expect(find.text(w.already), findsOneWidget);
        expect(find.text(w.done), findsNothing);
        expect(host.result, true);
      });

      testWidgets('(iv-6) ${w.title}: 409 は BE の文と題の窓・画面は閉じない・入力は残る・もう一度押せる',
          (tester) async {
        final api = _Fake()..sendResult = _fail(409, _kAlreadyFix, code: 'ALREADY_REQUESTED');
        await _pump(tester, screenOf(api, w.kind));
        await tester.enterText(find.byType(TextField), '片付け');
        await tester.pump();
        await tester.tap(find.text(w.button));
        await tester.pumpAndSettle();
        expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(w.denyTitle)),
            findsOneWidget);
        expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(_kAlreadyFix)),
            findsOneWidget);
        await tester.tap(find.text('閉じる'));
        await tester.pumpAndSettle();
        expect(find.byType(DayRequestScreen), findsOneWidget);
        expect(find.text('片付け'), findsOneWidget, reason: '入力が消えた');
        await tester.tap(find.text(w.button));
        await tester.pumpAndSettle();
        expect(api.sendKinds.length, 2, reason: '送っている印が戻っていない');
      });
    }

    testWidgets('(iv-7) 送っている間に、もう一度押しても口は1回だけ', (tester) async {
      final api = _Fake()..sendHold = Completer<void>();
      await _pump(tester, screenOf(api, DayRequestKind.reportMissing));
      await tester.enterText(find.byType(TextField), '片付け');
      await tester.pump();
      await tester.tap(find.text('申告を送る'));
      await tester.pump();
      await tester.tap(find.text('申告を送る'), warnIfMissed: false);
      await tester.pump();
      expect(api.sendKinds.length, 1);
      api.sendHold!.complete();
      await tester.pumpAndSettle();
      expect(api.sendKinds.length, 1);
    });

    testWidgets('(iv-8) 届かなかった時は「通信エラーが発生しました」（例外の字は出ない）・符号の無い 502 は窓の決まりの文',
        (tester) async {
      final api = _Fake()
        ..sendResult = _fail(0, 'サーバーに接続できません: SocketException: boom');
      await _pump(tester, screenOf(api, DayRequestKind.attendanceFix));
      await tester.enterText(find.byType(TextField), '片付け');
      await tester.pump();
      await tester.tap(find.text('依頼を送る'));
      await tester.pumpAndSettle();
      final dlg = find.byType(AlertDialog);
      expect(find.descendant(of: dlg, matching: find.text('依頼できませんでした')), findsOneWidget);
      expect(find.descendant(of: dlg, matching: find.text(_kNetError)), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.byType(DayRequestScreen), findsOneWidget);

      // 符号の無い失敗（502 と HTML の本文）。もう一度押せる。
      api.sendResult = _fail(502, '<html>Bad Gateway</html>');
      await tester.tap(find.text('依頼を送る'));
      await tester.pumpAndSettle();
      expect(api.sendKinds.length, 2);
      expect(find.descendant(of: dlg, matching: find.text(_kDenyDefault)), findsOneWidget);
      expect(find.textContaining('<html>'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (v) 出す日の条件・数え方・組み立て
  // ══════════════════════════════════════════════════════════
  group('(v) 出す日の条件', () {
    bool offer(String d, {int own = 0, bool rest = false, bool pending = false}) =>
        shouldOfferDayRequestEntry(
          workDate: d,
          today: _kToday,
          ownReportCount: own,
          hasOwnRest: rest,
          substitutePendingRest: pending,
        );

    test('(v-1) 今日より前・自分の日報0枚・休み無し → 出す', () {
      expect(offer('2026-10-06'), isTrue);
      expect(offer('2025-12-31'), isTrue);
    });

    test('(v-2) 今日／先の日／自分の日報の在る日／休みの在る日／同意待ちの振替の休む日 → 出さない', () {
      expect(offer('2026-10-07'), isFalse, reason: '今日に出している');
      expect(offer('2026-10-08'), isFalse, reason: '先の日に出している');
      expect(offer('2026-10-06', own: 1), isFalse, reason: '自分の日報が在る日に出している');
      expect(offer('2026-10-06', rest: true), isFalse, reason: '休みの在る日に出している');
      expect(offer('2026-10-06', pending: true), isFalse, reason: '同意待ちの休む日に出している');
      // 対照（同じ日で条件を外すと出る）。
      expect(offer('2026-10-06'), isTrue);
    });

    testWidgets('(v-3) 入口を組み立てる関数の答えで箱を立てる: 出さない5つの日は入口が無く口は0回・出す日は入口が在り口は1回',
        (tester) async {
      final cases = <(String, Widget? Function(_Fake))>[
        ('今日', (api) => _entryFor(api, '2026-10-07')),
        ('先の日', (api) => _entryFor(api, '2026-10-08')),
        ('自分の日報の在る日', (api) => _entryFor(api, '2026-10-03', own: 1)),
        ('休みの在る日', (api) => _entryFor(api, '2026-10-03', rest: true)),
        ('同意待ちの振替の休む日', (api) => _entryFor(api, '2026-10-03', pending: true)),
      ];
      for (final (name, make) in cases) {
        final api = _Fake(elig: [_missingAllowed()]);
        final entry = make(api);
        expect(entry, isNull, reason: '$name に入口を組み立てた');
        await _pumpSheet(tester, CalendarDayInfo(date: DateTime(2026, 10, 3)), entry);
        expect(find.byType(DayRequestEntry), findsNothing, reason: name);
        expect(find.text(_kBtnDeclare), findsNothing, reason: name);
        expect(api.eligCalls, isEmpty, reason: '$name で尋ねる口を呼んだ');
      }
      final api = _Fake(elig: [_missingAllowed()]);
      await _pumpSheet(tester, CalendarDayInfo(date: DateTime(2026, 10, 3)),
          _entryFor(api, '2026-10-03'));
      expect(find.byType(DayRequestEntry), findsOneWidget);
      expect(api.eligCalls, ['report_missing|2026-10-03']);
    });

    test('(v-4) 自分の生きている日報を数える関数', () {
      final mine1 = _report('r1', 'u-me');
      final mine2 = _report('r2', 'u-me');
      final other = _report('r3', 'u-other');
      expect(ownLiveReportCount([mine1, mine2, other], 'u-me'), 2);
      expect(ownLiveReportCount([other, _report('r4', 'u-x'), _report('r5', 'u-y')], 'u-me'), 0,
          reason: '職長の箱（ほかの人の日報だけの日）');
      expect(ownLiveReportCount([mine1, other, _report('r6', 'u-z')], null), 3,
          reason: 'id が null の時に行の全部を数えていない');
      expect(ownLiveReportCount([mine1, other, _report('r6', 'u-z')], ''), 3,
          reason: 'id が空の字の時に行の全部を数えていない');
      final noKey = Map<String, dynamic>.from(mine1)..remove('user_id');
      final nullKey = Map<String, dynamic>.from(mine1)..['user_id'] = null;
      expect(ownLiveReportCount([noKey, nullKey, mine2], 'u-me'), 1,
          reason: 'user_id が無い行・null の行を自分の行に数えた');
      expect(ownLiveReportCount(const [], 'u-me'), 0);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (vi) カレンダーの箱の入口
  // ══════════════════════════════════════════════════════════
  group('(vi) 箱の入口', () {
    final info = CalendarDayInfo(date: DateTime(2026, 10, 3));

    testWidgets('(vi-1) 開いたら type=report_missing とその日で1回だけ聞く・聞いている間はくるくる',
        (tester) async {
      final api = _Fake(elig: [_missingAllowed()])..eligHold = Completer<void>();
      // pumpAndSettle はくるくるで終わらないので、1枚ずつ進める。
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CalendarDaySheet(
                  info: info,
                  maxHeight: 2000,
                  dayRequestEntry: _entryFor(api, '2026-10-03')))));
      await tester.pump();
      expect(_in(DayRequestEntry, find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.text(_kBtnDeclare), findsNothing);
      api.eligHold!.complete();
      await tester.pumpAndSettle();
      expect(_in(DayRequestEntry, find.byType(CircularProgressIndicator)), findsNothing);
      expect(api.eligCalls, ['report_missing|2026-10-03']);
    });

    testWidgets('(vi-2) 出せる日: 「日報漏れを申告する」と※が出る', (tester) async {
      final api = _Fake(elig: [_missingAllowed()]);
      await _pumpSheet(tester, info, _entryFor(api, '2026-10-03'));
      expect(find.text(_kBtnDeclare), findsOneWidget);
      expect(find.text(_kNoteDeclare), findsOneWidget);
      expect(find.byIcon(Icons.assignment_late_outlined), findsOneWidget);
      expect(find.text(_kHeadCannotDeclare), findsNothing);
      expect(find.text(_kRetry), findsNothing);
    });

    testWidgets('(vi-3) 出せない日（OUT_OF_CLOSING_PERIOD）: 枠「申告できません」と BE の文・申告のボタンは無い',
        (tester) async {
      final api = _Fake(elig: [
        _ok(_answer('report_missing', '2026-10-03',
            canDeclare: false, code: 'OUT_OF_CLOSING_PERIOD', reason: _kOutOfClosing)),
      ]);
      await _pumpSheet(tester, info, _entryFor(api, '2026-10-03'));
      expect(find.text(_kHeadCannotDeclare), findsOneWidget);
      expect(find.text(_kOutOfClosing), findsOneWidget);
      expect(find.text(_kBtnDeclare), findsNothing);
      expect(find.text(_kNoteDeclare), findsNothing);
      expect(find.text(_kRetry), findsNothing);
    });

    testWidgets('(vi-4) 聞けなかった時: 符号つきの失敗はその文・届かなかった失敗は決めた字・もう一度で聞き直す',
        (tester) async {
      final api1 = _Fake(elig: [_fail(500, _kServerError, code: 'SERVER_ERROR')]);
      await _pumpSheet(tester, info, _entryFor(api1, '2026-10-03'));
      expect(find.text(_kServerError), findsOneWidget);
      expect(find.text(_kRetry), findsOneWidget);
      expect(find.text(_kBtnDeclare), findsNothing);

      final api2 = _Fake(elig: [
        _fail(0, 'サーバーに接続できません: SocketException: boom'),
        _missingAllowed(),
      ]);
      await _pumpSheet(tester, info, _entryFor(api2, '2026-10-03'));
      expect(find.text(_kCannotAskMissing), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.text(_kRetry), findsOneWidget);
      await tester.tap(find.text(_kRetry));
      await tester.pumpAndSettle();
      expect(api2.eligCalls.length, 2);
      expect(find.text(_kBtnDeclare), findsOneWidget);
      expect(find.text(_kCannotAskMissing), findsNothing);
    });

    testWidgets('(vi-5) 押すと箱が閉じて申告の画面が開く・対象の日は箱の日・送ると箱の日が渡る', (tester) async {
      final api = _Fake(elig: [_missingAllowed()]);
      final day = CalendarDayInfo(date: DateTime(2026, 10, 12), jpHolidayName: 'スポーツの日');
      await _pump(
        tester,
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCalendarDaySheet(ctx,
                    info: day,
                    maxHeight: 2000,
                    dayRequestEntry: _entryFor(api, '2026-10-12',
                        today: '2026-10-13', dateText: day.dateText)),
                child: const Text('ひらく'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ひらく'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDaySheet), findsOneWidget);
      await tester.tap(find.text(_kBtnDeclare));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDaySheet), findsNothing, reason: '箱が残っている');
      expect(find.byType(DayRequestScreen), findsOneWidget);
      expect(find.text('日報漏れの申告'), findsOneWidget);
      expect(find.text('10月12日（月）'), findsOneWidget, reason: '対象の日が箱の日でない');
      expect(find.textContaining('スポーツの日'), findsNothing, reason: '対象の日に祝日の名前が付いている');
      await tester.enterText(find.byType(TextField), '電池切れ');
      await tester.pump();
      await tester.tap(find.text('申告を送る'));
      await tester.pumpAndSettle();
      expect(api.sendKinds, ['missing']);
      expect(api.sentDates, ['2026-10-12']);
    });

    testWidgets('(vi-6) サーバが符号つきで断った（403 ATTENDANCE_EMPLOYEE_ONLY）: 出せない日の形で文・もう一度は無い',
        (tester) async {
      final api = _Fake(elig: [_fail(403, _kEmployeeOnly, code: 'ATTENDANCE_EMPLOYEE_ONLY')]);
      await _pumpSheet(tester, info, _entryFor(api, '2026-10-03'));
      expect(find.text(_kHeadCannotDeclare), findsOneWidget);
      expect(find.text(_kEmployeeOnly), findsOneWidget);
      expect(find.text(_kRetry), findsNothing);
      expect(find.text(_kBtnDeclare), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (vii) 箱の今の形・置き場・見出し
  // ══════════════════════════════════════════════════════════
  group('(vii) 箱', () {
    testWidgets('(vii-1) 入口を渡さない箱: 日報の行の下に入口の部品が1つも無い', (tester) async {
      await _pumpSheet(tester, CalendarDayInfo(date: DateTime(2026, 10, 3)), null);
      expect(find.text('日報：なし'), findsOneWidget);
      expect(find.byType(DayRequestEntry), findsNothing);
      expect(find.text(_kBtnDeclare), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_kRetry), findsNothing);
    });

    testWidgets('(vii-2) 入口は日報の行のすぐ下・職長の箱（ほかの人の日報だけ）でも日報の一覧の1枚目より上',
        (tester) async {
      final api = _Fake(elig: [_missingAllowed()]);
      await _pumpSheet(tester, CalendarDayInfo(date: DateTime(2026, 10, 3)),
          _entryFor(api, '2026-10-03'));
      final row = tester.getRect(find.text('日報：なし'));
      final rowBox = tester.getRect(find
          .ancestor(of: find.text('日報：なし'), matching: find.byType(SizedBox))
          .first);
      final entry = tester.getRect(find.byType(DayRequestEntry));
      expect(entry.top, rowBox.bottom, reason: '入口が日報の行のすぐ下に無い');
      expect(entry.top > row.top, isTrue);

      // 職長の箱: ほかの人の日報だけが在る日（自分の id で数えて0枚）。
      final api2 = _Fake(elig: [_missingAllowed()]);
      final day = CalendarDayInfo(
          date: DateTime(2026, 10, 3), reports: [_report('r1', 'u-other')]);
      await _pumpSheet(tester, day,
          _entryFor(api2, '2026-10-03', own: ownLiveReportCount(day.liveReports, 'u-me')));
      final row2 = tester.getRect(find
          .ancestor(of: find.text('日報：1件'), matching: find.byType(SizedBox))
          .first);
      final entry2 = tester.getRect(find.byType(DayRequestEntry));
      final tile = tester.getRect(find.byType(JsReportTile).first);
      expect(entry2.top, row2.bottom, reason: '職長の箱で入口が日報の行のすぐ下に無い');
      expect(entry2.bottom <= tile.top, isTrue, reason: '入口が日報の一覧の1枚目より下');
      expect(find.text(_kBtnDeclare), findsOneWidget);
    });

    test('(vii-3) 見出しの字は今と1字も同じ・日付だけの字は祝日の日でも M月D日（曜）だけ', () {
      final plain = CalendarDayInfo(date: DateTime(2026, 10, 3));
      expect(plain.title, '10月3日（土）');
      expect(plain.dateText, '10月3日（土）');
      final hol = CalendarDayInfo(date: DateTime(2026, 10, 12), jpHolidayName: 'スポーツの日');
      expect(hol.title, '10月12日（月）・祝日：スポーツの日');
      expect(hol.dateText, '10月12日（月）');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (viii) 押せる物の高さ（本物のテーマ）
  // ══════════════════════════════════════════════════════════
  group('(viii) 押せる物の高さ', () {
    const phone = Size(393, 852);
    void tall(WidgetTester tester, Finder f, String name) {
      expect(f, findsOneWidget, reason: '$name が無い');
      final h = tester.getRect(f).height;
      // ignore: avoid_print
      print('［計測］$name の高さ=$h');
      expect(h >= 44, isTrue, reason: '$name の高さが $h（44 未満）');
    }

    testWidgets('(viii-1) no_report の行・3択のボタン3つ・3択の「もう一度」', (tester) async {
      final api = _Fake(elig: [_fixAllowed(), _fail(0, 'x')]);
      await _pump(tester, _register(api), theme: AppTheme.dark, size: phone);
      tall(tester, find.descendant(of: _rowOf(_kRowNoReport), matching: find.byType(InkWell)),
          'no_report の行');
      await tester.tap(find.text(_kRowNoReport));
      await tester.pumpAndSettle();
      tall(tester, find.widgetWithText(OutlinedButton, _kBtnFix), _kBtnFix);
      tall(tester, find.widgetWithText(OutlinedButton, _kBtnCompOff), _kBtnCompOff);
      tall(tester, find.widgetWithText(TextButton, _kBtnPickAgain), _kBtnPickAgain);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text(_kRowNoReport));
      await tester.pumpAndSettle();
      tall(tester, find.widgetWithText(OutlinedButton, _kRetry), '3択の「もう一度」');
    });

    testWidgets('(viii-1) 「依頼を送る」・箱の「日報漏れを申告する」・箱の「もう一度」', (tester) async {
      await _pump(
          tester,
          DayRequestScreen(
              kind: DayRequestKind.attendanceFix,
              workDate: '2026-10-06',
              dateText: _kRowNoReport,
              permitUntilText: _kWeekLast,
              service: _Fake()),
          theme: AppTheme.dark,
          size: phone);
      tall(tester, find.widgetWithText(ElevatedButton, '依頼を送る'), '依頼を送る');

      final api = _Fake(elig: [_missingAllowed()]);
      await _pumpSheet(tester, CalendarDayInfo(date: DateTime(2026, 10, 3)),
          _entryFor(api, '2026-10-03'),
          theme: AppTheme.dark);
      tall(
          tester,
          find
              .ancestor(
                  of: find.text(_kBtnDeclare),
                  matching: find.byWidgetPredicate((w) => w is OutlinedButton))
              .first,
          _kBtnDeclare);

      final api2 = _Fake(elig: [_fail(0, 'x')]);
      await _pumpSheet(tester, CalendarDayInfo(date: DateTime(2026, 10, 3)),
          _entryFor(api2, '2026-10-03'),
          theme: AppTheme.dark);
      tall(tester, find.widgetWithText(OutlinedButton, _kRetry), '箱の「もう一度」');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (ix) 答えの読み方
  // ══════════════════════════════════════════════════════════
  group('(ix) 答えの読み方', () {
    test('(ix-1) 出せる日／出せない日／聞けなかった時に分ける', () {
      final allowed = readDayRequestEligibility(
          _ok(_answer('report_missing', '2026-10-03', canDeclare: true)));
      expect(allowed.kind, DayRequestEligibilityKind.allowed);
      expect(allowed.answer!['type'], 'report_missing');
      expect(allowed.answer!.keys.length, 8);

      final denied = readDayRequestEligibility(_fixDenied());
      expect(denied.kind, DayRequestEligibilityKind.denied);
      expect(denied.text, _kAlreadyFix);
      expect(denied.answer!['request_id'], 'cq-1', reason: '答えを Map のまま持っていない');

      final coded403 =
          readDayRequestEligibility(_fail(403, _kEmployeeOnly, code: 'ATTENDANCE_EMPLOYEE_ONLY'));
      expect(coded403.kind, DayRequestEligibilityKind.denied);
      expect(coded403.text, _kEmployeeOnly);

      final cases = <(String, ApiResult<Map<String, dynamic>>, String?)>[
        ('符号の無い 404', _fail(404, '<html>Not Found</html>'), null),
        ('通信の失敗', _fail(0, 'サーバーに接続できません: SocketException: boom'), null),
        ('500', _fail(500, _kServerError, code: 'SERVER_ERROR'), _kServerError),
        ('can_declare が null', _ok(_answer('report_missing', '2026-10-03', canDeclare: null)), null),
        ('can_declare が字', _ok(_answer('report_missing', '2026-10-03', canDeclare: 'true')), null),
        ('false で reason が空',
            _ok(_answer('report_missing', '2026-10-03', canDeclare: false, code: 'X', reason: '')),
            null),
        ('false で reason が null',
            _ok(_answer('report_missing', '2026-10-03', canDeclare: false, code: 'X')), null),
      ];
      for (final (name, res, text) in cases) {
        final r = readDayRequestEligibility(res);
        expect(r.kind, DayRequestEligibilityKind.unknown, reason: '$name が聞けなかった時になっていない');
        expect(r.text, text, reason: '$name の文が違う');
      }
    });
  });

  // ══════════════════════════════════════════════════════════
  // (x) ソースの字
  // ══════════════════════════════════════════════════════════
  group('(x) ソースの字', () {
    test('(x-1) 箱を開く所が dayRequestEntryOrNull を1回呼び、その答えを箱へ渡す／入口と画面の本は時計を読まない',
        () {
      final src = _codeOnly('lib/screens/home_screen.dart');
      expect('dayRequestEntryOrNull('.allMatches(src).length, 1,
          reason: 'dayRequestEntryOrNull を呼ぶ所が1つでない');
      expect(RegExp(r'dayRequestEntry:\s*dayRequestEntryOrNull\(').hasMatch(src), isTrue,
          reason: '答えを箱（dayRequestEntry）へ渡していない');
      for (final p in ['lib/widgets/day_request_entry.dart', 'lib/screens/day_request_screen.dart']) {
        final all = File(p).readAsStringSync();
        expect(all.contains('DateTime.now'), isFalse, reason: '$p が時計を読んでいる');
        expect(all.contains('jstDateString'), isFalse, reason: '$p が今日を自分で読んでいる');
      }
    });

    test('(x-2) 自分の日報の数を ownLiveReportCount で数えて渡す／自分の id を読む所は1つ', () {
      final src = _codeOnly('lib/screens/home_screen.dart');
      expect('ownLiveReportCount('.allMatches(src).length, 1,
          reason: 'ownLiveReportCount を呼ぶ所が1つでない');
      expect(
          RegExp(r'dayRequestEntryOrNull\([^;]*?ownReportCount:\s*ownLiveReportCount\(',
                  dotAll: true)
              .hasMatch(src),
          isTrue,
          reason: '自分の日報の数を dayRequestEntryOrNull へ渡していない');
      expect('getUserId('.allMatches(src).length, 1,
          reason: 'getUserId を呼ぶ所が1つでない');
    });
  });
}
