// ============================================================
// test/future_date_limit_test.dart — 先の日の上限（便F12）
//
// 見ているのは2つ:
//   (b) 上限の関数（lib/utils/future_date_limit.dart）の答え。
//       今日から選べる最後の日は、移す前の式 DateTime(now.year + 1, now.month, now.day) の
//       値のまま（うるう日も含む）。カレンダーは、その最後の日を含む月まで送れる。
//       表示中の月の【日】は答えに効かない。
//   (c) 管理・履歴のカレンダー（CalendarTab）を立てて、今月を表示中に › が押せること。
//       ‹ › の押せる大きさは変えていないので、測って報告だけする（期待値は置かない）。
//
// ★期待する日付はここへ直書きする（実装の式をここで組み立て直さない）。
// ★(c) の通信は package:http の runWithClient + MockClient ただ1つ
//   （test/widget_test_report_test.dart が ManagementHistoryScreen を立てる形と同じ）。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/screens/home_screen.dart' show CalendarTab;
import 'package:js_awake_app/utils/future_date_limit.dart';

void main() {
  group('(b) 上限の関数', () {
    test('今日 2026-09-28 → 最後の日 2027-09-28', () {
      expect(lastSelectableDate(DateTime(2026, 9, 28)), DateTime(2027, 9, 28));
    });
    test('時刻つきの今日でも最後の日は日付だけ（移す前の式と同じ値）', () {
      expect(lastSelectableDate(DateTime(2026, 9, 28, 23, 59, 30)),
          DateTime(2027, 9, 28));
    });
    test('2027年8月を表示中なら次の月（9月）へ送れる', () {
      expect(canGoToNextMonth(
              shownMonth: DateTime(2027, 8, 1), today: DateTime(2026, 9, 28)),
          isTrue);
    });
    test('2027年9月を表示中なら送れない（10月は最後の日を含む月を越える）', () {
      expect(canGoToNextMonth(
              shownMonth: DateTime(2027, 9, 1), today: DateTime(2026, 9, 28)),
          isFalse);
    });
    test('今月（2026年9月）を表示中なら送れる', () {
      expect(canGoToNextMonth(
              shownMonth: DateTime(2026, 9, 1), today: DateTime(2026, 9, 28)),
          isTrue);
    });
    test('表示中の月の日が1日でなくても、1日で持つときと同じ答え', () {
      final today = DateTime(2026, 9, 28);
      expect(canGoToNextMonth(shownMonth: DateTime(2026, 9, 28), today: today),
          isTrue);
      expect(canGoToNextMonth(shownMonth: DateTime(2026, 9, 28), today: today),
          canGoToNextMonth(shownMonth: DateTime(2026, 9, 1), today: today));
      // 最後の月の月末の日で持っていても、送れない答えは変わらない。
      expect(canGoToNextMonth(shownMonth: DateTime(2027, 9, 30), today: today),
          isFalse);
    });
    test('年またぎ: 今日 2026-12-15・2026年12月を表示中 → 2027年1月へ送れる', () {
      expect(canGoToNextMonth(
              shownMonth: DateTime(2026, 12, 1), today: DateTime(2026, 12, 15)),
          isTrue);
    });
    test('うるう日: 今日 2028-02-29 → 最後の日は DateTime(2029, 2, 29)＝2029年3月1日と同じ', () {
      final last = lastSelectableDate(DateTime(2028, 2, 29));
      expect(last, DateTime(2029, 2, 29));
      expect(last, DateTime(2029, 3, 1));
    });
    test('うるう日: 2029年2月を表示中なら送れる・2029年3月を表示中なら送れない', () {
      final today = DateTime(2028, 2, 29);
      expect(canGoToNextMonth(shownMonth: DateTime(2029, 2, 1), today: today),
          isTrue);
      expect(canGoToNextMonth(shownMonth: DateTime(2029, 3, 1), today: today),
          isFalse);
    });
  });

  group('(c) CalendarTab の月送り', () {
    setUp(() {
      // AuthService.getToken が読むキー。無いと通信の手前で止まる。
      SharedPreferences.setMockInitialValues({'auth_token': 'T', 'company_id': 'C1'});
    });

    testWidgets('今月を表示中に › が押せる・‹ › の押せる大きさを測る', (tester) async {
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 1);
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: Scaffold(
            body: CalendarTab(),
          )));
          await tester.pumpAndSettle();
        },
        () => MockClient((req) async => http.Response('{}', 200,
            request: req, headers: {'content-type': 'application/json'})),
      );
      final ex = tester.takeException();
      // ★捨てた例外があれば中身を出す（報告に写すため）。
      // ignore: avoid_print
      print('CalendarTab を立てたときの例外: ${ex ?? 'なし'}');

      expect(find.text('${now.year}年${now.month}月'), findsOneWidget,
          reason: '今月を表示している');
      final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
      final prev = find.widgetWithIcon(IconButton, Icons.chevron_left);
      expect(tester.widget<IconButton>(next).onPressed, isNotNull,
          reason: '今月を表示中でも › が押せる（便F12）');
      expect(tester.widget<IconButton>(prev).onPressed, isNotNull,
          reason: '‹ は今のまま押せる');

      // ignore: avoid_print
      print('‹ の押せる大きさ: ${tester.getSize(prev)} / › の押せる大きさ: ${tester.getSize(next)}');

      await http.runWithClient(
        () async {
          await tester.tap(next);
          await tester.pumpAndSettle();
        },
        () => MockClient((req) async => http.Response('{}', 200,
            request: req, headers: {'content-type': 'application/json'})),
      );
      final ex2 = tester.takeException();
      // ignore: avoid_print
      print('› を押したときの例外: ${ex2 ?? 'なし'}');
      expect(find.text('${nextMonth.year}年${nextMonth.month}月'), findsOneWidget,
          reason: '› を押すと来月へ送れる');
    });
  });
}
