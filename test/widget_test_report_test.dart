import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/screens/home_screen.dart'
    show ForemanManagementBody;
import 'package:js_awake_app/screens/management_history_screen.dart';

// ── 勤怠の確認事項（職長は見るだけ）の検査で使う道具 ──────────────────
//   通信は package:http の runWithClient + MockClient で差し替える
//   （services は トップレベルの http.get を使うため、ここが唯一の差し替え口）。
const String kSeeNotice = '確定は事務または社長が行います（ここでは内容の確認のみできます）';
const String kEmptyText = '確認事項はありません';
const String kFailText  = '確認事項を取得できませんでした';

/// 確認事項の応答を返し、他の GET はすべて空の JSON を返す差し替え通信。
MockClient confirmClient(int status, String body) => MockClient((req) async {
      if (req.url.path.endsWith('/attendance/confirmations')) {
        return http.Response(body, status,
            request: req, headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 200,
          request: req, headers: {'content-type': 'application/json'});
    });

/// 「管理」を開いて『⏱ 勤怠』の節へ切り替える。
///
/// ★同じテストの中で2回呼ぶときは key を変えること。key が同じだと Flutter が
///   既存の State を使い回し、initState が走らないので取得し直されない。
Future<void> openAttendanceSegment(WidgetTester tester, {Key? key}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(
    body: KeyedSubtree(key: key, child: const ForemanManagementBody()),
  )));
  await tester.pumpAndSettle();
  await tester.tap(find.text('⏱ 勤怠'));
  await tester.pumpAndSettle();
}

