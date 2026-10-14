// ============================================================
// test/f8b2_late_report_test.dart
//   便F8b-2＝事務の許可が出た過去の1日ぶんの日報を出す画面（lib/screens/late_report_screen.dart）と、
//   その入口（カレンダーの箱・振替の3択）と、そのために広げた今の物を、機械で固定する。
//
// ★何を守るか（すべて二者比較。「出ない」だけで合格にしない）:
//   (a) 尋ねる口の答えの読み方（許可が出ている日＝permitted）
//   (b) カレンダーの箱の入口（見本 G1）
//   (c) 振替の3択（見本 G2）
//   (d) 新しい画面の段と字（帯・確認の画面の※・提出完了の※・段1・段3）
//   (e) 送る本文（口が断る鍵を除く・confirmation_id）と口の行き先・待ち時間
//   (f) 提出の答えの分け方（見本 H6）
//   (g) 端末の保存に書かない
//   (h) 目安（現場の id で聞く・聞かない時・前の目安を残さない）と compareRoutesV2 の本文
//   (i) 途中で戻る（見本 H1 の※）
//   (j) 今の物の既定（今日の日報は変わらない）
//
// ★掟: 期待の字はこの本の中に直に書く（指示の字・BE の文をそのまま写した）。色は16進の生の値。
//   時計を読まない（日付は字で渡す）。口は ReportsService・RoutesService を extends した偽物を引数で渡す
//   （test/comp_off_flow_test.dart ほかの書き方）。現場の一覧・会社名・同僚は package:http の
//   runWithClient＋MockClient で答える（前例 test/f8b1_report_wire_test.dart）。端末の保存は setMockInitialValues。
// ★検査の名前の頭の番号（(a-1) ほか）は、ログの赤い行からどの検査かを機械で読むための物。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/main.dart'
    show
        TransportType,
        WorkerReportItem,
        permittedReportBodyFor,
        reportBodyFor,
        showConfirmDialog;
import 'package:js_awake_app/screens/home_screen.dart'
    show CalendarDayInfo, CalendarDaySheet, showCalendarDaySheet;
import 'package:js_awake_app/screens/late_report_screen.dart';
import 'package:js_awake_app/screens/substitute_past_day_screen.dart'
    show PastDayFrame, WorkDateNoReportScreen;
import 'package:js_awake_app/screens/substitute_register_screen.dart'
    show SubstituteRegisterScreen;
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';
import 'package:js_awake_app/services/routes_service.dart';
import 'package:js_awake_app/widgets/day_request_entry.dart'
    show
        DayRequestEligibilityKind,
        dayRequestEntryOrNull,
        readDayRequestEligibility;
import 'package:js_awake_app/widgets/photo_strip_field.dart'
    show PhotoStripField;
import 'package:js_awake_app/widgets/report_form_parts.dart';
import 'package:js_awake_app/widgets/report_form_steps.dart';

// ── 色（lib/core/theme/field_tokens.dart の値を16進の生の値で写した）──────
const int _kAccent = 0xFF6FD6B4;
const int _kBrand = 0xFFD9C08A;
const int _kStatusError = 0xFFE05252;

// ── その日・許可（検査が字で決める）─────────────────────────────────
const String _kWorkDate = '2026-09-20';
const String _kDateText = '9月20日（日）';
const String _kPermitUntil = '2026-09-26';

// ── BE の文（js-office-api の services/dayRequests.js・services/permittedReport.js の実文字列を写した）──
const String _kPermitReason = '許可が出ています。9月26日（土）までにこの日の日報を出してください';
const String _kAlreadyFix = 'すでに出勤の修正を依頼しています（事務の確認待ち）';
const String _kNotFound = '許可が見つかりません';
const String _kAlreadySubmitted = 'この許可ではすでに日報を出しています';
const String _kDeadlinePassed = '提出期限（9月26日（土））を過ぎています。事務へご相談ください';
const String _kShiftInvalid = 'shift_type は day または night を指定してください';

// ── 画面の字（指示の字をそのまま写した）──────────────────────────────
const String _kBtnLate = 'この日の日報を出す';
const String _kMarkFix = '振替の出勤日の日報（許可あり）';
const String _kMarkMissing = '日報漏れの日報（許可あり）';
const String _kNoteFix = '※事務が承認すると、この日を振替休日の出勤する日に選べるようになります。';
const String _kNoteMissing = '※出した日報は、事務の承認で確定します。';
const String _kNoteDeadline = '※提出期限は 9月26日（土）です。';
const String _kHeading = 'この内容で提出します';
const String _kSend = '提出する';
const String _kBackToFix = '戻って直す';
const String _kCheck = '内容を確認する';
const String _kCheckNote = '※次の画面で見直してから提出します';
const String _kCheckNoteToday = '※次の画面で見直してから送信します';
const String _kDone = '提出完了';
const String _kDoneDay = '☀日勤 9/20分を提出しました';
const String _kClose = '閉じる';
const String _kCannot = '提出できません';
const String _kNet = '通信エラーが発生しました';
const String _kDenyDefault = 'できませんでした。時間をおいて、もう一度お試しください。';
const String _kPhotoFail = '写真を読み込めませんでした。戻って撮り直してください';
const String _kNightNote = '※夜勤は、9月20日の夜に始まった勤務です';
const String _kLeaveMsg = '入力した内容は保存されません。閉じますか？';
const String _kKeepGoing = '入力を続ける';
const String _kRouteNoData = 'この手段の目安は取得できません';
const String _kRouteFailed = '移動情報を取得できません（タップで再取得）';
const String _kThreeNote = '※日報を出して、事務が承認すると、この日を出勤する日に選べるようになります。';
const String _kNoSite = '該当現場なし';
const String _kSiteName = 'テスト現場';
const String _kHomeAddr = 'テスト県自宅町1-1';
const String _kOfficeAddr = 'テスト県会社町2-2';

// ── 尋ねる口の答え（BE の8つのキーの形）──────────────────────────────
Map<String, dynamic> _permitAns(
  String type, {
  Object? requestId = 42,
  Object? permitUntil = _kPermitUntil,
  Object? reason = _kPermitReason,
  String? confirmType = 'report_missing',
}) =>
    {
      'type': type,
      'work_date': _kWorkDate,
      'can_declare': false,
      'code': 'ALREADY_PERMITTED',
      'reason': reason,
      'permit_until': permitUntil,
      'request_id': requestId,
      'confirm_type': confirmType,
    };

ApiResult<Map<String, dynamic>> _ok(Map<String, dynamic> d) =>
    apiSuccess<Map<String, dynamic>>(statusCode: 200, data: d);

// ── 提出の口の答え ───────────────────────────────────────────────
ApiResult<Map<String, dynamic>> _created() => apiSuccess<Map<String, dynamic>>(
    statusCode: 201,
    data: const {
      'success': true,
      'message': '日報を受信しました',
      'report_id': 'r-1',
      'report_date': _kWorkDate,
    });

ApiResult<Map<String, dynamic>> _conflict(String code, String msg) =>
    apiFailure<Map<String, dynamic>>(
        statusCode: 409,
        errorMessage: msg,
        errorCode: code,
        errorDetails: {'error': msg, 'code': code});

/// サーバまで届かなかった（runApiCall の例外の道の形）。
ApiResult<Map<String, dynamic>> _net0() => apiFailure<Map<String, dynamic>>(
    statusCode: 0, errorMessage: 'サーバーに接続できません: SocketException: boom');

ApiResult<Map<String, dynamic>> _already() =>
    _conflict('ALREADY_SUBMITTED', _kAlreadySubmitted);

/// 本文が JSON でない答え（中継の 502 や、HTML の 400）。
ApiResult<Map<String, dynamic>> _html(int status) => apiFailure<Map<String, dynamic>>(
    statusCode: status, errorMessage: '<html>Bad Gateway</html>');

// ── 差し替える口 ──────────────────────────────────────────────────
class _Fake extends ReportsService {
  _Fake({
    List<ApiResult<Map<String, dynamic>>>? elig,
    List<ApiResult<Map<String, dynamic>>>? sends,
  })  : elig = elig ?? [_ok(_permitAns('report_missing'))],
        sends = sends ?? [_created()],
        super.forTest();

