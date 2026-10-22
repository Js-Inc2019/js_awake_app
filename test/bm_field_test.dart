// ============================================================
// test/bm_field_test.dart
//   便BM（見本 claude/field_refused_today_mock_v1.html の ②③・claude/field_close_date_remove_mock_v1.html の (41)(42)(44)・
//   ボスの裁定【Q150】【Q151】【Q152】【Q153】＝１・見つけた事 (43)）の職人アプリの直しを、機械で見張る検査。
//
// ★掟: 期待の字・数はこの本の中に直に書く（実装の字の定数は import しない）。二者比較（あり／なし）で見る。
//   端末の保存は SharedPreferences の偽物。シェル（JsMainShell）は検査で立てられない（通知・位置・通信の部品が多い）ので、
//   シェルの繋ぎはソースの字で見る（説明の行は除く＝_codeOnly）＝便BK の test/bk_field_test.dart と同じ流儀。
// ★検査の名前の頭の番号（(BM-a1) ほか）は、ログの赤い行からどの検査かを機械で読むための物。
// ============================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/core/report_send_texts.dart';
import 'package:js_awake_app/core/theme/app_theme.dart';
import 'package:js_awake_app/main.dart' show ReportStore;
import 'package:js_awake_app/screens/after_report_screen.dart';
import 'package:js_awake_app/screens/pending_reports_screen.dart';
import 'package:js_awake_app/screens/punch_screen.dart';
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';
import 'package:js_awake_app/utils/business_date.dart';
import 'package:js_awake_app/utils/pending_view.dart';

// ── 本の場所 ─────────────────────────────────────────────────────
const String _home = 'lib/screens/home_screen.dart';
const String _punch = 'lib/screens/punch_screen.dart';

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

/// ホームの打刻の画面に渡す偽物（本日休みの状態だけを答える・便BK の検査と同じ）。
class _FakeReports extends ReportsService {
  _FakeReports() : super.forTest();

  @override
  Future<ApiResult<RestDayToday>> getRestDayToday() async => apiSuccess<RestDayToday>(
        statusCode: 200,
        data: const RestDayToday(rested: false, reason: null, portion: 'full'),
      );
}

