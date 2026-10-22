// ============================================================
// test/bk_field_test.dart
//   便BK（見本 claude/field_report_fix_mock_v3.html の ⑮⑯⑰・ボスの裁定【Q143】【Q144】【Q145】＝１・
//   見つけた事 (26)(28)(29)(30)・CC の見つけた2つ）の職人アプリの直しを、機械で見張る検査。
//
// ★掟: 期待の字・数はこの本の中に直に書く（実装の字の定数は import しない）。二者比較（あり／なし）で見る。
//   通信は package:http の runWithClient＋MockClient の偽物・端末の保存は SharedPreferences の偽物・
//   写真の置き場は一時の置き場に差し替える（終わりに消す）。シェル（JsMainShell）は検査で立てられない
//   （通知・位置・通信の部品が多い）ので、シェルの繋ぎはソースの字で見る（説明の行は除く＝_codeOnly）。
// ★検査の名前の頭の番号（(BK-a1) ほか）は、ログの赤い行からどの検査かを機械で読むための物。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/config/constants.dart';
import 'package:js_awake_app/core/report_send_texts.dart';
import 'package:js_awake_app/core/theme/app_theme.dart';
import 'package:js_awake_app/main.dart'
    show
        ReportStore,
        TransportType,
        WorkerReportItem,
        pendingBoxWriter,
        permittedReportBodyFor,
        reportBodyFor;
import 'package:js_awake_app/screens/after_report_screen.dart';
import 'package:js_awake_app/screens/device_error_log_screen.dart';
import 'package:js_awake_app/screens/punch_screen.dart';
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';
import 'package:js_awake_app/utils/device_error_log.dart';
import 'package:js_awake_app/utils/pending_view.dart';
import 'package:js_awake_app/utils/personal_data_cleanup.dart';
import 'package:js_awake_app/utils/report_photo_store.dart';
import 'package:js_awake_app/utils/session_lockout.dart';
import 'package:js_awake_app/utils/today_marks.dart';
import 'package:js_awake_app/widgets/photo_strip_field.dart';
import 'package:js_awake_app/widgets/report_form_parts.dart' show ReportSnapshot;
import 'package:js_awake_app/widgets/report_form_steps.dart';

// ── 本の場所 ─────────────────────────────────────────────────────
const String _home = 'lib/screens/home_screen.dart';
const String _main = 'lib/main.dart';
const String _late = 'lib/screens/late_report_screen.dart';
const String _login = 'lib/screens/login_screen.dart';

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

// ── 日報の入れ物（検査が字で決める・時計を読まない）────────────────
//   既定の時刻 2026-10-14 01:00 UTC＝日本の 10:00（日勤の業務日 2026-10-14）。
WorkerReportItem _item(String id,
        {String name = '検査 太郎',
        String? owner = 'U1',
        List<String>? work,
        List<String>? parking,
        String shift = 'day',
        DateTime? at,
        String? refused}) =>
    WorkerReportItem(
      id: id,
      name: name,
      transport: TransportType.train,
      transportTypes: ['train'],
      workPhotoPaths: work,
      parkingPhotoPaths: parking,
      gpsAddress: 'テスト県テスト市1-2-3',
      shiftType: shift,
      timestamp: at ?? DateTime.utc(2026, 10, 14, 1, 0),
      ownerUserId: owner,
    )..refusedMessage = refused;

/// 読めない行（このアプリの日報の形でない＝id が数）。写真の道を1つ持つ。
Map<String, dynamic> _badRow(String photoPath) => {
      'id': 5,
      'name': 3,
      'workPhotoPaths': [photoPath],
    };