  final List<ApiResult<Map<String, dynamic>>> elig;
  final List<ApiResult<Map<String, dynamic>>> sends;
  final List<String> eligCalls = [];
  final List<String> candidateCalls = [];
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<ApiResult<Map<String, dynamic>>> getDayRequestEligibility(
      String type, String workDate) async {
    eligCalls.add('$type|$workDate');
    final i = eligCalls.length - 1;
    return elig[i < elig.length ? i : elig.length - 1];
  }

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
      'days': _week(),
    });
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> submitPermittedReport(
      Map<String, dynamic> body) async {
    bodies.add(Map<String, dynamic>.from(body));
    final i = bodies.length - 1;
    return sends[i < sends.length ? i : sends.length - 1];
  }
}

class _Routes extends RoutesService {
  _Routes([List<RouteCompareResult>? results])
      : results = results ?? [const RouteCompareResult.failed(RouteFailure.empty)];
  final List<RouteCompareResult> results;
  final List<({String origin, String? destination, String? siteId})> calls = [];

  @override
  Future<RouteCompareResult> compareRoutesV2({
    required String origin,
    String? destination,
    String? siteId,
  }) async {
    calls.add((origin: origin, destination: destination, siteId: siteId));
    final i = calls.length - 1;
    return results[i < results.length ? i : results.length - 1];
  }
}

/// 1回目はすぐ答え、2回目からは答えを待たせる目安の口（便BJ・取り直しの間を作る）。
class _SlowRoutes extends _Routes {
  _SlowRoutes(this.first) : super();
  final RouteCompareResult first;
  final List<Completer<RouteCompareResult>> pending = [];
  int count = 0;

  @override
  Future<RouteCompareResult> compareRoutesV2({
    required String origin,
    String? destination,
    String? siteId,
  }) {
    count++;
    if (count == 1) return Future.value(first);
    final c = Completer<RouteCompareResult>();
    pending.add(c);
    return c.future;
  }
}

CarRoute _car() => CarRoute(
      time: 28,
      distanceM: 12400,
      distanceText: '12.4km',
      tollNormal: 300,
      tollLight: 250,
      gasCost: 141,
      totalNormal: 441,
      totalLight: 391,
    );

// ── 候補の口の days[]（2026-09-20（日）〜09-26（土）・09-20 が no_report）──────
Map<String, dynamic> _day(String date, int dow, {String? code, String? reason}) => {
      'date': date,
      'dow': dow,
      'selectable': code == null,
      'reason_code': code,
      'reason': reason,
    };

List<Map<String, dynamic>> _week() => [
      _day('2026-09-20', 0, code: 'no_report', reason: 'この日の日報がありません'),
      _day('2026-09-21', 1, code: 'not_holiday', reason: '会社の休みの日ではありません'),
      _day('2026-09-22', 2, code: 'same_as_rest_date', reason: '休む日と同じ日です'),
      _day('2026-09-23', 3),
      _day('2026-09-24', 4, code: 'not_holiday', reason: '会社の休みの日ではありません'),
      _day('2026-09-25', 5, code: 'not_holiday', reason: '会社の休みの日ではありません'),
      _day('2026-09-26', 6),
    ];

// ── 端末の保存（読むだけの値）────────────────────────────────────────
Map<String, Object> _prefs({Map<String, Object> extra = const {}}) => {
      'auth_token': 'T',
      'user_name': '検査 太郎',
      'company_name': 'J電気',
      'last_transports': 'train',
      ...extra,
    };

