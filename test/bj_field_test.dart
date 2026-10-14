// ============================================================
// test/bj_field_test.dart
//   便BJ（見本 claude/field_report_fix_mock_v1.html の ①〜⑧⑪ と A・B・C・ボスの裁定【Q137】〜【Q140】）の
//   職人アプリの直しを、機械で見張る検査。
//
// ★掟: 期待の字・数はこの本の中に直に書く（実装の字の定数は import しない）。二者比較（あり／なし）で見る。
//   通信は package:http の runWithClient＋MockClient の偽物・端末の保存は SharedPreferences の偽物・
//   写真の置き場は一時の置き場に差し替える（終わりに消す）。シェル（JsMainShell）は検査で立てられない
//   （通知・位置・通信の部品が多い）ので、シェルの繋ぎはソースの字で見る（説明の行は除く＝_codeOnly）。
// ★検査の名前の頭の番号（(BJ-a1) ほか）は、ログの赤い行からどの検査かを機械で読むための物（ほかの本の (a-1) と
//   取り違えないよう、頭に BJ- を付けた）。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/config/constants.dart';
import 'package:js_awake_app/core/report_place_labels.dart'
    show reportPlaceOf, reportPlaceText;
import 'package:js_awake_app/main.dart'
    show
        OvertimeDialog,
        ReportStore,
        TransportType,
        WorkerReportItem,
        pendingBoxWriter,
        permittedReportBodyFor,
        refusedMessageOf,
        reportBodyFor;
import 'package:js_awake_app/screens/after_report_screen.dart';
import 'package:js_awake_app/screens/home_screen.dart'
    show CalendarDayInfo, calendarDayReportsUnknown;
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/pending_report_auto_retry.dart';
import 'package:js_awake_app/services/reports_service.dart';
import 'package:js_awake_app/utils/business_date.dart';
import 'package:js_awake_app/utils/personal_data_cleanup.dart';
import 'package:js_awake_app/utils/report_photo_store.dart';
import 'package:js_awake_app/utils/saved_shift_type.dart';
import 'package:js_awake_app/utils/session_lockout.dart';
import 'package:js_awake_app/utils/today_marks.dart';
import 'package:js_awake_app/widgets/report_form_parts.dart';
import 'package:js_awake_app/widgets/report_form_steps.dart';
import 'package:js_awake_app/widgets/reports_truncated_bar.dart';

// ── 本の場所 ─────────────────────────────────────────────────────
const String _home = 'lib/screens/home_screen.dart';
const String _main = 'lib/main.dart';
const String _late = 'lib/screens/late_report_screen.dart';