/// 届いた求めを控え、送った順に statuses の答えを返す偽物のサーバ（足りなくなったら最後の値を使い続ける）。
///   onRequest は、答える前に呼ぶ（送っている途中の端末の保存を見るため）。bodyOf は答えの本文（既定は 201 の report_id）。
Future<T> _withServer<T>(
    List<http.Request> seen, List<int> statuses, Future<T> Function() run,
    {Future<void> Function(http.Request req)? onRequest,
    Map<String, dynamic> Function(int status, int n)? bodyOf}) {
  var n = 0;
  return http.runWithClient(
    run,
    () => MockClient((req) async {
      if (onRequest != null) await onRequest(req);
      seen.add(req);
      final status = statuses[n < statuses.length ? n : statuses.length - 1];
      n++;
      final body = bodyOf != null
          ? bodyOf(status, n)
          : status == 201
              ? {'report_id': 'r-$n'}
              : {'error': 'サーバーエラー'};
      return http.Response(jsonEncode(body), status,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );
}

Future<List<Map<String, dynamic>>> _box() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('pending_reports');
  if (raw == null) return [];
  return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(800, 2000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

/// 送った後の画面（呼び手が渡す値だけで組む）。
Widget _after({
  bool sent = true,
  String? refused,
  bool readFailed = false,
  List<PendingReportRow> others = const [],
  int unreadable = 0,
  bool unknown = false,
  Future<void> Function(PendingReportRow row)? onRemoveRow,
  Future<void> Function()? onRemoveUnreadable,
}) =>
    SingleChildScrollView(
      child: AfterReportBody(
        workerName: '山田',
        sent: sent,
        shiftType: 'day',
        onOvertime: () async {},
        onRetry: () {},
        onClose: () {},
        refusedMessage: refused,
        pendingReadFailed: readFailed,
        otherRows: others,
        unreadableCount: unreadable,
        unreadableUnknown: unknown,
        onRemoveRow: onRemoveRow ?? (_) async {},
        onRemoveUnreadable: onRemoveUnreadable ?? () async {},
      ),
    );

const _refusedRow = PendingReportRow(
    id: 'r13', shiftType: 'day', businessDate: '2026-10-13', refusedMessage: '名前・日付・出勤時刻は必須です');
const _netRow = PendingReportRow(id: 'n12', shiftType: 'night', businessDate: '2026-10-12');

/// ホームの打刻の画面に渡す偽物（本日休みの状態だけを答える）。
class _FakeReports extends ReportsService {
  _FakeReports() : super.forTest();

  @override
  Future<ApiResult<RestDayToday>> getRestDayToday() async => apiSuccess<RestDayToday>(
        statusCode: 200,
        data: const RestDayToday(rested: false, reason: null, portion: 'full'),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory photoBase;
  late Directory photoDir;
  late Future<Directory> Function() origDirOf;
  late DateTime Function() origClock;

  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'T', 'user_id': 'U1', 'user_name': '検査 太郎'});
    ReportStore.instance.pendingView.value = const PendingView();
    ReportStore.instance.droppedPhotoCount.value = 0;
    deviceErrorCount.value = 0;
    personalCleanupFailedAgain.value = false;
    // 置き場の名前は本物と同じ report_photos（写真の見分けは置き場の中の名前）。
    photoBase = Directory.systemTemp.createTempSync('bk_photos_');
    photoDir = Directory('${photoBase.path}/report_photos')..createSync();
    origDirOf = reportPhotoDirOf;
    reportPhotoDirOf = () async => photoDir;
    origClock = deviceErrorClock;
  });
  tearDown(() {
    reportPhotoDirOf = origDirOf;
    deviceErrorClock = origClock;
    if (photoBase.existsSync()) photoBase.deleteSync(recursive: true);
  });

  File photo(String name) => File('${photoDir.path}/$name')..writeAsBytesSync([1, 2, 3]);

  Future<List<String>> errorKinds() async =>
      (await readDeviceErrors())!.map((e) => e.kind).toList();

  // ══════════════════════════════════════════════════════════
  // (a) 送った後の画面（見本 v3 の ⑮⑯⑰②）
  // ══════════════════════════════════════════════════════════
  group('(a) 送った後の画面', () {
    test('(BK-a1) 今日の分＝同じ勤務の種類で同じ業務日・ほかは「ほかの日」（夜勤の午前は前の日）・並びは箱のまま', () {
      const v = PendingView(own: [
        PendingReportRow(id: 'd14', shiftType: 'day', businessDate: '2026-10-14'),
        PendingReportRow(id: 'd13', shiftType: 'day', businessDate: '2026-10-13', refusedMessage: 'x'),
        PendingReportRow(id: 'n13', shiftType: 'night', businessDate: '2026-10-13', refusedMessage: 'y'),
        PendingReportRow(id: 'n14', shiftType: 'night', businessDate: '2026-10-14'),
        PendingReportRow(id: 'd14b', shiftType: 'day', businessDate: '2026-10-14', refusedMessage: 'z'),
      ]);
      // 日本の 2026-10-14 10:00（UTC 01:00）。
      final now = DateTime.utc(2026, 10, 14, 1, 0);
      List<String> ids(List<PendingReportRow> rs) => rs.map((r) => r.id).toList();
      expect(ids(pendingTodayRows(v, shiftType: 'day', now: now)), ['d14', 'd14b']);
      expect(ids(pendingOtherRows(v, shiftType: 'day', now: now)), ['d13', 'n13', 'n14']);
      // 夜勤の午前は前の日（10/13）が今日の分。
      expect(ids(pendingTodayRows(v, shiftType: 'night', now: now)), ['n13'],
          reason: '夜勤の午前の業務日を前の日にしていない');
      expect(ids(pendingOtherRows(v, shiftType: 'night', now: now)), ['d14', 'd13', 'n14', 'd14b']);
      // 最初の受け付けなかった字（今日の分だけで見る＝ほかの日の字を頭に出さない）。
      expect(firstRefusedMessageOf(pendingTodayRows(v, shiftType: 'day', now: now)), 'z');
      expect(firstRefusedMessageOf(const []), isNull);
      expect(firstRefusedMessageOf(pendingTodayRows(const PendingView(own: [
        PendingReportRow(id: 'a', shiftType: 'day', businessDate: '2026-10-14'),
      ]), shiftType: 'day', now: now)), isNull);
    });

    test('(BK-a2) 姿の読み直し：今の人の日報だけ（業務日は送る日付と同じ物差し）・読めない行と読めない箱の数（二者比較）', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'user_name': '検査 太郎',
        'pending_reports': jsonEncode([
          _item('mine-day', refused: '有効な所属がありません').toJson(),
          _item('other-user', owner: 'U2').toJson(),
          // 日本の 2026-10-14 03:00（UTC 10/13 18:00）の夜勤＝業務日は 10/13。
          _item('mine-night', shift: 'night', at: DateTime.utc(2026, 10, 13, 18, 0)).toJson(),
          _badRow('/x/report_photos/u1.jpg'),
        ]),
        'pending_reports_unreadable': <String>['{壊れた'],
      });
      await ReportStore.instance.refreshPendingCount();
      final v = ReportStore.instance.pendingView.value;
      expect(v.own.map((r) => r.id), ['mine-day', 'mine-night'], reason: 'ほかの人の日報を今の人の物にした');
      expect(v.own.map((r) => r.businessDate), ['2026-10-14', '2026-10-13']);
      expect(v.own.map((r) => r.shiftType), ['day', 'night']);
      expect(v.own.first.refusedMessage, '有効な所属がありません');
      expect(v.own.last.refusedMessage, isNull);
      expect(v.unreadableRows, 1);
      expect(v.unreadableBoxes, 1);
      expect(v.readFailed, isFalse);
      // 読めない物が無い箱（二者比較）。
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': jsonEncode([_item('only').toJson()]),
      });
      await ReportStore.instance.refreshPendingCount();
      final w = ReportStore.instance.pendingView.value;
      expect(w.own.map((r) => r.id), ['only']);
      expect(w.unreadableRows, 0);
      expect(w.unreadableBoxes, 0);
      expect(w.hasUnreadable, isFalse);
    });

    test('(BK-a3) 読めなかった時：前の姿のまま「読めなかった」の印・控えは1件だけ・読めたら印を消す', () async {
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': jsonEncode([_item('a3').toJson()]),
      });
      await ReportStore.instance.refreshPendingCount();
      expect(ReportStore.instance.pendingView.value.own.single.id, 'a3');
      // 箱の鍵に字でない値（読むと投げる）を入れる。
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pending_reports', 7);
      await ReportStore.instance.refreshPendingCount();
      await ReportStore.instance.refreshPendingCount();
      final v = ReportStore.instance.pendingView.value;
      expect(v.readFailed, isTrue, reason: '読めなかったのに印が立たない');
      expect(v.own.single.id, 'a3', reason: '読めなかった時に前の姿を消した');
      expect(await errorKinds(), ['pending_read'], reason: '控えが1件でない（読み直すたびに残した・残さない）');
      await prefs.setString('pending_reports', '[]');
      await ReportStore.instance.refreshPendingCount();
      expect(ReportStore.instance.pendingView.value.readFailed, isFalse);
      expect(ReportStore.instance.pendingView.value.own, isEmpty);
    });

    testWidgets('(BK-a4) 今日の分が送れて、ほかの日の受け付けなかった日報が在る：頭は「報告完了」・下に未送信日報と外す・再送は下に1つ・※2つ',
        (tester) async {
      await _pump(tester, _after(sent: true, others: const [_refusedRow]));
      expect(find.text('報告完了'), findsOneWidget);
      expect(find.text('未送信（再送待ち）'), findsNothing);
      expect(find.text('未送信日報'), findsOneWidget);
      expect(find.text('1件'), findsOneWidget);
      expect(find.text('☀日勤 10/13分'), findsOneWidget);
      expect(find.text('提出できません（名前・日付・出勤時刻は必須です）'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '外す'), findsOneWidget);
      expect(find.text('今すぐ再送する'), findsOneWidget);
      expect(find.text('※会社のご担当者にご確認ください。'), findsOneWidget);
      expect(find.text('※外した日報は送信されません。管理・履歴のカレンダーに「日報漏れを申告する」が出ている日は、そこから出し直しを申告できます。'), findsOneWidget);
      expect(find.text('※日報の無い日は、管理・履歴のカレンダーで確かめられます。'), findsNothing);
      // 「未送信日報」は「続けて報告」の後（下）。再送は未送信日報の中（見出しの下）。
      final cont = tester.getRect(find.text('続けて報告'));
      final head = tester.getRect(find.text('未送信日報'));
      final retry = tester.getRect(find.text('今すぐ再送する'));
      expect(head.top > cont.bottom, isTrue, reason: '未送信日報が「続けて報告」の下に無い');
      expect(retry.top > head.bottom, isTrue, reason: '再送が未送信日報の中に無い');
      // 通信で送れていない行（二者比較）：外すは無い・字は通信の字・※の2つは出ない。
      await _pump(tester, _after(sent: true, others: const [_netRow]));
      expect(find.text('🌙夜勤 10/12分'), findsOneWidget);
      expect(find.text('通信状況により未送信です'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '外す'), findsNothing, reason: '通信の行に外すを出した');
      expect(find.text('今すぐ再送する'), findsOneWidget);
      expect(find.text('※会社のご担当者にご確認ください。'), findsNothing);
      expect(find.text('※外した日報は送信されません。管理・履歴のカレンダーに「日報漏れを申告する」が出ている日は、そこから出し直しを申告できます。'), findsNothing);
      // ほかの日が無い（二者比較）：未送信日報も再送も出ない。
      await _pump(tester, _after(sent: true));
      expect(find.text('未送信日報'), findsNothing);
      expect(find.text('今すぐ再送する'), findsNothing);
    });

    testWidgets('(BK-a5) 今日の分が未送信：頭は「未送信（再送待ち）」・再送は頭の下に1つだけ（未送信日報の中に出さない）', (tester) async {
      await _pump(tester, _after(sent: false, refused: '有効な所属がありません', others: const [_netRow]));
      expect(find.text('未送信（再送待ち）'), findsOneWidget);
      expect(find.text('提出できません（有効な所属がありません）'), findsOneWidget);
      expect(find.text('今すぐ再送する'), findsOneWidget, reason: '再送が2つ在る・無い');
      final retry = tester.getRect(find.text('今すぐ再送する'));
      final head = tester.getRect(find.text('未送信日報'));
      expect(retry.bottom < head.top, isTrue, reason: '再送が頭の下に無い');
      // 今日の分もほかの日も受け付けられなかった時：「※会社のご担当者にご確認ください。」は頭の下の1つだけ（同じ字を2回出さない）・
      //   「※外した日報は…」は下に出る（二者比較＝今日の分が送れていれば、下に1つ）。
      await _pump(tester, _after(sent: false, refused: '有効な所属がありません', others: const [_refusedRow]));
      expect(find.text('※会社のご担当者にご確認ください。'), findsOneWidget, reason: '同じ※が2回出た・出ない');
      expect(find.text('※外した日報は送信されません。管理・履歴のカレンダーに「日報漏れを申告する」が出ている日は、そこから出し直しを申告できます。'), findsOneWidget);
      final noteTop = tester.getRect(find.text('※会社のご担当者にご確認ください。')).top;
      expect(noteTop < tester.getRect(find.text('未送信日報')).top, isTrue, reason: '頭の下の※でない');
      await _pump(tester, _after(sent: true, others: const [_refusedRow]));
      expect(find.text('※会社のご担当者にご確認ください。'), findsOneWidget);
      expect(tester.getRect(find.text('※会社のご担当者にご確認ください。')).top >
          tester.getRect(find.text('未送信日報')).top, isTrue, reason: '下の※でない');
    });

    testWidgets('(BK-a6) 読み込めない日報：行の題（1件・N件・件数不明）・件数（N件・N件以上・件数不明）・※・外す・再送は出ない', (tester) async {
      await _pump(tester, _after(sent: true, unreadable: 1));
      expect(find.text('読み込めない日報'), findsOneWidget);
      expect(find.text('内容を読み込めないため、送信されません'), findsOneWidget);
      expect(find.text('1件'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '外す'), findsOneWidget);
      expect(find.text('※日報の無い日は、管理・履歴のカレンダーで確かめられます。'), findsOneWidget);
      expect(find.text('※外した日報は送信されません。管理・履歴のカレンダーに「日報漏れを申告する」が出ている日は、そこから出し直しを申告できます。'), findsNothing,
          reason: '読み込めない日報だけなのに、出し直しの※を出した');
      expect(find.text('今すぐ再送する'), findsNothing, reason: '送れない日報だけなのに再送を出した');
      await _pump(tester, _after(sent: true, unreadable: 2));
      expect(find.text('読み込めない日報 2件'), findsOneWidget);
      expect(find.text('2件'), findsOneWidget);
      await _pump(tester, _after(sent: true, unknown: true));
      expect(find.text('読み込めない日報（件数不明）'), findsOneWidget);
      expect(find.text('件数不明'), findsOneWidget);
      await _pump(tester, _after(sent: true, others: const [_netRow], unknown: true));
      expect(find.text('1件以上'), findsOneWidget, reason: '分からない数を少なく見せた');
      await _pump(tester, _after(sent: true, others: const [_refusedRow, _netRow], unreadable: 2));
      expect(find.text('4件'), findsOneWidget);
    });

    testWidgets('(BK-a7) 未送信の箱を読めなかった時：頭の下に※（報告完了でも未送信でも）・読めた時は出ない（二者比較）', (tester) async {
      await _pump(tester, _after(sent: true, readFailed: true));
      expect(find.text('※送信状況を読み込めませんでした。'), findsOneWidget);
      final sub = tester.getRect(find.textContaining('分を送信しました'));
      final note = tester.getRect(find.text('※送信状況を読み込めませんでした。'));
      expect(note.top >= sub.bottom, isTrue);
      await _pump(tester, _after(sent: false, readFailed: true));
      expect(find.text('※送信状況を読み込めませんでした。'), findsOneWidget);
      final note2 = tester.getRect(find.text('※送信状況を読み込めませんでした。'));
      final retry = tester.getRect(find.text('今すぐ再送する'));
      expect(note2.bottom <= retry.top, isTrue, reason: '※が頭の下（再送の上）に無い');
      await _pump(tester, _after(sent: true));
      expect(find.text('※送信状況を読み込めませんでした。'), findsNothing);
      await _pump(tester, _after(sent: false));
      expect(find.text('※送信状況を読み込めませんでした。'), findsNothing);
    });

    testWidgets('(BK-a8) 外す：高さ44以上・幅64以上・押すと、その行（読み込めない日報はその口）を渡す', (tester) async {
      final removed = <String>[];
      var unreadableTapped = 0;
      await _pump(
          tester,
          _after(
            sent: true,
            others: const [_refusedRow],
            unreadable: 1,
            onRemoveRow: (r) async => removed.add(r.id),
            onRemoveUnreadable: () async => unreadableTapped++,
          ));
      final buttons = find.widgetWithText(OutlinedButton, '外す');
      expect(buttons, findsNWidgets(2));
      for (final b in buttons.evaluate()) {
        final size = tester.getSize(find.byWidget(b.widget));
        expect(size.height, greaterThanOrEqualTo(44), reason: '外すの高さ $size');
        expect(size.width, greaterThanOrEqualTo(64), reason: '外すの幅 $size');
      }
      await tester.tap(buttons.first);
      await tester.pumpAndSettle();
      expect(removed, ['r13']);
      expect(unreadableTapped, 0);
      await tester.tap(buttons.last);
      await tester.pumpAndSettle();
      expect(unreadableTapped, 1);
      // 行の高さは 52 以上。
      final row = find.ancestor(of: find.text('☀日勤 10/13分'), matching: find.byType(Container)).first;
      expect(tester.getSize(row).height, greaterThanOrEqualTo(52));
    });

    testWidgets('(BK-a9) 外す時の窓：題・2つの段・キャンセル／外す・写真の数（0枚なら写真の字を出さない）', (tester) async {
      bool? got;
      await _pump(
          tester,
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async => got = await confirmRemovePendingDialog(ctx,
                  title: removePendingTitle('2026-10-13'),
                  line1: removePendingLine1(2),
                  line2: removePendingLine2('2026-10-13')),
              child: const Text('開く'),
            ),
          ));
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.text('10/13分の日報を外しますか？'), findsOneWidget);
      expect(find.text('端末から外し、送信しません。写真2枚も消えます。'), findsOneWidget);
      expect(find.text('管理・履歴のカレンダーの10/13に「日報漏れを申告する」が出ていれば、そこから出し直しを申告できます。'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(got, isFalse);
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('外す')));
      await tester.pumpAndSettle();
      expect(got, isTrue);
      // 字の組み方（写真0枚・読み込めない日報）。
      expect(removePendingLine1(0), '端末から外し、送信しません。');
      expect(kRemoveUnreadableTitle, '読み込めない日報を外しますか？');
      expect(kRemoveUnreadableLine2, '日報の無い日は、管理・履歴のカレンダーで確かめられます。');
      expect(pendingRowTitle('night', '2026-01-05'), '🌙夜勤 1/5分');
      expect(monthDayOfBusinessDate('x'), 'x');
    });

    test('(BK-a10) シェルの繋ぎ：外すは写真の数を読んでから窓・外した結果の知らせ（送信中・外せない）（ソースの字）', () {
      final src = _codeOnly(_home);
      final flat = _flat(src);
      for (final p in [
        'pendingReadFailed: view.readFailed,',
        // 元: 'otherRows: pendingOtherRows(view, shiftType: _shiftType, now: now),'。
        // →再（2026-10-21・便BN・下調べの (D3)）: 出している印（shown）の勤務の種類と業務日で分ける。
        'otherRows: pendingOtherRows(view, shiftType: shown.shift, now: now, bizDate: shown.bizDate),',
        'unreadableCount: view.unreadableRows,',
        'unreadableUnknown: view.unreadableBoxes > 0,',
        'onRemoveRow: _confirmRemovePending,',
        'onRemoveUnreadable: _confirmRemoveUnreadable,',
      ]) {
        expect(flat.contains(p), isTrue, reason: '送った後の画面へ「$p」を渡していない');
      }
      final rm = _flat(_bodyOf(src, '  Future<void> _confirmRemovePending(PendingReportRow row) async {'));
      final iCount = rm.indexOf('await ReportStore.instance.removablePhotoCount(row.id);');
      final iDialog = rm.indexOf('await confirmRemovePendingDialog(context,');
      final iRemove = rm.indexOf('await ReportStore.instance.removePending(row.id)');
      expect(iCount >= 0 && iCount < iDialog && iDialog < iRemove, isTrue, reason: '写真の数→窓→外すの並びでない');
      expect(rm.contains('if (!ok || !mounted) return;'), isTrue, reason: 'キャンセルでも外す');
      final un = _flat(_bodyOf(src, '  Future<void> _confirmRemoveUnreadable() async {'));
      expect(un.contains('await ReportStore.instance.removablePhotoCount(null);'), isTrue);
      expect(un.contains('await ReportStore.instance.removeUnreadable()'), isTrue);
      final show = _flat(_bodyOf(src, '  void _showRemoveResult(PendingRemoveResult r) {'));
      expect(show.contains('case PendingRemoveResult.inFlight: showJsSnackbar(context, kRemoveInFlightText, isWarning: true);'),
          isTrue);
      expect(show.contains('case PendingRemoveResult.failed: showJsSnackbar(context, kRemoveFailedText, isError: true);'),
          isTrue, reason: '外せなかった時に黙る');
      expect(kRemoveInFlightText, '送信中のため外せません。少し待ってから、もう一度お試しください。');
      expect(kRemoveFailedText, '外せませんでした。もう一度お試しください。');
      // 外している間は、ほかの「外す」を受けない（素早く2回押して窓が2つ開かない）。
      expect(rm.startsWith('Future<void> _confirmRemovePending(PendingReportRow row) async { if (_removing) return; _removing = true; try {') ||
              rm.contains('async { if (_removing) return; // 外す1件 _removing = true; try {'),
          isTrue, reason: '外している間の止めが無い');
      expect(un.contains('if (_removing) return;'), isTrue);
      expect(rm.contains('} finally { _removing = false; }'), isTrue, reason: '止めを外さない（2回目から押せない）');
      // 「今すぐ再送する」の残りの数は、送り直しの後に読み直した姿から取る（読めなかった時は数を出さない）。
      //   →再（2026-10-19・便BM）: 中身は _retryPendingNow の1本（送った後の画面と「未送信日報」の画面が同じ口）＝見る所をそこへ移した
      //   （見る事は今のまま）。
      final afterWire = _flat(src.substring(src.indexOf('return AfterReportBody('), src.indexOf('onOvertime: _openExtraDeclarationPicker,')));
      expect(afterWire.contains('onRetry: _retryPendingNow,'), isTrue, reason: '送った後の画面の再送が _retryPendingNow でない');
      final retry = _flat(_bodyOf(src, '  Future<void> _retryPendingNow() async {'));
      expect(retry.contains('await ReportStore.instance.retryPending(); final v = ReportStore.instance.pendingView.value; '
              'if (mounted && !v.readFailed) { final remaining = v.own.length;'),
          isTrue, reason: '残りの数を、姿と別の道で数えている・読めなかった時に数を出す');
      expect(retry.contains('pendingCount()'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (b) 外す・写真（見本 v3 の ⑮⑯・見つけた事 (30)）
  // ══════════════════════════════════════════════════════════
  group('(b) 外す・写真', () {
    test('(BK-b1) 今の人の日報を外す：箱から外し、ほかが指していない写真だけ消す・姿を読み直す（二者比較）', () async {
      final own = photo('own.jpg');
      final shared = photo('shared.jpg');
      final badRef = photo('bad.jpg');
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': jsonEncode([
          _item('b1', refused: 'x', work: [own.path, shared.path], parking: [badRef.path]).toJson(),
          _item('keep', work: [shared.path]).toJson(),
          _badRow(badRef.path),
        ]),
      });
      final r = await ReportStore.instance.removePending('b1');
      expect(r, PendingRemoveResult.removed);
      final box = await _box();
      expect(box.where((e) => e['id'] is String).map((e) => e['id']), ['keep']);
      expect(box.length, 2, reason: '読めない行を消した');
      expect(own.existsSync(), isFalse, reason: 'ほかが指していない写真を残した');
      expect(shared.existsSync(), isTrue, reason: 'ほかの日報が指している写真を消した');
      expect(badRef.existsSync(), isTrue, reason: '読めない行が指している写真を消した');
      expect(ReportStore.instance.pendingView.value.own.map((e) => e.id), ['keep']);
    });

    test('(BK-b2) 送っている途中の日報は外さない（inFlight）・送り終えると箱は空', () async {
      final seen = <http.Request>[];
      final started = Completer<void>();
      final gate = Completer<void>();
      await _withServer(seen, [201], () async {
        final sending = ReportStore.instance.addReport(_item('b2'));
        await started.future;
        expect(await ReportStore.instance.removePending('b2'), PendingRemoveResult.inFlight,
            reason: '送っている途中の日報を外した');
        expect((await _box()).map((e) => e['id']), ['b2']);
        gate.complete();
        expect(await sending, isTrue);
      }, onRequest: (_) async {
        if (!started.isCompleted) started.complete();
        await gate.future;
      });
      expect(await _box(), isEmpty);
      expect(seen.length, 1);
    });

    test('(BK-b3) もう無い日報・ほかの人の日報は外さない（gone）・箱はそのまま', () async {
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': jsonEncode([_item('u2row', owner: 'U2', refused: 'x').toJson()]),
      });
      expect(await ReportStore.instance.removePending('nothing'), PendingRemoveResult.gone);
      expect(await ReportStore.instance.removePending('u2row'), PendingRemoveResult.gone,
          reason: 'ほかの人の日報を外した');
      expect((await _box()).map((e) => e['id']), ['u2row']);
    });

    test('(BK-b4) 箱に書けなかった時：failed・手元の写しの箱も元のまま（外した事にしない）・写真も消さない', () async {
      final p = photo('b4.jpg');
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': jsonEncode([_item('b4', refused: 'x', work: [p.path]).toJson()]),
      });
      final orig = pendingBoxWriter;
      addTearDown(() => pendingBoxWriter = orig);
      pendingBoxWriter = (prefs, key, value) async {
        // 手元の写しは替わる（shared_preferences は先に写しを替える）が、端末へ書く所で投げた形。
        await prefs.setString(key, value);
        throw Exception('端末へ書けない');
      };
      expect(await ReportStore.instance.removePending('b4'), PendingRemoveResult.failed);
      expect((await _box()).map((e) => e['id']), ['b4'], reason: '書けなかったのに手元の写しの箱から外した');
      expect(p.existsSync(), isTrue, reason: '外せなかったのに写真を消した');
      pendingBoxWriter = orig;
      expect(await ReportStore.instance.removePending('b4'), PendingRemoveResult.removed);
      expect(await _box(), isEmpty);
    });

    test('(BK-b5) 読み込めない日報を外す：読めない行と読めない箱の元の字を消し、読めた日報は残す・拾った写真だけ消す', () async {
      final u1 = photo('u1.jpg');
      final u2 = photo('u2.jpg');
      final both = photo('both.jpg');
      final other = photo('other.jpg');
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': jsonEncode([
          _item('stay', work: [both.path]).toJson(),
          _badRow(u1.path),
          _badRow(both.path),
        ]),
        'pending_reports_unreadable': <String>['{"workPhotoPaths":["/old/report_photos/u2.jpg"] 壊れた'],
      });
      expect(await ReportStore.instance.removeUnreadable(), PendingRemoveResult.removed);
      final box = await _box();
      expect(box.map((e) => e['id']), ['stay'], reason: '読めない行が残った・読めた日報を消した');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('pending_reports_unreadable'), isNull, reason: '読めない箱の元の字が残った');
      expect(u1.existsSync(), isFalse);
      expect(u2.existsSync(), isFalse, reason: '読めない箱の字から拾った写真を消していない');
      expect(both.existsSync(), isTrue, reason: '読めた日報が指している写真を消した');
      expect(other.existsSync(), isTrue, reason: 'どれも指していない写真まで消した（掃除の仕事）');
      expect(ReportStore.instance.pendingView.value.hasUnreadable, isFalse);
      // 無い時は gone。
      expect(await ReportStore.instance.removeUnreadable(), PendingRemoveResult.gone);
    });

    test('(BK-b6) 箱そのものが読めない時に外す：箱を読めた形に書き直す（次に読んだ時に元の字を写し直さない）', () async {
      SharedPreferences.setMockInitialValues({'user_id': 'U1', 'pending_reports': '{壊れた箱'});
      await ReportStore.instance.refreshPendingCount();
      expect(ReportStore.instance.pendingView.value.unreadableBoxes, 1);
      expect(await ReportStore.instance.removeUnreadable(), PendingRemoveResult.removed);
      await ReportStore.instance.refreshPendingCount();
      expect(ReportStore.instance.pendingView.value.unreadableBoxes, 0, reason: '箱の元の字を、また写し直した');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_reports'), '[]');
    });

    test('(BK-b7) 読み込めない日報を外せなかった時：failed・箱と読めない箱の元の字は元のまま', () async {
      final raw = jsonEncode([_badRow('/x/report_photos/u.jpg')]);
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': raw,
        'pending_reports_unreadable': <String>['{x'],
      });
      final orig = pendingBoxWriter;
      addTearDown(() => pendingBoxWriter = orig);
      pendingBoxWriter = (prefs, key, value) async {
        await prefs.setString(key, value);
        throw Exception('端末へ書けない');
      };
      expect(await ReportStore.instance.removeUnreadable(), PendingRemoveResult.failed);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_reports'), raw, reason: '書けなかったのに手元の写しの箱を替えた');
      expect(prefs.getStringList('pending_reports_unreadable'), ['{x']);
      expect(ReportStore.instance.pendingView.value.unreadableRows, 1);
    });

    test('(BK-b14) 箱の数を読む口（pendingCount）も箱の列に並ぶ：箱を書いている途中には数えない（列の外で読むと、外す途中の箱を読む）', () async {
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': jsonEncode([_item('k1', refused: 'x').toJson(), _item('k2').toJson()]),
      });
      final orig = pendingBoxWriter;
      addTearDown(() => pendingBoxWriter = orig);
      final gate = Completer<void>();
      final entered = Completer<void>();
      // ★赤で止まった時も、止めた書き込みを必ず放す（放さないと箱の列が詰まり、後の検査まで赤くなる）。
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      // 外す書き込みを、列の中で止めておく。
      pendingBoxWriter = (prefs, key, value) async {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
        return prefs.setString(key, value);
      };
      final removing = ReportStore.instance.removePending('k1');
      await entered.future;
      var counted = false;
      final counting = ReportStore.instance.pendingCount().then((n) {
        counted = true;
        return n;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(counted, isFalse, reason: '箱を書いている途中に、列の外で箱を数えた');
      gate.complete();
      expect(await removing, PendingRemoveResult.removed);
      expect(await counting, 1, reason: '外し終えた後の数でない');
    });

    test('(BK-b8) 外す前の写真の数：置き場に在って、ほかが指していない写真だけ（読み込めない日報は拾った名前）', () async {
      final a = photo('a.jpg');
      final s = photo('s.jpg');
      final u = photo('u.jpg');
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': jsonEncode([
          _item('c1', work: [a.path, s.path, '${photoDir.path}/missing.jpg', '/elsewhere/x.jpg']).toJson(),
          _item('c2', work: [s.path]).toJson(),
          _badRow(u.path),
        ]),
      });
      expect(await ReportStore.instance.removablePhotoCount('c1'), 1,
          reason: '在る・ほかが指していない写真は a.jpg だけ（s.jpg はほか・missing は無い・置き場の外は数えない）');
      expect(await ReportStore.instance.removablePhotoCount('c2'), 0);
      expect(await ReportStore.instance.removablePhotoCount(null), 1);
      expect(await ReportStore.instance.removablePhotoCount('nothing'), 0);
    });

    test('(BK-b9) 写真の掃除：読めない行と読めない箱の字が指す写真は残す（二者比較＝どれも指さない写真は消す）', () async {
      final r = photo('row.jpg');
      final b = photo('box.jpg');
      final n = photo('none.jpg');
      SharedPreferences.setMockInitialValues({
        'pending_reports': jsonEncode([_badRow(r.path)]),
        'pending_reports_unreadable': <String>['xx report_photos\\/box.jpg"'],
      });
      await ReportStore.instance.sweepPhotos();
      expect(r.existsSync(), isTrue, reason: '読めない行が指す写真を消した');
      expect(b.existsSync(), isTrue, reason: '読めない箱の字が指す写真を消した');
      expect(n.existsSync(), isFalse);
    });

    test('(BK-b10) 送れた日報の写真：読めない行が指す写真は残す（二者比較）', () async {
      final shared = photo('sh.jpg');
      final mine = photo('mine.jpg');
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': jsonEncode([_badRow(shared.path)]),
      });
      final seen = <http.Request>[];
      await _withServer(seen, [201], () async {
        expect(await ReportStore.instance.addReport(_item('b10', work: [shared.path, mine.path])), isTrue);
      });
      expect(mine.existsSync(), isFalse);
      expect(shared.existsSync(), isTrue, reason: '読めない行が指す写真を、送れた時に消した');
    });

    test('(BK-b11) ✕で外した写真を消してよいか：箱のどれも指していない時だけ（置き場の外は消さない）・main() が口を差す', () async {
      final a = photo('a.jpg');
      final used = photo('used.jpg');
      final bad = photo('bad.jpg');
      SharedPreferences.setMockInitialValues({
        'user_id': 'U1',
        'pending_reports': jsonEncode([
          _item('x', owner: 'U2', work: ['/old/report_photos/used.jpg']).toJson(),
          _badRow(bad.path),
        ]),
      });
      expect(await ReportStore.instance.isPhotoUnused(a.path), isTrue);
      expect(await ReportStore.instance.isPhotoUnused(used.path), isFalse, reason: 'ほかの人の箱の日報が指す写真を消してよいとした');
      expect(await ReportStore.instance.isPhotoUnused(bad.path), isFalse, reason: '読めない行が指す写真を消してよいとした');
      expect(await ReportStore.instance.isPhotoUnused('/tmp/camera/a.jpg'), isFalse, reason: '置き場の外を消してよいとした');
      final mainSrc = _flat(_codeOnly(_main));
      expect(mainSrc.contains('removedPhotoUnused = ReportStore.instance.isPhotoUnused;'), isTrue,
          reason: 'main() が ✕ の口を差していない');
    });

    // 見比べの口（ReportStore.isPhotoUnused）そのものは (BK-b11) が見る。ここは、帯の ✕ が外した写真の道を口に渡し、
    //   true の時だけ消す事を見る（口は検査の偽物＝画面の検査の時計の中で、箱の列を動かさない）。
    testWidgets('(BK-b12) 写真の帯の ✕：外した写真の道を口に渡し、消してよい時だけ消す（二者比較）', (tester) async {
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
      final free = File('${photoDir.path}/free.png')..writeAsBytesSync(png);
      final held = File('${photoDir.path}/held.png')..writeAsBytesSync(png);
      final orig = removedPhotoUnused;
      addTearDown(() => removedPhotoUnused = orig);
      final asked = <String>[];
      removedPhotoUnused = (p) async {
        asked.add(p);
        return p == free.path;
      };
      var paths = <String>[free.path, held.path];
      await _pump(
          tester,
          StatefulBuilder(
            builder: (ctx, set) => PhotoStripField(
              label: '作業写真',
              paths: paths,
              onChanged: (v) => set(() => paths = v),
            ),
          ));
      Future<void> tapClose() async {
        await tester.tap(find.byIcon(Icons.close).first);
        await tester.pump();
        // 消す所は待たずに走る（端末の置き場の読み書き＝本物の時間が要る）。
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
      }

      // 表示は逆順（最新が左）＝最初の ✕ は held.png。
      await tapClose();
      expect(paths, [free.path]);
      expect(asked, [held.path]);
      expect(held.existsSync(), isTrue, reason: '消してよくない写真を消した');
      await tapClose();
      expect(paths, isEmpty);
      expect(asked, [held.path, free.path]);
      expect(free.existsSync(), isFalse, reason: '消してよい写真を残した');
    });

    test('(BK-b13) 字の中の写真の名前を拾う（「/」と JSON の「\\/」・「.」「..」は拾わない）', () {
      expect(reportPhotoNamesIn('{"a":"/x/report_photos/1_2.jpg","b":"report_photos\\/3_4.png"}'),
          {'1_2.jpg', '3_4.png'});
      expect(reportPhotoNamesIn('report_photos/. report_photos/.. report_photos/ok.jpg'), {'ok.jpg'});
      expect(reportPhotoNamesIn('photos/x.jpg'), isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (c) 裏で止まった失敗（見本 v3 の ⑰）
  // ══════════════════════════════════════════════════════════
  group('(c) 裏の失敗', () {
    test('(BK-c1) エラー記録：種類と時刻だけ・新しい順・50件まで・名簿に無い鍵は「不明な記録」・件数を知らせる・投げない', () async {
      var t = DateTime(2026, 10, 14, 8, 12);
      deviceErrorClock = () => t;
      await recordDeviceError('net_watch');
      t = DateTime(2026, 10, 14, 17, 5);
      await recordDeviceError('photo_keep');
      expect(deviceErrorCount.value, 2, reason: '残した時に件数を知らせない');
      final list = (await readDeviceErrors())!;
      expect(list.map((e) => e.kind), ['photo_keep', 'net_watch'], reason: '新しい順でない');
      expect(list.first.title, '写真の保存');
      expect(list.first.fallback, '元の写真のまま送信');
      expect(deviceErrorTimeLabel(list.first.at), '10/14 17:05');
      expect(list.last.title, '電波の監視');
      expect(list.last.fallback, 'アプリを開いた時に再送');
      expect(deviceErrorCount.value, 2);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('device_error_log')!;
      expect(raw.length, 2);
      expect(raw.every((l) => RegExp(r'^\d+\|[a-z_]+$').hasMatch(l)), isTrue, reason: '種類と時刻のほかの字を残した');
      for (var i = 0; i < 60; i++) {
        await recordDeviceError('cleanup_keys');
      }
      expect((await readDeviceErrors())!.length, 50);
      expect(deviceErrorCount.value, 50);
      await prefs.setStringList('device_error_log', ['1|gone_kind', 'こわれた']);
      final odd = (await readDeviceErrors())!;
      expect(odd.map((e) => e.title), ['不明な記録', '不明な記録'], reason: '読めない行を黙って消した');
      expect(odd.first.fallback, '—');
      // 控えの鍵に字の並びでない値（読むと投げる）：読む口は null（「ありません」と言い切らない）・件数は前のまま・投げない。
      //   残す口は、その鍵をこの1件で書き直す（以後ずっと残せない形にしない）。
      await prefs.setInt('device_error_log', 3);
      final before = deviceErrorCount.value;
      expect(await readDeviceErrors(), isNull);
      expect(deviceErrorCount.value, before);
      await recordDeviceError('net_watch');
      expect((await readDeviceErrors())!.map((e) => e.kind), ['net_watch'], reason: '読めない鍵のまま、二度と残せない');
    });

    // →再（2026-10-21・便BN・見つけた事 (53)・【Q160】＝１・見本 claude/field_unread_unwritten_mock_v1.html）: 'today_mark_save' を足した（20→21）。
    test('(BK-c2) 種類の名簿：決まった21の鍵と字（題｜代わりにした事）・どの鍵にも残す所が在る・残す所の鍵は全部名簿に在る（ソースの字）', () {
      const want = <String, String>{
        'photo_keep': '写真の保存｜元の写真のまま送信',
        'photo_path': '写真の読み込み｜覚えた道のまま読む',
        'photo_delete': '写真の削除｜写真を残した',
        'photo_sweep': '写真の掃除｜写真を残した',
        'net_watch': '電波の監視｜アプリを開いた時に再送',
        'cleanup_keys': '端末の掃除｜次に開いた時にもう一度',
        'shift_restore': '勤務区分の読み込み｜日勤で表示',
        'shift_save': '勤務区分の保存｜選んだ区分で表示',
        'done_mark_read': '送信記録の読み込み｜日報のフォームを表示',
        'today_mark_save': '送信記録の保存｜印を残さずに続行',
        'today_marks_clear': '別の人の印の掃除｜使わずに続行',
        'unowned_marks_clear': '前の形の印の掃除｜残したまま続行',
        'pending_read': '送信状況の読み込み｜前の表示のまま',
        'pending_unreadable': '読み込めない日報｜端末に残した',
        'pending_unreadable_keep': '読み込めない日報の控え｜控えずに続行',
        'box_undo': '未送信の箱の戻し｜「送信できません」と表示',
        'box_remove_after_send': '送れた日報の片付け｜送れた事として続行',
        'note_answer': '送り先の答えの控え｜前の表示のまま',
        'retry_failed': '送り直し｜次の機会に再送',
        'remove_undo': '外す時の箱の戻し｜「外せませんでした」と表示',
        'lockout_token_read': '資格の読み込み｜締め出しを続行',
      };
      final kinds = want.keys.toSet();
      expect(kDeviceErrorKinds.keys.toSet(), kinds);
      for (final e in want.entries) {
        final v = kDeviceErrorKinds[e.key]!;
        expect('${v.title}｜${v.fallback}', e.value, reason: '${e.key} の字');
      }
      final used = <String>{};
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        for (final m in RegExp(r"recordDeviceError\('([a-z_]+)'\)").allMatches(_codeOnly(f.path))) {
          used.add(m.group(1)!);
        }
      }
      expect(used.difference(kinds), isEmpty, reason: '名簿に無い鍵を残している');
      expect(kinds.difference(used), isEmpty, reason: '残す所の無い鍵が名簿に在る（嘘の記号）');
    });

    testWidgets('(BK-c3) エラー記録の画面：1件＝題と「M/D HH:MM・代わりにした事」・※・0件の字（二者比較）', (tester) async {
      deviceErrorClock = () => DateTime(2026, 10, 13, 18, 40);
      await tester.runAsync(() => recordDeviceError('cleanup_keys'));
      await _pump(tester, const DeviceErrorLogScreen());
      expect(find.text('エラー記録'), findsOneWidget);
      expect(find.text('端末の掃除'), findsOneWidget);
      expect(find.text('10/13 18:40・次に開いた時にもう一度'), findsOneWidget);
      expect(find.text('※新しい順に50件まで残します。'), findsOneWidget);
      expect(find.text('エラー記録はありません'), findsNothing);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, const DeviceErrorLogScreen());
      expect(find.text('エラー記録はありません'), findsOneWidget);
      expect(find.text('※新しい順に50件まで残します。'), findsOneWidget);
      // 控えそのものを読めない時：「ありません」と言い切らず、読めなかった事を出す。
      SharedPreferences.setMockInitialValues({'device_error_log': 3});
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, const DeviceErrorLogScreen());
      expect(find.text('エラー記録を読み込めませんでした'), findsOneWidget);
      expect(find.text('エラー記録はありません'), findsNothing, reason: '読めないのに「ありません」と言い切った');
    });

    test('(BK-c4) 設定の「端末｜エラー記録」の行：件数（0件は「なし」）・※・押すと一覧・プロフィールを読めない時も出す（ソースの字）', () {
      final src = _codeOnly('lib/screens/profile_screen.dart');
      final tile = _flat(_bodyOf(src, '  Widget _buildDeviceErrorLogTile() {'));
      for (final p in [
        "Text('端末',",
        'Text(kDeviceErrorLogTitle,',
        'valueListenable: deviceErrorCount,',
        "Text(n > 0 ? '\$n件' : 'なし',",
        'MaterialPageRoute(builder: (_) => const DeviceErrorLogScreen()),',
        'const Text(kDeviceErrorTileNote,',
      ]) {
        expect(tile.contains(p), isTrue, reason: '行に「$p」が無い');
      }
      expect('_buildDeviceErrorLogTile()'.allMatches(src).length, 3, reason: '定義1つと、出す所2つ（ふだん・読めない時）');
      expect(_flat(src).contains('_loadConsentInfo(); readDeviceErrors();'), isTrue, reason: '開いた時に件数を読まない');
      expect(kDeviceErrorTileNote, '※不具合の問い合わせの時にお伝えください。');
      expect(kDeviceErrorLogTitle, 'エラー記録');
      expect(_codeOnly('lib/screens/device_error_log_screen.dart').contains('title: const Text(kDeviceErrorLogTitle),'), isTrue);
    });

    testWidgets('(BK-c5) ホームの勤務区分：読み込めなかった時だけ、選ぶ所の下に※（二者比較）', (tester) async {
      Future<void> pumpPunch(bool failed) async {
        tester.view.physicalSize = const Size(1200, 2600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: PunchScreen(
            key: UniqueKey(),
            reports: _FakeReports(),
            shiftType: 'day',
            onShiftTypeChanged: (_) {},
            shiftReadFailed: failed,
          ),
        ));
        await tester.pumpAndSettle();
      }

      await pumpPunch(true);
      expect(find.text('※勤務区分を読み込めませんでした。日勤で表示しています。'), findsOneWidget);
      final biz = tester.getRect(find.textContaining('業務日 ').first);
      final note = tester.getRect(find.text('※勤務区分を読み込めませんでした。日勤で表示しています。'));
      expect(note.top >= biz.bottom, isTrue, reason: '※が業務日の行の下に無い');
      await pumpPunch(false);
      expect(find.text('※勤務区分を読み込めませんでした。日勤で表示しています。'), findsNothing);
    });

    test('(BK-c6) シェルの繋ぎ：勤務区分・送った印・別の人の印の失敗を、※と控えに出す・保存できたら※を消す（ソースの字）', () {
      final src = _codeOnly(_home);
      final today = _flat(_bodyOf(src, '  Future<void> _restoreTodayState() async {'));
      // →再（2026-10-21・便BN・下調べの (D1)(D6)）: 送った印の写しと※は、勤務の種類と業務日を持つ形（_setMark・_clearMark・
      //   _setDoneMarkFail）になった。勤務の種類を戻せなかった時は、決めた時の業務日も覚える（(D6)）。
      for (final p in [
        "await recordDeviceError('today_marks_clear');",
        'final shift = _shiftType; final biz = businessDateForShift(shift, businessNow()); '
            'try { await _initTodayReportDone(shift, biz); }',
        "if (mounted) setState(() => _setDoneMarkFail(shift, biz)); await recordDeviceError('done_mark_read');",
      ]) {
        expect(today.contains(p), isTrue, reason: '開く時の失敗に「$p」が無い');
      }
      // 勤務の種類を戻せなかった時：※（日勤で表示している時だけ）→ 決めた時の業務日を覚える（(D6)）→ 控えに残す、の並び。
      final iFlag = today.indexOf("if (mounted && _shiftType == 'day') setState(() => _shiftReadFailed = true);");
      final iDecide = today.indexOf('if (_shiftDecidedBiz == null) { _shiftDecidedBiz = businessDateForShift(_shiftType, businessNow()); '
          '_maybeReturnToDayShift();');
      final iRecord = today.indexOf("await recordDeviceError('shift_restore');");
      expect(iFlag >= 0 && iFlag < iDecide && iDecide < iRecord, isTrue,
          reason: '勤務の種類を戻せなかった時の、※・覚える・控えの並びが違う（どれかが無い）');
      final re = _flat(_bodyOf(src, '  Future<void> _reevaluateReportDone() async {'));
      // 読めなかった時（catch の中）＝フォームへ戻し・※を立て・控えに残して終わる。
      final iCatch = re.indexOf('} catch (e) {');
      final iAfter = re.indexOf('_setMark(shift, biz, s);');
      expect(iCatch >= 0 && iAfter > iCatch, isTrue);
      final onFail = re.substring(iCatch, iAfter);
      for (final p in [
        '_clearMark();',
        '_setDoneMarkFail(shift, biz);',
        "await recordDeviceError('done_mark_read');",
        'return;',
      ]) {
        expect(onFail.contains(p), isTrue, reason: '切り替えの時に読めない時の「$p」が無い（前の勤務の種類の送った後の画面が残る）');
      }
      expect(re.substring(iAfter).contains('_setDoneMarkFail(null, null);'), isTrue, reason: '読めた時に※を消さない');
      final chosen = _flat(_bodyOf(src, '  Future<void> _onShiftTypeChosen(String v) async {'));
      expect(chosen.contains('if (await _saveShiftType(v) && mounted && _shiftReadFailed) { setState(() => _shiftReadFailed = false); }'),
          isTrue, reason: '保存できた時に※を消さない');
      expect(chosen.contains("await recordDeviceError('shift_save');"), isTrue);
      final flat = _flat(src);
      expect(flat.contains("shiftReadFailed: _shiftReadFailed && _shiftType == 'day',"), isTrue,
          reason: '夜勤の表示のまま「日勤で表示しています。」を出す道がある');
      expect(flat.contains('_onShiftTypeChosen(v);'), isTrue);
      expect(flat.contains('if (_doneMarkReadFailed) ...[ const SizedBox(height: 4), const Text(kDoneMarkReadFailedNote,'), isTrue,
          reason: '日報のフォームの見出しの下に※が無い');
      expect(kDoneMarkReadFailedNote, '※今日の送信記録を読み込めませんでした。送信済みかは、管理・履歴で確かめてください。');
      // 「今日の報告」の見出しの直後。
      final iHead = flat.indexOf("const Text('今日の報告',");
      final iNote = flat.indexOf('if (_doneMarkReadFailed) ...[');
      expect(iHead >= 0 && iNote > iHead && iNote - iHead < 300, isTrue);
    });

    test('(BK-c7) 掃除で消せなかった時：残りは消す・印と控えを残す・やり直して消せなければ※・消せたら印を消す（二者比較）', () async {
      // 名簿の前の方の鍵（user_name）を消せない形にし、その後ろの鍵（home_address と、名簿の最後の consent_version）が
      //   消える事を見る（1つ消せないと残りを消さない、を見分ける＝鍵の並びは名簿の順）。
      SharedPreferences.setMockInitialValues({
        'auth_token': 'T',
        'user_id': 'U1',
        'home_address': '前の人の住所',
        'user_name': '前の人',
        'consent_version': '1.0',
      });
      expect(kPersonalDataKeys.indexOf('user_name') < kPersonalDataKeys.indexOf('home_address'), isTrue);
      expect(kPersonalDataKeys.last, 'consent_version');
      final orig = personalKeyRemover;
      addTearDown(() => personalKeyRemover = orig);
      var failing = true;
      personalKeyRemover = (prefs, key) async {
        if (failing && key == 'user_name') return false;
        return prefs.remove(key);
      };
      expect(await clearPersonalData(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_name'), '前の人');
      expect(prefs.getString('home_address'), isNull, reason: '1つ消せないと、残りを消さなかった');
      expect(prefs.getString('consent_version'), isNull, reason: '1つ消せないと、名簿の最後まで消さなかった');
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getBool('personal_cleanup_pending'), isTrue, reason: 'やり直しの印を残していない');
      expect(await errorKinds(), ['cleanup_keys']);
      // やり直しても消せない → ※。
      await retryPendingPersonalCleanup();
      expect(personalCleanupFailedAgain.value, isTrue);
      expect(prefs.getBool('personal_cleanup_pending'), isTrue);
      // 消せるようになった → 消す・印を消す・※を消す。
      failing = false;
      await retryPendingPersonalCleanup();
      expect(personalCleanupFailedAgain.value, isFalse);
      expect(prefs.getString('user_name'), isNull);
      expect(prefs.getBool('personal_cleanup_pending'), isNull, reason: '消せたのに印が残った');
      // 印が無い時は何もしない（二者比較：資格は消えない）。
      await prefs.setString('auth_token', 'T2');
      await retryPendingPersonalCleanup();
      expect(prefs.getString('auth_token'), 'T2', reason: '印が無いのに掃除した');
      expect(kPersonalCleanupFailedNote, '※前の利用者の記録の一部を消せませんでした。アプリを開き直すと、もう一度消します。');
      // ※が立ったまま、印が別の道（後の掃除で全部消せた）で消えた時：やり直しは※を下ろす（出続けない）。
      personalCleanupFailedAgain.value = true;
      await retryPendingPersonalCleanup();
      expect(personalCleanupFailedAgain.value, isFalse, reason: '印が無いのに※が出続ける');
      // 印が在る時のやり直しは、資格も消す（前の人の資格を次の人に使わせない）。
      await prefs.setBool('personal_cleanup_pending', true);
      await retryPendingPersonalCleanup();
      expect(prefs.getString('auth_token'), isNull, reason: '印が在るのに資格を残した');
      // ログインが通った時（新しい資格を書き終えた時）：印を消し※を下ろす（次に開いた時に、今の人の資格を消さない）。
      await prefs.setBool('personal_cleanup_pending', true);
      personalCleanupFailedAgain.value = true;
      await endPersonalCleanupPending();
      expect(prefs.getBool('personal_cleanup_pending'), isNull, reason: 'ログインの後も印が残る');
      expect(personalCleanupFailedAgain.value, isFalse);
      // エラー記録はログアウトの掃除で消さない（人に付く物でない）。
      expect((await errorKinds()).isNotEmpty, isTrue);
      final kept = (await errorKinds()).length;
      await clearPersonalData();
      expect((await errorKinds()).length, kept, reason: '掃除でエラー記録を消した');
      // 印を読めない時（字でない値）は、控えに残す（黙らない）・※は替えない。
      await prefs.setString('personal_cleanup_pending', 'x');
      final n0 = (await errorKinds()).length;
      await retryPendingPersonalCleanup();
      final ks = await errorKinds();
      expect(ks.length, n0 + 1);
      expect(ks.first, 'cleanup_keys', reason: '印を読めないのに黙った');
    });

    test('(BK-c8) ログイン画面：資格を読む前にやり直す・※は PIN の画面・生体の画面・はじめの画面の3か所（ソースの字）', () {
      final src = _codeOnly(_login);
      final init = _flat(_bodyOf(src, '  Future<void> _init() async {'));
      final iRetry0 = init.indexOf('await retryPendingPersonalCleanup();');
      final iWarm = init.indexOf('await _warmUpServer();');
      final iTok0 = init.indexOf("prefs.getString('auth_token')");
      expect(init.trimLeft().startsWith('Future<void> _init() async { await retryPendingPersonalCleanup();'), isTrue,
          reason: '開いた時の一番初めにやり直していない');
      expect(iRetry0 >= 0 && iRetry0 < iWarm && iWarm < iTok0, isTrue, reason: '資格を読む前にやり直していない');
      expect('_buildCleanupFailedNote(),'.allMatches(src).length, 3);
      final iDef = src.indexOf('  Widget _buildCleanupFailedNote() => ValueListenableBuilder<bool>(');
      expect(iDef, greaterThan(0));
      final note = _flat(src.substring(iDef, src.indexOf('SizedBox.shrink(),', iDef)));
      expect(note.contains('valueListenable: personalCleanupFailedAgain,'), isTrue);
      expect(note.contains('Text(kPersonalCleanupFailedNote,'), isTrue);
      // PIN の画面は「ログイン」のボタンのすぐ下。
      final pin = _flat(_bodyOf(src, '  Widget _buildPinLoginScreen() {'));
      final iBtn = pin.indexOf("const Text('ログイン',");
      final iNote = pin.indexOf('_buildCleanupFailedNote(),');
      expect(iBtn >= 0 && iNote > iBtn, isTrue);
      // やり直しても消せなかった時は、残った資格で自動のログインをしない。
      expect(init.contains('if (cachedToken.isNotEmpty && !personalCleanupFailedAgain.value) {'), isTrue,
          reason: '前の人の資格かもしれない資格で、自動のログインをする');
      // 新しくログインする3つの道：書く前にやり直し・書き終えたら印を消す（次に開いた時に、今の人の資格を消さない）。
      for (final e in <String, String>{
        _login: '  Future<void> _saveAndNavigate(Map<String, dynamic> data) async {',
        'lib/screens/recovery_screen.dart': '  Future<void> _saveAndNavigate(Map<String, dynamic> data, String deviceId) async {',
      }.entries) {
        final b = _flat(_bodyOf(_codeOnly(e.key), e.value));
        final iRetry = b.indexOf('await retryPendingPersonalCleanup();');
        final iToken = b.indexOf("await prefs.setString('auth_token',");
        final iEnd = b.indexOf('await endPersonalCleanupPending();');
        final iGo = b.indexOf("Navigator.of(context).pushReplacementNamed('/gate');");
        expect(iRetry >= 0 && iRetry < iToken && iToken < iEnd && iEnd < iGo, isTrue,
            reason: '${e.key}：やり直し→資格を書く→印を消す→進む、の並びでない');
      }
      final reg = _flat(_codeOnly('lib/screens/register_screen.dart'));
      final rRetry = reg.indexOf('await retryPendingPersonalCleanup();');
      final rToken = reg.indexOf("await prefs.setString('auth_token', body['token']");
      final rEnd = reg.indexOf('await endPersonalCleanupPending();');
      expect(rRetry >= 0 && rRetry < rToken && rToken < rEnd, isTrue, reason: '登録の画面：やり直し→資格を書く→印を消す、の並びでない');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (d) 見つけた事 (26)(28)(29)・CC の見つけた2つ
  // ══════════════════════════════════════════════════════════
  group('(d) 見つけた事', () {
    test('(BK-d1) ログインした人を書く：前が空か別の人なら、人の印の無い前の形の印を消す・同じ人なら残す・人の印の付いた印は残す', () async {
      Map<String, Object> marks(String? user) => {
            if (user != null) 'user_id': user,
            'report_done_day': '2026-10-14|done',
            'report_done_night': '2026-10-13|done|U1',
            'shift_type': 'night',
            'shift_business_date': '2026-10-13',
          };
      Future<SharedPreferences> run(String? before, String after) async {
        SharedPreferences.setMockInitialValues(marks(before));
        final prefs = await SharedPreferences.getInstance();
        await saveLoginUserId(prefs, after);
        expect(prefs.getString('user_id'), after);
        return prefs;
      }

      final same = await run('U1', 'U1');
      expect(same.getString('report_done_day'), '2026-10-14|done', reason: '同じ人の前の形の印を消した');
      expect(same.getString('shift_type'), 'night');
      final other = await run('U1', 'U2');
      expect(other.getString('report_done_day'), isNull, reason: '前の人の前の形の印を、次の人に残した');
      expect(other.getString('shift_type'), isNull);
      expect(other.getString('shift_business_date'), isNull);
      expect(other.getString('report_done_night'), '2026-10-13|done|U1', reason: '人の印の付いた印を消した');
      final empty = await run(null, 'U1');
      expect(empty.getString('report_done_day'), isNull, reason: '前が空なのに前の形の印を残した');
      // 消せない時（字でない値＝読むと投げる）も書く・控えに残す。
      SharedPreferences.setMockInitialValues({'user_id': 'U1', 'report_done_day': 5});
      final prefs = await SharedPreferences.getInstance();
      await saveLoginUserId(prefs, 'U2');
      expect(prefs.getString('user_id'), 'U2', reason: '消せないとログインを止めた');
      expect(await errorKinds(), ['unowned_marks_clear']);
      // 書く前の 'user_id' を読めない時（字でない値）：空として扱う＝前の形の印を消してから書く（ログインを止めない）。
      SharedPreferences.setMockInitialValues({'user_id': 7, 'report_done_day': '2026-10-14|done'});
      final p2 = await SharedPreferences.getInstance();
      await saveLoginUserId(p2, 'U3');
      expect(p2.getString('user_id'), 'U3', reason: '書く前を読めないとログインを止めた');
      expect(p2.getString('report_done_day'), isNull, reason: '書く前を読めないのに、前の形の印を残した');
    });

    test("(BK-d2) 'user_id' を書く所は1本・4か所はその1本を呼ぶ（ソースの字）", () {
      var writers = 0;
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        writers += "setString('user_id'".allMatches(_codeOnly(f.path)).length;
      }
      expect(writers, 1, reason: "'user_id' を書く所が1本でない");
      expect(_codeOnly('lib/utils/today_marks.dart').contains("await prefs.setString('user_id', userId);"), isTrue);
      expect('await saveLoginUserId('.allMatches(_codeOnly(_login)).length, 2);
      expect('await saveLoginUserId('.allMatches(_codeOnly('lib/screens/recovery_screen.dart')).length, 1);
      expect('await saveLoginUserId('.allMatches(_codeOnly('lib/screens/register_screen.dart')).length, 1);
    });

    test('(BK-d3) 資格を付けずに送った頼みの締め出しの答え：今の資格が在れば締め出さない・無ければ締め出す（二者比較）', () async {
      Future<void> answer() => runApiCall<Map<String, dynamic>>('Test', () async {
            final req = http.Request('GET', Uri.parse('$kApiBaseUrl/reports/today'));
            return http.Response('{"error":"x","code":"NO_TOKEN"}', 401,
                request: req, headers: const {'content-type': 'application/json; charset=utf-8'});
          }, apiJsonMap);
      SharedPreferences.setMockInitialValues({'auth_token': 'token-now', 'user_id': 'U1', 'user_name': '今の人'});
      resetLockoutGuardForTest();
      await answer();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'token-now', reason: '資格を付けない頼みの答えで、今の人を締め出した');
      expect(prefs.getString('user_name'), '今の人');
      expect(await takeLockoutReason(), isNull);
      // 今の資格が無い（もうログアウトしている）→ 締め出す（理由を残す）。
      //   ★多重の鍵は戻さずに続ける（締め出さなかった空の資格の答えが鍵に残ると、ここで止まって理由を残さない）。
      await prefs.remove('auth_token');
      await answer();
      expect(await takeLockoutReason(), isNotNull, reason: '今の資格が無いのに理由を残さない（空の資格が多重の鍵に残った）');
      // 今の資格を読めない時（字でない値）→ 締め出す側に倒す・控えに残す。
      SharedPreferences.setMockInitialValues({'auth_token': 5, 'user_id': 'U1'});
      resetLockoutGuardForTest();
      await answer();
      expect(await takeLockoutReason(), isNotNull, reason: '今の資格を読めないのに締め出さない');
      expect((await errorKinds()).contains('lockout_token_read'), isTrue);
    });

    test('(BK-d4) 同じ日報を2回作らせない印：今日の日報を送る本文に client_report_id（日報の id）・後から出す日報には付けない・重なりの 200 は送れた事', () async {
      final seen = <http.Request>[];
      await _withServer(seen, [500, 200], () async {
        expect(await ReportStore.instance.addReport(_item('1791974555249128')), isFalse);
        await ReportStore.instance.retryPending();
      }, bodyOf: (status, n) => status == 200
          ? {'success': true, 'message': '日報を受信しました', 'report_id': 'r-1', 'duplicate': true}
          : {'error': 'サーバーエラー'});
      expect(seen.length, 2);
      for (final r in seen) {
        expect(jsonDecode(r.body)['client_report_id'], '1791974555249128', reason: '送る本文に印が無い・日報の id でない');
      }
      expect(await _box(), isEmpty, reason: '重なりの 200（duplicate）を送れた事にしない');
      // 本文の組み方（後から出す日報も使う）には付けない（二者比較）。
      final item = _item('x1');
      expect(reportBodyFor(item).containsKey('client_report_id'), isFalse);
      expect(permittedReportBodyFor(item, confirmationId: 'c1').containsKey('client_report_id'), isFalse);
    });

    test('(BK-d5) 駐車料金と駐車場の写真：帯が出ている時だけ送る・数える（今日の日報と後から出す日報・ソースの字）', () {
      final home = _flat(_codeOnly(_home));
      expect(home.contains('final parkingShown = reportParkingVisible(_transports, _carType);'), isTrue);
      expect(home.contains('parkingFee: parkingShown ? parkingFeeValue : null,'), isTrue);
      expect(home.contains('parkingPhotoPaths: parkingShown ? _parkingPhotoPaths : const <String>[],'), isTrue);
      final late = _flat(_codeOnly(_late));
      expect(late.contains('final parkingShown = reportParkingVisible(_transports, _carType);'), isTrue);
      expect(late.contains('parkingFee: parkingShown ? reportParkingFeeValue(_parkingCtrl.text) : null,'), isTrue);
      expect(late.contains('parkingPhotoPaths: parkingShown ? _parkingPhotoPaths : const <String>[],'), isTrue);
      expect(late.contains('if (photos.length < item.workPhotoPaths.length + item.parkingPhotoPaths.length) {'), isTrue,
          reason: '隠れた帯の写真を数えている');
      expect(late.contains('jsonEncode(body), item.workPhotoPaths, item.parkingPhotoPaths, ]);'), isTrue,
          reason: '届いたか分からなかった回と比べる字に、隠れた帯の写真が入る');
      // 確認の画面の材料（二者比較：相乗りで隠れる・社用車・自家用車で出る）。
      ReportSnapshot snap(String carType) => reportSnapshotFrom(
            dateLabel: 'd',
            shiftLabel: 's',
            siteId: null,
            siteName: null,
            originType: 'home',
            transports: {TransportType.car},
            carType: carType,
            routeComparisons: const {},
            parkingText: '800',
            carpoolCompanyText: '',
            carpoolNameText: '',
            workText: '',
            workPhotoCount: 0,
            parkingPhotoCount: 2,
          );
      expect(snap('carpool').parkingFeeRaw, '');
      expect(snap('carpool').parkingPhotoCount, 0);
      expect(snap('own').parkingFeeRaw, '800');
      expect(snap('own').parkingPhotoCount, 2);
    });

    test('(BK-d6) カレンダーの1日ぶんの中身の説明は class の上・見えない日の決まりの説明は自分の事だけ（ソースの字）', () {
      final lines = File(_home).readAsLinesSync();
      final iClass = lines.indexWhere((l) => l.startsWith('class CalendarDayInfo {'));
      final iFn = lines.indexWhere((l) => l.startsWith('bool calendarDayReportsUnknown({'));
      expect(iClass > 0 && iFn > 0, isTrue);
      // class の上の説明の塊に「カレンダーの1日ぶんの中身。」が在る。
      var j = iClass - 1;
      final classDoc = <String>[];
      while (j >= 0 && lines[j].startsWith('///')) {
        classDoc.add(lines[j]);
        j--;
      }
      expect(classDoc.any((l) => l.contains('カレンダーの1日ぶんの中身。')), isTrue, reason: 'class の上に説明が無い');
      var k = iFn - 1;
      final fnDoc = <String>[];
      while (k >= 0 && lines[k].startsWith('///')) {
        fnDoc.add(lines[k]);
        k--;
      }
      expect(fnDoc.any((l) => l.contains('カレンダーの1日ぶんの中身。')), isFalse, reason: '決まりの説明に class の説明が付いたまま');
      expect(fnDoc.last.startsWith('/// その日の日報が取れていない'), isTrue);
    });
  });
}