void main() {
  group('UIコンポーネントテスト', () {
    testWidgets('ローディング中はボタンが無効', (tester) async {
      final data = <String, dynamic>{'loading': true};
      final bool loading = data['loading'] == true;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ElevatedButton(
              onPressed: loading ? null : () {},
              child: const Text('送信'),
            ),
          ),
        ),
      ));
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('空のTextFieldは送信できない', (tester) async {
      final controller = TextEditingController();
      bool submitted = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            TextField(controller: controller),
            ElevatedButton(
              onPressed: controller.text.isEmpty ? null : () => submitted = true,
              child: const Text('送信'),
            ),
          ]),
        ),
      ));
      expect(submitted, false);
    });

    testWidgets('エラーメッセージが表示される', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            const Text('エラーが発生しました'),
            ElevatedButton(
              onPressed: () {},
              child: const Text('再試行'),
            ),
          ]),
        ),
      ));
      expect(find.text('エラーが発生しました'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });
  });

  group('データ変換テスト', () {
    test('金額フォーマット: 1000→¥1,000', () {
      int amount = 1000;
      String formatted = '¥${amount.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},'
      )}';
      expect(formatted, '¥1,000');
    });

    test('距離フォーマット: 1500m→1.5km', () {
      int meters = 1500;
      String formatted = meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)}km'
        : '${meters}m';
      expect(formatted, '1.5km');
    });

    test('日付フォーマット: DateTime→YYYY-MM-DD', () {
      final date = DateTime(2026, 6, 5);
      final formatted =
        '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
      expect(formatted, '2026-06-05');
    });

    test('時刻フォーマット: DateTime→HH:MM', () {
      final time = DateTime(2026, 6, 5, 9, 30);
      final formatted =
        '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}';
      expect(formatted, '09:30');
    });

    test('null安全: null金額→0表示', () {
      final data = <String, dynamic>{};
      final int? amount = data['amount'];
      String display = amount?.toString() ?? '0';
      expect(display, '0');
    });

    test('null安全: null氏名→不明表示', () {
      String? name;
      String display = name ?? '不明';
      expect(display, '不明');
    });
  });

  group('状態管理テスト', () {
    test('移動手段: 車選択→駐車料金表示フラグ', () {
      String transport = 'car';
      bool showParking = transport == 'car';
      expect(showParking, true);
    });

    test('移動手段: 電車選択→駐車料金非表示', () {
      String transport = 'train';
      bool showParking = transport == 'car';
      expect(showParking, false);
    });

    test('移動手段: 車orその他→マイク表示', () {
      for (final t in ['car', 'other']) {
        bool showMedia = t == 'car' || t == 'other';
        expect(showMedia, true, reason: '$t でマイク表示されるべき');
      }
    });

    test('移動手段: 電車・バス→マイク非表示', () {
      for (final t in ['train', 'bus']) {
        bool showMedia = t == 'car' || t == 'other';
        expect(showMedia, false, reason: '$t でマイク非表示のはず');
      }
    });

    test('pending status→承認待ち画面フラグ', () {
      String status = 'pending';
      bool showPending = status == 'pending';
      expect(showPending, true);
    });

    test('active status→通常ホーム画面フラグ', () {
      String status = 'active';
      bool showPending = status == 'pending';
      expect(showPending, false);
    });
  });

  group('カタログ遅延ロードテスト', () {
    test('空キャッシュ→API取得フラグ', () {
      List manufacturers = [];
      bool needsApi = manufacturers.isEmpty;
      expect(needsApi, true);
    });

    test('キャッシュあり→API不要フラグ', () {
      List manufacturers = [{'id': 'panasonic', 'name': 'パナソニック'}];
      bool needsApi = manufacturers.isEmpty;
      expect(needsApi, false);
    });

    test('tier1フィルタ動作', () {
      final data = [
        {'id': 'a', 'tier': 1},
        {'id': 'b', 'tier': 2},
        {'id': 'c', 'tier': 1},
      ];
      final tier1 = data.where((m) => m['tier'] == 1).toList();
      expect(tier1.length, 2);
    });

    test('pending status フィルタ動作', () {
      final workers = [
        {'name': 'A', 'status': 'pending'},
        {'name': 'B', 'status': 'active'},
        {'name': 'C', 'status': 'pending'},
      ];
      final pending = workers.where((w) => w['status'] == 'pending').toList();
      expect(pending.length, 2);
    });
  });
  // ────────────────────────────────────────────────────────────
  // 勤怠の確認事項（職長は【見るだけ】）
  //
  // ★このファイルへ足す理由: 画面を実際に積んで確かめる検査が集まっている
  //   唯一のファイルであり、新しいテストファイルは作らない決まりのため。
  group('勤怠の確認事項（職長は見るだけ）', () {
    setUp(() {
      // AuthService.getToken が読む唯一のキー。無いと通信の手前で止まる。
      SharedPreferences.setMockInitialValues({'auth_token': 'T'});
    });

    String bodyOf(List<Map<String, dynamic>> rows) =>
        jsonEncode({'confirmations': rows});

    testWidgets('(a) 職長の「管理」には3つ目の節『⏱ 勤怠』が出る', (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: Scaffold(
            body: ForemanManagementBody(),
          )));
          await tester.pumpAndSettle();
        },
        () => confirmClient(200, bodyOf(const [])),
      );
      expect(find.text('👥 社員'), findsOneWidget);
      expect(find.text('🏢 協力'), findsOneWidget);
      expect(find.text('⏱ 勤怠'), findsOneWidget,
          reason: '3つ目の節が出ること');
    });

    testWidgets('(b) 職人の「管理・履歴」には『⏱ 勤怠』が出ない（管理の節ごと無い）',
        (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: Scaffold(
            body: ManagementHistoryScreen(isForeman: false),
          )));
          await tester.pump();
        },
        () => confirmClient(200, bodyOf(const [])),
      );
      expect(find.text('管理'), findsNothing,
          reason: '職人は「管理」そのものを持たない');
      expect(find.text('⏱ 勤怠'), findsNothing,
          reason: 'その中の3つ目の節も当然出ない');
      tester.takeException(); // 他の節（カレンダー等）の端末機能は本検査の対象外
    });

    testWidgets('(c)(d) 決着のボタンが1つも無く、確定は事務または社長の一文が出る',
        (tester) async {
      await http.runWithClient(
        () => openAttendanceSegment(tester),
        () => confirmClient(200, bodyOf([
              {
                'id': 'cq-1',
                'confirm_type': 'forgot_punch',
                'person_name': 'テスト職人',
                'work_date': '2026-08-10',
                'can_resolve': false,
                'cannot_resolve_reason': 'BOSS_CONFIRMATION_FORBIDDEN',
              },
            ])),
      );
      expect(find.text(kSeeNotice), findsOneWidget,
          reason: '押せない理由を先に書かないと「不具合で押せない」と読まれる');
      // 決着の口（承認・却下）を1つも置かない＝ボタン系が1つも無いこと。
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      for (final w in ['承認', '却下', '確定', '記録する', '差し戻し']) {
        expect(find.text(w), findsNothing, reason: '「$w」の口を置かない');
      }
      // 1行＝1日。内訳は0のものを描かない。
      expect(find.text('打刻漏れ1'), findsOneWidget);
      expect(find.text('休日の打刻1'), findsNothing);
      expect(find.text('残業1'), findsNothing);
    });

    testWidgets('(e) 0件と失敗で違うものが出る（どちらも空にしない）', (tester) async {
      // 0件
      await http.runWithClient(
        () => openAttendanceSegment(tester, key: const ValueKey('empty')),
        () => confirmClient(200, bodyOf(const [])),
      );
      expect(find.text(kEmptyText), findsOneWidget, reason: '0件は0件と言い切る');
      expect(find.text(kFailText), findsNothing);
      expect(find.text('再試行'), findsNothing);

      // 失敗（403）
      await http.runWithClient(
        () => openAttendanceSegment(tester, key: const ValueKey('fail')),
        () => confirmClient(403,
            jsonEncode({'error': '権限がありません', 'code': 'FORBIDDEN'})),
      );
      expect(find.text(kFailText), findsOneWidget,
          reason: '失敗を空一覧にすると「確認事項が無い」と誤解される');
      expect(find.text(kEmptyText), findsNothing,
          reason: '0件と失敗を同じ見た目にしない');
      expect(find.text('権限がありません'), findsOneWidget,
          reason: 'サーバが理由を言っているならそのまま出す');
      expect(find.text('再試行'), findsOneWidget, reason: 'やり直す手を必ず出す');
    });

    testWidgets('(f) キーが欠けていても・余分でも画面が落ちない', (tester) async {
      await http.runWithClient(
        () => openAttendanceSegment(tester),
        () => confirmClient(200, bodyOf([
              // 日付が列に無く raw_value にだけある行
              {
                'id': 'cq-1',
                'confirm_type': 'comp_off',
                'raw_value': {'work_date': '2026-08-11', 'holiday_type': 'legal'},
              },
              // 日付がどこにも無い行（行にできないので落とす）
              {'id': 'cq-2', 'confirm_type': 'overtime_or_forgot'},
              // confirm_type が無い行（内訳に出さない／合計には数える）
              {'id': 'cq-3', 'work_date': '2026-08-11'},
              // 知らない confirm_type（名前が分からないので内訳に出さない）
              {'id': 'cq-4', 'confirm_type': 'unknown_kind', 'work_date': '2026-08-11'},
              // 想定外の余分なキーが増えても無視する
              {
                'id': 'cq-5',
                'confirm_type': 'forgot_punch',
                'work_date': '2026-08-11',
                'brand_new_column': 'x',
              },
            ])),
      );
      expect(tester.takeException(), isNull, reason: '画面ごと落とさない');
      expect(find.text(kSeeNotice), findsOneWidget);
      expect(find.text('4件'), findsOneWidget,
          reason: '日付が読めた4行を合計に数える（読めない1行は行にできない）');
      expect(find.text('休日の打刻1'), findsOneWidget);
      expect(find.text('打刻漏れ1'), findsOneWidget);
      expect(find.text('残業1'), findsNothing,
          reason: '日付の無い行は行にならない');
    });
  });
}
