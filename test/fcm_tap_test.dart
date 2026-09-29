// ============================================================
// test/fcm_tap_test.dart — スマホの通知を押したときの行き先（便F12）
//
// 見ているのは「押したのに何も起きない（沈黙障害）」が残っていないか:
//   ① 振替休日の6種類は data の rest_day_id でその1件の画面（SubstituteDetailScreen）が開く
//   ② rest_day_id が無い・空なら、推測で別の休みを開かず、お知らせの一覧が開く
//   ③ 名簿に無い種類（rest_day_cancelled を含む）は、何もしないのをやめ、お知らせの一覧が開く
//      （日報のタブへは落ちない）
//   ④ 今までの行き先（report_remind → 日報のタブ・revision_request → 差し戻しの受け箱）は今のまま
//   ⑤ ログインしていなければ、どの種類でも何も開かない（今のまま）
//
// ★通信はしない。差し替え口は package:http の runWithClient + MockClient ただ1つ
//   （test/widget_test_report_test.dart・test/report_cancel_gate_test.dart と同じ方式）。
//   handleNotificationTap は画面を中で作るので、画面の service 引数は渡せない。
//   開いた画面が叩く口には http.Response('{}', 200) を返し、来た URL を控える。
// ★ログインの印は SharedPreferences の auth_token（AuthService.getToken が読むキー）。
// ★期待する種類の名・画面は実装から import した定数を使わず、ここへ直書きする
//   （kSubstituteNoticeTypes を import すると、名簿が減っても検査が一緒に減る）。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/screens/home_screen.dart' show ReportTabNavigator;
import 'package:js_awake_app/screens/notification_list_screen.dart'
    show NotificationListScreen;
import 'package:js_awake_app/screens/revision_inbox_screen.dart'
    show RevisionInboxScreen;
import 'package:js_awake_app/screens/substitute_detail_screen.dart'
    show SubstituteDetailScreen;
import 'package:js_awake_app/services/fcm_service.dart';

// BE が職人へ送る振替休日の知らせ6種類（BE services/notify.js の NOTICE_TYPES の値を直書き）。
const List<String> kSixSubstituteTypes = [
  'substitute_registered',
  'substitute_change_confirmed',
  'substitute_change_auto_settled',
  'substitute_change_blocked',
  'substitute_agree_remind',
  'substitute_change_withdrawn',
];

void main() {
  // 開いた画面が叩いた URL の path（MockClient が控える）。
  final requested = <String>[];
  MockClient okClient() => MockClient((req) async {
        requested.add(req.url.path);
        return http.Response('{}', 200,
            request: req, headers: {'content-type': 'application/json'});
      });

  // 日報のタブへ行ったかの印。★unregister は identical で見るので、同じ実体を渡す。
  var reportTabOpened = false;
  void onReportTab() => reportTabOpened = true;
  late VoidCallback reportHandler;

  setUp(() {
    requested.clear();
    reportTabOpened = false;
    reportHandler = onReportTab;
    ReportTabNavigator.register(reportHandler);
    SharedPreferences.setMockInitialValues({'auth_token': 'T'});
  });

  tearDown(() {
    ReportTabNavigator.unregister(reportHandler);
  });

  /// navigatorKey を持つ MaterialApp を立て、通知を押したときと同じ入口を呼ぶ。
  Future<void> tap(WidgetTester tester, Map<String, dynamic> data) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(MaterialApp(
          navigatorKey: FcmService.navigatorKey,
          home: const Scaffold(body: Text('home')),
        ));
        await FcmService().handleNotificationTap(data);
        await tester.pumpAndSettle();
      },
      okClient,
    );
  }

  group('① 振替休日の6種類 → その1件の画面', () {
    for (final type in kSixSubstituteTypes) {
      testWidgets('$type（rest_day_id=rd_9）→ SubstituteDetailScreen(restDayId: rd_9)',
          (tester) async {
        await tap(tester, {'type': type, 'rest_day_id': 'rd_9'});
        final found = find.byType(SubstituteDetailScreen);
        expect(found, findsOneWidget, reason: '1件の画面が開くこと');
        expect(tester.widget<SubstituteDetailScreen>(found).restDayId, 'rd_9',
            reason: 'data の rest_day_id の休みを開くこと（推測しない）');
        expect(requested.any((p) => p.endsWith('/rest-days/rd_9')), isTrue,
            reason: '開いた画面が GET /rest-days/rd_9 を叩くこと: $requested');
        expect(find.byType(NotificationListScreen), findsNothing);
        expect(reportTabOpened, isFalse, reason: '日報のタブへは行かない');
      });
    }
  });

  group('② rest_day_id が無い・空 → お知らせの一覧', () {
    testWidgets('rest_day_id が無い', (tester) async {
      await tap(tester, {'type': 'substitute_registered'});
      expect(find.byType(NotificationListScreen), findsOneWidget);
      expect(find.byType(SubstituteDetailScreen), findsNothing,
          reason: '推測で別の休みを開かない');
      expect(reportTabOpened, isFalse);
    });
    testWidgets('rest_day_id が空文字', (tester) async {
      await tap(tester, {'type': 'substitute_change_confirmed', 'rest_day_id': ''});
      expect(find.byType(NotificationListScreen), findsOneWidget);
      expect(find.byType(SubstituteDetailScreen), findsNothing);
      expect(reportTabOpened, isFalse);
    });
  });

  group('③ 名簿に無い種類 → お知らせの一覧（日報のタブへ落ちない）', () {
    for (final type in ['rest_day_cancelled', 'no_such_type']) {
      testWidgets(type, (tester) async {
        await tap(tester, {'type': type, 'rest_day_id': 'rd_9'});
        expect(find.byType(NotificationListScreen), findsOneWidget,
            reason: '何もしないのをやめ、お知らせの一覧へ');
        expect(find.byType(SubstituteDetailScreen), findsNothing,
            reason: 'rest_day_cancelled は休みの種類を問わないので振替の画面へは行かない');
        expect(reportTabOpened, isFalse, reason: 'report_remind の else へ落ちない');
      });
    }
  });

  group('④ 今までの行き先は今のまま', () {
    testWidgets('report_remind → 日報のタブ（お知らせの一覧は開かない）', (tester) async {
      await tap(tester, {'type': 'report_remind'});
      expect(reportTabOpened, isTrue);
      expect(find.byType(NotificationListScreen), findsNothing);
    });
    testWidgets('revision_request → RevisionInboxScreen', (tester) async {
      await tap(tester, {'type': 'revision_request'});
      expect(find.byType(RevisionInboxScreen), findsOneWidget);
      expect(find.byType(NotificationListScreen), findsNothing);
      expect(reportTabOpened, isFalse);
    });
  });

  group('⑤ ログインしていない → 何も開かない', () {
    for (final type in ['substitute_registered', 'no_such_type', 'report_remind']) {
      testWidgets(type, (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tap(tester, {'type': type, 'rest_day_id': 'rd_9'});
        expect(find.byType(SubstituteDetailScreen), findsNothing);
        expect(find.byType(NotificationListScreen), findsNothing);
        expect(find.byType(RevisionInboxScreen), findsNothing);
        expect(find.text('home'), findsOneWidget, reason: '元の画面のまま');
        expect(reportTabOpened, isFalse);
        expect(requested, isEmpty, reason: '通信も起きない');
      });
    }
  });
}
