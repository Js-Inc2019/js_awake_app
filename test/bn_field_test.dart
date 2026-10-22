// ============================================================
// test/bn_field_test.dart
//   便BN（見つけた事 (45)〜(54)・ボスの裁定【Q155】【Q156】【Q157】【Q159】【Q160】【Q161】＝１・見本 claude/field_read_failed_windows_mock_v1.html・
//   claude/field_close_busy_mock_v1.html・claude/field_punch_read_failed_mock_v1.html・claude/field_unread_unwritten_mock_v1.html）の
//   職人アプリの直しを、機械で見張る検査。
//
// ★掟: 期待の字・数はこの本の中に直に書く（実装の字の定数は import しない）。二者比較（あり／なし）で見る。
//   今（業務日の今）は lib/utils/business_date.dart の businessClock を差し替える（tearDown で戻す）。通信は package:http の
//   runWithClient＋MockClient の偽物（答える時は検査が決める＝止めておいて答える）・本日休みの口は ReportsService の差し替え
//   （forTest）・端末の保存は SharedPreferences の偽物。シェル（JsMainShell）は検査で立てられない（通知・位置・通信の部品が多い）ので、
//   シェルの繋ぎはソースの字で見る（説明の行は除く＝_codeOnly）＝便BK・便BM の検査と同じ流儀。
// ★検査の名前の頭の番号（(BN-a1) ほか）は、ログの赤い行からどの検査かを機械で読むための物。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/core/theme/app_theme.dart';
import 'package:js_awake_app/main.dart' show ReportStore;
import 'package:js_awake_app/screens/after_report_screen.dart';
import 'package:js_awake_app/screens/pending_reports_screen.dart';
import 'package:js_awake_app/screens/punch_screen.dart'
    show PunchScreen, PunchOutStart, PunchOutStartKind;
import 'package:js_awake_app/screens/rest_day_screen.dart' show RestDayScreen;
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';
import 'package:js_awake_app/utils/business_date.dart';
import 'package:js_awake_app/utils/business_day_tick.dart';
import 'package:js_awake_app/utils/pending_view.dart';
import 'package:js_awake_app/widgets/business_day_dialog_guard.dart';

// ── 本の場所 ─────────────────────────────────────────────────────
const String _home = 'lib/screens/home_screen.dart';
const String _punch = 'lib/screens/punch_screen.dart';
const String _main = 'lib/main.dart';

/// 説明だけの行（空白の後が // で始まる行）を除いたソースの字。
String _codeOnly(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 空白を1つに畳む（改行と字下げの違いで落ちないように）。
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// head（本体の「{」まで含む頭の字）で始まる関数の本体（head の最後の「{」から、対になる「}」まで）。
String _bodyFrom(String src, String head) {
  final start = src.indexOf(head);
  if (start < 0) return '';
  final open = start + head.lastIndexOf('{');
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  return '';
}

// ── 字（見本の字・直に書く）──────────────────────────────────────
const String _kKept = '※最新の打刻状態を確認できませんでした。前に読めた状態で表示しています（タップで再取得）';
const String _kReset = '※最新の打刻状態を確認できませんでした。未出勤で表示しています（タップで再取得）';
const String _kRest = '※本日休みの登録状況を確認できませんでした（タップで再取得）';
const String _kSettings = '勤務の設定を読み込めませんでした（タップで再取得）';
const String _kReading = '取得中...';
const String _kPendingNote = '※送信状況を読み込めませんでした。';
const Color _kWarning = Color(0xFFE0603A);
const Color _kFaint = Color(0xFF635F55);

// ── 今（日本の 2026-10-21 水 10:00＝世界標準時 01:00・日勤の業務日 10-21・夜勤の業務日 10-20）──
final DateTime _t0 = DateTime.utc(2026, 10, 21, 1, 0);
void _setNow(DateTime t) => businessClock = () => t;

// ── 偽物のサーバ（打刻の画面の3つの口）────────────────────────────
http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

http.Response _settingsRes({bool actual = true}) => _json(200, {
      'setting': {
        'work_mode': actual ? 'actual' : 'deemed',
        'deemed_start': '08:00:00',
        'deemed_end': '17:00:00',
        'break_minutes': 60,
      }
    });

http.Response _todayRes({bool inn = false, bool out = false, int? breakMin = 60}) => _json(200, {
      'record': inn
          ? {'punch_in': '2026-10-20T23:00:00.000Z', 'punch_out': out ? '2026-10-21T08:00:00.000Z' : null}
          : null,
      'punched_in': inn,
      'punched_out': out,
      'standard_break_min': breakMin,
    });

http.Response _punchRes({bool out = false, bool noRecord = false}) => _json(200, {
      'record': noRecord
          ? null
          : {'punch_in': '2026-10-20T23:00:00.000Z', 'punch_out': out ? '2026-10-21T08:00:00.000Z' : null},
    });

http.Response _ng() => _json(500, {'error': 'サーバーエラー'});

String _keyOf(http.Request r) {
  final p = r.url.path;
  if (p.endsWith('/work_settings/my')) return 'settings';
  if (p.endsWith('/attendance/today')) return 'today';
  if (p.endsWith('/attendance/punch')) return 'punch';
  return 'other';
}

class _Srv {
  final seen = <http.Request>[];
  http.Response Function(http.Request r) settings = (_) => _settingsRes();
  http.Response Function(http.Request r) today = (_) => _todayRes();
  http.Response Function(http.Request r) punch = (_) => _punchRes();
  // 止めておく口（ここに入っている口の求めは、検査が held の Completer で答えるまで返さない）。
  final Set<String> holding = {};
  final Map<String, List<Completer<http.Response>>> held = {};

  int count(String key) => seen.where((r) => _keyOf(r) == key).length;
  List<String> shiftsOf(String key) => [
        for (final r in seen)
          if (_keyOf(r) == key)
            r.method == 'GET'
                ? (r.url.queryParameters['shift_type'] ?? '')
                : (jsonDecode(r.body)['shift_type'] as String)
      ];

  MockClient get client => MockClient((req) async {
        seen.add(req);
        final k = _keyOf(req);
        if (holding.contains(k)) {
          final c = Completer<http.Response>();
          (held[k] ??= <Completer<http.Response>>[]).add(c);
          return c.future;
        }
        switch (k) {
          case 'settings':
            return settings(req);
          case 'today':
            return today(req);
          case 'punch':
            return punch(req);
        }
        return _json(404, {'error': 'x'});
      });
}

// ── 本日休みの口の差し替え ─────────────────────────────────────────
ApiResult<RestDayToday> _restOk({bool rested = false}) => apiSuccess<RestDayToday>(
    statusCode: 200, data: RestDayToday(rested: rested, reason: null, portion: 'full'));
ApiResult<RestDayToday> _restNg() =>
    apiFailure<RestDayToday>(statusCode: 500, errorMessage: 'サーバーエラー');

class _Rest extends ReportsService {
  _Rest() : super.forTest();
  int calls = 0;
  int deletes = 0;
  ApiResult<RestDayToday> Function() answer = _restOk;
  bool throwNext = false;
  bool hold = false;
  final held = <Completer<ApiResult<RestDayToday>>>[];

  @override
  Future<ApiResult<RestDayToday>> getRestDayToday() async {
    calls++;
    if (throwNext) {
      throwNext = false;
      throw StateError('端末の保存を読めない');
    }
    if (hold) {
      final c = Completer<ApiResult<RestDayToday>>();
      held.add(c);
      return c.future;
    }
    return answer();
  }

  @override
  Future<ApiResult<RestDayMutation>> deleteRestDay() async {
    deletes++;
    return apiSuccess<RestDayMutation>(
        statusCode: 200, data: const RestDayMutation(restDate: '2026-10-21', reason: null, cancelled: true));
  }
}

// ── 打刻の画面の器（親が下ろす値を替えられる）───────────────────────
class _Props {
  const _Props({this.shift = 'day', this.tick = 0, this.restReq = 0});
  final String shift;
  final int tick;
  final int restReq;
  _Props copy({String? shift, int? tick, int? restReq}) =>
      _Props(shift: shift ?? this.shift, tick: tick ?? this.tick, restReq: restReq ?? this.restReq);
}

Future<void> _pumpPunch(
  WidgetTester tester,
  ValueNotifier<_Props> props,
  _Rest rest, {
  VoidCallback? onReport,
  void Function(PunchOutStart Function() punchOut)? onHandler,
  bool Function()? isReportDone,
  bool Function()? isPendingReadFailed,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    home: ValueListenableBuilder<_Props>(
      valueListenable: props,
      builder: (_, p, __) => PunchScreen(
        reports: rest,
        shiftType: p.shift,
        onShiftTypeChanged: (_) {},
        businessDayTick: p.tick,
        restStatusRequestId: p.restReq,
        onNavigateToReport: onReport,
        onPunchOutHandlerReady: onHandler,
        isReportDone: isReportDone,
        isPendingReadFailed: isPendingReadFailed,
      ),
    ),
  ));
  if (settle) await tester.pumpAndSettle();
}