const _rowA = PendingReportRow(id: 'a', shiftType: 'day', businessDate: '2026-10-15', refusedMessage: '有効な所属がありません');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'T', 'user_id': 'U1', 'user_name': '検査 太郎'});
    ReportStore.instance.pendingView.value = const PendingView();
  });

  // ══════════════════════════════════════════════════════════
  // (a) 数の決まり（見本 claude/field_close_date_remove_mock_v1.html の「決めた所」）
  // ══════════════════════════════════════════════════════════
  group('(a) 数の決まり', () {
    test('(BM-a1) 数と単位：N件・N件以上・件数不明・読めなかった時は件数不明（見出しの字も同じ決まり）', () {
      String show(PendingCountLabel c) => '${c.number}|${c.unit}|${c.text}';
      expect(show(pendingCountLabel(2, unknown: false)), '2|件|2件');
      expect(show(pendingCountLabel(2, unknown: true)), '2|件以上|2件以上');
      expect(show(pendingCountLabel(0, unknown: true)), 'null|件数不明|件数不明');
      expect(show(pendingCountLabel(3, unknown: false, readFailed: true)), 'null|件数不明|件数不明',
          reason: '読めなかった時に前に読めた数を出した（少なく見せうる）');
      expect(show(pendingCountLabel(3, unknown: true, readFailed: true)), 'null|件数不明|件数不明');
      // 送った後の画面の見出しの字（二者比較＝読めた時は今までの字）。
      expect(pendingSectionCountLabel(2, unknown: false), '2件');
      expect(pendingSectionCountLabel(2, unknown: true), '2件以上');
      expect(pendingSectionCountLabel(0, unknown: true), '件数不明');
      expect(pendingSectionCountLabel(2, unknown: false, readFailed: true), '件数不明');
    });

    test('(BM-a2) ホームの行の数：今の人の日報（今日の分も）と読めない行・読めない箱は「以上」・読めなかった時も行を出す', () {
      String? show(PendingView v) {
        final c = homePendingCountOf(v);
        return c == null ? null : '${c.number}|${c.unit}';
      }

      const today = PendingReportRow(id: 't', shiftType: 'day', businessDate: '2026-10-19');
      expect(show(const PendingView()), isNull, reason: '何も無いのに行を出した');
      expect(show(const PendingView(own: [today])), '1|件');
      expect(show(const PendingView(own: [today, _rowA])), '2|件', reason: '今日の分かほかの日の分を数えていない');
      expect(show(const PendingView(unreadableRows: 2)), '2|件');
      expect(show(const PendingView(own: [today], unreadableRows: 1)), '2|件');
      expect(show(const PendingView(own: [today], unreadableBoxes: 1)), '1|件以上');
      expect(show(const PendingView(unreadableBoxes: 1)), 'null|件数不明');
      expect(show(const PendingView(readFailed: true)), 'null|件数不明', reason: '読めなかった事を黙った（行を出さない）');
      expect(show(const PendingView(own: [today, _rowA], readFailed: true)), 'null|件数不明');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (b) ホームの要対応の「未送信日報」の行と、本日休みの窓（見本 ②③）
  // ══════════════════════════════════════════════════════════
  group('(b) ホーム', () {
    Future<void> pumpPunch(WidgetTester tester,
        {PendingCountLabel? count,
        VoidCallback? onOpen,
        int revisionCount = 0,
        bool Function()? isReportDone,
        bool Function()? isTodayPending}) async {
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
          revisionCount: revisionCount,
          onOpenRevisions: () {},
          pendingReportsCount: count,
          onOpenPendingReports: onOpen,
          isReportDone: isReportDone,
          isTodayPending: isTodayPending,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('(BM-b1) 行：名前と数（数＝20・単位＝11）・高さ 56・数が無い時は行を出さない（二者比較）', (tester) async {
      await pumpPunch(tester, count: const PendingCountLabel('2', '件'), onOpen: () {});
      expect(find.text('未送信日報'), findsOneWidget);
      final n = tester.widget<Text>(find.text('2'));
      expect(n.style?.fontSize, 20);
      final u = tester.widget<Text>(find.descendant(
          of: find.ancestor(of: find.text('未送信日報'), matching: find.byType(Row)).first,
          matching: find.text('件')));
      expect(u.style?.fontSize, 11);
      final row = tester.getRect(find.ancestor(of: find.text('未送信日報'), matching: find.byType(SizedBox)).first);
      expect(row.height, 56, reason: '行の高さが差し戻しの行と違う');
      await pumpPunch(tester, count: null, onOpen: () {});
      expect(find.text('未送信日報'), findsNothing, reason: '数が無いのに行を出した');
    });

    testWidgets('(BM-b2) 行の数の字：N件以上は数＋「件以上」・件数不明は1つの字（13・太字）', (tester) async {
      await pumpPunch(tester, count: const PendingCountLabel('2', '件以上'), onOpen: () {});
      expect(find.text('2'), findsOneWidget);
      expect(find.text('件以上'), findsOneWidget);
      await pumpPunch(tester, count: const PendingCountLabel(null, '件数不明'), onOpen: () {});
      final k = tester.widget<Text>(find.text('件数不明'));
      expect(k.style?.fontSize, 13);
      expect(k.style?.fontWeight, FontWeight.w600);
      expect(find.text('件'), findsNothing, reason: '件数不明の時に「件」を足した');
    });

    testWidgets('(BM-b3) 行は要対応の一番上（差し戻しの行より上）・押すと開く口を呼ぶ', (tester) async {
      var opened = 0;
      await pumpPunch(tester,
          count: const PendingCountLabel('1', '件'), onOpen: () => opened++, revisionCount: 1);
      final pending = tester.getRect(find.text('未送信日報'));
      final revision = tester.getRect(find.text('差し戻し'));
      expect(pending.top < revision.top, isTrue, reason: '未送信日報の行が差し戻しの行より上に無い');
      // 今までの呼び手（差し戻し）の数と単位は今までどおり（数＝20・「件」＝11）＝未送信日報の行と並べた二者比較。
      final revRow = find.ancestor(of: find.text('差し戻し'), matching: find.byType(Row)).first;
      final revN = tester.widget<Text>(find.descendant(of: revRow, matching: find.text('1')));
      final revU = tester.widget<Text>(find.descendant(of: revRow, matching: find.text('件')));
      expect(revN.style?.fontSize, 20, reason: '差し戻しの行の数の字が替わった');
      expect(revU.style?.fontSize, 11, reason: '差し戻しの行の「件」が替わった');
      await tester.tap(find.text('未送信日報'));
      await tester.pumpAndSettle();
      expect(opened, 1, reason: '押しても開く口を呼ばない');
    });

    testWidgets('(BM-b4) 本日休みの窓：今日の分に未送信が在る時だけ題と本文を替える（二者比較・押した瞬間に読む）', (tester) async {
      var pending = true;
      await pumpPunch(tester, isReportDone: () => true, isTodayPending: () => pending);
      await tester.tap(find.text('本日休み'));
      await tester.pumpAndSettle();
      expect(find.text('本日の日報に未送信があります'), findsOneWidget);
      expect(find.text('未送信の日報は、届くまで送り直しを続けます。休みとして登録しますか？'), findsOneWidget);
      expect(find.text('本日は報告済みです'), findsNothing);
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      pending = false;
      await tester.tap(find.text('本日休み'));
      await tester.pumpAndSettle();
      expect(find.text('本日は報告済みです'), findsOneWidget);
      expect(find.text('本日は既に日報を提出済みです。休みとして登録しますか？'), findsOneWidget);
      expect(find.text('本日の日報に未送信があります'), findsNothing);
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
    });
  });

  // ══════════════════════════════════════════════════════════
  // (c) 「未送信日報」の画面（見本 ②・決めた所）
  // ══════════════════════════════════════════════════════════
  group('(c) 未送信日報の画面', () {
    final removed = <String>[];
    var removedUnreadable = 0;
    var retried = 0;

    // ★姿は ReportStore.instance.pendingView に直に置く（画面はそれを聞く）。箱の読み直しの列は ReportStore の1つの鎖で、
    //   偽の時計の検査をまたぐと前の検査の時計に繋がったまま進まない＝箱を読ませる形にすると、検査の並びで結果が替わる。
    //   開いた時に読み直す事は (BM-c8) でソースの字で見る。
    Future<void> show(WidgetTester tester, PendingView v, {String shift = 'day'}) async {
      removed.clear();
      removedUnreadable = 0;
      retried = 0;
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: PendingReportsScreen(
          shiftType: shift,
          onRemoveRow: (r) async => removed.add(r.id),
          onRemoveUnreadable: () async => removedUnreadable++,
          onRetry: () async => retried++,
        ),
      ));
      await tester.pumpAndSettle();
      ReportStore.instance.pendingView.value = v;
      await tester.pumpAndSettle();
    }

    String md(String biz) {
      final p = biz.split('-');
      return '${int.parse(p[1])}/${int.parse(p[2])}';
    }

    // ★今日の業務日は、検査ごとに、その検査の中で求める（登録した時に求めると、走らせている間に日をまたいだ時に赤になる）。
    PendingReportRow row(String id, String biz, {String shift = 'day', String? refused}) =>
        PendingReportRow(id: id, shiftType: shift, businessDate: biz, refusedMessage: refused);

    testWidgets('(BM-c1) 今日の分の行を上に・今日の分に「外す」は無い・ほかの日の受け付けなかった行だけ「外す」・再送1つ・※2つ',
        (tester) async {
      final todayBiz = businessDateForShift('day', DateTime.now());
      final todayMd = md(todayBiz);
      await show(
          tester,
          PendingView(own: [
            row('old-net', '2026-10-13'),
            row('old-ref', '2026-10-14', refused: '有効な所属がありません'),
            row('today-ref', todayBiz, refused: '有効な所属がありません'),
          ]));
      expect(find.text('未送信日報'), findsOneWidget, reason: '画面の題が無い');
      final todayTitle = find.text('☀日勤 $todayMd分');
      expect(todayTitle, findsOneWidget);
      expect(find.text('☀日勤 10/14分'), findsOneWidget);
      expect(find.text('☀日勤 10/13分'), findsOneWidget);
      // 並び：今日の分が上・ほかの日は箱の並び（10/13 → 10/14）。
      final yT = tester.getRect(todayTitle).top;
      final y13 = tester.getRect(find.text('☀日勤 10/13分')).top;
      final y14 = tester.getRect(find.text('☀日勤 10/14分')).top;
      expect(yT < y13 && y13 < y14, isTrue, reason: '今日の分が上・ほかは箱の並び、になっていない');
      // 「外す」は 10/14（受け付けなかった・今日でない）だけ。
      expect(find.text('外す'), findsOneWidget, reason: '今日の分か、通信で送れていない行に「外す」を付けた');
      final remove = tester.getRect(find.text('外す'));
      expect(remove.top > y13, isTrue, reason: '「外す」が 10/14 の行に無い');
      final btn = tester.getRect(find.widgetWithText(OutlinedButton, '外す'));
      expect(btn.height >= 44 && btn.width >= 64, isTrue, reason: '「外す」が触れる大きさでない');
      await tester.tap(find.text('外す'));
      await tester.pumpAndSettle();
      expect(removed, ['old-ref'], reason: '「外す」が、その行を渡さない');
      // 字（今の送った後の画面と同じ字）。
      expect(find.text('提出できません（有効な所属がありません）'), findsNWidgets(2));
      expect(find.text('通信状況により未送信です'), findsOneWidget);
      // 「今すぐ再送する」は1つ・※は会社の※と外した※（読めない※は無い）。
      expect(find.text('今すぐ再送する'), findsOneWidget);
      await tester.tap(find.text('今すぐ再送する'));
      await tester.pumpAndSettle();
      expect(retried, 1, reason: '「今すぐ再送する」が口を呼ばない');
      expect(find.text('※会社のご担当者にご確認ください。'), findsOneWidget);
      expect(find.text('※外した日報は送信されません。管理・履歴のカレンダーに「日報漏れを申告する」が出ている日は、そこから出し直しを申告できます。'),
          findsOneWidget);
      expect(find.text('※日報の無い日は、管理・履歴のカレンダーで確かめられます。'), findsNothing);
      expect(find.text('未送信日報はありません'), findsNothing);
    });

    testWidgets('(BM-c2) 今日の分の受け付けなかった行だけ：「外す」も外した※も無い・会社の※は出る（二者比較は c1）', (tester) async {
      final todayBiz = businessDateForShift('day', DateTime.now());
      final todayMd = md(todayBiz);
      await show(tester, PendingView(own: [row('today-ref', todayBiz, refused: '有効な所属がありません')]));
      expect(find.text('☀日勤 $todayMd分'), findsOneWidget);
      expect(find.text('外す'), findsNothing, reason: '今日の分に「外す」を付けた（④ 案１）');
      expect(find.text('※会社のご担当者にご確認ください。'), findsOneWidget);
      expect(find.textContaining('※外した日報は'), findsNothing, reason: '外せる行が無いのに外した※を出した');
      expect(find.text('今すぐ再送する'), findsOneWidget);
    });

    testWidgets('(BM-c3) 夜勤の画面：今日の分は夜勤の今の業務日（日勤の今日の行はほかの日の側＝外せる）', (tester) async {
      final now = DateTime.now();
      final todayBiz = businessDateForShift('day', now);
      final todayMd = md(todayBiz);
      final nightBiz = businessDateForShift('night', now);
      await show(
          tester,
          PendingView(own: [
            row('day-today', todayBiz, refused: '有効な所属がありません'),
            row('night-today', nightBiz, shift: 'night', refused: '有効な所属がありません'),
          ]),
          shift: 'night');
      final yN = tester.getRect(find.text('🌙夜勤 ${md(nightBiz)}分')).top;
      final yD = tester.getRect(find.text('☀日勤 $todayMd分')).top;
      expect(yN < yD, isTrue, reason: '夜勤の画面で夜勤の今日の分が上に無い');
      expect(find.text('外す'), findsOneWidget, reason: 'もう一方の勤務の行を外せない・今日の分を外せる');
      await tester.tap(find.text('外す'));
      await tester.pumpAndSettle();
      expect(removed, ['day-today']);
    });

    testWidgets('(BM-c4) 読み込めない日報：行と「外す」と読めない※・今の人の日報が無ければ「今すぐ再送する」は出ない', (tester) async {
      await show(tester, const PendingView(unreadableRows: 1, unreadableBoxes: 1));
      expect(find.text('読み込めない日報（件数不明）'), findsOneWidget);
      expect(find.text('内容を読み込めないため、送信されません'), findsOneWidget);
      expect(find.text('※日報の無い日は、管理・履歴のカレンダーで確かめられます。'), findsOneWidget);
      expect(find.text('今すぐ再送する'), findsNothing, reason: '送れる日報が無いのに再送を出した');
      expect(find.text('※会社のご担当者にご確認ください。'), findsNothing, reason: '受け付けなかった行が無いのに会社の※を出した');
      await tester.tap(find.text('外す'));
      await tester.pumpAndSettle();
      expect(removedUnreadable, 1, reason: '読み込めない日報の「外す」が口を呼ばない');
    });

    testWidgets('(BM-c5) 0件：「未送信日報はありません」（絵つき）・読めなかった時は※だけで「ありません」と言わない（二者比較）',
        (tester) async {
      await show(tester, const PendingView());
      expect(find.text('未送信日報はありません'), findsOneWidget);
      expect(find.byIcon(Icons.inbox), findsOneWidget);
      expect(find.text('※送信状況を読み込めませんでした。'), findsNothing);
      ReportStore.instance.pendingView.value = const PendingView(readFailed: true);
      await tester.pumpAndSettle();
      expect(find.text('※送信状況を読み込めませんでした。'), findsOneWidget);
      expect(find.text('未送信日報はありません'), findsNothing, reason: '読めなかったのに「ありません」と言った');
    });

    testWidgets('(BM-c6) 読めなかった時：頭に※・前に読めた時の行は出したまま（二者比較）', (tester) async {
      final v = PendingView(own: [row('old-ref', '2026-10-14', refused: '有効な所属がありません')]);
      await show(tester, v);
      expect(find.text('※送信状況を読み込めませんでした。'), findsNothing);
      ReportStore.instance.pendingView.value = v.copyWith(readFailed: true);
      await tester.pumpAndSettle();
      final note = tester.getRect(find.text('※送信状況を読み込めませんでした。'));
      final r = tester.getRect(find.text('☀日勤 10/14分'));
      expect(note.bottom <= r.top, isTrue, reason: '※が頭に無い');
    });

    testWidgets('(BM-c7) 姿を聞く：届いて0件になると「未送信日報はありません」に替わる', (tester) async {
      await show(tester, PendingView(own: [row('old-net', '2026-10-14')]));
      expect(find.text('☀日勤 10/14分'), findsOneWidget);
      expect(find.text('※会社のご担当者にご確認ください。'), findsNothing, reason: '通信で送れていない行だけなのに会社の※を出した');
      expect(find.textContaining('※外した日報は'), findsNothing, reason: '外せる行が無いのに外した※を出した');
      ReportStore.instance.pendingView.value = const PendingView();
      await tester.pumpAndSettle();
      expect(find.text('☀日勤 10/14分'), findsNothing);
      expect(find.text('未送信日報はありません'), findsOneWidget);
    });

    test('(BM-c8) 開いた時に箱を読み直す（initState で refreshPendingCount・ソースの字）', () {
      final f = _flat(_bodyOf(_codeOnly('lib/screens/pending_reports_screen.dart'), 'void initState()'));
      expect(f, contains('super.initState(); ReportStore.instance.refreshPendingCount();'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // (d) 字（見本 ③・(41)・(44)）と、送った後の画面の見出しの数
  // ══════════════════════════════════════════════════════════
  group('(d) 字', () {
    test('(BM-d1) 窓の字：未送信が在る時の題と本文・締めの窓の1行目（業務日と勤務区分）・外すの窓の2行目と※（いつも事実になる字）', () {
      expect(kTodayPendingTitle, '本日の日報に未送信があります');
      expect(kSecondReportPendingBody, '未送信の日報は、届くまで送り直しを続けます。2件目を作成しますか？');
      expect(kRestDayPendingBody, '未送信の日報は、届くまで送り直しを続けます。休みとして登録しますか？');
      expect(closeTodayLine1('day', '2026-10-19'), '締めると、10/19の日勤の2件目の日報は作れなくなります。');
      expect(closeTodayLine1('night', '2026-10-05'), '締めると、10/5の夜勤の2件目の日報は作れなくなります。');
      expect(removePendingLine2('2026-10-15'),
          '管理・履歴のカレンダーの10/15に「日報漏れを申告する」が出ていれば、そこから出し直しを申告できます。');
      expect(kRemovedReportNote,
          '※外した日報は送信されません。管理・履歴のカレンダーに「日報漏れを申告する」が出ている日は、そこから出し直しを申告できます。');
      expect(kPendingEmptyText, '未送信日報はありません');
    });

    testWidgets('(BM-d2) 送った後の画面の見出しの数：読めなかった時は「件数不明」（二者比較）', (tester) async {
      Future<void> pumpAfter(bool readFailed) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AfterReportBody(
                key: UniqueKey(),
                workerName: '山田',
                sent: true,
                shiftType: 'day',
                onOvertime: () async {},
                onRetry: () {},
                onClose: () {},
                pendingReadFailed: readFailed,
                otherRows: const [_rowA],
                onRemoveRow: (_) async {},
                onRemoveUnreadable: () async {},
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
      }

      await pumpAfter(false);
      expect(find.text('1件'), findsOneWidget);
      expect(find.text('件数不明'), findsNothing);
      await pumpAfter(true);
      expect(find.text('件数不明'), findsOneWidget, reason: '読めなかったのに前に読めた数を出した');
      expect(find.text('1件'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (e) シェルの繋ぎ（ソースの字・シェルは検査で立てられない）と説明文 (43)
  // ══════════════════════════════════════════════════════════
  group('(e) シェルの繋ぎ', () {
    test('(BM-e1) 2件目の窓：今日の分に未送信が在る時だけ題と本文を替える・今日の分は pendingTodayRows の1本（ソースの字）', () {
      final src = _codeOnly(_home);
      final f = _flat(_bodyOf(src, 'Future<bool> _confirmSecondReportIfNeeded()'));
      expect(f, contains('final pending = _todayHasPending;'));
      expect(f, contains("Text(pending ? kTodayPendingTitle : '本日は報告済みです',"));
      expect(f, contains("Text(pending ? kSecondReportPendingBody : '本日の日報は提出済みです。2件目を作成しますか？',"));
      final i = src.indexOf('bool get _todayHasPending =>');
      expect(i, greaterThan(0), reason: '今日の分に未送信が在るかを読む所が無い');
      final g = _flat(src.substring(i, src.indexOf(';', i) + 1));
      // 元: now: DateTime.now()。→再（2026-10-21・便BN・下調べの ■4）: 今は businessNow()（業務日の真実源の本の今の口）。
      expect(g, contains('pendingTodayRows(ReportStore.instance.pendingView.value, shiftType: _shiftType, now: businessNow()) .isNotEmpty;'));
    });

    test('(BM-e2) 締めの窓の1行目：締める業務日と勤務区分（_saveWorkStatus が書く物と同じ物差し）（ソースの字）', () {
      final f = _flat(_bodyOf(_codeOnly(_home), 'Future<void> _onCloseToday()'));
      // 元: 窓の字は窓を組む時の業務日（closeTodayLine1(_shiftType, businessDateForShift(_shiftType, DateTime.now()))）で、締める印は
      //   _saveWorkStatus の中で押した時の業務日＝窓を開いたまま業務日が替わると、字と違う日を締めた（見つけた事 (45)）。
      // →再（2026-10-21・便BN・下調べの ■1）: 窓の字と締める印の両方を、出している印（_shownMark）の1つの値で出す＝同じ物差し。
      expect(f, contains('final m = _shownMark;'));
      expect(f, contains(r"'${closeTodayLine1(m.shift, m.bizDate)}\n'"));
      expect(f, contains("await _saveWorkStatus('closed', shiftType: m.shift, bizDate: m.bizDate);"));
      expect(f, contains("setState(() => _setMark(m.shift, m.bizDate, 'closed'));"));
      expect(f, contains("'残業や休憩の申告はこのあとも行えます。'"));
      expect(f, isNot(contains('次の現場へ移動')), reason: '今の作りと違う字が残っている');
      final src = _codeOnly(_home);
      final i = src.indexOf('Future<void> _saveWorkStatus(String status,');
      expect(i, greaterThan(0));
      final w = _flat(src.substring(i, src.indexOf('Future<String?> _readWorkStatusOn(', i)));
      // 渡さない時は今のとおり、今の _shiftType と今の業務日（業務日の真実源の本の今の口）。
      expect(w, contains('final shift = shiftType ?? _shiftType; final biz = bizDate ?? businessDateForShift(shift, businessNow());'));
      expect(w, contains("final ok = await prefs.setString(reportDoneKey(shift), reportDoneValue(biz, status, who));"));
    });

    test('(BM-e3) 上の段の日付：どのタブも暦の日（管理・履歴のタブだけ業務日にしない）（ソースの字）', () {
      final f = _flat(_bodyOf(_codeOnly(_home), 'String get _dateLabel'));
      // 元: DateTime.now()。→再（2026-10-21・便BN・下調べの ■4）: 今は businessNow()。
      expect(f, contains("final ds = businessDateForShift('day', businessNow());"));
      expect(f, isNot(contains('_tabIndex')), reason: 'タブで日付の物差しを替えている');
    });

    test('(BM-e4) ホームの行と画面の口：数は homePendingCountOf・押すと PendingReportsScreen（外す・再送は送った後の画面と同じ口）（ソースの字）', () {
      final src = _flat(_codeOnly(_home));
      expect(src, contains('ValueListenableBuilder<PendingView>( valueListenable: ReportStore.instance.pendingView, '
          'builder: (_, pendingViewNow, __) => PunchScreen('));
      expect(src, contains('pendingReportsCount: homePendingCountOf(pendingViewNow),'));
      expect(src, contains('onOpenPendingReports: _openPendingReports,'));
      expect(src, contains('isTodayPending: () => _todayHasPending,'));
      final o = _flat(_bodyOf(_codeOnly(_home), 'Future<void> _openPendingReports()'));
      expect(o, contains('if (_pendingReportsOpen) return; _pendingReportsOpen = true; try {'),
          reason: '開いている間に、もう一度開く（同じ画面が2枚積まれる）');
      expect(o, contains('} finally { _pendingReportsOpen = false; }'), reason: '止めを外さない（2回目から開けない）');
      expect(o, contains('PendingReportsScreen( shiftType: _shiftType, onRemoveRow: _confirmRemovePending, '
          'onRemoveUnreadable: _confirmRemoveUnreadable, onRetry: _retryPendingNow, )'));
      expect(RegExp(r'onRetry: _retryPendingNow,').allMatches(src).length, 2,
          reason: '送った後の画面と「未送信日報」の画面の再送が、同じ口（_retryPendingNow）でない');
      expect(RegExp('✅ 再送しました').allMatches(src).length, 1, reason: '今すぐ再送の知らせが2つに割れた');
    });

    test('(BM-e5) 本日休みの窓と要対応の行（ソースの字）：押した瞬間に isTodayPending を読む・行は差し戻しの行より前', () {
      final src = _codeOnly(_punch);
      final g = _flat(_bodyOf(src, 'Future<bool> _restDayGuard()'));
      expect(g, contains('final pending = widget.isTodayPending?.call() == true;'));
      final iPending = src.indexOf('if (widget.pendingReportsCount != null)');
      final iRevision = src.indexOf('if (widget.revisionCount > 0)');
      expect(iPending > 0 && iPending < iRevision, isTrue, reason: '未送信日報の行が要対応の一番上でない');
    });

    test('(BM-e6) 説明文 (43)：「日報タブ」「フォームが自然に開く」「index1 を占有」の字は、元の説明として残す行だけ', () {
      const files = [
        'lib/services/fcm_service.dart',
        'lib/main.dart',
        'lib/screens/notification_list_screen.dart',
        'lib/screens/after_report_screen.dart',
        'lib/screens/home_screen.dart',
        'lib/screens/punch_screen.dart',
      ];
      final stale = RegExp(r'日報タブ|フォームが自然に開く|index1 を占有|の `_setTab\(1\)`');
      final bad = <String>[];
      for (final f in files) {
        final lines = File(f).readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (!l.trimLeft().startsWith('//')) continue;
          if (!stale.hasMatch(l)) continue;
          if (l.contains('元の説明') || l.contains('（元）')) continue;
          bad.add('$f:${i + 1}');
        }
      }
      expect(bad, isEmpty, reason: '今の作りと違う説明文が残っている');
    });
  });
}