// ── 偽物の通信（現場の一覧・会社名・同僚）────────────────────────────────
final List<http.Request> _seen = [];
Future<T> _withServer<T>(Future<T> Function() run) => http.runWithClient(
      run,
      () => MockClient((req) async {
        _seen.add(req);
        final path = req.url.path;
        Object body;
        if (path.endsWith('/sites')) {
          body = {
            'sites': [
              {'site_id': 's-1', 'site_name': _kSiteName},
            ],
          };
        } else if (path.endsWith('/workers/colleagues')) {
          body = {
            'names': ['同僚 一郎'],
          };
        } else if (path.endsWith('/companies/search')) {
          body = {
            'companies': [
              {'company_name': '相乗り商事'},
            ],
          };
        } else {
          body = {'error': 'not found'};
          return http.Response(jsonEncode(body), 404,
              request: req,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response(jsonEncode(body), 200,
            request: req,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

// ── 立て方 ──────────────────────────────────────────────────────────
Future<void> _pump(WidgetTester tester, Widget home,
    {Size size = const Size(800, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
}

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

Future<_Host> _openLate(
  WidgetTester tester, {
  _Fake? api,
  _Routes? routes,
  String? confirmType = 'report_missing',
}) async {
  final host = _Host();
  final a = api ?? _Fake();
  final r = routes ?? _Routes();
  await _pump(
      tester,
      host.build(() => LateReportScreen(
            workDate: _kWorkDate,
            dateText: _kDateText,
            confirmationId: '42',
            confirmType: confirmType,
            permitUntil: _kPermitUntil,
            reportsService: a,
            routesService: r,
          )));
  await tester.tap(find.text('ひらく'));
  await tester.pumpAndSettle();
  return host;
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// 移動手段の札（2度押しの待ちがある＝1回押しは待ちの後に届く）。
Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// 段1 → 段2 → 段3 → 確認の画面。
Future<void> _toConfirm(WidgetTester tester) async {
  await _tapText(tester, '次へ');
  await _tapText(tester, '次へ');
  await _tapText(tester, _kCheck);
}

/// 「提出する」→ 駐車場の写真なしの窓 →「このまま提出」。
///   ★窓が出ている間、確認の画面の送るボタンは回っている（くるくるは止まらない）ので、pumpAndSettle で待たない。
Future<void> _sendThroughPhotoDialog(WidgetTester tester) async {
  await tester.tap(find.text(_kSend));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text('写真が添付されていません'), findsOneWidget);
  await _tapText(tester, 'このまま提出');
}

/// 1x1 の PNG（写真の帯が絵として読める中身）。
const String _kPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

/// 本物のファイルを読む道（写真）を待つ。
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder _inConfirm(Finder f) =>
    find.descendant(of: find.byType(ReportConfirmScreen), matching: f);

String _band(String? mark) => mark == null ? _kDateText : '$mark　$_kDateText';

/// 説明文だけの行（空白の後が // で始まる行）を除いたソースの字。
String _codeOnly(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  setUp(() {
    _seen.clear();
    SharedPreferences.setMockInitialValues(_prefs());
  });

  // ══════════════════════════════════════════════════════════
  // (a) 答えの読み方
  // ══════════════════════════════════════════════════════════
  group('(a) 読み方', () {
    test('(a-1) ALREADY_PERMITTED と request_id と reason と permit_until が在る → permitted（文と答え）／欠ければ unknown', () {
      final ans = _permitAns('report_missing');
      final r = readDayRequestEligibility(_ok(ans));
      expect(r.kind, DayRequestEligibilityKind.permitted);
      expect(r.text, _kPermitReason);
      expect(identical(r.answer, ans), isTrue, reason: '答えを Map のまま持っていない');
      // 二者比較：どれかが欠けると「聞けなかった時」。
      for (final (name, bad) in [
        ('request_id が null', _permitAns('report_missing', requestId: null)),
        ('request_id が空', _permitAns('report_missing', requestId: '')),
        ('permit_until が空', _permitAns('report_missing', permitUntil: '')),
        ('permit_until が null', _permitAns('report_missing', permitUntil: null)),
        ('reason が空', _permitAns('report_missing', reason: '')),
      ]) {
        final x = readDayRequestEligibility(_ok(bad));
        expect(x.kind, DayRequestEligibilityKind.unknown, reason: name);
        expect(x.answer, bad, reason: '$name の答えを持っていない');
      }
    });

    test('(a-2) 今の分け方は変わらない：ALREADY_REQUESTED は denied・can_declare true は allowed', () {
      final denied = readDayRequestEligibility(_ok({
        ..._permitAns('attendance_fix'),
        'code': 'ALREADY_REQUESTED',
        'reason': _kAlreadyFix,
      }));
      expect(denied.kind, DayRequestEligibilityKind.denied);
      expect(denied.text, _kAlreadyFix);
      final allowed = readDayRequestEligibility(_ok({
        ..._permitAns('attendance_fix'),
        'can_declare': true,
        'code': null,
        'reason': null,
      }));
      expect(allowed.kind, DayRequestEligibilityKind.allowed);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (b) カレンダーの箱の入口（見本 G1）
  // ══════════════════════════════════════════════════════════
  group('(b) 箱の入口', () {
    Future<void> openBox(WidgetTester tester, _Fake api, void Function() onChanged) async {
      final day = CalendarDayInfo(date: DateTime(2026, 9, 20));
      await _pump(
        tester,
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCalendarDaySheet(ctx,
                    info: day,
                    maxHeight: 2000,
                    dayRequestEntry: dayRequestEntryOrNull(
                      workDate: _kWorkDate,
                      today: '2026-10-11',
                      ownReportCount: 0,
                      hasOwnRest: false,
                      substitutePendingRest: false,
                      dateText: day.dateText,
                      service: api,
                      onReportsChanged: onChanged,
                    )),
                child: const Text('ひらく'),
              ),
            ),
          ),
        ),
      );
      await _tapText(tester, 'ひらく');
    }

    testWidgets('(b-1) 許可が出ている日：accent の線の枠（見出しなし）にサーバの文・「この日の日報を出す」（幅いっぱい）／申告の字は無い',
        (tester) async {
      final api = _Fake();
      await openBox(tester, api, () {});
      expect(api.eligCalls, ['report_missing|$_kWorkDate']);
      expect(find.text(_kPermitReason), findsOneWidget);
      final frame = tester.widget<PastDayFrame>(find.byType(PastDayFrame));
      expect(frame.lineColor.toARGB32(), _kAccent);
      expect(frame.heading, isNull, reason: '枠に見出しが在る');
      expect(find.text(_kBtnLate), findsOneWidget);
      expect(tester.getSize(find.widgetWithText(OutlinedButton, _kBtnLate)).width,
          tester.getSize(find.byType(PastDayFrame)).width,
          reason: 'ボタンが幅いっぱいでない');
      for (final t in ['申告できません', '日報漏れを申告する', 'もう一度']) {
        expect(find.text(t), findsNothing, reason: '$t が在る');
      }
      // 二者比較：出せない日（ALREADY_REQUESTED）は「申告できません」で、入口のボタンは無い。
      final api2 = _Fake(elig: [
        _ok({..._permitAns('report_missing'), 'code': 'ALREADY_REQUESTED', 'reason': _kAlreadyFix})
      ]);
      await openBox(tester, api2, () {});
      expect(find.text('申告できません'), findsOneWidget);
      expect(find.text(_kBtnLate), findsNothing);
    });

    testWidgets('(b-2) 押すと箱が閉じて新しい画面（帯と日付）／出せたら提出完了の「閉じる」で1回呼ぶ・戻る矢印でも1回',
        (tester) async {
      for (final byArrow in [false, true]) {
        var changed = 0;
        final api = _Fake();
        await openBox(tester, api, () => changed++);
        await _tapText(tester, _kBtnLate);
        expect(find.byType(CalendarDaySheet), findsNothing, reason: '箱が残っている');
        expect(find.byType(LateReportScreen), findsOneWidget);
        expect(find.text(_band(_kMarkMissing)), findsOneWidget, reason: '帯が無い');
        expect(find.text('$_kDateText・☀日勤'), findsOneWidget);
        await _toConfirm(tester);
        await _tapText(tester, _kSend);
        expect(api.bodies.single['confirmation_id'], '42', reason: 'request_id を字にして渡していない');
        expect(find.text(_kDone), findsOneWidget);
        expect(changed, 0, reason: '閉じる前に呼んでいる');
        if (byArrow) {
          await tester.pageBack();
        } else {
          await tester.tap(find.text(_kClose));
        }
        await tester.pumpAndSettle();
        expect(find.byType(LateReportScreen), findsNothing);
        expect(changed, 1, reason: byArrow ? '戻る矢印で閉じた時' : '「閉じる」で閉じた時');
      }
    });

    testWidgets('(b-3) closed で戻っても1回呼ぶ／出さずに戻ったら呼ばない', (tester) async {
      var changed = 0;
      final api = _Fake(sends: [_conflict('PERMIT_NOT_FOUND', _kNotFound)]);
      await openBox(tester, api, () => changed++);
      await _tapText(tester, _kBtnLate);
      await _toConfirm(tester);
      await _tapText(tester, _kSend);
      await _tapText(tester, _kClose);
      expect(find.byType(LateReportScreen), findsNothing);
      expect(changed, 1, reason: 'closed で戻った時に呼んでいない');

      var changed2 = 0;
      await openBox(tester, _Fake(), () => changed2++);
      await _tapText(tester, _kBtnLate);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(LateReportScreen), findsNothing);
      expect(changed2, 0, reason: '出さずに戻ったのに呼んでいる');
    });

    testWidgets('(b-4) permit_until が空の答えは「聞けなかった時」（もう一度）・入口のボタンは無い', (tester) async {
      await openBox(tester, _Fake(elig: [_ok(_permitAns('report_missing', permitUntil: ''))]), () {});
      expect(find.text('もう一度'), findsOneWidget);
      expect(find.text(_kBtnLate), findsNothing);
      expect(find.text(_kPermitReason), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (c) 振替の3択（見本 G2）
  // ══════════════════════════════════════════════════════════
  group('(c) 3択', () {
    _Fake fixApi({List<ApiResult<Map<String, dynamic>>>? sends,
            List<ApiResult<Map<String, dynamic>>>? elig}) =>
        _Fake(
            elig: elig ?? [_ok(_permitAns('attendance_fix', confirmType: 'attendance_fix'))],
            sends: sends);

    Future<void> open3(WidgetTester tester, _Fake api) async {
      await _pump(tester, SubstituteRegisterScreen(restDate: '2026-09-22', service: api));
      await _tapText(tester, _kDateText);
      expect(find.byType(WorkDateNoReportScreen), findsOneWidget);
    }

    testWidgets('(c-1) 許可が出ている日：枠（見出しなし）・「この日の日報を出す」「代休で取る」「日を選び直す」・※が上から順／依頼のボタンは無い',
        (tester) async {
      final api = fixApi();
      await open3(tester, api);
      expect(api.eligCalls, ['attendance_fix|$_kWorkDate']);
      final frame = tester.widget<PastDayFrame>(find.byType(PastDayFrame));
      expect(frame.lineColor.toARGB32(), _kAccent);
      expect(frame.heading, isNull);
      final ys = [
        tester.getTopLeft(find.text(_kPermitReason)).dy,
        tester.getTopLeft(find.text(_kBtnLate)).dy,
        tester.getTopLeft(find.text('代休で取る')).dy,
        tester.getTopLeft(find.text('日を選び直す')).dy,
        tester.getTopLeft(find.text(_kThreeNote)).dy,
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i] > ys[i - 1], isTrue, reason: '並びが違う（$ys）');
      }
      expect(find.text('出勤の修正を依頼する'), findsNothing);
      // 二者比較：出せる日は依頼のボタンが在り、「この日の日報を出す」は無い。
      final api2 = fixApi(elig: [
        _ok({..._permitAns('attendance_fix'), 'can_declare': true, 'code': null, 'reason': null})
      ]);
      await open3(tester, api2);
      expect(find.text('出勤の修正を依頼する'), findsOneWidget);
      expect(find.text(_kBtnLate), findsNothing);
      expect(find.text(_kThreeNote), findsNothing);
    });

    testWidgets('(c-2) 出せたら reported で閉じ、登録の画面が候補を引き直す（「閉じる」でも戻る矢印でも）', (tester) async {
      for (final byArrow in [false, true]) {
        final api = fixApi();
        await open3(tester, api);
        expect(api.candidateCalls.length, 1);
        await _tapText(tester, _kBtnLate);
        expect(find.text(_band(_kMarkFix)), findsOneWidget);
        await _toConfirm(tester);
        await _tapText(tester, _kSend);
        expect(find.text(_kDone), findsOneWidget);
        if (byArrow) {
          await tester.pageBack();
        } else {
          await tester.tap(find.text(_kClose));
        }
        await tester.pumpAndSettle();
        expect(find.byType(LateReportScreen), findsNothing);
        expect(find.byType(WorkDateNoReportScreen), findsNothing, reason: '3択が閉じていない');
        expect(find.byType(SubstituteRegisterScreen), findsOneWidget);
        expect(api.candidateCalls.length, 2, reason: '候補を引き直していない（${byArrow ? '戻る矢印' : '閉じる'}）');
      }
    });

    testWidgets('(c-3) closed で戻ったら3択が聞き直す／出さずに戻ったら何も起きない', (tester) async {
      final api = fixApi(sends: [_conflict('PERMIT_DEADLINE_PASSED', _kDeadlinePassed)]);
      await open3(tester, api);
      await _tapText(tester, _kBtnLate);
      await _toConfirm(tester);
      await _tapText(tester, _kSend);
      await _tapText(tester, _kClose);
      expect(find.byType(LateReportScreen), findsNothing);
      expect(find.byType(WorkDateNoReportScreen), findsOneWidget);
      expect(api.eligCalls.length, 2, reason: '聞き直していない');
      expect(api.candidateCalls.length, 1);

      final api2 = fixApi();
      await open3(tester, api2);
      await _tapText(tester, _kBtnLate);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(LateReportScreen), findsNothing);
      expect(find.byType(WorkDateNoReportScreen), findsOneWidget);
      expect(api2.eligCalls.length, 1, reason: '出さずに戻ったのに聞き直した');
      expect(api2.candidateCalls.length, 1);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (d) 新しい画面の段と字
  // ══════════════════════════════════════════════════════════
  group('(d) 画面の段と字', () {
    testWidgets('(d-1) 帯・確認の画面の※2行・提出完了の※を、attendance_fix・report_missing・null の3つで見る',
        (tester) async {
      for (final (type, mark, note) in [
        ('attendance_fix', _kMarkFix, _kNoteFix),
        ('report_missing', _kMarkMissing, _kNoteMissing),
        (null, null, null),
      ]) {
        await _openLate(tester, confirmType: type);
        final band = find.text(_band(mark));
        expect(band, findsOneWidget, reason: '$type の帯（フォーム）');
        final bandText = tester.widget<Text>(band);
        expect(bandText.style?.color?.toARGB32(), _kBrand);
        expect(bandText.style?.fontSize, 12);
        if (mark == null) {
          expect(find.textContaining('（許可あり）'), findsNothing, reason: 'null で印の語が在る');
        }
        await _toConfirm(tester);
        expect(_inConfirm(find.text(_band(mark))), findsOneWidget, reason: '$type の帯（確認の画面）');
        expect(_inConfirm(find.text(_kHeading)), findsOneWidget);
        expect(_inConfirm(find.text(_kNoteDeadline)), findsOneWidget, reason: '※の1行目');
        expect(_inConfirm(find.textContaining('1回だけ')), findsNothing);
        for (final n in [_kNoteFix, _kNoteMissing]) {
          expect(_inConfirm(find.text(n)), n == note ? findsOneWidget : findsNothing,
              reason: '$type の※の2行目（$n）');
        }
        await _tapText(tester, _kSend);
        expect(find.text(_kDone), findsOneWidget);
        expect(find.text(_kDoneDay), findsOneWidget);
        expect(find.text(_band(mark)), findsNothing, reason: '提出完了に帯が在る');
        for (final n in [_kNoteFix, _kNoteMissing]) {
          expect(find.text(n), n == note ? findsOneWidget : findsNothing,
              reason: '$type の提出完了の※（$n）');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('(d-2) 段1の字（日付と勤務・この日の報告・勤務の2つ・該当現場なし）／現在地と今日の報告が無い／夜勤の※／段3の※',
        (tester) async {
      await _openLate(tester);
      expect(find.text('$_kDateText・☀日勤'), findsOneWidget);
      expect(find.text('この日の報告'), findsOneWidget);
      expect(find.text('☀ 日勤'), findsOneWidget);
      expect(find.text('🌙 夜勤'), findsOneWidget);
      expect(find.text(_kNoSite), findsOneWidget);
      expect(find.text('今日の報告'), findsNothing);
      expect(find.textContaining('現在地'), findsNothing);
      // 二者比較：日勤の時は夜勤の※が無い → 夜勤を押すと在る。
      expect(find.text(_kNightNote), findsNothing);
      await _tapText(tester, '🌙 夜勤');
      expect(find.text(_kNightNote), findsOneWidget);
      expect(find.text('$_kDateText・🌙夜勤'), findsOneWidget);
      await _tapText(tester, '次へ');
      await _tapText(tester, '次へ');
      expect(find.text(_kCheckNote), findsOneWidget);
      expect(find.text(_kCheckNoteToday), findsNothing);
    });

    test('(d-3) 曜日の字：jpMonthDayDowOf（形が違えば受けた字のまま）', () {
      expect(jpMonthDayDowOf('2026-09-26'), '9月26日（土）');
      expect(jpMonthDayDowOf('2026-10-11'), '10月11日（日）');
      expect(jpMonthDayDowOf('2026-02-30'), '2026-02-30');
      expect(jpMonthDayDowOf('9/26'), '9/26');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (e) 送る本文
  // ══════════════════════════════════════════════════════════
  group('(e) 送る本文', () {
    test('(e-1) 口が断る鍵を除き confirmation_id を足す・ほかの鍵と値は reportBodyFor と同じ', () {
      final item = WorkerReportItem(
        id: 'e1',
        name: '検査 太郎',
        transport: TransportType.car,
        transportTypes: ['car'],
        parkingFee: '500',
        workContent: '配線',
        gpsAddress: 'テスト県テスト市1-2-3',
        gpsLat: 34.5,
        gpsLon: 135.25,
        originType: 'office',
        siteId: 's-1',
        shiftType: 'night',
        timestamp: DateTime.utc(2026, 9, 20, 9, 5),
      );
      final today = reportBodyFor(item);
      final late = permittedReportBodyFor(item, confirmationId: '42');
      const refused = ['report_date', 'clock_in_time', 'gps_address', 'gps_lat', 'gps_lon'];
      for (final k in refused) {
        expect(today.containsKey(k), isTrue, reason: '今日の本文に $k が無い（対照）');
        expect(late.containsKey(k), isFalse, reason: '後から出す本文に $k が在る');
      }
      expect(late.containsKey('clock_out_time'), isFalse);
      expect(late['confirmation_id'], '42');
      expect(today.containsKey('confirmation_id'), isFalse);
      final rest = Map<String, dynamic>.from(today)..removeWhere((k, _) => refused.contains(k));
      expect(Map<String, dynamic>.from(late)..remove('confirmation_id'), rest);
      expect(late.keys.toList(), [...rest.keys, 'confirmation_id'], reason: '鍵の並び');
    });

    test('(e-2) 口の行き先は /reports/permitted・待ち時間は30秒（ソースの字）', () {
      final src = _codeOnly('lib/services/reports_service.dart');
      final i = src.indexOf('submitPermittedReport(');
      expect(i, greaterThan(0));
      final end = src.indexOf('apiJsonMap', i);
      final block = src.substring(i, end);
      expect(block.contains(r"Uri.parse('$kApiBaseUrl/reports/permitted')"), isTrue);
      expect(block.contains('http.post('), isTrue);
      expect(block.contains('.timeout(const Duration(seconds: 30))'), isTrue);
      expect(block.contains("'ReportsService.submitPermittedReport'"), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (f) 提出の答えの分け方（見本 H6）
  // ══════════════════════════════════════════════════════════
  group('(f) 提出', () {
    void expectTwoButtons() {
      expect(_inConfirm(find.text(_kSend)), findsOneWidget, reason: '提出するが無い');
      expect(_inConfirm(find.text(_kBackToFix)), findsOneWidget, reason: '戻って直すが無い');
      expect(_inConfirm(find.text(_kClose)), findsNothing);
    }

    void expectCloseOnly() {
      expect(_inConfirm(find.text(_kClose)), findsOneWidget, reason: '閉じるが無い');
      expect(_inConfirm(find.text(_kSend)), findsNothing, reason: '提出するが在る');
      expect(_inConfirm(find.text(_kBackToFix)), findsNothing, reason: '戻って直すが在る');
    }

    testWidgets('(f-1) 成功：提出完了の字と※と「閉じる」・閉じると submitted', (tester) async {
      final api = _Fake();
      final host = await _openLate(tester, api: api);
      await _toConfirm(tester);
      await _tapText(tester, _kSend);
      expect(api.bodies.length, 1);
      expect(find.byType(ReportConfirmScreen), findsNothing);
      expect(find.text(_kDone), findsOneWidget);
      expect(find.text(_kDoneDay), findsOneWidget);
      expect(find.text(_kNoteMissing), findsOneWidget);
      await _tapText(tester, _kClose);
      expect(host.closed, isTrue);
      expect(host.result, LateReportResult.submitted);
    });

    testWidgets('(f-2) 409 の3つ：「提出できません」とサーバの文と「閉じる」だけ・閉じると closed', (tester) async {
      for (final (code, msg) in [
        ('PERMIT_NOT_FOUND', _kNotFound),
        ('PERMIT_DEADLINE_PASSED', _kDeadlinePassed),
        ('ALREADY_SUBMITTED', _kAlreadySubmitted),
      ]) {
        final host = await _openLate(tester, api: _Fake(sends: [_conflict(code, msg)]));
        await _toConfirm(tester);
        await _tapText(tester, _kSend);
        expect(_inConfirm(find.text(_kCannot)), findsOneWidget, reason: code);
        expect(_inConfirm(find.text(msg)), findsOneWidget, reason: code);
        final frame = tester.widget<PastDayFrame>(_inConfirm(find.byType(PastDayFrame)));
        expect(frame.lineColor.toARGB32(), _kStatusError);
        expectCloseOnly();
        await _tapText(tester, _kClose);
        expect(find.byType(ReportConfirmScreen), findsNothing);
        expect(find.byType(LateReportScreen), findsNothing);
        expect(host.result, LateReportResult.closed, reason: code);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('(f-3) statusCode 0：見出しの無い「通信エラーが発生しました」とボタン2つ（例外の字は出ない）', (tester) async {
      await _openLate(tester, api: _Fake(sends: [_net0()]));
      await _toConfirm(tester);
      await _tapText(tester, _kSend);
      expect(_inConfirm(find.text(_kNet)), findsOneWidget);
      expect(_inConfirm(find.text(_kCannot)), findsNothing);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(tester.widget<PastDayFrame>(_inConfirm(find.byType(PastDayFrame))).heading, isNull);
      expectTwoButtons();
    });

    testWidgets('(f-4) 0 の後に内容を変えずに押し直して ALREADY_SUBMITTED → 提出完了', (tester) async {
      final api = _Fake(sends: [_net0(), _already()]);
      final host = await _openLate(tester, api: api);
      await _toConfirm(tester);
      await _tapText(tester, _kSend);
      expect(_inConfirm(find.text(_kNet)), findsOneWidget);
      await _tapText(tester, _kSend);
      expect(api.bodies.length, 2);
      expect(find.text(_kDone), findsOneWidget);
      await _tapText(tester, _kClose);
      expect(host.result, LateReportResult.submitted);
    });

    testWidgets('(f-5) 0 の後に、作業内容／勤務だけ／出発地だけを替えて押し直して ALREADY_SUBMITTED → どれも「提出できません」と「閉じる」だけ',
        (tester) async {
      for (final change in ['work', 'shift', 'origin']) {
        final api = _Fake(sends: [_net0(), _already()]);
        await _openLate(tester, api: api);
        await _toConfirm(tester);
        await _tapText(tester, _kSend);
        await _tapText(tester, _kBackToFix);
        switch (change) {
          case 'work':
            await tester.enterText(find.byType(TextField).first, '配線の直し');
            await tester.pumpAndSettle();
          case 'shift':
            await _tapText(tester, '戻る');
            await _tapText(tester, '戻る');
            await _tapText(tester, '🌙 夜勤');
            await _tapText(tester, '次へ');
            await _tapText(tester, '次へ');
          case 'origin':
            await _tapText(tester, '戻る');
            await _tapText(tester, '会社');
            await _tapText(tester, '次へ');
        }
        await _tapText(tester, _kCheck);
        await _tapText(tester, _kSend);
        expect(api.bodies.length, 2, reason: change);
        expect(api.bodies[0].toString() == api.bodies[1].toString(), isFalse,
            reason: '$change を替えても本文が同じ');
        expect(find.text(_kDone), findsNothing, reason: change);
        expect(_inConfirm(find.text(_kCannot)), findsOneWidget, reason: change);
        expect(_inConfirm(find.text(_kAlreadySubmitted)), findsOneWidget, reason: change);
        expectCloseOnly();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('(f-6) 内容の違う 0 が2回の後に、2回目と同じ内容で押し直して ALREADY_SUBMITTED →「提出できません」と「閉じる」だけ',
        (tester) async {
      final api = _Fake(sends: [_net0(), _net0(), _already()]);
      await _openLate(tester, api: api);
      await _toConfirm(tester);
      await _tapText(tester, _kSend);
      await _tapText(tester, _kBackToFix);
      await tester.enterText(find.byType(TextField).first, '2回目の内容');
      await tester.pumpAndSettle();
      await _tapText(tester, _kCheck);
      await _tapText(tester, _kSend);
      expect(_inConfirm(find.text(_kNet)), findsOneWidget);
      await _tapText(tester, _kSend);
      expect(api.bodies.length, 3);
      expect(api.bodies[1].toString(), api.bodies[2].toString());
      expect(find.text(_kDone), findsNothing);
      expect(_inConfirm(find.text(_kCannot)), findsOneWidget);
      expectCloseOnly();
    });

    testWidgets('(f-7) 0 の後に「戻って直す」から確認の画面を開き直すと、前の知らせは出ていない', (tester) async {
      await _openLate(tester, api: _Fake(sends: [_net0()]));
      await _toConfirm(tester);
      await _tapText(tester, _kSend);
      expect(_inConfirm(find.text(_kNet)), findsOneWidget);
      await _tapText(tester, _kBackToFix);
      await _tapText(tester, _kCheck);
      expect(_inConfirm(find.text(_kNet)), findsNothing);
      expect(_inConfirm(find.byType(PastDayFrame)), findsNothing);
      expectTwoButtons();
    });

    testWidgets('(f-8) 400 の符号つき（code の物も error_code の物も）：サーバの文とボタン2つ', (tester) async {
      for (final res in [
        apiFailure<Map<String, dynamic>>(
            statusCode: 400,
            errorMessage: '名前は必須です',
            errorCode: 'SOME_CODE',
            errorDetails: {'success': false, 'error': '名前は必須です', 'code': 'SOME_CODE'}),
        apiFailure<Map<String, dynamic>>(
            statusCode: 400,
            errorMessage: _kShiftInvalid,
            errorDetails: {
              'success': false,
              'error': _kShiftInvalid,
              'error_code': 'INVALID_SHIFT_TYPE'
            }),
      ]) {
        await _openLate(tester, api: _Fake(sends: [res]));
        await _toConfirm(tester);
        await _tapText(tester, _kSend);
        expect(_inConfirm(find.text(_kCannot)), findsOneWidget);
        expect(_inConfirm(find.text(res.errorMessage!)), findsOneWidget);
        expect(_inConfirm(find.text(_kDenyDefault)), findsNothing);
        expectTwoButtons();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('(f-9) 本文が JSON でない 502：見出しの無い「通信エラーが発生しました」とボタン2つ・押し直して ALREADY_SUBMITTED → 提出完了',
        (tester) async {
      final api = _Fake(sends: [_html(502), _already()]);
      await _openLate(tester, api: api);
      await _toConfirm(tester);
      await _tapText(tester, _kSend);
      expect(_inConfirm(find.text(_kNet)), findsOneWidget);
      expect(_inConfirm(find.text(_kCannot)), findsNothing);
      expect(find.textContaining('<html>'), findsNothing);
      expectTwoButtons();
      await _tapText(tester, _kSend);
      expect(find.text(_kDone), findsOneWidget);
    });

    testWidgets('(f-10) 本文が JSON でない 400：決まりの字とボタン2つ（本文の頭の字は出ない）', (tester) async {
      await _openLate(tester, api: _Fake(sends: [_html(400)]));
      await _toConfirm(tester);
      await _tapText(tester, _kSend);
      expect(_inConfirm(find.text(_kCannot)), findsOneWidget);
      expect(_inConfirm(find.text(_kDenyDefault)), findsOneWidget);
      expect(find.textContaining('<html>'), findsNothing);
      expectTwoButtons();
    });

    testWidgets('(f-11) 200 台で本文を読めない答え：「通信エラーが発生しました」とボタン2つ・押し直して ALREADY_SUBMITTED → 提出完了',
        (tester) async {
      final api = _Fake(sends: [
        apiFailure<Map<String, dynamic>>(statusCode: 201, errorMessage: '応答の解析に失敗しました'),
        _already(),
      ]);
      await _openLate(tester, api: api);
      await _toConfirm(tester);
      await _tapText(tester, _kSend);
      expect(_inConfirm(find.text(_kNet)), findsOneWidget);
      expect(find.text('応答の解析に失敗しました'), findsNothing);
      expectTwoButtons();
      await _tapText(tester, _kSend);
      expect(find.text(_kDone), findsOneWidget);
    });

    testWidgets('(f-12) 写真が読めない：「写真を読み込めませんでした…」で送らない／対照：読める写真は送る', (tester) async {
      final dir = Directory.systemTemp.createTempSync('f8b2_late_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      // ★写真の帯は絵として読むので、中身は本物の PNG。読めない回は、帯が読み終えた後にファイルを消す
      //   （送る時に読めない＝消えた・壊れた写真）。
      for (final readable in [false, true]) {
        final path = '${dir.path}/work_$readable.png';
        File(path).writeAsBytesSync(base64Decode(_kPngBase64));
        final api = _Fake();
        await _openLate(tester, api: api);
        await _tapText(tester, '次へ');
        await _tapText(tester, '次へ');
        tester.widget<PhotoStripField>(find.byType(PhotoStripField)).onChanged([path]);
        await _settleIo(tester);
        if (!readable) File(path).deleteSync();
        await _tapText(tester, _kCheck);
        await tester.tap(find.text(_kSend));
        await _settleIo(tester);
        if (readable) {
          expect(api.bodies.length, 1);
          expect(api.bodies.single['photos'], [
            {'photo_type': 'site', 'base64': _kPngBase64}
          ]);
          expect(find.text(_kDone), findsOneWidget);
        } else {
          expect(api.bodies.length, 0, reason: '読めない写真で送った');
          expect(_inConfirm(find.text(_kPhotoFail)), findsOneWidget);
          expect(_inConfirm(find.text(_kCannot)), findsOneWidget);
          expectTwoButtons();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });

  // ══════════════════════════════════════════════════════════
  // (g) 端末の保存に書かない
  // ══════════════════════════════════════════════════════════
  group('(g) 端末の保存', () {
    testWidgets('(g-1) 開いてから出し終わるまで、端末の保存の鍵と値の全部が同じ（入力の途中の操作を含む）', (tester) async {
      await _withServer(() async {
        final prefs = await SharedPreferences.getInstance();
        Map<String, Object?> snap() => {for (final k in prefs.getKeys()) k: prefs.get(k)};
        final before = snap();
        final api = _Fake();
        final host = await _openLate(tester, api: api);
        await _tapText(tester, '🌙 夜勤');
        await _tapText(tester, '次へ');
        await _tapText(tester, '会社');
        await _tapChip(tester, '車');
        await _tapText(tester, '相乗り');
        await tester.enterText(
            find.widgetWithText(TextField, '相乗り相手の会社名（任意）'), '相乗り商事');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.widgetWithText(TextField, '相乗り相手の氏名（任意）'), '同僚 一郎');
        await tester.pumpAndSettle();
        await _tapText(tester, '社用車・自家用車');
        await tester.enterText(find.widgetWithText(TextField, '駐車料金（円）'), '500');
        await tester.pumpAndSettle();
        await _tapText(tester, '次へ');
        await tester.enterText(find.byType(TextField).first, '配線');
        await tester.pumpAndSettle();
        await _tapText(tester, _kCheck);
        await _sendThroughPhotoDialog(tester);
        expect(api.bodies.length, 1);
        expect(api.bodies.single['shift_type'], 'night');
        expect(api.bodies.single['origin_type'], 'office');
        expect(api.bodies.single['parking_fee'], 500);
        await _tapText(tester, _kClose);
        expect(host.result, LateReportResult.submitted);
        expect(_seen.any((r) => r.url.path.endsWith('/workers/colleagues')), isTrue,
            reason: '相乗りで同僚を読んでいない（操作が届いていない）');
        expect(snap(), before, reason: '端末の保存が変わった');
        expect(prefs.getKeys().contains('pending_reports'), isFalse);
        expect(prefs.getKeys().contains('worker_reports_history'), isFalse);
      });
    });
  });

  // ══════════════════════════════════════════════════════════
  // (h) 目安
  // ══════════════════════════════════════════════════════════
  group('(h) 目安', () {
    Future<void> pickSite(WidgetTester tester) async {
      await _tapText(tester, _kNoSite);
      await tester.tap(find.widgetWithText(ListTile, _kSiteName));
      await tester.pumpAndSettle();
    }

    testWidgets('(h-1) 現場なしでは口を呼ばない／現場を選ぶと siteId を付けて呼ぶ（destination は付けない）', (tester) async {
      SharedPreferences.setMockInitialValues(_prefs(extra: {'home_address': _kHomeAddr}));
      await _withServer(() async {
        final routes = _Routes([RouteCompareResult.ok({'car': _car()})]);
        await _openLate(tester, routes: routes);
        await _tapText(tester, '次へ');
        await _tapText(tester, '会社');
        await _tapText(tester, '自宅');
        expect(routes.calls, isEmpty, reason: '現場なしで目安を聞いた');
        await _tapText(tester, '戻る');
        await pickSite(tester);
        expect(find.text(_kSiteName), findsOneWidget);
        expect(routes.calls.length, 1);
        expect(routes.calls.single.siteId, 's-1');
        expect(routes.calls.single.destination, isNull);
        expect(routes.calls.single.origin, _kHomeAddr);
      });
    });

    testWidgets('(h-2) 空の答えは「この手段の目安は取得できません」・ほかの失敗は「移動情報を取得できません（タップで再取得）」',
        (tester) async {
      for (final (fail, text, other) in [
        (RouteFailure.empty, _kRouteNoData, _kRouteFailed),
        (RouteFailure.network, _kRouteFailed, _kRouteNoData),
      ]) {
        SharedPreferences.setMockInitialValues(_prefs(extra: {'home_address': _kHomeAddr}));
        await _withServer(() async {
          final routes = _Routes([RouteCompareResult.failed(fail)]);
          await _openLate(tester, routes: routes);
          await pickSite(tester);
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          await _tapText(tester, '次へ');
          expect(routes.calls.length, 2, reason: '2回まで聞いていない');
          expect(find.text(text), findsOneWidget, reason: '$fail');
          expect(find.text(other), findsNothing, reason: '$fail');
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('(h-3) 出発地の住所が無い時は呼ばない（決め打ちの住所を使わない）', (tester) async {
      await _withServer(() async {
        final routes = _Routes([RouteCompareResult.ok({'car': _car()})]);
        await _openLate(tester, routes: routes);
        await pickSite(tester);
        expect(routes.calls, isEmpty, reason: '住所が無いのに聞いた');
        await _tapText(tester, '次へ');
        expect(find.text(_kRouteNoData), findsOneWidget);
      });
    });

    testWidgets('(h-4) 会社の住所で目安が出た後に、住所の無い自宅へ替える → 前の目安を残さない（帯・確認の画面・送る本文）',
        (tester) async {
      SharedPreferences.setMockInitialValues(_prefs(extra: {
        'default_origin': 'office',
        'company_address': _kOfficeAddr,
        'last_transports': 'car',
        'last_car_type': 'own',
      }));
      await _withServer(() async {
        final api = _Fake();
        final routes = _Routes([RouteCompareResult.ok({'car': _car()})]);
        await _openLate(tester, api: api, routes: routes);
        await pickSite(tester);
        expect(routes.calls.single.origin, _kOfficeAddr);
        await _tapText(tester, '次へ');
        expect(find.text('28分'), findsOneWidget, reason: '会社の住所の目安が出ていない（対照）');
        await _tapText(tester, '自宅');
        expect(routes.calls.length, 1);
        expect(find.text('28分'), findsNothing, reason: '前の出発地の目安が残っている');
        expect(find.text(_kRouteNoData), findsOneWidget);
        await _tapText(tester, '次へ');
        await _tapText(tester, _kCheck);
        expect(_inConfirm(find.text('車　—　—')), findsOneWidget);
        await _sendThroughPhotoDialog(tester);
        final b = api.bodies.single;
        for (final k in [
          'transport_distance_km',
          'transport_fuel_cost',
          'transport_fare',
          'transport_toll',
        ]) {
          expect(b.containsKey(k), isTrue);
          expect(b[k], isNull, reason: '$k に前の目安が残っている');
        }
      });
    });

    test('(h-5) compareRoutesV2 の本文：destination だけは今と同じ字・siteId だけは origin と site_id・どちらも無しは通信しない',
        () async {
      final seen = <http.Request>[];
      Future<RouteCompareResult> call({String? destination, String? siteId}) =>
          http.runWithClient(
            () => RoutesService().compareRoutesV2(
                origin: '起点', destination: destination, siteId: siteId),
            () => MockClient((req) async {
              seen.add(req);
              return http.Response(jsonEncode({'routes': {}}), 200,
                  request: req,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }),
          );
      final r1 = await call(destination: '34.500000,135.250000');
      expect(seen.single.body, '{"origin":"起点","destination":"34.500000,135.250000"}');
      expect(r1.failure, RouteFailure.empty);
      seen.clear();
      await call(siteId: 's-1');
      expect(seen.single.body, '{"origin":"起点","site_id":"s-1"}');
      seen.clear();
      final r3 = await call();
      expect(seen, isEmpty, reason: '行き先が無いのに通信した');
      expect(r3.failure, RouteFailure.empty);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (i) 途中で戻る
  // ══════════════════════════════════════════════════════════
  group('(i) 途中で戻る', () {
    testWidgets('(i-1) 何も変えていない → 窓なしで閉じる（null）', (tester) async {
      final host = await _openLate(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LateReportScreen), findsNothing);
      expect(host.closed, isTrue);
      expect(host.result, isNull);
    });

    testWidgets('(i-2) 1つ変えた → 窓（題なし・本文と2つのボタン）・「入力を続ける」で残る・「閉じる」で閉じる', (tester) async {
      final host = await _openLate(tester);
      await _tapText(tester, '🌙 夜勤');
      await tester.pageBack();
      await tester.pumpAndSettle();
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.title, isNull, reason: '窓に題が在る');
      expect(find.text(_kLeaveMsg), findsOneWidget);
      expect(find.text(_kKeepGoing), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, _kClose), findsOneWidget);
      await _tapText(tester, _kKeepGoing);
      expect(find.byType(LateReportScreen), findsOneWidget);
      expect(host.closed, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, _kClose));
      await tester.pumpAndSettle();
      expect(find.byType(LateReportScreen), findsNothing);
      expect(host.closed, isTrue);
      expect(host.result, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (j) 今の物の既定（今日の日報は変わらない）
  // ══════════════════════════════════════════════════════════
  group('(j) 今の物の既定', () {
    ReportSnapshot snap() => reportSnapshotFrom(
          dateLabel: '9月20日（日）',
          shiftLabel: '☀日勤',
          siteId: null,
          siteName: null,
          originType: 'home',
          transports: {TransportType.train},
          carType: 'own',
          routeComparisons: const {},
          parkingText: '',
          carpoolCompanyText: '',
          carpoolNameText: '',
          workText: '配線',
          workPhotoCount: 0,
          parkingPhotoCount: 0,
        );

    testWidgets('(j-1) ReportStepButtons の※の既定は今の字／渡せばその字', (tester) async {
      await _pump(
          tester,
          Scaffold(
              body: ReportStepButtons(
                  step: 3, onGoStep: (_) {}, checkBusy: false, onCheck: () async {})));
      expect(find.text(_kCheckNoteToday), findsOneWidget);
      await _pump(
          tester,
          Scaffold(
              body: ReportStepButtons(
                  step: 3,
                  onGoStep: (_) {},
                  checkBusy: false,
                  onCheck: () async {},
                  checkNote: _kCheckNote)));
      expect(find.text(_kCheckNote), findsOneWidget);
      expect(find.text(_kCheckNoteToday), findsNothing);
    });

    testWidgets('(j-2) ReportConfirmScreen の既定：見出し・ボタン2つ・帯と※と知らせが無く、その空きも無い', (tester) async {
      Future<void> pumpConfirm({bool extra = false}) => _pump(
          tester,
          ReportConfirmScreen(
            initial: snap(),
            currentOf: snap,
            onSend: () async {},
            isDone: () => false,
            band: extra ? const Text('帯') : null,
            notes: extra ? const ['※1行目'] : const [],
          ));
      Column contentColumn() => tester.widget<Column>(find
          .descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Column))
          .first);
      Rect contentRect() => tester.getRect(find
          .descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Column))
          .first);

      await pumpConfirm();
      expect(find.text('この内容で送ります'), findsOneWidget);
      expect(find.text('報告を送信'), findsOneWidget);
      expect(find.text(_kBackToFix), findsOneWidget);
      expect(find.text(_kClose), findsNothing);
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(tester.getTopLeft(find.text('この内容で送ります')).dy - appBarBottom, 8,
          reason: '見出しの上に空きが足されている');
      expect(contentRect().bottom, tester.getRect(find.byType(ReportFormCard)).bottom,
          reason: 'カードの下に空きが足されている');
      expect(contentColumn().children.length, 3, reason: '見出し・空き・カードのほかの物が在る');

      // 二者比較：帯と※を渡すと、見出しが下がり、カードの下に物が足される。
      await pumpConfirm(extra: true);
      expect(tester.getTopLeft(find.text('この内容で送ります')).dy - appBarBottom, greaterThan(8));
      expect(contentRect().bottom, greaterThan(tester.getRect(find.byType(ReportFormCard)).bottom));
    });

    testWidgets('(j-3) 2つの窓の既定の字は今の字と1字も同じ・返りは進む時だけ true', (tester) async {
      final results = <String, bool>{};
      await _pump(
        tester,
        Builder(
          builder: (ctx) => Scaffold(
            body: Column(children: [
              ElevatedButton(
                  onPressed: () async => results['route'] = await confirmProceedWhileRouting(ctx),
                  child: const Text('目安')),
              ElevatedButton(
                  onPressed: () async => results['photo'] = await confirmNoParkingPhoto(ctx),
                  child: const Text('写真')),
            ]),
          ),
        ),
      );
      await _tapText(tester, '目安');
      expect(find.text('移動の目安を計算中です'), findsOneWidget);
      expect(find.text('このまま送ると金額が入りません。'), findsOneWidget);
      expect(find.text('待つ'), findsOneWidget);
      await _tapText(tester, 'このまま送る');
      expect(results['route'], isTrue);
      await _tapText(tester, '目安');
      await _tapText(tester, '待つ');
      expect(results['route'], isFalse);

      await _tapText(tester, '写真');
      expect(find.text('写真が添付されていません'), findsOneWidget);
      expect(
          find.text('駐車場の看板または領収書の写真が添付されていません。このまま送信しますか？\n\n'
              '※戻ると、駐車場写真の帯にある「＋撮影」から撮影できます。'),
          findsOneWidget);
      expect(find.text('戻って撮影する'), findsOneWidget);
      await _tapText(tester, 'このまま送信');
      expect(results['photo'], isTrue);
      await _tapText(tester, '写真');
      await _tapText(tester, '戻って撮影する');
      expect(results['photo'], isFalse);
    });

    testWidgets('(j-4) showConfirmDialog：題が在る時は今の姿（accent の字）／null なら題を置かない', (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (ctx) => Scaffold(
            body: Column(children: [
              ElevatedButton(
                  onPressed: () => showConfirmDialog(ctx, title: '題の字', message: '本文'),
                  child: const Text('題あり')),
              ElevatedButton(
                  onPressed: () => showConfirmDialog(ctx, title: null, message: '本文'),
                  child: const Text('題なし')),
            ]),
          ),
        ),
      );
      await _tapText(tester, '題あり');
      expect(tester.widget<Text>(find.text('題の字')).style?.color?.toARGB32(), _kAccent);
      expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).title, isNotNull);
      await _tapText(tester, 'キャンセル');
      await _tapText(tester, '題なし');
      expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).title, isNull);
      expect(find.text('本文'), findsOneWidget);
      await _tapText(tester, 'キャンセル');
    });

    test('(j-5) reportTransportsFromSaved：null・空・知らない名前と none を捨てる', () {
      expect(reportTransportsFromSaved(null), isNull);
      expect(reportTransportsFromSaved(''), <TransportType>{});
      expect(reportTransportsFromSaved('car,train'), {TransportType.car, TransportType.train});
      expect(reportTransportsFromSaved('car,xx,none'), {TransportType.car});
    });

    test('(j-6) 相乗りの3つの関数（シェルの式と同じ答え）', () {
      expect(normalizeCompanyNameLocal(''), '');
      expect(normalizeCompanyNameLocal('株式会社 J電気'), 'j電気');
      expect(normalizeCompanyNameLocal('J電気(株)'), 'j電気');
      expect(normalizeCompanyNameLocal('　一般社団法人Ｘ会　'), 'ｘ会');
      const colleagues = ['同僚 一郎', '同僚 二郎'];
      expect(
          carpoolNameCandidatesFor(companyText: '  ', ownCompanyName: 'J電気', colleagues: colleagues),
          colleagues);
      expect(
          carpoolNameCandidatesFor(
              companyText: '株式会社J電気', ownCompanyName: 'J電気', colleagues: colleagues),
          colleagues);
      expect(
          carpoolNameCandidatesFor(
              companyText: '相乗り商事', ownCompanyName: 'J電気', colleagues: colleagues),
          isEmpty);
      expect(
          carpoolCompanyNamesOf([
            {'company_name': ' 相乗り商事 '},
            {'company_name': ''},
            {'company_name': null},
            <String, dynamic>{},
            {'company_name': 'B社'},
          ]),
          ['相乗り商事', 'B社']);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (k) 便BJ の直し（見本 claude/field_report_fix_mock_v1.html の ④・⑥・(8)・(9)）
  //   ★2026-10-14・便BJ で足した。今日の日報（シェル）は検査で立てられないので、同じ部品と同じ決まりを使う
  //     後から出す日報の画面で、動きを見る。
  // ══════════════════════════════════════════════════════════
  group('(k) 便BJ の直し', () {
    Future<void> pickSite(WidgetTester tester) async {
      await _tapText(tester, _kNoSite);
      await tester.tap(find.widgetWithText(ListTile, _kSiteName));
      await tester.pumpAndSettle();
    }

    for (final (carType, dialog) in [('carpool', false), ('own', true)]) {
      testWidgets('(k-1) 車で${carType == 'own' ? '社用車・自家用車' : '相乗り'}・駐車場の写真なし → 「写真が添付されていません」の窓は${dialog ? '出る' : '出ない'}（二者比較・見本 v1 の ④）',
          (tester) async {
        SharedPreferences.setMockInitialValues(_prefs(extra: {
          'last_transports': 'car',
          'last_car_type': carType,
        }));
        await _withServer(() async {
          final api = _Fake();
          await _openLate(tester, api: api);
          await _tapText(tester, '次へ');
          await _tapText(tester, '次へ');
          await _tapText(tester, _kCheck);
          await tester.tap(find.text(_kSend));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('写真が添付されていません'), dialog ? findsOneWidget : findsNothing);
          if (dialog) await _tapText(tester, 'このまま提出');
          await tester.pumpAndSettle();
          expect(api.bodies.length, 1, reason: '提出していない');
        });
      });
    }

    testWidgets('(k-2) 出発地が自宅で自宅の住所が無い時は、帯の外に※・住所が在れば※は無い（二者比較・見本 v1 の ⑥）', (tester) async {
      const note = '※自宅の住所が未登録のため、自宅からの目安は出せません。';
      for (final hasHome in [false, true]) {
        SharedPreferences.setMockInitialValues(
            _prefs(extra: {if (hasHome) 'home_address': _kHomeAddr}));
        await _withServer(() async {
          final routes = _Routes([RouteCompareResult.ok({'car': _car()})]);
          await _openLate(tester, routes: routes);
          await pickSite(tester);
          await _tapText(tester, '次へ');
          expect(find.text(note), hasHome ? findsNothing : findsOneWidget,
              reason: hasHome ? '住所が在るのに※が出た' : '住所が無いのに※が無い');
          expect(routes.calls.length, hasHome ? 1 : 0);
        });
      }
    });

    for (final (init, visible) in [('other', true), ('train', false)]) {
      testWidgets('(k-3) 補足の欄${visible ? 'が出ている' : 'が隠れた'}時の字 → 戻る時の「閉じますか？」は${visible ? '出る' : '出ない'}（二者比較・見本 v1 の (8)）',
          (tester) async {
        SharedPreferences.setMockInitialValues(_prefs(extra: {'last_transports': init}));
        final host = await _openLate(tester);
        await _tapText(tester, '次へ');
        if (!visible) {
          // 電車に車を2度押しで足す（確かめの窓は OK）→ 補足の欄が出る。
          await tester.tap(find.text('車'));
          await tester.pump(const Duration(milliseconds: 60));
          await tester.tap(find.text('車'));
          await tester.pumpAndSettle();
          await _tapText(tester, 'OK');
        }
        await tester.enterText(
            find.widgetWithText(TextField, '移動手段の補足（任意）例：バイクで駅まで → 電車 → 徒歩'), 'バイクで駅まで');
        await tester.pumpAndSettle();
        if (!visible) {
          // 車を1回押して外す（2つ選んでいる時は外れる）→ 電車だけ＝補足の欄が隠れる・選びは開いた時と同じ。
          await _tapChip(tester, '車');
          expect(find.widgetWithText(TextField, '移動手段の補足（任意）例：バイクで駅まで → 電車 → 徒歩'), findsNothing);
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text(_kLeaveMsg), visible ? findsOneWidget : findsNothing);
        if (!visible) {
          expect(host.closed, isTrue, reason: '隠れた欄の字で「閉じますか？」が出た');
        }
      });
    }

    testWidgets('(k-4) 目安の取り直しの間は前の値を使わない：確認の画面に前の距離が出ず、提出の本文の距離も null（見本 v1 の (9)）',
        (tester) async {
      SharedPreferences.setMockInitialValues(_prefs(extra: {
        'home_address': _kHomeAddr,
        'company_address': _kOfficeAddr,
        'last_transports': 'car',
        'last_car_type': 'carpool',
      }));
      await _withServer(() async {
        final api = _Fake();
        final routes = _SlowRoutes(RouteCompareResult.ok({'car': _car()}));
        await _openLate(tester, api: api, routes: routes);
        await pickSite(tester);
        await _tapText(tester, '次へ');
        expect(find.textContaining('12.4km'), findsOneWidget, reason: '1回目の目安が出ていない');
        // 出発地を会社へ替える → 取り直し（答えはまだ来ない＝計算中）。くるくるが回るので落ち着くのを待たない。
        await tester.tap(find.text('会社'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(routes.count, 2);
        expect(find.textContaining('12.4km'), findsNothing, reason: '取り直しの間に前の値が出ている');
        await tester.tap(find.text('次へ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_kCheck));
        await tester.pumpAndSettle();
        await _tapText(tester, 'このまま提出する');
        expect(_inConfirm(find.textContaining('12.4km')), findsNothing, reason: '確認の画面に前の距離が出た');
        await tester.tap(find.text(_kSend));
        await tester.pumpAndSettle();
        expect(api.bodies.length, 1);
        expect(api.bodies.single['transport_distance_km'], isNull, reason: '取り直しの間に前の距離を送った');
        routes.pending.single.complete(RouteCompareResult.ok({'car': _car()}));
        await tester.pumpAndSettle();
      });
    });
  });
}