/// 打つ（ボタン→時刻の確かめの窓→「出勤する」か「退勤する」）。
Future<void> _punchVia(WidgetTester tester, String button, String confirm, {bool settle = true}) async {
  await tester.tap(find.text(button));
  await tester.pumpAndSettle();
  await tester.tap(find.text(confirm));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// アプリへ戻った時（WidgetsBindingObserver の resumed）。
void _resume(WidgetTester tester) =>
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime Function() origClock;

  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'T', 'user_id': 'U1', 'user_name': '検査 太郎'});
    origClock = businessClock;
    ReportStore.instance.pendingView.value = const PendingView();
  });
  tearDown(() {
    businessClock = origClock;
  });

  // ══════════════════════════════════════════════════════════
  // (a) 業務日の切り替わりの時計と知らせ（下調べの (D5)）
  // ══════════════════════════════════════════════════════════
  group('(a) 時計と知らせ', () {
    test('(BN-a1) 次の切り替わりの時刻：日本の時刻で次の 0 時と次の 12 時の早い方（ちょうどの時は次の物）', () {
      expect(nextBusinessBoundary(DateTime.utc(2026, 10, 21, 1, 0)), DateTime.utc(2026, 10, 21, 3, 0),
          reason: '日本の 10:00 → 12:00');
      expect(nextBusinessBoundary(DateTime.utc(2026, 10, 21, 3, 0)), DateTime.utc(2026, 10, 21, 15, 0),
          reason: '日本の 12:00 ちょうど → 次の 0:00');
      expect(nextBusinessBoundary(DateTime.utc(2026, 10, 21, 14, 59)), DateTime.utc(2026, 10, 21, 15, 0),
          reason: '日本の 23:59 → 0:00');
      expect(nextBusinessBoundary(DateTime.utc(2026, 10, 21, 15, 0)), DateTime.utc(2026, 10, 22, 3, 0),
          reason: '日本の 0:00 ちょうど → 12:00');
      expect(nextBusinessBoundary(DateTime.utc(2026, 10, 31, 4, 0)), DateTime.utc(2026, 10, 31, 15, 0),
          reason: '月の終わり（日本の 10/31 13:00 → 11/1 0:00）');
      expect(nextBusinessBoundary(DateTime.utc(2026, 10, 21, 1, 0).toLocal()), DateTime.utc(2026, 10, 21, 3, 0),
          reason: '端末の時刻の書き方でも、同じ瞬間なら同じ答え');
      // 切り替わりの前と後で、日勤か夜勤の業務日が替わる（12 時は夜勤・0 時は日勤）。
      for (final now in [DateTime.utc(2026, 10, 21, 1, 0), DateTime.utc(2026, 10, 21, 5, 0)]) {
        final b = nextBusinessBoundary(now);
        final before = b.subtract(const Duration(milliseconds: 1));
        final changed = businessDateForShift('night', before) != businessDateForShift('night', b) ||
            businessDateForShift('day', before) != businessDateForShift('day', b);
        expect(changed, isTrue, reason: '切り替わりの時刻をまたいでも、どの業務日も替わらない＝$b');
      }
    });

    testWidgets('(BN-a2) 時計：切り替わりの時刻に1回鳴って次へ掛け直す・今から掛け直すと前の時計は鳴らない・早く鳴った時は鳴らずに同じ切り替わりへ・止めると鳴らない',
        (tester) async {
      var now = DateTime.utc(2026, 10, 21, 1, 0);
      businessClock = () => now;
      var ticks = 0;
      final clock = BusinessDayClock(() => ticks++);
      clock.restart();
      expect(clock.target, DateTime.utc(2026, 10, 21, 3, 0));
      now = DateTime.utc(2026, 10, 21, 2, 59);
      await tester.pump(const Duration(hours: 1, minutes: 59));
      expect(ticks, 0, reason: '切り替わりの前に鳴った');
      now = DateTime.utc(2026, 10, 21, 3, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(ticks, 1, reason: '切り替わりの時刻に鳴らない');
      expect(clock.target, DateTime.utc(2026, 10, 21, 15, 0), reason: '鳴った後に次の切り替わりへ掛け直していない');
      // 戻った時：前の時計を止めて、今から次の切り替わりへ（裏に居た間に 0 時をまたいだ）。
      now = DateTime.utc(2026, 10, 21, 16, 0);
      clock.restart();
      expect(clock.target, DateTime.utc(2026, 10, 22, 3, 0));
      await tester.pump(const Duration(hours: 10, minutes: 59));
      expect(ticks, 1, reason: '前の時計（12時間後）が止まっていない・または早く鳴った');
      now = DateTime.utc(2026, 10, 22, 3, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(ticks, 2, reason: '掛け直した時計が鳴らない');
      await tester.pump(const Duration(hours: 1));
      expect(ticks, 2, reason: '同じ切り替わりで2回鳴った（前の時計が残っている）');
      // 早く鳴った時（端末の時計が戻った）：鳴らさずに、同じ切り替わりへ掛け直し、その時刻に1回鳴る。
      //   →再（2026-10-21・検分 a430）: 元は「掛けていた時刻の後へ掛け直す」を見ていた＝早く鳴った時に鳴って、本当の切り替わりを
      //   飛ばす形を決めていた。
      final target = clock.target!;
      final ticksEarly = ticks;
      now = target.subtract(const Duration(hours: 1));
      await tester.pump(target.difference(DateTime.utc(2026, 10, 22, 4, 0)));
      expect(ticks, ticksEarly, reason: '切り替わりの前（早く鳴った時）に鳴った');
      expect(clock.target, target, reason: '早く鳴った後に、同じ切り替わりへ掛け直していない');
      now = target;
      await tester.pump(const Duration(hours: 1));
      expect(ticks, ticksEarly + 1, reason: '早く鳴った後の、本当の切り替わりの時刻に鳴らない');
      expect(clock.target!.isAfter(target), isTrue, reason: '鳴った後に次の切り替わりへ掛け直していない');
      // 止めると鳴らない。
      final before = ticks;
      clock.stop();
      expect(clock.target, isNull);
      await tester.pump(const Duration(days: 2));
      expect(ticks, before, reason: '止めた後に鳴った');
    });

    test('(BN-a3) 知らせ：鳴らすと数が1つ進む', () {
      final before = BusinessDayTick.changes.value;
      BusinessDayTick.ring();
      expect(BusinessDayTick.changes.value, before + 1);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (b) 今日を前に置く字の窓（下調べの (D8)・lib/widgets/business_day_dialog_guard.dart）
  // ══════════════════════════════════════════════════════════
  group('(b) 今日を前に置く字の窓', () {
    // 窓を開く器。結果（閉じた時の値）は result に入る。上にもう1つ窓を開く口（openOver）も持つ。
    Future<void> host(WidgetTester tester, {required String shift, Object? closeValue = false,
        required void Function(Future<Object?>) onResult}) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => onResult(showDialog<Object?>(
                  context: ctx,
                  builder: (dctx) => CloseOnBusinessDayChange(
                    shiftType: shift,
                    closeValue: closeValue,
                    child: AlertDialog(
                      title: const Text('窓の題'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dctx, 'pressed'), child: const Text('戻る')),
                        TextButton(
                          onPressed: () => showDialog<void>(
                            context: dctx,
                            builder: (c2) => AlertDialog(
                              title: const Text('上の窓'),
                              actions: [TextButton(onPressed: () => Navigator.pop(c2), child: const Text('上を閉じる'))],
                            ),
                          ),
                          child: const Text('上に開く'),
                        ),
                      ],
                    ),
                  ),
                )),
                child: const Text('ひらく'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ひらく'));
      await tester.pumpAndSettle();
    }

    testWidgets('(BN-b1) 業務日が同じ時の知らせでは閉じない・替わった時の知らせで「戻る」と同じ値で閉じる・下の画面は残る（二者比較）',
        (tester) async {
      _setNow(DateTime.utc(2026, 10, 21, 14, 0)); // 日本の 23:00
      Future<Object?>? result;
      await host(tester, shift: 'day', onResult: (f) => result = f);
      BusinessDayTick.ring();
      await tester.pumpAndSettle();
      expect(find.text('窓の題'), findsOneWidget, reason: '業務日が同じなのに閉じた');
      _setNow(DateTime.utc(2026, 10, 21, 15, 0)); // 日本の 0:00（日勤の業務日が替わる）
      BusinessDayTick.ring();
      await tester.pumpAndSettle();
      expect(find.text('窓の題'), findsNothing, reason: '業務日が替わったのに閉じない');
      expect(await result, false, reason: '「戻る」と同じ値で閉じていない');
      expect(find.text('ひらく'), findsOneWidget, reason: '下の画面まで閉じた');
    });

    testWidgets('(BN-b2) 覆われていた窓：知らせの時は閉じず、上の窓が閉じて一番上に戻った時に閉じる（描いた後）', (tester) async {
      _setNow(DateTime.utc(2026, 10, 21, 14, 0));
      Future<Object?>? result;
      await host(tester, shift: 'day', onResult: (f) => result = f);
      await tester.tap(find.text('上に開く'));
      await tester.pumpAndSettle();
      _setNow(DateTime.utc(2026, 10, 21, 15, 0));
      BusinessDayTick.ring();
      await tester.pumpAndSettle();
      expect(find.text('上の窓'), findsOneWidget, reason: '上の窓を閉じた（下の窓が閉じる時に一番上の物を閉じた）');
      expect(find.text('窓の題'), findsOneWidget, reason: '覆われていたのに閉じた');
      await tester.tap(find.text('上を閉じる'));
      await tester.pumpAndSettle();
      expect(find.text('窓の題'), findsNothing, reason: '一番上に戻ったのに閉じない');
      expect(await result, false);
      expect(find.text('ひらく'), findsOneWidget);
    });

    testWidgets('(BN-b3) 押した直後の出ていく間に知らせが来ても、下の画面を閉じない（押した値のまま）', (tester) async {
      _setNow(DateTime.utc(2026, 10, 21, 14, 0));
      Future<Object?>? result;
      await host(tester, shift: 'day', onResult: (f) => result = f);
      await tester.tap(find.text('戻る'));
      await tester.pump(); // 出ていく動きの最中
      _setNow(DateTime.utc(2026, 10, 21, 15, 0));
      BusinessDayTick.ring();
      await tester.pumpAndSettle();
      expect(find.text('ひらく'), findsOneWidget, reason: '出ていく窓の下の画面を閉じた');
      expect(await result, 'pressed');
    });

    testWidgets('(BN-b4) 物差しは開いた時の勤務の種類：夜勤の窓は 12 時で閉じ 0 時では閉じない・日勤の窓は 12 時では閉じない',
        (tester) async {
      _setNow(DateTime.utc(2026, 10, 21, 14, 0)); // 日本の 23:00
      await host(tester, shift: 'night', onResult: (_) {});
      _setNow(DateTime.utc(2026, 10, 21, 15, 0)); // 0:00（夜勤の業務日は替わらない）
      BusinessDayTick.ring();
      await tester.pumpAndSettle();
      expect(find.text('窓の題'), findsOneWidget, reason: '夜勤の窓が 0 時で閉じた');
      _setNow(DateTime.utc(2026, 10, 22, 3, 0)); // 12:00（夜勤の業務日が替わる）
      BusinessDayTick.ring();
      await tester.pumpAndSettle();
      expect(find.text('窓の題'), findsNothing, reason: '夜勤の窓が 12 時で閉じない');

      _setNow(DateTime.utc(2026, 10, 21, 1, 0)); // 10:00
      await host(tester, shift: 'day', onResult: (_) {});
      _setNow(DateTime.utc(2026, 10, 21, 3, 0)); // 12:00（日勤の業務日は替わらない）
      BusinessDayTick.ring();
      await tester.pumpAndSettle();
      expect(find.text('窓の題'), findsOneWidget, reason: '日勤の窓が 12 時で閉じた');
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
    });
  });

  // ══════════════════════════════════════════════════════════
  // (c) ホームの打刻の画面（(51)(52)(54)・(お)・(D5) の (P1)〜(P4)・(D10)・(Z1)・(46)・(D8)）
  // ══════════════════════════════════════════════════════════
  group('(c) 打刻の画面', () {
    late _Srv srv;
    late _Rest rest;
    late ValueNotifier<_Props> props;
    // 位置の口（geolocator）は検査の器に無い＝答えが来ない。許可が「ずっと拒否」と答えさせて、すぐ「取れない」で進める
    //   （打つ所は位置を待ってから送る）。
    const geo = MethodChannel('flutter.baseflow.com/geolocator');
    setUp(() {
      _setNow(_t0);
      srv = _Srv();
      rest = _Rest();
      props = ValueNotifier<_Props>(const _Props());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(geo, (call) async => 1);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(geo, null);
    });

    testWidgets('(BN-c1) 開いた時に読めない：未出勤の姿と「未出勤で表示しています」の※（形）・押すと「取得中...」・読めれば消える',
        (tester) async {
      await http.runWithClient(() async {
        srv.today = (_) => _ng();
        await _pumpPunch(tester, props, rest);
        expect(find.text('今日はまだ出勤していません'), findsOneWidget);
        expect(find.text(_kReset), findsOneWidget, reason: '読めなかった事が出ない');
        expect(find.text(_kKept), findsNothing);
        final t = tester.widget<Text>(find.text(_kReset));
        expect(t.style?.fontSize, 11.5);
        expect(t.style?.color, _kWarning);
        expect(t.textAlign, TextAlign.center);
        final tap = tester.getRect(find.ancestor(of: find.text(_kReset), matching: find.byType(GestureDetector)).first);
        expect(tap.height >= 44, isTrue, reason: '※の押せる高さが 44 より小さい');
        // 状態の下・勤務区分の上（上は 8・下は 12）。
        final status = tester.getRect(find.text('今日はまだ出勤していません'));
        final chips = tester.getRect(find.text('日勤'));
        expect(tap.top - status.bottom, closeTo(8, 0.01));
        expect(chips.top > tap.bottom, isTrue);
        expect(find.text('出勤'), findsOneWidget);
        // 押すと読み直す（読む間は「取得中...」）。
        srv.holding.add('today');
        await tester.tap(find.text(_kReset));
        await tester.pump();
        expect(find.text(_kReading), findsOneWidget, reason: '読む間の字が「取得中...」でない');
        srv.held['today']!.last.complete(_todayRes(inn: true));
        await tester.pumpAndSettle();
        expect(find.text(_kReading), findsNothing);
        expect(find.text(_kReset), findsNothing, reason: '読めたのに※が消えない');
        expect(find.text('出勤中'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c2) 勤務区分を替えた後の読みが取れない：前の種類の「出勤中」と［退勤］を出さず未出勤の姿と※（二者比較）',
        (tester) async {
      await http.runWithClient(() async {
        srv.today = (_) => _todayRes(inn: true);
        await _pumpPunch(tester, props, rest);
        expect(find.text('出勤中'), findsOneWidget);
        expect(find.text('退勤'), findsOneWidget);
        srv.today = (_) => _ng();
        props.value = props.value.copy(shift: 'night');
        await tester.pumpAndSettle();
        expect(srv.shiftsOf('today').last, 'night');
        expect(find.text('出勤中'), findsNothing, reason: '前の種類の状態を出した');
        expect(find.text('退勤'), findsNothing, reason: '前の種類の［退勤］を出した');
        expect(find.text('今日はまだ出勤していません'), findsOneWidget);
        expect(find.text(_kReset), findsOneWidget);
        // 二者比較：読めた時は※が無い。
        srv.today = (_) => _todayRes(inn: true);
        props.value = props.value.copy(shift: 'day');
        await tester.pumpAndSettle();
        expect(find.text('出勤中'), findsOneWidget);
        expect(find.text(_kReset), findsNothing);
        expect(find.text(_kKept), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c3) 同じ業務日に戻った時の読みが取れない：前の状態のまま「前に読めた状態で表示しています」（ボタンもそのまま）',
        (tester) async {
      await http.runWithClient(() async {
        srv.today = (_) => _todayRes(inn: true);
        await _pumpPunch(tester, props, rest);
        srv.today = (_) => _ng();
        _resume(tester);
        await tester.pumpAndSettle();
        expect(find.text('出勤中'), findsOneWidget, reason: '前に読めた状態を消した');
        expect(find.text('退勤'), findsOneWidget);
        expect(find.text(_kKept), findsOneWidget);
        expect(find.text(_kReset), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c4) 業務日が替わった後の読みが取れない：未出勤の姿と※・替わる前に出した読みの答えは捨てる', (tester) async {
      await http.runWithClient(() async {
        srv.today = (_) => _todayRes(inn: true);
        await _pumpPunch(tester, props, rest);
        // 時計の番号で読む（日本の 10/22 0:00 をまたいだ後）→ 取れない。
        _setNow(DateTime.utc(2026, 10, 21, 15, 0));
        srv.today = (_) => _ng();
        props.value = props.value.copy(tick: 1);
        await tester.pumpAndSettle();
        expect(find.text('出勤中'), findsNothing, reason: '前の業務日の状態を出した');
        expect(find.text(_kReset), findsOneWidget);
        // 出した後に業務日が替わった答え（取れた答え）は捨てる＝前の業務日の行を入れない。
        srv.holding.add('today');
        _resume(tester);
        await tester.pump();
        _setNow(DateTime.utc(2026, 10, 22, 15, 0)); // さらに次の日の 0:00
        srv.held['today']!.last.complete(_todayRes(inn: true));
        await tester.pumpAndSettle();
        expect(find.text('出勤中'), findsNothing, reason: '出した時の行と違う答えを入れた');
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c5) 番号の口：先に着いた新しい答えは入り、後に着いた古い答えは入らない・古い取れない答えは※を立てない',
        (tester) async {
      await http.runWithClient(() async {
        await _pumpPunch(tester, props, rest);
        srv.holding.add('today');
        _resume(tester); // 読み A
        await tester.pump();
        props.value = props.value.copy(tick: 1); // 読み B（_busy を立てない）
        await tester.pump();
        expect(srv.held['today']!.length, 2);
        srv.held['today']![1].complete(_todayRes(inn: true)); // B が先に着く
        await tester.pump();
        expect(find.text('出勤中'), findsOneWidget, reason: '先に着いた新しい答えを入れない');
        srv.held['today']![0].complete(_ng()); // 古い A は取れない
        await tester.pumpAndSettle();
        expect(find.text('出勤中'), findsOneWidget, reason: '古い答えで状態を替えた');
        expect(find.text(_kKept), findsNothing, reason: '古い取れない答えで※を立てた');
        expect(find.text(_kReset), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c6) 「取得中...」は一番新しく出した読みの答えで下りる（古い答えが先に着いても下りない・後に着いても戻らない）', (tester) async {
      await http.runWithClient(() async {
        srv.today = (_) => _ng();
        await _pumpPunch(tester, props, rest);
        expect(find.text(_kReset), findsOneWidget);
        srv.holding.add('today');
        _resume(tester); // A
        await tester.pump();
        props.value = props.value.copy(tick: 1); // B
        await tester.pump();
        expect(find.text(_kReading), findsOneWidget);
        srv.held['today']![0].complete(_ng()); // 古い A
        await tester.pump();
        expect(find.text(_kReading), findsOneWidget, reason: '古い答えで「取得中...」を下ろした');
        srv.held['today']![1].complete(_ng()); // 新しい B
        await tester.pumpAndSettle();
        expect(find.text(_kReading), findsNothing, reason: '一番新しい答えが着いたのに「取得中...」のまま');
        expect(find.text(_kReset), findsOneWidget);
        // 逆の順：新しい答えが先に着いて下りた後に、古い答えが着いても「取得中...」に戻らない。
        _resume(tester); // C
        await tester.pump();
        props.value = props.value.copy(tick: 2); // D
        await tester.pump();
        expect(find.text(_kReading), findsOneWidget);
        srv.held['today']![3].complete(_ng()); // 新しい D が先
        await tester.pump();
        expect(find.text(_kReading), findsNothing, reason: '一番新しい答えが着いたのに「取得中...」のまま');
        srv.held['today']![2].complete(_ng()); // 古い C が後
        await tester.pumpAndSettle();
        expect(find.text(_kReading), findsNothing, reason: '後に着いた古い答えで「取得中...」に戻した');
        expect(find.text(_kReset), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c7) 打った後の読みが取れない：打てた時の答えの行で状態を作る（退勤済みなら日報のフォームを開く・二者比較）',
        (tester) async {
      await http.runWithClient(() async {
        var reports = 0;
        srv.today = (_) => _todayRes(inn: true);
        await _pumpPunch(tester, props, rest, onReport: () => reports++);
        srv.today = (_) => _ng();
        srv.punch = (_) => _punchRes(out: true);
        await _punchVia(tester, '退勤', '退勤する');
        expect(find.text('本日終了'), findsOneWidget, reason: '打てた時の答えで状態を作っていない');
        expect(find.text(_kKept), findsNothing);
        expect(find.text(_kReset), findsNothing);
        expect(reports, 1, reason: '退勤済みの答えなのに日報のフォームを開かない');
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c8) 打った後の読みが取れない時に作らない回：答えに行が無い・会社の休憩の設定を一度も読めていない（※）',
        (tester) async {
      await http.runWithClient(() async {
        // 行が無い。
        await _pumpPunch(tester, props, rest);
        srv.today = (_) => _ng();
        srv.punch = (_) => _punchRes(noRecord: true);
        await _punchVia(tester, '出勤', '出勤する');
        expect(find.text('出勤中'), findsNothing);
        expect(find.text(_kKept), findsOneWidget, reason: '作れない時に※を出さない');
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
      final srv2 = _Srv();
      await http.runWithClient(() async {
        // 休憩の設定を一度も読めていない（開いた時から読めない）。
        srv2.today = (_) => _ng();
        srv2.punch = (_) => _punchRes();
        await _pumpPunch(tester, ValueNotifier<_Props>(const _Props()), _Rest());
        await _punchVia(tester, '出勤', '出勤する');
        expect(find.text('出勤中'), findsNothing, reason: '休憩の設定を読めていないのに状態を作った');
        expect(find.text(_kReset), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => srv2.client);
    });

    testWidgets('(BN-c9) 断られた時（すでに出勤）は知らせの後に読み直す・ほかの断りでは読み直さない（二者比較）', (tester) async {
      await http.runWithClient(() async {
        await _pumpPunch(tester, props, rest);
        srv.punch = (_) => _json(409, {
              'error': 'すでに出勤の打刻があります。時刻の訂正は事務へご連絡ください。',
              'code': 'ALREADY_PUNCHED_IN',
            });
        srv.today = (_) => _todayRes(inn: true);
        final before = srv.count('today');
        await _punchVia(tester, '出勤', '出勤する');
        expect(find.text('すでに出勤の打刻があります。時刻の訂正は事務へご連絡ください。'), findsOneWidget);
        expect(srv.count('today'), before + 1, reason: '断られた後に読み直さない');
        expect(find.text('出勤中'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
      final srv2 = _Srv();
      await http.runWithClient(() async {
        await _pumpPunch(tester, ValueNotifier<_Props>(const _Props()), _Rest());
        srv2.punch = (_) => _json(400, {'error': '締め済みの期間です', 'code': 'CLOSED_PERIOD'});
        final before = srv2.count('today');
        await _punchVia(tester, '出勤', '出勤する');
        expect(find.text('締め済みの期間です'), findsOneWidget);
        expect(srv2.count('today'), before, reason: 'ほかの断りで読み直した');
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpWidget(const SizedBox());
      }, () => srv2.client);
    });

    testWidgets('(BN-c10) 打つ間に勤務区分が替わった：押した時の種類で打ち、読み直しは今の種類で1回・日報のフォームは開かない',
        (tester) async {
      await http.runWithClient(() async {
        var reports = 0;
        srv.today = (_) => _todayRes(inn: true);
        await _pumpPunch(tester, props, rest, onReport: () => reports++);
        srv.holding.add('punch');
        await _punchVia(tester, '退勤', '退勤する', settle: false);
        await tester.pump();
        expect(srv.shiftsOf('punch'), ['day']);
        final before = srv.count('today');
        props.value = props.value.copy(shift: 'night'); // 打つ間に替わる（_busy の間は見送る）
        await tester.pump();
        expect(srv.count('today'), before, reason: '打刻の最中に読み直した');
        // 読み直しの答えは「退勤済み」（この打刻の答え）でも、種類が替わっていたので日報のフォームは開かない。
        srv.today = (_) => _todayRes(inn: true, out: true);
        srv.held['punch']!.single.complete(_punchRes(out: true));
        await tester.pumpAndSettle();
        expect(srv.shiftsOf('today').sublist(before), ['night'], reason: '読み直しが今の種類の1回でない');
        expect(reports, 0, reason: '前の種類の退勤の後に、今の種類の日報のフォームを開いた');
        expect(find.text('本日終了'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
      // 二者比較：替わらなければ、読み直しの答え（退勤済み）で日報のフォームを開く。
      final srv2 = _Srv()..today = (_) => _todayRes(inn: true);
      await http.runWithClient(() async {
        var reports = 0;
        await _pumpPunch(tester, ValueNotifier<_Props>(const _Props()), _Rest(), onReport: () => reports++);
        srv2.today = (_) => _todayRes(inn: true, out: true);
        srv2.punch = (_) => _punchRes(out: true);
        await _punchVia(tester, '退勤', '退勤する');
        expect(reports, 1, reason: '同じ種類の退勤の後に日報のフォームを開かない');
        await tester.pumpWidget(const SizedBox());
      }, () => srv2.client);
    });

    testWidgets('(BN-c11) 打った後の読み直しの間に替わった分は、下ろした後に1回 _busy を立てて読む（古い答えは入らない）',
        (tester) async {
      await http.runWithClient(() async {
        srv.today = (_) => _todayRes(inn: true);
        await _pumpPunch(tester, props, rest);
        srv.punch = (_) => _punchRes(out: true);
        srv.holding.add('today');
        await _punchVia(tester, '退勤', '退勤する', settle: false);
        await tester.pump();
        await tester.pump();
        final n0 = srv.held['today']!.length; // 打った後の読み直し（日勤）
        props.value = props.value.copy(shift: 'night');
        await tester.pump();
        expect(srv.held['today']!.length, n0, reason: '_busy の間に読み直した');
        srv.held['today']![n0 - 1].complete(_todayRes(inn: true, out: true)); // 日勤の答え＝今の行（夜勤）と違う
        await tester.pump();
        await tester.pump();
        expect(srv.held['today']!.length, n0 + 1, reason: '下ろした後に、見送った読み直しを1回読まない');
        expect(srv.shiftsOf('today').last, 'night');
        expect(find.byType(CircularProgressIndicator), findsOneWidget,
            reason: '見送った読み直しの間に _busy を立てていない（打刻を押せる）');
        expect(find.text('本日終了'), findsNothing, reason: '前の行（日勤）の答えを入れた');
        srv.held['today']!.last.complete(_todayRes());
        await tester.pumpAndSettle();
        expect(find.text('今日はまだ出勤していません'), findsOneWidget);
        expect(srv.held['today']!.length, n0 + 1, reason: '2回読んだ');
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c12) 時計の番号：_busy を立てずに打刻と本日休みを読む・同じ描きで勤務区分と両方替わった時は1回ずつ（_busy で読む）',
        (tester) async {
      await http.runWithClient(() async {
        await _pumpPunch(tester, props, rest);
        final t0 = srv.count('today');
        final r0 = rest.calls;
        srv.holding.add('today');
        props.value = props.value.copy(tick: 1);
        await tester.pump();
        expect(srv.count('today'), t0 + 1, reason: '時計の番号で打刻を読まない');
        expect(rest.calls, r0 + 1, reason: '時計の番号で本日休みを読まない');
        expect(find.byType(CircularProgressIndicator), findsNothing, reason: '時計の番号の読みで _busy を立てた');
        srv.held['today']!.last.complete(_todayRes());
        await tester.pumpAndSettle();
        // 両方が同じ描きで替わる。
        props.value = props.value.copy(shift: 'night', tick: 2);
        await tester.pump();
        expect(srv.count('today'), t0 + 2, reason: '打刻の行の読み直しが1回でない');
        expect(rest.calls, r0 + 2, reason: '本日休みの読み直しが1回でない');
        expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: '勤務区分を替えた読みで _busy を立てない');
        srv.held['today']!.last.complete(_todayRes());
        await tester.pumpAndSettle();
        expect(srv.count('today'), t0 + 2);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c13) 本日休みを読めない：どの姿でも下のボタンの下に※（形）・押すと「取得中...」・読めれば消える・ボタンは止めない',
        (tester) async {
      await http.runWithClient(() async {
        var reports = 0;
        rest.answer = _restNg;
        srv.settings = (_) => _settingsRes(actual: false);
        await _pumpPunch(tester, props, rest, onReport: () => reports++);
        expect(find.text(_kRest), findsOneWidget, reason: 'みなしで※が出ない');
        final t = tester.widget<Text>(find.text(_kRest));
        expect(t.style?.fontSize, 11.5);
        expect(t.style?.color, _kWarning);
        final note = tester.getRect(find.ancestor(of: find.text(_kRest), matching: find.byType(GestureDetector)).first);
        final btn = tester.getRect(find.widgetWithText(OutlinedButton, '日報を報告'));
        expect(note.height >= 44, isTrue);
        expect(note.top - btn.bottom, closeTo(6, 0.01), reason: '※がボタンの 6 下に無い');
        expect(find.text('本日休み'), findsOneWidget);
        await tester.tap(find.text('日報を報告'));
        await tester.pumpAndSettle();
        expect(reports, 1, reason: '※が出ている間に［日報を報告］を止めた');
        // 押すと読み直す。
        rest.hold = true;
        await tester.tap(find.text(_kRest));
        await tester.pump();
        expect(find.text(_kReading), findsOneWidget);
        rest.held.last.complete(_restOk(rested: true));
        await tester.pumpAndSettle();
        expect(find.text(_kRest), findsNothing);
        expect(find.text('本日休み 登録済み'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
      // 実勤務の3つの姿（未出勤・出勤中・退勤済み）でも出る。
      for (final s in [_todayRes(), _todayRes(inn: true), _todayRes(inn: true, out: true)]) {
        final srv2 = _Srv()..today = (_) => s;
        final rest2 = _Rest()..answer = _restNg;
        await http.runWithClient(() async {
          await _pumpPunch(tester, ValueNotifier<_Props>(const _Props()), rest2);
          expect(find.text(_kRest), findsOneWidget, reason: '実勤務の姿で※が出ない＝${s.body}');
          await tester.pumpWidget(const SizedBox());
        }, () => srv2.client);
      }
    });

    testWidgets('(BN-c14) 本日休み：同じ日に前に読めた値は残す・日が替わった後は初めの値・投げても同じ（二者比較）', (tester) async {
      await http.runWithClient(() async {
        srv.settings = (_) => _settingsRes(actual: false);
        rest.answer = () => _restOk(rested: true);
        await _pumpPunch(tester, props, rest);
        expect(find.text('本日休み 登録済み'), findsOneWidget);
        rest.answer = _restNg;
        props.value = props.value.copy(restReq: 1);
        await tester.pumpAndSettle();
        expect(find.text('本日休み 登録済み'), findsOneWidget, reason: '同じ日に読めた値を消した');
        expect(find.text(_kRest), findsOneWidget);
        // 投げた時も同じ。
        rest.throwNext = true;
        props.value = props.value.copy(restReq: 2);
        await tester.pumpAndSettle();
        expect(find.text('本日休み 登録済み'), findsOneWidget);
        expect(find.text(_kRest), findsOneWidget, reason: '投げた時に※が出ない');
        // 日が替わった後は初めの値。
        _setNow(DateTime.utc(2026, 10, 21, 15, 0));
        props.value = props.value.copy(restReq: 3);
        await tester.pumpAndSettle();
        expect(find.text('本日休み 登録済み'), findsNothing, reason: '前の日の値を出した');
        expect(find.text('本日休み'), findsOneWidget);
        expect(find.text(_kRest), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c15) 本日休みの番号の口：日をまたいだ答えと古い答えは捨てる・取れない答えの後に着いた前の取れた答えは入る',
        (tester) async {
      await http.runWithClient(() async {
        srv.settings = (_) => _settingsRes(actual: false);
        await _pumpPunch(tester, props, rest);
        rest.hold = true;
        // 日をまたいだ答え。
        props.value = props.value.copy(restReq: 1);
        await tester.pump();
        _setNow(DateTime.utc(2026, 10, 21, 15, 0));
        rest.held.last.complete(_restOk(rested: true));
        await tester.pumpAndSettle();
        expect(find.text('本日休み 登録済み'), findsNothing, reason: '出した日と違う日の答えを入れた');
        // 古い答え：A・B を出し、B（休みでない）が先・A（休み）が後。
        props.value = props.value.copy(restReq: 2); // A
        await tester.pump();
        props.value = props.value.copy(restReq: 3); // B
        await tester.pump();
        rest.held[2].complete(_restOk());
        await tester.pump();
        rest.held[1].complete(_restOk(rested: true));
        await tester.pumpAndSettle();
        expect(find.text('本日休み 登録済み'), findsNothing, reason: '古い答えを入れた');
        // 取れない答えの後に着いた、それより前に出した取れた答え：C・D を出し、D（取れない）が先・C（休み）が後。
        props.value = props.value.copy(restReq: 4); // C
        await tester.pump();
        props.value = props.value.copy(restReq: 5); // D
        await tester.pump();
        rest.held[4].complete(_restNg());
        await tester.pumpAndSettle();
        expect(find.text(_kRest), findsOneWidget);
        rest.held[3].complete(_restOk(rested: true));
        await tester.pumpAndSettle();
        expect(find.text('本日休み 登録済み'), findsOneWidget, reason: '取れない答えの後の、前に出した取れた答えを入れない');
        expect(find.text(_kRest), findsNothing, reason: '取れた答えを入れたのに※が消えない');
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c16) どちらの※を押しても読めなかった分をまとめて読み直す・_busy の間も本日休みは読む', (tester) async {
      await http.runWithClient(() async {
        srv.today = (_) => _ng();
        rest.answer = _restNg;
        await _pumpPunch(tester, props, rest);
        expect(find.text(_kReset), findsOneWidget);
        expect(find.text(_kRest), findsOneWidget);
        final t0 = srv.count('today');
        final r0 = rest.calls;
        await tester.tap(find.text(_kRest));
        await tester.pumpAndSettle();
        expect(rest.calls, r0 + 1);
        expect(srv.count('today'), t0 + 1, reason: '本日休みの※で、打刻の状態を読み直さない');
        await tester.tap(find.text(_kReset));
        await tester.pumpAndSettle();
        expect(rest.calls, r0 + 2, reason: '打刻の※で、本日休みを読み直さない');
        expect(srv.count('today'), t0 + 2);
        // _busy の間（打つ間）に本日休みの※を押しても、本日休みは読む（打刻の分は見送る）。
        srv.holding.add('punch');
        await _punchVia(tester, '出勤', '出勤する', settle: false);
        await tester.pump();
        final r1 = rest.calls;
        final t1 = srv.count('today');
        await tester.tap(find.text(_kRest));
        await tester.pump();
        expect(rest.calls, r1 + 1, reason: '_busy の間に本日休みを読まない');
        expect(srv.count('today'), t1, reason: '_busy の間に打刻の状態を読んだ');
        srv.held['punch']!.single.complete(_punchRes());
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c17) (お) 勤務の設定を一度も読めない：回る印の代わりに字（形）・押すと「取得中...」・読めなければまた同じ字・読めれば今の画面',
        (tester) async {
      SharedPreferences.setMockInitialValues({'auth_token': 'T', 'user_id': 'U1', 'work_mode': 1});
      await http.runWithClient(() async {
        srv.settings = (_) => _ng(); // サーバから取れない → 端末の保存（読めない）＝投げる
        await _pumpPunch(tester, props, rest, settle: false);
        await tester.pump();
        await tester.pump();
        expect(find.text(_kSettings), findsOneWidget, reason: '勤務の設定を読めない事が出ない');
        expect(find.byType(CircularProgressIndicator), findsNothing, reason: '回る印のまま');
        final t = tester.widget<Text>(find.text(_kSettings));
        expect(t.style?.fontSize, 14);
        expect(t.style?.color, _kWarning);
        expect(tester.getRect(find.ancestor(of: find.text(_kSettings), matching: find.byType(GestureDetector)).first).height >= 44,
            isTrue);
        expect(find.text('みなし勤務'), findsNothing, reason: '初めの値（みなし）の姿で描いた');
        // 押す → 読む間は「取得中...」→ 読めない → また同じ字。
        srv.holding.add('settings');
        await tester.tap(find.text(_kSettings));
        await tester.pump();
        expect(find.text(_kReading), findsOneWidget);
        srv.held['settings']!.last.complete(_ng());
        await tester.pump();
        await tester.pump();
        expect(find.text(_kSettings), findsOneWidget, reason: '読めない時に同じ字へ戻らない');
        // 読めれば今の画面。
        srv.holding.clear();
        srv.settings = (_) => _settingsRes();
        await tester.tap(find.text(_kSettings));
        await tester.pumpAndSettle();
        expect(find.text(_kSettings), findsNothing);
        expect(find.text('今日はまだ出勤していません'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c18) 打つ所が投げた：既定の字で知らせ・_busy は下りる・締めの窓の口には「取れなかった」が返る', (tester) async {
      await http.runWithClient(() async {
        PunchOutStart Function()? handler;
        srv.today = (_) => _todayRes(inn: true);
        await _pumpPunch(tester, props, rest, onHandler: (fn) => handler = fn);
        (await SharedPreferences.getInstance()).setInt('auth_token', 1); // 打つ時に資格を読めない＝投げる
        final start = handler!();
        expect(start.kind, PunchOutStartKind.started);
        var done = true;
        unawaited(start.done!.then((v) => done = v));
        await tester.pump();
        await tester.pump();
        expect(done, isFalse, reason: '投げたのに「打てた」と返した');
        expect(find.text('エラーが発生しました'), findsOneWidget, reason: '投げた事を知らせない');
        expect(srv.count('punch'), 0);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing, reason: '_busy が下りない');
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c19) 締めの窓の退勤の口：最中は busy（打たない）・打ち始めたら started（打てたら true）・画面が無ければ absent',
        (tester) async {
      await http.runWithClient(() async {
        PunchOutStart Function()? handler;
        srv.today = (_) => _todayRes(inn: true);
        await _pumpPunch(tester, props, rest, onHandler: (fn) => handler = fn);
        srv.holding.add('punch');
        await _punchVia(tester, '退勤', '退勤する', settle: false);
        await tester.pump();
        final busy = handler!();
        expect(busy.kind, PunchOutStartKind.busy, reason: '最中なのに打ち始めた');
        expect(busy.done, isNull);
        expect(srv.count('punch'), 1, reason: '最中に2回目を打った');
        srv.held['punch']!.single.complete(_punchRes(out: true));
        await tester.pumpAndSettle();
        srv.holding.clear();
        srv.punch = (_) => _punchRes(out: true);
        final ok = handler!();
        expect(ok.kind, PunchOutStartKind.started);
        bool? done;
        unawaited(ok.done!.then((v) => done = v));
        await tester.pumpAndSettle();
        expect(done, isTrue);
        await tester.pumpWidget(const SizedBox());
        final gone = handler!();
        expect(gone.kind, PunchOutStartKind.absent, reason: '画面が無いのに absent を返さない');
      }, () => srv.client);
    });

    testWidgets('(BN-c20) みなしの時は打刻の状態を読めなくても※を出さない（二者比較は c1）', (tester) async {
      await http.runWithClient(() async {
        srv.settings = (_) => _settingsRes(actual: false);
        srv.today = (_) => _ng();
        await _pumpPunch(tester, props, rest);
        expect(find.text('みなし勤務'), findsOneWidget);
        expect(find.text(_kReset), findsNothing);
        expect(find.text(_kKept), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c21) 本日休みの窓：未送信の箱を読めなかった時だけ本文の下に※（左寄せ・上に 6）（二者比較）', (tester) async {
      await http.runWithClient(() async {
        var failed = true;
        srv.settings = (_) => _settingsRes(actual: false);
        await _pumpPunch(tester, props, rest, isReportDone: () => true, isPendingReadFailed: () => failed);
        await tester.tap(find.text('本日休み'));
        await tester.pumpAndSettle();
        expect(find.text(_kPendingNote), findsOneWidget);
        final t = tester.widget<Text>(find.text(_kPendingNote));
        expect(t.style?.fontSize, 11.5);
        expect(t.style?.color, _kWarning);
        expect(t.textAlign, TextAlign.start);
        final body = tester.getRect(find.text('本日は既に日報を提出済みです。休みとして登録しますか？'));
        final note = tester.getRect(find.text(_kPendingNote));
        expect(note.top - body.bottom, closeTo(6, 0.01));
        expect((note.left - body.left).abs() < 0.01, isTrue, reason: '※が本文と同じ左に無い');
        await tester.tap(find.text('戻る'));
        await tester.pumpAndSettle();
        failed = false;
        await tester.tap(find.text('本日休み'));
        await tester.pumpAndSettle();
        expect(find.text(_kPendingNote), findsNothing);
        await tester.tap(find.text('戻る'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
    });

    testWidgets('(BN-c22) 本日休みの窓と休みの取り消しの窓は、開いたまま業務日が替われば閉じる（何もしない）', (tester) async {
      await http.runWithClient(() async {
        srv.settings = (_) => _settingsRes(actual: false);
        await _pumpPunch(tester, props, rest, isReportDone: () => true);
        await tester.tap(find.text('本日休み'));
        await tester.pumpAndSettle();
        expect(find.text('本日は報告済みです'), findsOneWidget);
        _setNow(DateTime.utc(2026, 10, 21, 15, 0));
        BusinessDayTick.ring();
        await tester.pumpAndSettle();
        expect(find.text('本日は報告済みです'), findsNothing, reason: '本日休みの窓が閉じない');
        expect(find.byType(RestDayScreen), findsNothing, reason: '閉じた後に休みの画面へ進んだ');
        await tester.pumpWidget(const SizedBox());
      }, () => srv.client);
      final srv2 = _Srv()..settings = (_) => _settingsRes(actual: false);
      final rest2 = _Rest()..answer = () => _restOk(rested: true);
      _setNow(_t0);
      await http.runWithClient(() async {
        var reports = 0;
        await _pumpPunch(tester, ValueNotifier<_Props>(const _Props()), rest2, onReport: () => reports++);
        await tester.tap(find.text('日報を報告'));
        await tester.pumpAndSettle();
        expect(find.text('本日は休み登録済みです'), findsOneWidget);
        _setNow(DateTime.utc(2026, 10, 21, 15, 0));
        BusinessDayTick.ring();
        await tester.pumpAndSettle();
        expect(find.text('本日は休み登録済みです'), findsNothing, reason: '休みの取り消しの窓が閉じない');
        expect(rest2.deletes, 0, reason: '閉じた時に休みを取り消した');
        expect(reports, 0, reason: '閉じた時に日報のフォームを開いた');
        await tester.pumpWidget(const SizedBox());
      }, () => srv2.client);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (d) 送った後の画面（(Y1)・(D3)(48)）
  // ══════════════════════════════════════════════════════════
  group('(d) 送った後の画面', () {
    setUp(() => _setNow(_t0)); // 今の業務日（日勤）は 10-21
    Future<void> pumpAfter(WidgetTester tester,
        {bool closeBusy = false, String? bizDate, bool showOvertime = true, VoidCallback? onClose}) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AfterReportBody(
            workerName: '検査',
            sent: true,
            shiftType: 'day',
            onOvertime: () async {},
            onClose: onClose,
            closeBusy: closeBusy,
            bizDate: bizDate,
            showOvertime: showOvertime,
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('(BN-d1) 退勤を打つ間は［今日はここまで］が回る印で押せない（枠は textFaint の 1.5・印は 20×20・太さ 2.5）（二者比較）',
        (tester) async {
      var closed = 0;
      await pumpAfter(tester, closeBusy: true, onClose: () => closed++);
      expect(find.text('今日はここまで'), findsNothing);
      final spin = find.byType(CircularProgressIndicator);
      expect(spin, findsOneWidget);
      final ind = tester.widget<CircularProgressIndicator>(spin);
      expect(ind.color, _kFaint);
      expect(ind.strokeWidth, 2.5);
      expect(tester.getSize(spin), const Size(20, 20));
      await tester.tap(spin);
      await tester.pump();
      expect(closed, 0, reason: '打つ間に押せた');
      expect(find.text('⏰  追加の申告'), findsOneWidget, reason: 'ほかのボタンを消した');
      await pumpAfter(tester, onClose: () => closed++);
      expect(find.text('今日はここまで'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('今日はここまで'));
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('(BN-d2) 頭の日付は渡した業務日・またいで送った印の時は「続けて報告」と［追加の申告］を出さない（二者比較）', (tester) async {
      await pumpAfter(tester, bizDate: '2026-10-20', showOvertime: false);
      expect(find.text('☀日勤 10/20分を送信しました'), findsOneWidget);
      expect(find.text('続けて報告'), findsNothing);
      expect(find.text('⏰  追加の申告'), findsNothing);
      expect(find.text('今日はここまで'), findsOneWidget);
      await pumpAfter(tester, bizDate: '2026-10-21');
      expect(find.text('☀日勤 10/21分を送信しました'), findsOneWidget);
      expect(find.text('続けて報告'), findsOneWidget);
      expect(find.text('⏰  追加の申告'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (e) 「未送信日報」の画面（(D5)＝業務日の切り替わりの知らせで分け直す）
  // ══════════════════════════════════════════════════════════
  group('(e) 未送信日報の画面', () {
    testWidgets('(BN-e1) 業務日が替わった知らせで、今日の分とほかの日を分け直す（端末は読まない）', (tester) async {
      _setNow(DateTime.utc(2026, 10, 21, 14, 0)); // 日本の 10/21 23:00
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: PendingReportsScreen(
          shiftType: 'day',
          onRemoveRow: (_) async {},
          onRemoveUnreadable: () async {},
          onRetry: () async {},
        ),
      ));
      await tester.pumpAndSettle();
      ReportStore.instance.pendingView.value = const PendingView(own: [
        PendingReportRow(id: 'a', shiftType: 'day', businessDate: '2026-10-21', refusedMessage: '有効な所属がありません'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('外す'), findsNothing, reason: '今日の分に「外す」を付けた');
      _setNow(DateTime.utc(2026, 10, 21, 15, 0)); // 10/22 0:00
      BusinessDayTick.ring();
      await tester.pumpAndSettle();
      expect(find.text('外す'), findsOneWidget, reason: '業務日が替わったのに、前の日の行を今日の分のまま出した');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (f) シェルの繋ぎ（ソースの字）
  // ══════════════════════════════════════════════════════════
  group('(f) シェルの繋ぎ', () {
    final home = _codeOnly(_home);
    final flat = _flat(home);

    test('(BN-f1) (D1) 送った・締めた印の写しは勤務の種類・業務日・状態の3つ・読み口は今の業務日と比べる・書くのは _setMark と _clearMark だけ', () {
      expect(home.contains('bool _todayReportDone ='), isFalse, reason: '真偽だけの写しが残っている');
      expect(home.contains('bool _todayClosed ='), isFalse);
      expect(home.contains('bool _doneMarkReadFailed ='), isFalse);
      expect(flat.contains('bool get _markIsToday => _markShift != null && _markShift == _shiftType && '
          '_markBizDate == businessDateForShift(_shiftType, businessNow());'), isTrue);
      expect(flat.contains('bool get _todayReportDone => _markIsToday && _isReportDoneStatus(_markStatus);'), isTrue);
      expect(flat.contains("bool get _todayClosed => _markIsToday && _markStatus == 'closed';"), isTrue);
      expect(flat.contains('bool get _doneMarkReadFailed => _doneMarkFailShift != null && _doneMarkFailShift == _shiftType && '
          '_doneMarkFailBizDate == businessDateForShift(_shiftType, businessNow());'), isTrue);
      // 写しを書く所は2つの関数だけ（_markShift・_markBizDate・_markStatus に直に入れる所は、その中の3行ずつ）。
      expect(RegExp(r'_markShift = ').allMatches(home).length, 2);
      expect(RegExp(r'_markBizDate = ').allMatches(home).length, 2);
      expect(RegExp(r'_markStatus = ').allMatches(home).length, 2);
      // 読み直しの3か所は、業務日を1回求めて読む口へ渡し、読んだ物をそのまま写す。
      final re = _flat(_bodyFrom(home, '  Future<void> _reevaluateReportDone() async {'));
      expect(re.contains('final shift = _shiftType; final biz = businessDateForShift(shift, businessNow());'), isTrue);
      expect(re.contains('s = await _readWorkStatusOn(shift, biz);'), isTrue);
      final init = _flat(_bodyFrom(home, '  Future<void> _initTodayReportDone(String shift, String bizDate) async {'));
      expect(init.contains('setState(() => _setMark(shift, bizDate, s));'), isTrue);
    });

    test('(BN-f2) (D2)(48)(D4) 送る：押した時の今を頭で取り、日報の時刻と送った印と写しをその日で書く・送れたら段 1・返りは真偽', () {
      final s = _flat(_bodyFrom(home, '  Future<bool> _submit() async {'));
      final iNow = s.indexOf('final sendNow = _snapshotNow ?? businessNow();');
      final iFirstAwait = s.indexOf('await ');
      expect(iNow >= 0 && iNow < iFirstAwait, isTrue, reason: '押した時の今を、待つ前に手元に移していない');
      expect(s.contains('timestamp: sendNow,'), isTrue, reason: '日報の時刻が押した時の今でない');
      expect(s.contains('sentShift = item.shiftType; sentBizDate = businessDateForShift(item.shiftType, item.timestamp);'), isTrue);
      expect(s.contains("_saveWorkStatus('done', owner: item.ownerUserId, shiftType: sentShift, bizDate: sentBizDate);"), isTrue);
      expect(s.contains("_setMark(sentShift, sentBizDate, 'done'); if (!_markIsToday) _crossedSentMark = (shift: sentShift, bizDate: sentBizDate);"),
          isTrue, reason: 'またいで送った時の印を置いていない');
      expect(s.contains('_reportStep = 1;'), isTrue, reason: '送れた後に段を 1 へ戻さない');
      expect(s.contains('_routeComparisons = {}'), isFalse, reason: '目安を空にした');
      expect(s.contains('if (!stored) return false; if (!mounted) return true;'), isTrue);
      expect(s.contains('return true;'), isTrue);
      // 確かめの画面の日付の字と、その今を覚える所。
      expect(flat.contains('ReportSnapshot _buildSnapshot() { final now = businessNow(); _snapshotNow = now; '
          'return reportSnapshotFrom( dateLabel: _formDateLabelAt(now),'), isTrue);
      final parts = _flat(_codeOnly('lib/widgets/report_form_parts.dart'));
      expect(parts.contains('isDone'), isFalse, reason: '確かめの画面に isDone の口が残っている');
      expect(parts.contains('final Future<bool> Function() onSend;'), isTrue);
      expect(parts.contains('done = await widget.onSend();'), isTrue);
      expect(parts.contains('if (done) Navigator.pop(context);'), isTrue);
      final late = _flat(_codeOnly('lib/screens/late_report_screen.dart'));
      expect(late.contains('isDone'), isFalse);
      expect(late.contains('Future<bool> _submit() async {'), isTrue);
    });

    test('(BN-f3) (D3) 送った後の画面は「出している印」の日で出す・またいで送った時は［追加の申告］を出さない・全画面が閉じ終わったら印を消す', () {
      expect(flat.contains('final shown = _shownMark;'), isTrue);
      expect(flat.contains('if (shown != null) {'), isTrue);
      expect(flat.contains('shiftType: shown.shift, '), isTrue);
      expect(flat.contains('bizDate: shown.bizDate, '), isTrue, reason: '頭の日付が出している印の業務日でない');
      expect(flat.contains('showOvertime: shown.isToday,'), isTrue);
      expect(flat.contains('closeBusy: _closePunching,'), isTrue);
      final push = _flat(_bodyFrom(home, '  Future<void> _pushReportForm() async {'));
      final iCompleted = push.indexOf('await route.completed;');
      final iClear = push.indexOf('setState(() => _crossedSentMark = null);');
      expect(iCompleted >= 0 && iClear > iCompleted, isTrue, reason: '閉じ終わる前に、またいで送った印を消した（または消さない）');
      final open = _flat(_bodyFrom(home, '  Future<void> _openReportForm() async {'));
      expect(open.contains('} finally { _reportFormOpen = false;'), isTrue);
    });

    test('(BN-f4) (D5) 時計：initState の頭で掛ける・戻った時に今から掛け直して描き直しと知らせ・dispose で止める・鳴ったら番号を進める', () {
      final init = _flat(_bodyFrom(home, '  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addObserver(this);'));
      final iClock = init.indexOf('_dayClock.restart();');
      final iRestore = init.indexOf('_todayStateReady = _restoreTodayState();');
      expect(iClock >= 0 && iClock < iRestore, isTrue, reason: '時計を掛けるのが遅い');
      final resumed = _flat(_bodyFrom(home, '  void didChangeAppLifecycleState(AppLifecycleState state) {'));
      expect(resumed.contains('_dayClock.restart(); setState(() {}); BusinessDayTick.ring(); _maybeReturnToDayShift();'), isTrue);
      expect(resumed.contains('_businessDayTick'), isFalse, reason: '戻った時に PunchScreen の番号を進めた（2回引く）');
      final dispose = _flat(_bodyFrom(home, '  void dispose() {\n    _workCtrl.removeListener'));
      expect(dispose.contains('_dayClock.stop();'), isTrue);
      final tick = _flat(_bodyFrom(home, '  void _onBusinessDayTick() {'));
      expect(tick.contains('setState(() => _businessDayTick++); BusinessDayTick.ring(); _maybeReturnToDayShift();'), isTrue);
      expect(flat.contains('businessDayTick: _businessDayTick,'), isTrue);
      final pending = _flat(_codeOnly('lib/screens/pending_reports_screen.dart'));
      expect(pending.contains('BusinessDayTick.changes.addListener(_onBusinessDayTick);'), isTrue);
      expect(pending.contains('BusinessDayTick.changes.removeListener(_onBusinessDayTick);'), isTrue);
    });

    test('(BN-f5) (D6) 夜勤のまま業務日が替わった時：決まり1本・替えてよい時だけ・覚える所・見る所・見張り', () {
      final rule = _flat(_bodyFrom(home, '  void _maybeReturnToDayShift() {'));
      for (final p in [
        'if (!mounted) return;',
        'final decided = _shiftDecidedBiz; if (decided == null) return;',
        'if (businessDateForShift(_shiftType, now) == decided) { _formSwitchedInPlace = false;',
        'if (!_canSwitchShiftNow()) return;',
        "final changed = _shiftType != 'day';",
        "_shiftType = 'day'; _shiftDecidedBiz = businessDateForShift('day', now); _formSwitchedInPlace = false;",
        'if (changed) _reevaluateReportDone();',
      ]) {
        expect(rule.contains(p), isTrue, reason: '日勤へ戻す決まりに「$p」が無い');
      }
      expect(rule.contains('SharedPreferences'), isFalse, reason: '端末を読んだ・書いた');
      expect(rule.contains('_saveShiftType'), isFalse, reason: '端末の勤務の種類を書き替えた');
      expect(rule.contains('_shiftReadFailed'), isFalse, reason: '※に触った');
      final can = _flat(_bodyFrom(home, '  bool _canSwitchShiftNow() {'));
      expect(can.contains('if (!_reportFormOpen) return _shellRoute?.isCurrent ?? false;'), isTrue);
      expect(can.contains('return r != null && r.isCurrent && _formSwitchedInPlace;'), isTrue);
      // 覚える所。
      final restore = _flat(_bodyFrom(home, '  Future<void> _restoreShiftType() async {'));
      expect(restore.contains('final now = businessNow();'), isTrue);
      expect(restore.contains('_shiftType = savedType; _shiftDecidedBiz = businessDateForShift(savedType, now);'), isTrue);
      expect(restore.contains("_shiftType = 'day'; _shiftDecidedBiz = businessDateForShift('day', now);"), isTrue);
      expect(RegExp(r'_maybeReturnToDayShift\(\);').allMatches(restore).length, 2, reason: '覚えた時に見ない');
      expect(flat.contains('_shiftType = v; _shiftDecidedBiz = businessDateForShift(v, businessNow());'), isTrue,
          reason: '選び直した時に覚えない');
      // 見る所：シェルの route と全画面の見張りの didPopNext・全画面が閉じ終わった後・器が見つけた後。
      expect(flat.contains('void didPopNext() => _maybeReturnToDayShift();'), isTrue);
      final deps = _flat(_bodyFrom(home, '  void didChangeDependencies() {'));
      expect(deps.contains('appRouteObserver.subscribe(this, route);'), isTrue);
      expect(flat.contains('appRouteObserver.unsubscribe(this);'), isTrue);
      expect(flat.contains('_ReportFormRouteWatcher(route, onPopNext: _maybeReturnToDayShift)..start();'), isTrue);
      final open = _flat(_bodyFrom(home, '  Future<void> _openReportForm() async {'));
      expect(open.contains('_reportFormOpen = false; _maybeReturnToDayShift();'), isTrue);
      final tab = _flat(_bodyFrom(home, '  Widget _buildHomeTabContent() {'));
      expect(tab.contains('if (_formLastDrawnAfter == true && !drawnAfter) { _formSwitchedInPlace = true; '
          'WidgetsBinding.instance.addPostFrameCallback((_) => _maybeReturnToDayShift()); } _formLastDrawnAfter = drawnAfter;'),
          isTrue);
      final push = _flat(_bodyFrom(home, '  Future<void> _pushReportForm() async {'));
      expect(push.trimLeft().startsWith('Future<void> _pushReportForm() async { _formSwitchedInPlace = false; _formLastDrawnAfter = null;'),
          isTrue, reason: '開く時に、前の全画面の覚えを空にしない');
      final mainSrc = _flat(_codeOnly(_main));
      expect(mainSrc.contains('navigatorObservers: [appRouteObserver],'), isTrue);
      final obs = _flat(_codeOnly('lib/utils/app_route_observer.dart'));
      expect(obs.contains('final RouteObserver<ModalRoute<void>> appRouteObserver = RouteObserver<ModalRoute<void>>();'), isTrue,
          reason: '窓とシートの上の物が閉じた時の知らせが届かない型');
    });

    test('(BN-f6) (D8) 今日を前に置く字の窓（5つ）は業務日が替われば閉じる・締めの窓（字に日付が在る）は閉じない', () {
      expect('CloseOnBusinessDayChange('.allMatches(home).length, 3, reason: 'シェルの窓（2件目・退勤締め・追加の申告）');
      expect('CloseOnBusinessDayChange('.allMatches(_codeOnly(_punch)).length, 2, reason: '打刻の画面の窓（本日休み・休みの取り消し）');
      final second = _flat(_bodyFrom(home, '  Future<bool> _confirmSecondReportIfNeeded() async {'));
      expect(second.contains('builder: (ctx) => CloseOnBusinessDayChange( shiftType: _shiftType, closeValue: false,'), isTrue);
      final picker = _flat(_bodyFrom(home, '  Future<void> _openExtraDeclarationPicker() async {'));
      expect(picker.contains('builder: (ctx) => CloseOnBusinessDayChange( shiftType: _shiftType, child: AlertDialog('), isTrue);
      final close = _flat(_bodyFrom(home, '  Future<void> _onCloseToday() async {'));
      final iWin = close.indexOf("'今日の報告を締めますか？'");
      final iGuard = close.lastIndexOf('CloseOnBusinessDayChange(');
      expect(iWin > iGuard, isTrue, reason: '締めの窓を業務日の替わりで閉じる');
    });

    test('(BN-f7) (D9) 休憩の短縮のシートと残業の窓は開いた日に当てる', () {
      final sheet = _flat(_bodyFrom(home, '  Future<void> _openShortBreakSheet() async {'));
      final iDate = sheet.indexOf('final workDate = businessDateForShift(shift, businessNow());');
      final iShow = sheet.indexOf('await showModalBottomSheet<void>(');
      expect(iDate >= 0 && iDate < iShow, isTrue, reason: '開く前に業務日を求めていない');
      expect(sheet.contains('workDate: workDate,'), isTrue);
      expect(sheet.contains('DateTime.now()'), isFalse);
      final ot = _flat(_bodyFrom(home, '  Future<void> _openOvertimeDialog() async {'));
      final iAt = ot.indexOf('final openedAt = businessNow();');
      final iDialog = ot.indexOf('await showDialog(');
      expect(iAt >= 0 && iAt < iDialog, isTrue);
      expect(ot.contains('timestamp: openedAt,'), isTrue, reason: '残業の日報の時刻が開いた時の今でない');
    });

    test('(BN-f8) (50) 締めの窓の退勤：最中は知らせて打たず閉じず・打つ間は回る印・打てて一番上の時だけ閉じる・取れなければ閉じない', () {
      final close = _flat(_bodyFrom(home, '  Future<void> _onCloseToday() async {'));
      for (final p in [
        'final route = _reportFormRoute;',
        'final start = punchOut(); switch (start.kind) {',
        'case PunchOutStartKind.busy: showJsSnackbar(context, kCloseBusyText, isWarning: true);',
        'case PunchOutStartKind.absent: showJsSnackbar(context, kPunchErrorText, isError: true);',
        'setState(() => _closePunching = true);',
        'punched = await start.done!; } finally { if (mounted) setState(() => _closePunching = false); }',
        'if (!mounted) return;',
        'if (!punched) return;',
        'if (route != null && route.isCurrent) Navigator.of(context).pop();',
      ]) {
        expect(close.contains(p), isTrue, reason: '締めの窓の退勤に「$p」が無い');
      }
      expect(_flat(_codeOnly('lib/core/report_send_texts.dart'))
          .contains("const String kCloseBusyText = '処理中のため退勤できません。少し待ってから、もう一度お試しください。';"), isTrue);
    });

    test('(BN-f9) (53) 今日の印を書く所は投げない・書けない時は控えに1件（続く間は1件だけ・書けたら下ろす）', () {
      final save = _flat(_bodyFrom(home,
          '  Future<void> _saveWorkStatus(String status,\n      {String? owner, String? shiftType, String? bizDate}) async {'));
      for (final p in [
        'try {',
        "if (!ok) throw StateError('今日の印を端末に書けませんでした'); _todayMarkSaveFailed = false;",
        "} catch (e) { debugPrint('今日の印を端末に書けませんでした: \$e'); if (_todayMarkSaveFailed) return; "
            "_todayMarkSaveFailed = true; await recordDeviceError('today_mark_save'); }",
      ]) {
        expect(save.contains(p), isTrue, reason: '今日の印を書く所に「$p」が無い');
      }
      expect(_flat(_codeOnly('lib/utils/device_error_log.dart'))
          .contains("'today_mark_save': (title: '送信記録の保存', fallback: '印を残さずに続行'),"), isTrue);
    });

    test('(BN-f10) (46) 2件目の窓：未送信の箱を読めなかった時だけ本文の下に※・本日休みの窓の口へ同じ物を渡す', () {
      final second = _flat(_bodyFrom(home, '  Future<bool> _confirmSecondReportIfNeeded() async {'));
      expect(second.contains('final readFailed = ReportStore.instance.pendingView.value.readFailed;'), isTrue);
      expect(second.contains('if (readFailed) kPendingReadFailedNoteDialogView,'), isTrue);
      expect(flat.contains('isPendingReadFailed: () => ReportStore.instance.pendingView.value.readFailed,'), isTrue);
    });

    test('(BN-f11) 今は業務日の真実源の本の口（businessNow）から読む（名指しした所に DateTime.now() が無い）', () {
      for (final head in [
        '  Future<void> _restoreShiftType() async {',
        '  Future<bool> _saveShiftType(String v) async {',
        '  Future<void> _openDaySheet(String ds) async {',
        '  String get _dateLabel {',
        '  String _formDateLabelAt(DateTime now) {',
      ]) {
        final b = _bodyFrom(home, head);
        expect(b, isNotEmpty, reason: '$head が無い');
        expect(b.contains('DateTime.now()'), isFalse, reason: '$head の中で DateTime.now() を読んでいる');
      }
      expect(flat.contains("'d:\${businessDateForShift(_shiftType, businessNow())}',"), isTrue, reason: '目安の鍵の業務日');
      final punch = _codeOnly(_punch);
      expect(_flat(punch).contains('final isActual = _settings.mode == WorkModeType.actual; final now = businessNow();'), isTrue);
      expect(_flat(punch).contains('businessDate: businessDateForShift( widget.shiftType, businessNow()),'), isTrue);
      expect(_flat(_codeOnly('lib/utils/saved_shift_type.dart')).contains('DateTime.now()'), isFalse);
      expect(_flat(_codeOnly(_main)).contains('final bizDate = businessDateForShift(shiftType, businessNow());'), isTrue);
      expect(_flat(_codeOnly('lib/screens/pending_reports_screen.dart')).contains('final now = businessNow();'), isTrue);
    });

    test('(BN-f12) (D10)(52) 打つ所：押した時の行を頭で取り、打つ所だけに使う・投げた時は既定の字・断られた3つの符号だけ読み直す', () {
      final punch = _codeOnly(_punch);
      final d = _flat(_bodyFrom(punch, "  Future<bool> _doPunch(String type, {bool allowGoReport = true}) async {"));
      final iRow = d.indexOf('final pressedRow = _rowNow();');
      final iBusy = d.indexOf('setState(() => _busy = true);');
      final iGps = d.indexOf('gps = await fetchGpsAddress();');
      expect(iRow >= 0 && iRow < iBusy && iBusy < iGps, isTrue, reason: '押した時の行を、待つ前に取っていない');
      expect(d.contains('shiftType: pressedRow.shift,'), isTrue, reason: '打つ所が押した時の種類でない');
      expect(d.contains('widget.shiftType,'), isFalse, reason: '打つ所が今の種類を読んでいる');
      expect(d.contains('if (g == null || r == null) { showJsSnackbar(context, kPunchErrorText, isError: true); return false; }'), isTrue);
      expect(d.contains('if (kPunchRefusalRereadCodes.contains(r.errorCode)) {'), isTrue);
      expect(d.contains('pressedRow.shift == widget.shiftType;'), isTrue, reason: '替わった時も日報のフォームを開く');
      expect(_flat(punch).contains("const Set<String?> kPunchRefusalRereadCodes = { 'ALREADY_PUNCHED_IN', 'ALREADY_PUNCHED_OUT', 'NO_PUNCH_IN', };"),
          isTrue);
    });
  });
}
