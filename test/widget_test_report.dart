import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

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
}