/// 説明だけの行（空白の後が // で始まる行）を除いたソースの字。
String _codeOnly(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 空白を1つに畳む（改行と字下げの違いで落ちないように）。
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 名前で始まる関数の本体（最初の「名前」から、対になる「}」まで）。
String _bodyOf(String src, String head) {
  final start = src.indexOf(head);
  if (start < 0) return '';
  final open = src.indexOf('{', start);
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

/// 名前で始まる関数の本体（head の最後の「{」から、対になる「}」まで）。引数の並びに「{」が在る関数に使う。
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

// ── 日報の入れ物（検査が字で決める・時計を読まない）────────────────
WorkerReportItem _item(String id,
        {String name = '検査 太郎',
        String? owner,
        List<String>? work,
        List<String>? parking,
        String gpsAddress = 'テスト県テスト市1-2-3',
        String? failReason,
        double? lat,
        double? lon}) =>
    WorkerReportItem(
      id: id,
      name: name,
      transport: TransportType.train,
      transportTypes: ['train'],
      workPhotoPaths: work,
      parkingPhotoPaths: parking,
      gpsAddress: gpsAddress,
      gpsFailReason: failReason,
      gpsLat: lat,
      gpsLon: lon,
      shiftType: 'day',
      timestamp: DateTime.utc(2026, 10, 14, 1, 0),
      ownerUserId: owner,
    );

/// 届いた求めを控え、送った順に statuses の答えを返す偽物のサーバ（足りなくなったら最後の値を使い続ける）。
///   onRequest は、答える前に呼ぶ（送っている途中の端末の保存を見るため）。
Future<T> _withServer<T>(
    List<http.Request> seen, List<int> statuses, Future<T> Function() run,
    {Future<void> Function(http.Request req)? onRequest}) {
  var n = 0;
  return http.runWithClient(
    run,
    () => MockClient((req) async {
      if (onRequest != null) await onRequest(req);
      seen.add(req);
      final status = statuses[n < statuses.length ? n : statuses.length - 1];
      n++;
      final body = status == 201
          ? jsonEncode({'report_id': 'r-$n'})
          : jsonEncode({'error': 'サーバーエラー'});
      return http.Response(body, status,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );
}

Future<List<Map<String, dynamic>>> _box() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('pending_reports');
  if (raw == null) return [];
  return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(800, 1600), bool settle = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  // くるくる（回る印）が在る時は、落ち着くのを待たない（回り続ける）。
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory photoBase;
  late Directory photoDir;
  late Future<Directory> Function() origDirOf;

  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'T', 'user_id': 'U1', 'user_name': '検査 太郎'});
    ReportStore.instance.pendingOwnCount.value = 0;
    ReportStore.instance.droppedPhotoCount.value = 0;
    ReportStore.instance.pendingRefusedMessage.value = null;
    // 置き場の名前は本物と同じ report_photos（写真の見分けは置き場の中の名前＝検分 a251 の N1）。
    photoBase = Directory.systemTemp.createTempSync('bj_photos_');
    photoDir = Directory('${photoBase.path}/report_photos')..createSync();
    origDirOf = reportPhotoDirOf;
    reportPhotoDirOf = () async => photoDir;
  });
  tearDown(() {
    reportPhotoDirOf = origDirOf;
    if (photoBase.existsSync()) photoBase.deleteSync(recursive: true);
  });

  // ══════════════════════════════════════════════════════════
  // (a) 送った後の画面・保留の箱・持ち主（見本 v1 の ①案A・(5)・【Q140】）
  // ══════════════════════════════════════════════════════════
  group('(a) 送った後の画面と保留の箱', () {
    testWidgets('(BJ-a1) 送った後の画面：sent が false なら「未送信（再送待ち）」と今すぐ再送・true なら「報告完了」（二者比較）',
        (tester) async {
      Widget body(bool sent) => SingleChildScrollView(
            child: AfterReportBody(
              workerName: '山田',
              sent: sent,
              shiftType: 'day',
              onOvertime: () async {},
              onRetry: () {},
              onClose: () {},
            ),
          );
      await _pump(tester, body(false));
      expect(find.text('未送信（再送待ち）'), findsOneWidget);
      expect(find.text('山田さんの報告は保存されました'), findsOneWidget);
      expect(find.text('通信状況により未送信です。電波の良い場所で自動再送されます。'), findsOneWidget);
      expect(find.text('今すぐ再送する'), findsOneWidget);
      expect(find.text('報告完了'), findsNothing);
      await _pump(tester, body(true));
      expect(find.text('報告完了'), findsOneWidget);
      expect(find.text('未送信（再送待ち）'), findsNothing);
      expect(find.text('今すぐ再送する'), findsNothing);
    });

    test('(BJ-a2) 送る前に箱へ入れる・届かなければ箱に残り数は1・送り直して届けば箱は空で数は0', () async {
      final seen = <http.Request>[];
      final inBoxWhileSending = <bool>[];
      await _withServer(seen, [500, 201], () async {
        final ok = await ReportStore.instance.addReport(_item('a2'));
        expect(ok, isFalse);
        expect(ReportStore.instance.pendingOwnCount.value, 1);
        final box = await _box();
        expect(box.map((e) => e['id']), ['a2']);
        expect(box.single['ownerUserId'], 'U1', reason: '持ち主の印が無い');
        await ReportStore.instance.retryPending();
        expect(ReportStore.instance.pendingOwnCount.value, 0);
        expect(await _box(), isEmpty);
      }, onRequest: (_) async {
        // 送っている途中の箱。
        final p = await SharedPreferences.getInstance();
        inBoxWhileSending.add((p.getString('pending_reports') ?? '').contains('"a2"'));
      });
      expect(seen.length, 2);
      expect(inBoxWhileSending, [true, true], reason: '送る前に箱へ入っていない');
    });

    test('(BJ-a3) 送り直しは1件ずつ：1件目が届かず2件目が届けば、箱には1件目だけが残る', () async {
      final seen = <http.Request>[];
      await _withServer(seen, [500, 500, 500, 201], () async {
        await ReportStore.instance.addReport(_item('a3-1', gpsAddress: '一'));
        await ReportStore.instance.addReport(_item('a3-2', gpsAddress: '二'));
        expect(ReportStore.instance.pendingOwnCount.value, 2);
        await ReportStore.instance.retryPending();
      });
      expect(seen.length, 4);
      expect((await _box()).map((e) => e['id']), ['a3-1']);
      expect(ReportStore.instance.pendingOwnCount.value, 1);
    });

    test('(BJ-a4) 持ち主：ほかの人（U2）の日報は送らずに箱へ残す・数に入れない／U2 がログインし直すと送る（二者比較）', () async {
      final seen = <http.Request>[];
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': jsonEncode([_item('a4', name: '別 花子', owner: 'U2').toJson()]),
      });
      await _withServer(seen, [201], () async {
        await ReportStore.instance.retryPending();
        expect(seen, isEmpty, reason: 'ほかの人の日報を、今の人の資格で送った');
        expect(ReportStore.instance.pendingOwnCount.value, 0);
        expect((await _box()).map((e) => e['id']), ['a4']);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', 'U2');
        await prefs.setString('user_name', '別 花子');
        await ReportStore.instance.retryPending();
      });
      expect(seen.length, 1);
      expect(await _box(), isEmpty);
    });

    test('(BJ-a5) 印の無い前の日報：名前が今の人と同じなら印を付けて送る・違えば送らずに残す（二者比較）', () async {
      final seen = <http.Request>[];
      final mine = _item('a5-mine')..ownerUserId = null;
      final other = _item('a5-other', name: '別 花子')..ownerUserId = null;
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': jsonEncode([mine.toJson(), other.toJson()]),
      });
      await _withServer(seen, [201], () => ReportStore.instance.retryPending());
      expect(seen.length, 1);
      expect(jsonDecode(seen.single.body)['worker_name'], '検査 太郎');
      final box = await _box();
      expect(box.map((e) => e['id']), ['a5-other']);
      expect(box.single['ownerUserId'], isNull, reason: '別の名前の日報に印を付けた');
    });

    test('(BJ-a6) 送り直しが重なっても、同じ日報は1回だけ送る', () async {
      final seen = <http.Request>[];
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': jsonEncode([_item('a6', owner: 'U1').toJson()]),
      });
      await _withServer(seen, [201], () => Future.wait([
            ReportStore.instance.retryPending(),
            ReportStore.instance.retryPending(),
          ]));
      expect(seen.length, 1, reason: '同じ日報を2回送った');
      expect(await _box(), isEmpty);
    });

    test('(BJ-a7) 電波の知らせ：つながった時だけ送り直す・none だけの時は送らない・止めた後は送らない', () async {
      expect(isConnectivityOnline([ConnectivityResult.none]), isFalse);
      expect(isConnectivityOnline([]), isFalse);
      expect(isConnectivityOnline([ConnectivityResult.wifi]), isTrue);
      expect(isConnectivityOnline([ConnectivityResult.mobile, ConnectivityResult.vpn]), isTrue);
      final ctrl = StreamController<List<ConnectivityResult>>();
      var calls = 0;
      final auto = PendingReportAutoRetry(
          retry: () async => calls++, changes: ctrl.stream)
        ..start();
      ctrl.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0, reason: 'つながっていないのに送り直した');
      ctrl.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1, reason: 'つながったのに送り直さない');
      await auto.stop();
      ctrl.add([ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1, reason: '止めた後も送り直した');
      await ctrl.close();
    });

    test('(BJ-a8) シェルの繋ぎ：頭の字は残りの数・アプリへ戻った時と電波で送り直す・写真の知らせ（ソースの字）', () {
      final src = _codeOnly(_home);
      final flat = _flat(src);
      expect(src.contains('_lastSentOk'), isFalse, reason: '送った直後の成否の欄が残っている');
      expect(
          flat.contains('return ValueListenableBuilder<int>( '
              'valueListenable: ReportStore.instance.pendingOwnCount, '
              'builder: (_, pending, __) => ValueListenableBuilder<String?>( '
              'valueListenable: ReportStore.instance.pendingRefusedMessage, '
              'builder: (_, refused, __) => AfterReportBody( '
              'workerName: _userName, sent: pending == 0, refusedMessage: refused,'),
          isTrue,
          reason: '送った後の画面の頭の字が残りの数で、3行目が受け付けなかった字で決まっていない');
      final resumed = _flat(_bodyOf(src, 'void didChangeAppLifecycleState('));
      expect(resumed.contains('ReportStore.instance.retryPending();'), isTrue,
          reason: 'アプリへ戻った時に送り直していない');
      final init = _flat(_bodyOf(src, '  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addObserver(this);'));
      for (final p in [
        'ReportStore.instance.refreshPendingCount();',
        'ReportStore.instance.droppedPhotoCount.addListener(_onDroppedPhotos);',
        '_autoRetry.start();',
      ]) {
        expect(init.contains(p), isTrue, reason: '始めに「$p」が無い');
      }
      final dispose = _flat(_bodyOf(src, '  void dispose() {\n    _workCtrl.removeListener'));
      for (final p in [
        'ReportStore.instance.droppedPhotoCount.removeListener(_onDroppedPhotos);',
        '_autoRetry.stop();',
      ]) {
        expect(dispose.contains(p), isTrue, reason: '終わりに「$p」が無い');
      }
      expect(flat.contains('PendingReportAutoRetry(retry: ReportStore.instance.retryPending)'), isTrue);
      // 開いた時にも1回、除いた写真の数を見る（検分 a251 の N8）。
      expect(init.contains('WidgetsBinding.instance.addPostFrameCallback((_) => _onDroppedPhotos());'), isTrue,
          reason: '開いた時に、除いた写真の数を見ていない');
    });

    test('(BJ-a9) 送り直しの途中で人が替わったら、次の1件からは送らずに箱へ残す／同じ人に戻れば送る（二者比較）', () async {
      final seen = <http.Request>[];
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': jsonEncode([
          _item('a9-1', owner: 'U1').toJson(),
          _item('a9-2', owner: 'U1').toJson(),
        ]),
      });
      var switched = false;
      await _withServer(seen, [201], () => ReportStore.instance.retryPending(), onRequest: (_) async {
        // 1件目を送っている間に、U1 がログアウトして U2 がログインした。
        if (switched) return;
        switched = true;
        final p = await SharedPreferences.getInstance();
        await p.setString('user_id', 'U2');
        await p.setString('auth_token', 'T2');
      });
      expect(seen.length, 1, reason: '人が替わった後も、前の人の日報を次の人の資格で送った');
      expect((await _box()).map((e) => e['id']), ['a9-2']);
      expect((await _box()).single['ownerUserId'], 'U1');
      // 二者比較：U1 がログインし直すと、残った1件を送る。
      final p = await SharedPreferences.getInstance();
      await p.setString('user_id', 'U1');
      await p.setString('auth_token', 'T');
      await _withServer(seen, [201], () => ReportStore.instance.retryPending());
      expect(seen.length, 2);
      expect(await _box(), isEmpty);
    });

    test('(BJ-a10) 箱へ書けなかった時：投げて、手元の写しの箱にも残さない（すぐ後の送り直しが送らない）／書ければ送る（二者比較）', () async {
      final seen = <http.Request>[];
      final orig = pendingBoxWriter;
      addTearDown(() => pendingBoxWriter = orig);
      var failNext = true;
      pendingBoxWriter = (prefs, key, value) async {
        // 手元の写しは替わる（shared_preferences は先に写しを替える）が、端末へ書く所で投げた形。
        await prefs.setString(key, value);
        if (failNext) {
          failNext = false;
          throw Exception('端末へ書けない');
        }
        return true;
      };
      await _withServer(seen, [201], () async {
        await expectLater(ReportStore.instance.addReport(_item('a10-1')), throwsException);
        expect(await _box(), isEmpty, reason: '書けなかった日報が手元の写しの箱に残った');
        await ReportStore.instance.retryPending();
        expect(seen, isEmpty, reason: '書けなかった日報を送り直しが送った（もう一度押すと2枚目になる）');
        expect(ReportStore.instance.pendingOwnCount.value, 0);
        expect(await ReportStore.instance.addReport(_item('a10-2')), isTrue);
      });
      expect(seen.length, 1);
      expect(await _box(), isEmpty);
    });

    test('(BJ-a11) 送れた後に箱から外せなかった時：送れた事として返し、写真は消さない・同じ日報を2回送らない', () async {
      final photo = File('${photoDir.path}/a11.jpg')..writeAsBytesSync([1]);
      final seen = <http.Request>[];
      final orig = pendingBoxWriter;
      addTearDown(() => pendingBoxWriter = orig);
      var calls = 0;
      pendingBoxWriter = (prefs, key, value) async {
        calls++;
        await prefs.setString(key, value);
        // 1回目＝箱へ入れる（書ける）・2回目＝送れた後に外す（投げる）。
        if (calls == 2) throw Exception('端末へ書けない');
        return true;
      };
      await _withServer(seen, [201], () async {
        expect(await ReportStore.instance.addReport(_item('a11', work: [photo.path])), isTrue,
            reason: '送れたのに、送れなかった事にした');
        await ReportStore.instance.retryPending();
      });
      expect(seen.length, 1, reason: '送れた日報をもう一度送った');
      expect(photo.existsSync(), isTrue, reason: '箱から外せなかったのに写真を消した');
    });

    test('(BJ-a12) 箱の読めない行は消さずに書き戻す／箱そのものが読めない時は元の字を別の鍵へ残す', () async {
      final seen = <http.Request>[];
      const badRow = {'id': 12, 'name': 3};
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': jsonEncode([_item('a12', owner: 'U1').toJson(), badRow]),
      });
      await _withServer(seen, [201], () => ReportStore.instance.retryPending());
      expect(seen.length, 1);
      expect(await _box(), [badRow], reason: '読めない行を消した');
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': '{壊れた',
      });
      await _withServer(seen, [201], () => ReportStore.instance.addReport(_item('a12-2')));
      expect(seen.length, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('pending_reports_unreadable'), ['{壊れた'], reason: '読めない箱の元の字を残していない');
      expect(await _box(), isEmpty);
    });

    test('(BJ-a13) 受け付けなかったかを決める1本：4xx の答え（資格・待ち時間・回数・締め出しの符号を除く）は送り先の字・ほかは null', () {
      ApiResult<Map<String, dynamic>> res(int status, {String? msg, String? code, bool json = true}) =>
          apiFailure<Map<String, dynamic>>(
              statusCode: status,
              errorMessage: msg,
              errorCode: code,
              errorDetails: json ? {'error': msg, 'code': code} : null);
      expect(refusedMessageOf(res(403, msg: '有効な所属がありません', code: 'MEMBERSHIP_INACTIVE')), '有効な所属がありません');
      expect(refusedMessageOf(res(400, msg: 'shift_type は day または night を指定してください')),
          'shift_type は day または night を指定してください');
      expect(refusedMessageOf(res(413, msg: '<html>…', json: false)), '理由不明', reason: 'JSON でない本文の字を出した');
      expect(refusedMessageOf(res(422, msg: '  ')), '理由不明');
      // 本文が JSON でも error の字が無い時は「理由不明」（後から出す日報の枠と同じ決まり）。
      expect(
          refusedMessageOf(apiFailure<Map<String, dynamic>>(
              statusCode: 400, errorMessage: '{"message":"x"}', errorDetails: {'message': 'x'})),
          '理由不明',
          reason: 'error の無い JSON の本文の字を出した');
      for (final s in [401, 408, 429, 500, 503, 0]) {
        expect(refusedMessageOf(res(s, msg: 'x')), isNull, reason: '$s を受け付けなかった答えにした');
      }
      expect(refusedMessageOf(res(403, msg: 'x', code: 'ACCOUNT_DISABLED')), isNull,
          reason: '締め出しの符号（ログインし直せば送れる）を受け付けなかった答えにした');
    });

    test('(BJ-a14) 送り先が受け付けなかった時：日報は箱に残し、送り先の字を書き留めて知らせる・ほかの答えで消す・届かなければ前のまま', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': jsonEncode([_item('a14', owner: 'U1').toJson()]),
      });
      // 答えの並び：受け付けない（403）→ 500 → 届かない → 受け付けない → 届かない。
      var n = 0;
      Future<void> retryWith(http.Response Function(http.Request req) answer) => http.runWithClient(
          () => ReportStore.instance.retryPending(),
          () => MockClient((req) async {
                n++;
                return answer(req);
              }));
      http.Response json(int status, Map<String, dynamic> body, http.Request req) => http.Response(
          jsonEncode(body), status,
          request: req, headers: {'content-type': 'application/json; charset=utf-8'});
      await retryWith((req) => json(403, {'error': '有効な所属がありません', 'code': 'MEMBERSHIP_INACTIVE'}, req));
      expect((await _box()).single['refusedMessage'], '有効な所属がありません');
      expect(ReportStore.instance.pendingRefusedMessage.value, '有効な所属がありません');
      expect(ReportStore.instance.pendingOwnCount.value, 1, reason: '受け付けなかった日報を箱から外した');
      await retryWith((req) => json(500, {'error': 'サーバーエラー', 'code': 'SERVER_ERROR'}, req));
      expect((await _box()).single['refusedMessage'], isNull, reason: '受け付けない答えでなくなったのに字が残った');
      expect(ReportStore.instance.pendingRefusedMessage.value, isNull);
      await retryWith((req) => json(403, {'error': '有効な所属がありません', 'code': 'MEMBERSHIP_INACTIVE'}, req));
      await retryWith((req) => throw const SocketException('届かない'));
      expect((await _box()).single['refusedMessage'], '有効な所属がありません', reason: '届かなかった時に前の答えを消した');
      expect(ReportStore.instance.pendingRefusedMessage.value, '有効な所属がありません');
      expect(n, 4);
    });

    testWidgets('(BJ-a15) 送った後の画面：受け付けなかった字が在れば「提出できません（…）」と※・無ければ通信の字（二者比較）', (tester) async {
      Widget body(String? refused) => SingleChildScrollView(
            child: AfterReportBody(
              workerName: '山田',
              sent: false,
              shiftType: 'day',
              onOvertime: () async {},
              onRetry: () {},
              onClose: () {},
              refusedMessage: refused,
            ),
          );
      await _pump(tester, body('有効な所属がありません'));
      expect(find.text('未送信（再送待ち）'), findsOneWidget);
      expect(find.text('山田さんの報告は保存されました'), findsOneWidget);
      expect(find.text('提出できません（有効な所属がありません）'), findsOneWidget);
      expect(find.text('※会社のご担当者にご確認ください。'), findsOneWidget);
      expect(find.text('通信状況により未送信です。電波の良い場所で自動再送されます。'), findsNothing);
      expect(find.text('今すぐ再送する'), findsOneWidget);
      await _pump(tester, body(null));
      expect(find.text('通信状況により未送信です。電波の良い場所で自動再送されます。'), findsOneWidget);
      expect(find.textContaining('提出できません'), findsNothing);
      expect(find.text('※会社のご担当者にご確認ください。'), findsNothing);
    });

    test('(BJ-a16) 送り直しが3本重なっても、送っている途中の日報を3本目が取り直さない（同じ日報は届くまで1本ずつ）', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': jsonEncode([
          _item('a16-x', owner: 'U1', gpsAddress: 'X').toJson(),
          _item('a16-y', owner: 'U1', gpsAddress: 'Y').toJson(),
        ]),
      });
      final ySending = Completer<void>();
      final x2Sending = Completer<void>();
      final releaseY = Completer<void>();
      final releaseX2 = Completer<void>();
      var xCount = 0;
      http.Response ok(http.Request req, int status) => http.Response(
          status == 201 ? jsonEncode({'report_id': 'r'}) : jsonEncode({'error': 'サーバーエラー'}), status,
          request: req, headers: {'content-type': 'application/json; charset=utf-8'});
      await http.runWithClient(() async {
        // 1本目：X は 500 ですぐ戻り、Y は待たされる。
        final r1 = ReportStore.instance.retryPending();
        await ySending.future;
        // 2本目：X を取り直して送る（待たされる）。
        final r2 = ReportStore.instance.retryPending();
        await x2Sending.future;
        // 1本目が終わる。
        releaseY.complete();
        await r1;
        // 3本目：X は2本目が送っている途中＝取らない。
        await ReportStore.instance.retryPending();
        releaseX2.complete();
        await r2;
      }, () => MockClient((req) async {
            final addr = jsonDecode(req.body)['gps_address'];
            if (addr == 'Y') {
              ySending.complete();
              await releaseY.future;
              return ok(req, 201);
            }
            xCount++;
            if (xCount == 1) return ok(req, 500);
            if (xCount == 2) {
              x2Sending.complete();
              await releaseX2.future;
            }
            return ok(req, 201);
          }));
      expect(xCount, 2, reason: '送っている途中の日報を、ほかの送り直しが取り直して2回目を送った');
      expect(await _box(), isEmpty);
    });

    test('(BJ-a17) 端末が「書けなかった」と答えた時（false）も、箱へ入らなかった事として投げる／書ければ送る（二者比較）', () async {
      final seen = <http.Request>[];
      final orig = pendingBoxWriter;
      addTearDown(() => pendingBoxWriter = orig);
      var first = true;
      pendingBoxWriter = (prefs, key, value) async {
        if (first) {
          first = false;
          return false;
        }
        return prefs.setString(key, value);
      };
      await _withServer(seen, [201], () async {
        await expectLater(ReportStore.instance.addReport(_item('a17-1')), throwsA(isA<StateError>()));
        expect(await _box(), isEmpty);
        await ReportStore.instance.retryPending();
        expect(seen, isEmpty, reason: '箱へ入らなかった日報を送った');
        expect(await ReportStore.instance.addReport(_item('a17-2')), isTrue);
      });
      expect(seen.length, 1);
    });

    test('(BJ-a18) 今の人が分からない時（user_id が空）は、持ち主を空の字にせず（null）・送らない／同じ名前の人がログインし直せば送る（二者比較）', () async {
      final seen = <http.Request>[];
      SharedPreferences.setMockInitialValues({'auth_token': 'T', 'user_id': '', 'user_name': '検査 太郎'});
      await _withServer(seen, [201], () async {
        expect(await ReportStore.instance.addReport(_item('a18')), isFalse);
      });
      expect(seen, isEmpty, reason: '今の人が分からないのに送った');
      expect(ReportStore.instance.pendingOwnCount.value, 1,
          reason: '今の人が分からないのに、残った日報を数えない（送った後の画面が「報告完了」と事実と違う字を出す）');
      expect((await _box()).single['ownerUserId'], isNull, reason: '持ち主を空の字にした（名前で今の人の物と見られなくなる）');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', 'U1');
      await _withServer(seen, [201], () => ReportStore.instance.retryPending());
      expect(seen.length, 1);
      expect(await _box(), isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (b) 写真（見本 v1 の ③）
  // ══════════════════════════════════════════════════════════
  group('(b) 写真', () {
    test('(BJ-b1) 撮った写真は置き場へ写す（中身は同じ・元は残す）／写せなければ元の道のまま（二者比較）', () async {
      final src = Directory.systemTemp.createTempSync('bj_cam_');
      addTearDown(() => src.deleteSync(recursive: true));
      final f = File('${src.path}/cam.jpg')..writeAsBytesSync([1, 2, 3]);
      final kept = await keepReportPhoto(f.path);
      expect(kept, isNot(f.path));
      expect(kept.startsWith('${photoDir.path}/'), isTrue, reason: '置き場の中へ写していない: $kept');
      expect(kept.endsWith('.jpg'), isTrue);
      expect(File(kept).readAsBytesSync(), [1, 2, 3]);
      expect(f.existsSync(), isTrue, reason: '置き場の外の写真を消した');
      final missing = '${src.path}/none.jpg';
      expect(await keepReportPhoto(missing), missing);
    });

    test('(BJ-b2) 写真を消すのは置き場の中だけ（外の道は触らない）', () async {
      final out = Directory.systemTemp.createTempSync('bj_out_');
      addTearDown(() => out.deleteSync(recursive: true));
      final inside = File('${photoDir.path}/in.jpg')..writeAsBytesSync([1]);
      final outside = File('${out.path}/out.jpg')..writeAsBytesSync([2]);
      await deleteReportPhotos([inside.path, outside.path, '${photoDir.path}/../x.jpg']);
      expect(inside.existsSync(), isFalse);
      expect(outside.existsSync(), isTrue, reason: '置き場の外の写真を消した');
    });

    test('(BJ-b3) 掃除：箱が指す写真は残す・before より後に書かれた写真は残す・ほかは消す', () async {
      final keep = File('${photoDir.path}/keep.jpg')..writeAsBytesSync([1]);
      final old = File('${photoDir.path}/old.jpg')..writeAsBytesSync([2]);
      final fresh = File('${photoDir.path}/fresh.jpg')..writeAsBytesSync([3]);
      final t0 = DateTime(2026, 10, 14, 9);
      keep.setLastModifiedSync(t0.subtract(const Duration(hours: 1)));
      old.setLastModifiedSync(t0.subtract(const Duration(hours: 1)));
      fresh.setLastModifiedSync(t0.add(const Duration(minutes: 1)));
      final n = await sweepReportPhotos(keep: {keep.path}, before: t0);
      expect(n, 1);
      expect(keep.existsSync(), isTrue);
      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue, reason: '起動の後に撮った写真を消した');
      // before が無い時（ログアウトの掃除）は、箱が指す物のほかは全部消す。
      expect(await sweepReportPhotos(keep: {keep.path}), 1);
      expect(fresh.existsSync(), isFalse);
    });

    test('(BJ-b4) 送り直しで読めない写真は除いて送り、除いた数を知らせる／読めれば0・送れた写真は消す（二者比較）', () async {
      final ok = File('${photoDir.path}/ok.jpg')..writeAsBytesSync([1, 2, 3]);
      final gone = '${photoDir.path}/gone.jpg';
      final seen = <http.Request>[];
      await _withServer(seen, [500, 201], () async {
        await ReportStore.instance.addReport(_item('b4', work: [ok.path, gone]));
        expect(ok.existsSync(), isTrue, reason: '送れなかった日報の写真を消した');
        expect(ReportStore.instance.droppedPhotoCount.value, 0, reason: '送れていないのに知らせた');
        await ReportStore.instance.retryPending();
      });
      expect(seen.length, 2);
      final photos = (jsonDecode(seen.last.body)['photos'] as List);
      expect(photos.length, 1);
      expect(photos.single['base64'], 'AQID');
      expect(ReportStore.instance.droppedPhotoCount.value, 1);
      expect(ok.existsSync(), isFalse, reason: '送れた日報の写真が置き場に残った');
    });

    test('(BJ-b5) 繋ぎ：撮る所は置き場へ写す・今日の日報は送る前に写真を確かめる・起動の時に掃除する（ソースの字）', () {
      final strip = _flat(_codeOnly('lib/widgets/photo_strip_field.dart'));
      expect(strip.contains('final kept = await keepReportPhoto(f.path); onChanged(<String>[...paths, kept]);'), isTrue);
      expect(strip.contains('f.path]'), isFalse, reason: '一時の置き場の道をそのまま入れている');
      final submit = _flat(_bodyOf(_codeOnly(_home), '  Future<void> _submit() async {\n    if (_submitting) return;\n    if (_userName.isEmpty)'));
      final iCheck = submit.indexOf('final photos = await reportPhotosFor(item);');
      final iFrame = submit.indexOf('_sendFrame(kPhotoUnreadableText)');
      final iAdd = submit.indexOf('await ReportStore.instance.addReport(item);');
      expect(iCheck > 0 && iCheck < iFrame && iFrame < iAdd, isTrue, reason: '送る前に写真を確かめていない');
      final mainSrc = _flat(_codeOnly(_main));
      expect(mainSrc.contains('unawaited(ReportStore.instance.sweepPhotos(before: DateTime.now()));'), isTrue);
    });

    test('(BJ-b6) 置き場の場所が替わっても名前で当てる：読んで送る・掃除で残す・送れたら消す（前の場所の道で覚えた日報）', () async {
      final cur = File('${photoDir.path}/b6.jpg')..writeAsBytesSync([1, 2, 3]);
      const stale = '/old/container/Library/Application Support/report_photos/b6.jpg';
      expect(await resolveReportPhotoPath(stale), cur.path);
      expect(await resolveReportPhotoPath('/tmp/elsewhere/b6.jpg'), '/tmp/elsewhere/b6.jpg',
          reason: '置き場の外の道を読み替えた');
      final seen = <http.Request>[];
      await _withServer(seen, [500, 201], () async {
        await ReportStore.instance.addReport(_item('b6', work: [stale]));
        expect(await sweepReportPhotos(keep: {stale}), 0);
        expect(cur.existsSync(), isTrue, reason: '箱が前の場所の道で指す写真を、掃除で消した');
        await ReportStore.instance.retryPending();
      });
      expect(seen.length, 2);
      expect((jsonDecode(seen.last.body)['photos'] as List).single['base64'], 'AQID');
      expect(ReportStore.instance.droppedPhotoCount.value, 0, reason: '読めたのに除いた');
      expect(cur.existsSync(), isFalse, reason: '送れた日報の写真が置き場に残った');
    });

    test('(BJ-b7) 送れた日報の写真でも、箱に残るほかの日報が指す写真は消さない／指さなければ消す（二者比較）', () async {
      final shared = File('${photoDir.path}/b7.jpg')..writeAsBytesSync([1]);
      final own = File('${photoDir.path}/b7own.jpg')..writeAsBytesSync([2]);
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': jsonEncode([
          _item('b7-1', owner: 'U1', work: [shared.path, own.path]).toJson(),
          _item('b7-2', name: '別 花子', owner: 'U2', work: [shared.path]).toJson(),
        ]),
      });
      await _withServer(<http.Request>[], [201], () => ReportStore.instance.retryPending());
      expect((await _box()).map((e) => e['id']), ['b7-2']);
      expect(shared.existsSync(), isTrue, reason: 'ほかの日報が指す写真を消した');
      expect(own.existsSync(), isFalse, reason: '送れた日報だけが指す写真が残った');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (c) 送れなかった時（見本 v1 の ②）
  // ══════════════════════════════════════════════════════════
  group('(c) 送れなかった時', () {
    testWidgets('(BJ-c1) 残業の窓：送る途中で投げたら、回るのを止めて字を出し、もう一度押せる／送れたら字は出ない（二者比較）',
        (tester) async {
      var calls = 0;
      var fail = true;
      await _pump(
          tester,
          Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (dctx) => OvertimeDialog(
                    workerName: '山田',
                    gpsAddress: '',
                    // 本物の送る所（home_screen.dart の _openOvertimeDialog）と同じく、送れたら窓を閉じる。
                    onSubmit: (s, e, c) async {
                      calls++;
                      if (fail) throw StateError('boom');
                      if (dctx.mounted) Navigator.pop(dctx);
                    },
                  ),
                ),
                child: const Text('ひらく'),
              ),
            ),
          ));
      await tester.tap(find.text('ひらく'));
      await tester.pumpAndSettle();
      // 終了時刻を選ぶ（時刻の窓の「OK」）。
      await tester.tap(find.text('-- : --'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('送信'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('送れませんでした。もう一度お試しください。'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing, reason: '回ったまま');
      fail = false;
      await tester.tap(find.text('送信'));
      await tester.pumpAndSettle();
      expect(calls, 2, reason: 'もう一度押せない');
      expect(find.text('送れませんでした。もう一度お試しください。'), findsNothing);
      expect(find.byType(OvertimeDialog), findsNothing, reason: '送れたのに窓が閉じない');
    });

    test('(BJ-c2) 今日の日報・出し直し・休憩の短縮：例外を受けて字を出す（ソースの字）', () {
      final home = _codeOnly(_home);
      final submit = _flat(_bodyOf(home, '  Future<void> _submit() async {\n    if (_submitting) return;\n    if (_userName.isEmpty)'));
      expect(submit.contains('await ReportStore.instance.addReport(item); stored = true;'), isTrue);
      expect(
          submit.contains("} catch (e) { debugPrint('日報の送信に失敗: \$e'); "
              'if (!stored && mounted) setState(() => _sendNotice = _sendFrame(kSendFailedText)); }'),
          isTrue,
          reason: '端末に残る前の失敗で枠を出していない');
      expect(submit.contains('if (!stored || !mounted) return;'), isTrue,
          reason: '端末に残った後に完了の画面へ進む道が無い');
      final rev = _flat(_codeOnly('lib/screens/revision_edit_screen.dart'));
      expect(rev.contains("} catch (e) { debugPrint('出し直しの送信に失敗: \$e'); if (mounted) { "
          'setState(() => _submitting = false); showJsSnackbar(context, kSendFailedText, isError: true); } }'), isTrue);
      expect(_flat(home).contains('setState(() { _submitting = false; _error = kSendFailedText; });'), isTrue,
          reason: '休憩の短縮のシートが例外を受けていない');
    });

    testWidgets('(BJ-c3) 確認の画面の枠：今日の日報（bottomNoticeOf）は内容のカードの下・送るボタンの真上／後から出す日報（noticeOf）は見出しの上（二者比較）',
        (tester) async {
      // 内容のカードが画面より長い形（作業内容が長い）。
      final snap = reportSnapshotFrom(
        dateLabel: '10月14日（水）', shiftLabel: '☀日勤', siteId: null, siteName: null, originType: 'home',
        transports: const {TransportType.train}, carType: 'own', routeComparisons: const {},
        parkingText: '', carpoolCompanyText: '', carpoolNameText: '', workText: List.filled(60, '作業').join('\n'),
        workPhotoCount: 0, parkingPhotoCount: 0,
      );
      Future<void> open({required bool bottom}) async {
        await _pump(
            tester,
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => Navigator.of(ctx).push<void>(MaterialPageRoute(
                    builder: (_) => ReportConfirmScreen(
                          initial: snap,
                          currentOf: () => snap,
                          onSend: () async {},
                          isDone: () => false,
                          noticeOf: bottom ? null : () => const Text('枠の字'),
                          bottomNoticeOf: bottom ? () => const Text('枠の字') : null,
                        ))),
                child: const Text('ひらく'),
              ),
            ),
            size: const Size(400, 800));
        await tester.tap(find.text('ひらく'));
        await tester.pumpAndSettle();
      }

      await open(bottom: true);
      final frame = tester.getRect(find.text('枠の字'));
      final send = tester.getRect(find.byType(ReportOutlineActionButton));
      expect(frame.bottom <= send.top, isTrue, reason: '枠が送るボタンの上に無い');
      expect(send.top - frame.bottom, 12, reason: '枠が送るボタンの真上（空き 12）に無い');
      expect(frame.top >= 0 && frame.bottom <= 800, isTrue, reason: 'カードが長い時に、枠が画面の外に出た');
      // 二者比較：後から出す日報の置き方（noticeOf）は、見出しの上（スクロールの頭）。
      await tester.tap(find.text('戻って直す'));
      await tester.pumpAndSettle();
      await open(bottom: false);
      final top = tester.getRect(find.text('枠の字'));
      final heading = tester.getRect(find.text('この内容で送ります'));
      expect(top.bottom <= heading.top, isTrue, reason: 'noticeOf の枠が見出しの上に無い');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (d) 相乗りの時の窓（見本 v1 の ④）
  // ══════════════════════════════════════════════════════════
  group('(d) 窓の決まり', () {
    test('(BJ-d1) 駐車場の帯を出す時：車で社用車・自家用車／その他。相乗り・電車・空は出さない', () {
      expect(reportParkingVisible({TransportType.car}, 'own'), isTrue);
      expect(reportParkingVisible({TransportType.car}, 'carpool'), isFalse);
      expect(reportParkingVisible({TransportType.other}, 'carpool'), isTrue);
      expect(reportParkingVisible({TransportType.car, TransportType.other}, 'carpool'), isTrue);
      expect(reportParkingVisible({TransportType.train}, 'own'), isFalse);
      expect(reportParkingVisible({}, 'own'), isFalse);
    });

    test('(BJ-d2) 窓を出す式は、帯を出す式と同じ1本（今日の日報・後から出す日報）', () {
      for (final p in [_home, _late]) {
        final src = _flat(_codeOnly(p));
        expect(src.contains('if (reportParkingVisible(_transports, _carType) && _parkingPhotoPaths.isEmpty) {'), isTrue,
            reason: '$p の窓の式が帯の式と違う');
        expect(src.contains('_transports.contains(TransportType.other)) && _parkingPhotoPaths.isEmpty'), isFalse,
            reason: '$p に前の窓の式が残っている');
      }
      final steps = _codeOnly('lib/widgets/report_form_steps.dart');
      expect('if (reportParkingVisible(transports, carType)) ...['.allMatches(steps).length, 1);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (e) 押せる大きさ 44（見本 v1 の ⑤案1）
  // ══════════════════════════════════════════════════════════
  group('(e) 44', () {
    testWidgets('(BJ-e1) 出発地のチップ：2つとも高さ 44', (tester) async {
      await _pump(tester, ReportOriginSelector(selected: 'home', onChanged: (_) {}));
      for (final t in ['自宅', '会社']) {
        final box = tester.getSize(find.ancestor(of: find.text(t), matching: find.byType(AnimatedContainer)));
        expect(box.height, 44, reason: '$t の高さ');
      }
    });

    testWidgets('(BJ-e2) 車の種類の2択：2つとも高さ 44', (tester) async {
      await _pump(
          tester,
          SingleChildScrollView(
            child: ReportStepMove(
              originType: 'home',
              onOriginChanged: (_) {},
              transports: const {TransportType.car},
              onTransportTap: (_) {},
              onTransportDoubleTap: (_) {},
              transportMemoController: TextEditingController(),
              carType: 'own',
              onCarTypeOwn: () {},
              onCarTypeCarpool: () {},
              routeTransport: TransportType.car,
              routeComparisons: const {},
              loadingRoutes: false,
              routeFailed: false,
              routeFromCache: false,
              onRouteRetry: () async {},
              carpoolCompanyController: TextEditingController(),
              carpoolCompanyCandidatesOf: () => const [],
              onCarpoolCompanyChanged: (_) {},
              carpoolNameController: TextEditingController(),
              carpoolNameCandidatesOf: () => const [],
              onCarpoolNameChanged: (_) {},
              parkingFeeController: TextEditingController(),
              onParkingFeeChanged: (_) {},
              parkingPhotoPaths: const [],
              onParkingPhotosChanged: (_) {},
            ),
          ));
      for (final t in ['社用車・自家用車', '相乗り']) {
        final box = tester.getSize(find.ancestor(of: find.text(t), matching: find.byType(Container)).first);
        expect(box.height, 44, reason: '$t の高さ');
      }
    });

    testWidgets('(BJ-e3) 目安の帯：計算中・失敗・値なし・値ありのどれも高さ 44 以上（計算中は 44）', (tester) async {
      Future<double> h({bool loading = false, bool failed = false}) async {
        await _pump(
            tester,
            settle: !loading,
            ReportRouteInfoBar(
              transport: TransportType.walk,
              comparisons: const {},
              loading: loading,
              failed: failed,
              onRetry: () async {},
            ));
        return tester.getSize(find.byType(ReportRouteInfoBar)).height;
      }
      expect(await h(loading: true), 44);
      expect(await h(failed: true), greaterThanOrEqualTo(44));
      expect(await h(), greaterThanOrEqualTo(44));
    });

    testWidgets('(BJ-e4) マイク：44×44', (tester) async {
      await _pump(tester, Center(child: ReportSmallMediaButton(icon: Icons.mic_none, active: false, onTap: () {})));
      final box = tester.getSize(find.descendant(of: find.byType(ReportSmallMediaButton), matching: find.byType(Container)));
      expect(box, const Size(44, 44));
    });

    testWidgets('(BJ-e5) 確認の画面の「戻って直す」：行の高さ 44・横いっぱい（右の端を押しても閉じる）', (tester) async {
      final snap = reportSnapshotFrom(
        dateLabel: '10月14日（水）', shiftLabel: '☀日勤', siteId: null, siteName: null, originType: 'home',
        transports: const {TransportType.train}, carType: 'own', routeComparisons: const {},
        parkingText: '', carpoolCompanyText: '', carpoolNameText: '', workText: '',
        workPhotoCount: 0, parkingPhotoCount: 0,
      );
      var closed = false;
      await _pump(
          tester,
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                await Navigator.of(ctx).push<void>(MaterialPageRoute(
                    builder: (_) => ReportConfirmScreen(
                        initial: snap, currentOf: () => snap, onSend: () async {}, isDone: () => false)));
                closed = true;
              },
              child: const Text('ひらく'),
            ),
          ));
      await tester.tap(find.text('ひらく'));
      await tester.pumpAndSettle();
      final row = find.ancestor(of: find.text('戻って直す'), matching: find.byType(SizedBox)).first;
      expect(tester.getSize(row).height, 44);
      final send = tester.getRect(find.byType(ReportOutlineActionButton));
      expect(tester.getRect(row).width, send.width, reason: '横いっぱいでない');
      await tester.tapAt(Offset(tester.getRect(row).right - 2, tester.getRect(row).center.dy));
      await tester.pumpAndSettle();
      expect(closed, isTrue, reason: '右の端を押しても閉じない');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (f) 自宅の住所が無い時（見本 v1 の ⑥）
  // ══════════════════════════════════════════════════════════
  group('(f) 自宅の住所', () {
    testWidgets('(BJ-f1) 帯の外の※：渡した時だけ、帯のすぐ下（空き 6）に字 11 で出る（二者比較）', (tester) async {
      Widget move(String? note) => SingleChildScrollView(
            child: ReportStepMove(
              originType: 'home', onOriginChanged: (_) {}, transports: const {TransportType.train},
              onTransportTap: (_) {}, onTransportDoubleTap: (_) {},
              transportMemoController: TextEditingController(), carType: 'own',
              onCarTypeOwn: () {}, onCarTypeCarpool: () {}, routeTransport: TransportType.train,
              routeComparisons: const {}, loadingRoutes: false, routeFailed: false, routeFromCache: false,
              onRouteRetry: () async {}, carpoolCompanyController: TextEditingController(),
              carpoolCompanyCandidatesOf: () => const [], onCarpoolCompanyChanged: (_) {},
              carpoolNameController: TextEditingController(), carpoolNameCandidatesOf: () => const [],
              onCarpoolNameChanged: (_) {}, parkingFeeController: TextEditingController(),
              onParkingFeeChanged: (_) {}, parkingPhotoPaths: const [], onParkingPhotosChanged: (_) {},
              routeNote: note,
            ),
          );
      const note = '※自宅の住所が未登録のため、自宅からの目安は出せません。';
      await _pump(tester, move(note));
      expect(find.text(note), findsOneWidget);
      final bar = tester.getRect(find.byType(ReportRouteInfoBar));
      final t = tester.getRect(find.text(note));
      expect(t.top - bar.bottom, 6);
      expect(tester.widget<Text>(find.text(note)).style!.fontSize, 11);
      await _pump(tester, move(null));
      expect(find.textContaining('自宅の住所が未登録'), findsNothing);
    });

    test('(BJ-f2) 今日の日報：決め打ちの住所を使わない・住所が無い時は※を出して目安を取らない（ソースの字）', () {
      final src = _codeOnly(_home);
      expect(src.contains('兵庫県神戸市長田区'), isFalse, reason: '決め打ちの住所が残っている');
      final calc = _flat(_bodyOf(src, '  Future<void> _calculateRoutes() async {'));
      final iMissing = calc.indexOf('if (originAddr == null || originAddr.trim().isEmpty) {');
      final iCall = calc.indexOf('RoutesService().compareRoutesV2(');
      expect(iMissing > 0 && iMissing < iCall, isTrue, reason: '住所が無いのに口を呼ぶ道が在る');
      expect(calc.contains('_homeAddressMissing = true;'), isTrue);
      expect(_flat(src).contains('routeNote: _homeAddressMissing ? kHomeAddressMissingNote : null,'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (g) その他の字・隠れた字・取り直し（見本 v1 の ⑦・(8)・(9)）
  // ══════════════════════════════════════════════════════════
  group('(g) 隠れた字と取り直し', () {
    test('(BJ-g1) 補足の欄と相乗りの欄を出す時（欄を出す所・送る字・閉じますか？が同じ1本）', () {
      expect(reportTransportMemoVisible({TransportType.other}), isTrue);
      expect(reportTransportMemoVisible({TransportType.car, TransportType.train}), isTrue);
      expect(reportTransportMemoVisible({TransportType.car}), isFalse);
      expect(reportTransportMemoVisible({}), isFalse);
      expect(reportCarpoolVisible({TransportType.car}, 'carpool'), isTrue);
      expect(reportCarpoolVisible({TransportType.car}, 'own'), isFalse);
      expect(reportCarpoolVisible({TransportType.other}, 'carpool'), isFalse);
      // 送る値も同じ1本で見る（隠れた相乗りの字は送らない）。
      expect(reportCarpoolValue(transports: {TransportType.car}, carType: 'own', text: '相乗り商事'), isNull);
      expect(reportCarpoolValue(transports: {TransportType.car}, carType: 'carpool', text: ' 相乗り商事 '), '相乗り商事');
    });

    test('(BJ-g2) その他の字の欄を撤去・取り直しの頭で前の目安を消す（今日の日報・後から出す日報・ソースの字）', () {
      final home = _codeOnly(_home);
      expect(home.contains('_otherCtrl'), isFalse, reason: '使っていない「その他」の欄が残っている');
      final calcHome = _flat(_bodyOf(home, '  Future<void> _calculateRoutes() async {'));
      expect(calcHome.contains('_loadingRoutes = true; _routeFailed = false; _routeComparisons = {};'), isTrue,
          reason: '今日の日報の取り直しで前の目安を消していない');
      final calcLate = _flat(_bodyOf(_codeOnly(_late), '  Future<void> _calculateRoutes() async {'));
      expect(calcLate.contains('_loadingRoutes = true; _routeFailed = false; _routeComparisons = {};'), isTrue,
          reason: '後から出す日報の取り直しで前の目安を消していない');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (h) 月の日報の上限（見本 v1 の ⑪・【Q139】の C）
  // ══════════════════════════════════════════════════════════
  group('(h) 月の上限', () {
    test('(BJ-h1) 月の口：limit を付けずに頼み、切れた印（truncated）を運ぶ（二者比較）', () async {
      final seen = <http.Request>[];
      for (final truncated in [true, false]) {
        final res = await http.runWithClient(
            () => ReportsService().getReportsByMonth('2026-10', closingDates: const ['2026-10-20']),
            () => MockClient((req) async {
                  seen.add(req);
                  return http.Response(
                      jsonEncode({
                        'success': true,
                        'reports': [
                          {'report_id': 'r1', 'report_date': '2026-10-05'}
                        ],
                        'truncated': truncated,
                      }),
                      200,
                      request: req,
                      headers: {'content-type': 'application/json; charset=utf-8'});
                }));
        expect(res.ok, isTrue);
        expect(res.data!.truncated, truncated);
        expect(res.data!.reports.single['report_id'], 'r1');
      }
      for (final req in seen) {
        expect(req.url.queryParameters.containsKey('limit'), isFalse, reason: 'limit を付けた: ${req.url}');
        expect(req.url.queryParameters['date'], '2026-10');
      }
      expect(_codeOnly('lib/screens/monthly_history_screen.dart').contains('limit:'), isFalse);
    });

    test('(BJ-h2) その日の日報が取れていない日：取れなかった・締め日が未定・切れた時の一番古い日とそれより前', () {
      bool u(String day, {bool failed = false, bool closing = false, bool truncated = false, String? oldest}) =>
          calendarDayReportsUnknown(day: day, failed: failed, closingPending: closing, truncated: truncated, oldestDate: oldest);
      expect(u('2026-10-05'), isFalse);
      expect(u('2026-10-05', failed: true), isTrue);
      expect(u('2026-10-05', closing: true), isTrue);
      expect(u('2026-10-05', truncated: true, oldest: '2026-10-10'), isTrue);
      expect(u('2026-10-10', truncated: true, oldest: '2026-10-10'), isTrue);
      expect(u('2026-10-11', truncated: true, oldest: '2026-10-10'), isFalse);
      expect(u('2026-10-11', truncated: true), isTrue, reason: '1件も取れていない時');
      expect(u('2026-10-05', oldest: '2026-10-10'), isFalse, reason: '切れていない時');
    });

    test('(BJ-h3) 箱の日報の1行：取れていない日は「日報：取得できませんでした」（なし・件数と言い切らない）', () {
      CalendarDayInfo info({bool unknown = false, List<Map<String, dynamic>> reports = const []}) =>
          CalendarDayInfo(date: DateTime(2026, 10, 5), reports: reports, reportsUnknown: unknown);
      expect(info().reportLine, '日報：なし');
      expect(info(unknown: true).reportLine, '日報：取得できませんでした');
      final two = [
        {'report_id': 'a', 'status': 'submitted'},
        {'report_id': 'b', 'status': 'submitted'},
      ];
      expect(info(reports: two).reportLine, '日報：2件');
      expect(info(reports: two, unknown: true).reportLine, '日報：取得できませんでした');
    });

    testWidgets('(BJ-h4) 切れた時の帯：字・印 ⓘ・高さ 44 以上・字の色', (tester) async {
      await _pump(tester, const ReportsTruncatedBar());
      expect(find.text('件数が多いため、古い日の日報の一部を取得できませんでした'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(tester.getSize(find.byType(ReportsTruncatedBar)).height, greaterThanOrEqualTo(44));
      final style = tester.widget<Text>(find.text('件数が多いため、古い日の日報の一部を取得できませんでした')).style!;
      expect(style.color!.toARGB32(), 0xFFE0603A);
      expect(style.fontSize, 12);
    });

    test('(BJ-h5) カレンダー・承認のタブ・月の履歴：切れた時だけ帯を出す（ソースの字）', () {
      final home = _flat(_codeOnly(_home));
      expect(home.contains('if (_reportsTruncated && !_monthLoading) const ReportsTruncatedBar(),'), isTrue);
      expect(home.contains('if (_reportsTruncated && !_loading) const ReportsTruncatedBar(),'), isTrue);
      final mh = _flat(_codeOnly('lib/screens/monthly_history_screen.dart'));
      expect(mh.contains('if (!_loading && _error == null && _truncated) const ReportsTruncatedBar(),'), isTrue);
      expect(home.contains('getReportsByMonth(_monthStr, closingDates: dates)'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (i) 場所が測れなかった時の印（見本 v1 の A）
  // ══════════════════════════════════════════════════════════
  group('(i) 場所の印', () {
    test('(BJ-i5) 送る本文の座標：場所の印が在る時は送らない（前に測った値が残っている物）・無ければ送る（二者比較）', () {
      final failed = reportBodyFor(_item('i5', gpsAddress: '', failReason: 'gps_error', lat: 34.6, lon: 135.1));
      expect(failed.containsKey('gps_lat'), isFalse, reason: '測れなかった日報に、前に測った座標を付けた');
      expect(failed.containsKey('gps_lon'), isFalse);
      final ok = reportBodyFor(_item('i5b', lat: 34.6, lon: 135.1));
      expect(ok['gps_lat'], 34.6);
      expect(ok['gps_lon'], 135.1);
    });

    test('(BJ-i1) 送る本文：印が在れば住所の欄を空にして gps_fail_reason を足す・無ければ鍵を足さない（二者比較）', () {
      final failed = reportBodyFor(_item('i1', gpsAddress: '位置情報の権限がありません', failReason: 'no_permission'));
      expect(failed['gps_address'], '');
      expect(failed['gps_fail_reason'], 'no_permission');
      final ok = reportBodyFor(_item('i1b'));
      expect(ok['gps_address'], 'テスト県テスト市1-2-3');
      expect(ok.containsKey('gps_fail_reason'), isFalse);
      // 後から出す日報は、場所も場所の印も送らない。
      final permitted = permittedReportBodyFor(
          _item('i1c', gpsAddress: '', failReason: 'gps_error'), confirmationId: '42');
      expect(permitted.containsKey('gps_fail_reason'), isFalse);
      expect(permitted.containsKey('gps_address'), isFalse);
    });

    test('(BJ-i2) 箱の行：印と持ち主は書いて読める・表に無い印と欠落は null', () {
      final j = _item('i2', failReason: 'gps_disabled', owner: 'U9').toJson();
      final back = WorkerReportItem.fromJson(Map<String, dynamic>.from(jsonDecode(jsonEncode(j)) as Map));
      expect(back.gpsFailReason, 'gps_disabled');
      expect(back.ownerUserId, 'U9');
      expect(WorkerReportItem.fromJson({...j, 'gpsFailReason': 'foo'}).gpsFailReason, isNull);
      final old = Map<String, dynamic>.from(j)..remove('gpsFailReason')..remove('ownerUserId');
      expect(WorkerReportItem.fromJson(old).gpsFailReason, isNull);
      expect(WorkerReportItem.fromJson(old).ownerUserId, isNull);
    });

    test('(BJ-i3) 報告場所の字：3つの印・表に無い印・前の字3つ・住所・空・印と住所の両方（印が先）', () {
      String? t(Map<String, dynamic> r) => reportPlaceText(r);
      expect(t({'gps_fail_reason': 'no_permission'}), '測れませんでした（位置情報の権限なし）');
      expect(t({'gps_fail_reason': 'gps_disabled'}), '測れませんでした（GPS が無効）');
      expect(t({'gps_fail_reason': 'gps_error'}), '測れませんでした（GPS の取得に失敗）');
      expect(t({'gps_fail_reason': 'xyz'}), '測れませんでした（理由不明）');
      expect(t({'gps_address': '位置情報の権限がありません'}), '測れませんでした（位置情報の権限なし）');
      expect(t({'gps_address': 'GPS が無効です'}), '測れませんでした（GPS が無効）');
      expect(t({'gps_address': 'GPS取得失敗'}), '測れませんでした（GPS の取得に失敗）');
      expect(t({'gps_address': '  テスト県テスト市1-2-3 '}), 'テスト県テスト市1-2-3');
      expect(t({'gps_address': '   '}), isNull);
      expect(t({}), isNull);
      expect(t({'gps_address': 'テスト県', 'gps_fail_reason': 'gps_error'}), '測れませんでした（GPS の取得に失敗）');
      // 住所として使うのは address だけ。
      expect(reportPlaceOf({'gps_address': 'GPS取得失敗'}).address, isNull);
      expect(reportPlaceOf({'gps_address': 'テスト県'}).address, 'テスト県');
    });

    test('(BJ-i4) 場所を出す所と住所として使う所は、表を通す（ソースの字に gps_address の鍵の字が無い）', () {
      for (final p in [
        'lib/screens/share_inbox_screen.dart',
        'lib/screens/tamper_incident_detail_screen.dart',
        'lib/screens/share_receipt_detail_screen.dart',
        'lib/screens/revision_inbox_screen.dart',
        'lib/screens/day_reports_screen.dart',
        'lib/screens/monthly_history_screen.dart',
      ]) {
        expect(_codeOnly(p).contains("'gps_address'"), isFalse, reason: '$p が場所の鍵を直に読んでいる');
      }
      final home = _flat(_codeOnly(_home));
      expect(home.contains('final gps = reportPlaceText(r);'), isTrue);
      expect(home.contains('initialAddress: reportPlaceOf(widget.report).address,'), isTrue);
      expect(home.contains('gpsFailReason: _gpsFailReason,'), isTrue);
      final mainSrc = _codeOnly(_main);
      for (final w in ["'位置情報の権限がありません'", "'GPS が無効です'", "'GPS取得失敗'"]) {
        expect(mainSrc.contains(w), isFalse, reason: '測れなかった時の字を main.dart に写している: $w');
      }
      expect("failReason: 'no_permission'".allMatches(mainSrc).length, 2);
      expect("failReason: 'gps_disabled'".allMatches(mainSrc).length, 1);
      expect("failReason: 'gps_error'".allMatches(mainSrc).length, 1);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (j) ログアウトの掃除（見本 v1 の ⑧・【Q140】）
  // ══════════════════════════════════════════════════════════
  group('(j) 掃除', () {
    test('(BJ-j1) 人に付く物を消す・端末に付く物と未送信の箱と締め出しの理由は残す・後の口を1回呼ぶ', () async {
      const written = [
        'auth_token', 'cache_revision_count', 'cache_weather_v2_alert_level', 'cache_weather_v2_alert_message',
        'cache_weather_v2_desc', 'cache_weather_v2_humidity', 'cache_weather_v2_icon', 'cache_weather_v2_precip',
        'cache_weather_v2_temp', 'cache_weather_v2_wbgt_level', 'cache_weather_v2_wbgt_value', 'cache_weather_v2_wind',
        'company_address', 'company_id', 'company_name', 'consent_agreed', 'consent_agreed_at', 'consent_version',
        'default_origin', 'device_id', 'emergency_contact_name', 'emergency_contact_phone', 'experience_years',
        'gps_address', 'gps_lat', 'gps_lon', 'health_check_date_iso', 'home_address', 'is_registered', 'logged_out',
        'profile_blood_type', 'profile_phone', 'shift_type', 'today_carpool_company', 'today_carpool_name',
        'today_parking_fee', 'today_transport', 'today_work_content', 'user_id', 'user_name', 'user_role',
        'work_mode', 'worker_id', 'registered_worker_names', 'notification_hours', 'pending_reports',
        'worker_reports_history', 'last_site_id', 'last_site_name', 'last_transports', 'last_car_type',
        'route_cache_key', 'route_cache_json', 'deemed_start', 'deemed_end', 'break_minutes', 'work_checked_in',
        'session_lockout_reason', 'last_tab_index_v2_foreman', 'last_tab_index_v2_worker', 'report_done_day',
        'report_done_night', 'shift_business_date', 'pending_reports_unreadable',
      ];
      SharedPreferences.setMockInitialValues({for (final k in written) k: 'x'});
      var hooked = 0;
      final orig = afterPersonalDataCleared;
      afterPersonalDataCleared = () async => hooked++;
      addTearDown(() => afterPersonalDataCleared = orig);
      await clearPersonalData();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {
        'device_id', 'is_registered', 'logged_out', 'notification_hours',
        'pending_reports', 'pending_reports_unreadable', 'session_lockout_reason',
      });
      expect(hooked, 1);
    });

    test('(BJ-j2) 4つの道が同じ1本を呼ぶ・名簿を画面に写さない・氏名の名簿の作りを撤去（ソースの字）', () {
      for (final p in [
        'lib/screens/profile_screen.dart',
        'lib/utils/session_lockout.dart',
        'lib/screens/login_screen.dart',
        'lib/screens/monthly_history_screen.dart',
      ]) {
        expect('await clearPersonalData();'.allMatches(_codeOnly(p)).length, 1, reason: '$p で掃除の1本を呼ぶ数');
      }
      final logout = _bodyOf(_codeOnly('lib/screens/profile_screen.dart'), '  Future<void> _confirmLogout() async {');
      expect(logout, isNotEmpty);
      expect(logout.contains("prefs.remove('"), isFalse, reason: 'ログアウトの名簿を画面に写している');
      final lockout = _flat(_codeOnly('lib/utils/session_lockout.dart'));
      expect(lockout.contains("prefs.remove('auth_token')"), isFalse);
      final mainSrc = _flat(_codeOnly(_main));
      expect(mainSrc.contains('afterPersonalDataCleared = ReportStore.instance.afterPersonalDataCleared;'), isTrue,
          reason: 'main() が掃除の後の口を差していない');
      for (final p in [_main, _home]) {
        final s = _codeOnly(p);
        expect(s.contains('WorkerNameStore'), isFalse, reason: '$p に氏名の名簿の作りが残っている');
        expect(s.contains('WorkerNameScreen'), isFalse, reason: '$p に氏名の名簿の画面が残っている');
        expect(s.contains('registered_worker_names'), isFalse, reason: '$p に氏名の名簿の鍵が残っている');
      }
    });

    test('(BJ-j3) 締め出し：資格と人の物を消し、未送信の箱は残す（二者比較＝名前は消え、箱は残る）', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'token-a',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': '[]',
        'today_carpool_name': '相乗 次郎',
      });
      resetLockoutGuardForTest();
      final req = http.Request('GET', Uri.parse('$kApiBaseUrl/reports/today'))
        ..headers['Authorization'] = 'Bearer token-a';
      await runApiCall<Map<String, dynamic>>(
          'Test',
          () async => http.Response('{"error":"x","code":"RETIRED"}', 401,
              request: req, headers: const {'content-type': 'application/json; charset=utf-8'}),
          apiJsonMap);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('user_name'), isNull, reason: '前の人の名前が残った');
      expect(prefs.getString('today_carpool_name'), isNull, reason: '前の人の下書きが残った');
      expect(prefs.getString('pending_reports'), '[]', reason: '未送信の箱を消した');
      expect(prefs.getBool('logged_out'), isTrue);
    });

    test('(BJ-j4) 締め出しの帯：今日の日報を送る口（POST /reports）では「作成中の内容は…」を足さない・ほかの送る口では足す（二者比較）', () {
      String? msg(String method, String path) => judgeLockout(
              url: Uri.parse('$kApiBaseUrl$path'), method: method, errorCode: 'TOKEN_EXPIRED')
          .message;
      expect(msg('POST', '/reports'), '認証の有効期限が切れました。もう一度ログインしてください。');
      expect(msg('POST', '/reports/permitted'),
          '認証の有効期限が切れました。もう一度ログインしてください。作成中の内容は保存されていません。');
      expect(msg('POST', '/reports/r1/resubmit'), endsWith('作成中の内容は保存されていません。'));
      expect(msg('GET', '/reports'), '認証の有効期限が切れました。もう一度ログインしてください。');
      expect(isBoxedReportPost(Uri.parse('$kApiBaseUrl/reports'), 'post'), isTrue);
      expect(isBoxedReportPost(Uri.parse('$kApiBaseUrl/reports'), 'PUT'), isFalse);
      expect(isBoxedReportPost(Uri.parse('https://example.com/api/v1/reports'), 'POST'), isFalse);
    });

    test('(BJ-j8) 締め出し：送った資格が今の資格と違う時（送っている途中にログインし直した）は締め出さない・同じなら締め出す（二者比較）', () async {
      Future<void> answer(String sentToken) => runApiCall<Map<String, dynamic>>('Test', () async {
            final req = http.Request('POST', Uri.parse('$kApiBaseUrl/reports'))
              ..headers['Authorization'] = 'Bearer $sentToken';
            return http.Response('{"error":"x","code":"TOKEN_EXPIRED"}', 401,
                request: req, headers: const {'content-type': 'application/json; charset=utf-8'});
          }, apiJsonMap);
      SharedPreferences.setMockInitialValues({'auth_token': 'token-new', 'user_id': 'U2', 'user_name': '次の人'});
      resetLockoutGuardForTest();
      await answer('token-old');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'token-new', reason: '前の資格への答えで、今の人を締め出した');
      expect(prefs.getString('user_name'), '次の人', reason: '前の資格への答えで、今の人の物を消した');
      expect(await takeLockoutReason(), isNull);
      await answer('token-new');
      expect(prefs.getString('auth_token'), isNull);
      expect(await takeLockoutReason(), isNotNull);
    });

    test('(BJ-j5) 今日の印の読み方：業務日が同じで、書いた人が今の人（または人の印が無い前の形）の時だけ使う', () {
      expect(reportDoneStatusOf('2026-10-14|done|U1', bizDate: '2026-10-14', me: 'U1'), 'done');
      expect(reportDoneStatusOf('2026-10-14|done|U1', bizDate: '2026-10-14', me: 'U2'), isNull, reason: '別の人の印を使った');
      expect(reportDoneStatusOf('2026-10-14|done|U1', bizDate: '2026-10-14', me: ''), isNull);
      expect(reportDoneStatusOf('2026-10-14|closed', bizDate: '2026-10-14', me: 'U2'), 'closed', reason: '前の形を読まない');
      expect(reportDoneStatusOf('2026-10-13|done|U1', bizDate: '2026-10-14', me: 'U1'), isNull);
      expect(reportDoneStatusOf('x', bizDate: '2026-10-14', me: 'U1'), isNull);
      expect(reportDoneStatusOf(null, bizDate: '2026-10-14', me: 'U1'), isNull);
      expect(reportDoneValue('2026-10-14', 'done', 'U1'), '2026-10-14|done|U1');
      expect(shiftDateOf('2026-10-14|U1', me: 'U1'), '2026-10-14');
      expect(shiftDateOf('2026-10-14|U1', me: 'U2'), isNull, reason: '別の人の勤務の種類を使った');
      expect(shiftDateOf('2026-10-14', me: 'U2'), '2026-10-14', reason: '前の形を読まない');
      expect(shiftDateOf(null, me: 'U1'), isNull);
      expect(shiftDateValue('2026-10-14', 'U1'), '2026-10-14|U1');
    });

    test('(BJ-j6) 掃除：書いた人の印が付いた今日の印は残し、人の印の無い印は消す・別の人がログインしても使わない（二者比較）', () async {
      final biz = businessDateForShift('night', DateTime.now());
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'report_done_night': '$biz|done|U1',
        'report_done_day': '2026-10-14|done',
        'shift_type': 'night',
        'shift_business_date': '$biz|U1',
      });
      await clearPersonalData();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('report_done_night'), '$biz|done|U1', reason: '同じ人の送った印を消した');
      expect(prefs.getString('shift_type'), 'night');
      expect(prefs.getString('shift_business_date'), '$biz|U1');
      expect(prefs.getString('report_done_day'), isNull, reason: '人の印の無い前の形の印を残した');
      expect(prefs.getString('user_id'), isNull);
      // 同じ人がログインし直すと夜勤のまま・別の人なら日勤。
      await prefs.setString('user_id', 'U1');
      expect(await savedShiftTypeForNow(), 'night');
      await prefs.setString('user_id', 'U2');
      expect(await savedShiftTypeForNow(), 'day', reason: '別の人に前の人の勤務の種類を使った');
      // 別の人（U2）が開くと、U1 の送った印は消す・人の印の無い前の形は触らない（二者比較：U1 が開けば残る）。
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'report_done_night': '$biz|done|U1',
        'report_done_day': '2026-10-14|done',
      });
      await clearOtherOwnersTodayMarks(await SharedPreferences.getInstance());
      final p1 = await SharedPreferences.getInstance();
      expect(p1.getString('report_done_night'), '$biz|done|U1', reason: '同じ人の送った印を消した');
      await p1.setString('user_id', 'U2');
      await clearOtherOwnersTodayMarks(p1);
      expect(p1.getString('report_done_night'), isNull, reason: '別の人の送った印を残した');
      expect(p1.getString('report_done_day'), '2026-10-14|done', reason: '人の印の無い前の形を消した');
      // 日勤の鍵の、別の人の印も消す（夜勤の鍵だけでない）。
      await p1.setString('report_done_day', '2026-10-14|closed|U1');
      await clearOtherOwnersTodayMarks(p1);
      expect(p1.getString('report_done_day'), isNull, reason: '日勤の鍵の、別の人の締めた印を残した');
      await p1.remove('user_id');
      await p1.setString('report_done_night', '$biz|done|U1');
      await clearOtherOwnersTodayMarks(p1);
      expect(p1.getString('report_done_night'), '$biz|done|U1', reason: '今の人が分からないのに消した');
      // 人の印の無い勤務の種類は、掃除で2つとも消す。
      SharedPreferences.setMockInitialValues({'shift_type': 'night', 'shift_business_date': biz});
      await clearPersonalData();
      final p2 = await SharedPreferences.getInstance();
      expect(p2.getString('shift_type'), isNull);
      expect(p2.getString('shift_business_date'), isNull);
    });

    test('(BJ-j7) 今日の印の繋ぎ：読む所と書く所は1本の読み方・送った印は日報の持ち主で書く（ソースの字）', () {
      final home = _codeOnly(_home);
      final mainSrc = _codeOnly(_main);
      for (final src in [home, mainSrc]) {
        expect(src.contains("'report_done_"), isFalse, reason: '印の鍵の字を写している');
        expect(src.contains("'shift_business_date'"), isFalse, reason: '業務日の鍵の字を写している');
      }
      final submit = _flat(_bodyOf(home, '  Future<void> _submit() async {\n    if (_submitting) return;\n    if (_userName.isEmpty)'));
      expect(submit.contains("_saveWorkStatus('done', owner: item.ownerUserId);"), isTrue,
          reason: '送った印を日報の持ち主で書いていない');
      final save = _flat(_bodyFrom(home, '  Future<void> _saveWorkStatus(String status, {String? owner}) async {'));
      expect(save.contains('if (who.isEmpty) return;'), isTrue, reason: '書いた人が分からないのに書く');
      expect(save.contains('reportDoneValue(bizDate, status, who)'), isTrue);
      final read = _flat(_bodyOf(home, '  Future<String?> _readWorkStatusToday() async {'));
      expect(read.contains('return reportDoneStatusOf('), isTrue);
      final shift = _flat(_bodyOf(home, '  Future<void> _saveShiftType(String v) async {'));
      expect(shift.contains('shiftDateValue(businessDateForShift(v, DateTime.now()), who)'), isTrue);
      final push = _flat(_bodyOf(mainSrc, '  Future<void> _pushWorker(BuildContext context) async {'));
      expect(push.contains('final workStatus = reportDoneStatusOf(prefs.getString(reportDoneKeyOf(shiftType)),'), isTrue);
      expect(push.contains('final shiftType = await savedShiftTypeForNow();'), isTrue,
          reason: '入口の勤務の種類を1本で読んでいない');
      final restore = _flat(_bodyOf(home, '  Future<void> _restoreShiftType() async {'));
      expect(restore.contains('shiftDateOf(prefs.getString(kShiftBusinessDateKey), me: todayMarkOwnerOf(prefs)),'), isTrue,
          reason: '勤務の種類を戻す所が、書いた人を見ていない');
      // 開く時：別の人の印を消す → 勤務の種類を戻す → 戻した種類の送った印を読む（1つずつ待つ）。
      final today = _flat(_bodyOf(home, '  Future<void> _restoreTodayState() async {'));
      final iClear = today.indexOf('await clearOtherOwnersTodayMarks(await SharedPreferences.getInstance());');
      final iShift = today.indexOf('await _restoreShiftType();');
      final iDone = today.indexOf('await _initTodayReportDone();');
      expect(iClear >= 0 && iClear < iShift && iShift < iDone, isTrue,
          reason: '開く時の並びが違う（勤務の種類を戻す前に送った印を読むと、夜勤の人の送った後の画面が出ない）');
      final init = _flat(_bodyOf(home, '  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addObserver(this);'));
      expect(init.contains('_todayStateReady = _restoreTodayState();'), isTrue);
      // 下書きを戻す所は、今日の印が戻り終わるのを待ってから欄に字を入れる（検分 a254 の Y2）。
      final draft = _flat(_bodyOf(home, '  Future<void> _restoreDraft(String workStatus) async {'));
      final iWait = draft.indexOf('await _todayStateReady;');
      final iFill = draft.indexOf('_workCtrl.text = workContent;');
      expect(iWait >= 0 && iWait < iFill, isTrue, reason: '下書きを戻す所が、今日の印を戻すのを待たない（日勤の鍵に作業中を書く）');
      expect(init.contains('_initTodayReportDone();'), isFalse, reason: '送った印を、待たずに別に読んでいる');
      expect(init.contains('_restoreShiftType();'), isFalse, reason: '勤務の種類を、待たずに別に戻している');
      final clean = _flat(_codeOnly('lib/utils/personal_data_cleanup.dart'));
      expect(clean.contains('await clearUnownedTodayMarks(prefs);'), isTrue);
      for (final k in ["'report_done_day'", "'report_done_night'", "'shift_type'", "'shift_business_date'"]) {
        expect(clean.contains(k), isFalse, reason: '掃除の名簿に今日の印 $k が残っている');
      }
    });
  });

  // ══════════════════════════════════════════════════════════
  // (k) 夜勤の朝の「今日」（見本 v1 の B・【Q139】の B）
  // ══════════════════════════════════════════════════════════
  group('(k) 夜勤の朝', () {
    test('(BJ-k1) 保存した勤務の種類は、保存した業務日と今の業務日が同じ時だけ使う', () {
      // 日本の 12月2日 08:00（夜勤の業務日は 12月1日）。
      final now = DateTime.utc(2026, 12, 1, 23, 0);
      expect(shiftTypeIfSameBusinessDate('night', '2026-12-01', now), 'night');
      expect(shiftTypeIfSameBusinessDate('night', '2026-12-02', now), isNull);
      expect(shiftTypeIfSameBusinessDate('day', '2026-12-02', now), 'day');
      expect(shiftTypeIfSameBusinessDate('day', '2026-12-01', now), isNull);
      expect(shiftTypeIfSameBusinessDate('foo', '2026-12-01', now), isNull);
      expect(shiftTypeIfSameBusinessDate(null, null, now), isNull);
    });

    test('(BJ-k2) 尋ねる口と申告の口：夜勤の保存が今も使えれば shift_type=night・使えなければ day（二者比較）', () async {
      final seen = <http.Request>[];
      Future<void> askAll() => http.runWithClient(() async {
            await ReportsService().getDayRequestEligibility('report_missing', '2026-12-01');
            await ReportsService().declareReportMissing('2026-12-01', ' 理由 ');
            await ReportsService().requestAttendanceFix('2026-12-01', ' 理由 ');
          }, () => MockClient((req) async {
                seen.add(req);
                return http.Response('{}', 200,
                    request: req, headers: {'content-type': 'application/json; charset=utf-8'});
              }));
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'shift_type': 'night',
        'shift_business_date': businessDateForShift('night', DateTime.now()),
      });
      await askAll();
      expect(seen[0].url.queryParameters['shift_type'], 'night');
      expect(jsonDecode(seen[1].body)['shift_type'], 'night');
      expect(jsonDecode(seen[2].body)['shift_type'], 'night');
      expect(await savedShiftTypeForNow(), 'night');
      seen.clear();
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'shift_type': 'night',
        'shift_business_date': '2000-01-01',
      });
      await askAll();
      expect(seen[0].url.queryParameters['shift_type'], 'day');
      expect(jsonDecode(seen[1].body)['shift_type'], 'day');
      expect(await savedShiftTypeForNow(), 'day');
    });

    test('(BJ-k3) カレンダーの箱の「今日」は、今の勤務の種類の業務日（ソースの字）', () {
      final open = _flat(_bodyOf(_codeOnly(_home), '  Future<void> _openDaySheet(String ds) async {'));
      expect(open.contains('final today = businessDateForShift(await savedShiftTypeForNow(), DateTime.now());'), isTrue);
      expect(open.contains('today: today,'), isTrue);
      expect(open.contains('jstDateString'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (l) 送り直しの道の後片付け（ReportStore の公開の口がそろっている事の確かめ）
  // ══════════════════════════════════════════════════════════
  group('(l) 口', () {
    test('(BJ-l1) 掃除の後の口：写真は箱が指す物だけ残し、数は今の人が居なくなって 0', () async {
      final keep = File('${photoDir.path}/keep.jpg')..writeAsBytesSync([1]);
      final drop = File('${photoDir.path}/drop.jpg')..writeAsBytesSync([2]);
      SharedPreferences.setMockInitialValues({
        'pending_reports': jsonEncode([_item('l1', owner: 'U1', work: [keep.path]).toJson()]),
      });
      ReportStore.instance.pendingOwnCount.value = 3;
      ReportStore.instance.droppedPhotoCount.value = 2;
      ReportStore.instance.pendingRefusedMessage.value = '前の人の字';
      await ReportStore.instance.afterPersonalDataCleared();
      expect(ReportStore.instance.droppedPhotoCount.value, 0, reason: '前の人の除いた写真の数を残した');
      expect(ReportStore.instance.pendingRefusedMessage.value, isNull, reason: '前の人の受け付けなかった字を残した');
      expect(keep.existsSync(), isTrue, reason: '未送信の日報の写真を消した');
      expect(drop.existsSync(), isFalse);
      expect(ReportStore.instance.pendingOwnCount.value, 0);
      expect((await _box()).single['id'], 'l1', reason: '未送信の箱を消した');
    });
  });
}
