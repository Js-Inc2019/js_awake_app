// ============================================================
// test/share_send_confirm_test.dart — 送信内容の確認画面（widget テスト）
//
// ★なぜこの画面だけ widget テストできるか（正直な線引き）:
//   ShareSendConfirmScreen は Service を1つも呼ばない StatelessWidget で、
//   受け取った値を描くだけ＝HTTP を差し替える必要が無い。
//   送信画面本体（ShareSendScreen）は ReportsService 等のシングルトン
//   （factory が _instance を返す形）を直接触るため、lib/ に注入口を
//   作らない限り widget テストで実HTTPを避けられない。よって本テストの
//   対象外とし、あちらは純ロジック（test/share_gates_test.dart の
//   role 判定）だけを固定してある。
//   ※OFFICE 側は provider + Fake ApiService で画面ごと縛れているが
//     （js_office_admin_app/test/bundle_send_screen_test.dart）、
//     FIELD には provider が無く同じ手が使えない。
//
// ★何を縛るか（崩れると業務が壊れる点だけ）:
//   ① 日報は【全件】並ぶ（抜粋・「n件ほか」で丸めない）
//   ② 宛先は全社ぶんの名前が出る（「n社」で丸めない）
//   ③ 写真を含めるかが要約に出る（受信側の見え方が変わるため）
//   ④「送信する」で true / 「戻る」で false を返す（API はここで呼ばない）
//   ⑤ 宛先0件・日報0件では「送信する」を押せない
//   ⑥ 行タップは onPreview にその日報をそのまま渡す
//
// ★期待文言は実装から import せずここへ直書きする。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:js_awake_app/screens/share_send_confirm_screen.dart';

List<Map<String, dynamic>> _reports(int n) => List.generate(
      n,
      (i) => <String, dynamic>{
        'report_id': 'r$i',
        'report_date': '2026-06-${(10 + i).toString().padLeft(2, '0')}',
        'worker_name': '職人$i',
        'site_name': '現場$i',
      },
    );

/// 確認画面を1枚ポンプして、pop の戻り値を受け取れる形で返す。
Future<List<Object?>> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> reports,
  required List<String> receivers,
  String periodLabel = '2026-06-10〜2026-06-20',
  String workerSummary = '全員',
  String siteSummary = '全部（現場未設定を含む）',
  bool includePhotos = false,
  void Function(Map<String, dynamic>)? onPreview,
}) async {
  // ★既定のテスト画面（800x600 相当）だと ListView が画面外の行を
  //   遅延生成のまま作らず、「全件並ぶ」を検査できない（見えないだけで
  //   実装は正しい状態と、抜粋している状態を区別できない）。
  //   画面を十分に高くして全行を構築させる＝実装側は1行も変えない。
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final popped = <Object?>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () async {
            final r = await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => ShareSendConfirmScreen(
                reports: reports,
                receiverCompanyNames: receivers,
                periodLabel: periodLabel,
                workerSummary: workerSummary,
                siteSummary: siteSummary,
                includePhotos: includePhotos,
                onPreview: onPreview ?? (_) {},
              ),
            ));
            popped.add(r);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return popped;
}

void main() {
  testWidgets('① 日報は全件並ぶ（丸めない）', (tester) async {
    await _pump(tester, reports: _reports(3), receivers: const ['A社']);

    // 見出しに件数が出る
    expect(find.text('送る日報（3件）'), findsOneWidget);
    // 3件すべての日付が実際に描かれている（抜粋していない）
    for (final d in ['2026-06-10', '2026-06-11', '2026-06-12']) {
      expect(find.textContaining(d), findsWidgets, reason: d);
    }
    // 職人名も全件出る
    for (final w in ['職人0', '職人1', '職人2']) {
      expect(find.text(w), findsOneWidget, reason: w);
    }
  });

  testWidgets('② 宛先は全社ぶん名前が出る（「n社」に丸めない）', (tester) async {
    await _pump(tester,
        reports: _reports(1), receivers: const ['あかね電機', 'さくら工業', '大和設備']);

    expect(find.text('あかね電機'), findsOneWidget);
    expect(find.text('さくら工業'), findsOneWidget);
    expect(find.text('大和設備'), findsOneWidget);
    // 件数へ丸めた表現は出さない
    expect(find.text('3社'), findsNothing);
  });

  testWidgets('③ 写真を含めるかが要約に出る', (tester) async {
    await _pump(tester,
        reports: _reports(1), receivers: const ['A社'], includePhotos: true);
    expect(find.text('含める'), findsOneWidget);
    expect(find.text('含めない'), findsNothing);
  });

  testWidgets('③\' 写真を含めないときは「含めない」と言い切る', (tester) async {
    await _pump(tester,
        reports: _reports(1), receivers: const ['A社'], includePhotos: false);
    expect(find.text('含めない'), findsOneWidget);
    expect(find.text('含める'), findsNothing);
  });

  testWidgets('③\'\' 期間・職人・現場の要約がそのまま出る', (tester) async {
    await _pump(tester,
        reports: _reports(1),
        receivers: const ['A社'],
        periodLabel: '2026-06-10以降',
        workerSummary: '2名を指定（佐藤・田中）',
        siteSummary: '1件を指定（現場未設定）');

    expect(find.text('2026-06-10以降'), findsOneWidget);
    expect(find.text('2名を指定（佐藤・田中）'), findsOneWidget);
    expect(find.text('1件を指定（現場未設定）'), findsOneWidget);
  });

  testWidgets('③\'\'\' 期間が空なら「（指定なし）」と出す（空欄にしない）', (tester) async {
    await _pump(tester,
        reports: _reports(1), receivers: const ['A社'], periodLabel: '');
    expect(find.text('（指定なし）'), findsOneWidget);
  });

  testWidgets('④ 「送信する」で true を返す', (tester) async {
    final popped =
        await _pump(tester, reports: _reports(2), receivers: const ['A社']);

    await tester.tap(find.text('送信する'));
    await tester.pumpAndSettle();
    expect(popped, [true]);
  });

  testWidgets('④\' 「戻る」で false を返す', (tester) async {
    final popped =
        await _pump(tester, reports: _reports(2), receivers: const ['A社']);

    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(popped, [false]);
  });

  testWidgets('⑤ 宛先0件では送信できず、その事実を出す', (tester) async {
    await _pump(tester, reports: _reports(2), receivers: const []);

    expect(find.text('（宛先が選ばれていません）'), findsOneWidget);
    final btn = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('送信する'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('⑤\' 日報0件では送信できない', (tester) async {
    await _pump(tester, reports: const [], receivers: const ['A社']);

    expect(find.text('送る日報（0件）'), findsOneWidget);
    final btn = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('送信する'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('⑥ 行タップは onPreview にその日報をそのまま渡す', (tester) async {
    final seen = <Map<String, dynamic>>[];
    final rows = _reports(3);
    await _pump(tester,
        reports: rows, receivers: const ['A社'], onPreview: seen.add);

    await tester.tap(find.text('職人1'));
    await tester.pumpAndSettle();

    expect(seen.length, 1);
    expect(seen.single['report_id'], 'r1');
    // 同一インスタンスが渡る（コピーで渡すと確認内容と送る内容がずれ得る）
    expect(identical(seen.single, rows[1]), isTrue);
  });

  testWidgets('現場名は master_site_name > site_name > 現場未設定 の順', (tester) async {
    await _pump(
      tester,
      receivers: const ['A社'],
      reports: [
        {
          'report_id': 'a',
          'report_date': '2026-06-10',
          'worker_name': 'W1',
          'site_name': '職人入力',
          'master_site_name': 'マスタ正式名',
        },
        {
          'report_id': 'b',
          'report_date': '2026-06-11',
          'worker_name': 'W2',
          'site_name': '職人入力のみ',
        },
        {
          'report_id': 'c',
          'report_date': '2026-06-12',
          'worker_name': 'W3',
        },
      ],
    );

    expect(find.text('マスタ正式名'), findsOneWidget);
    expect(find.text('職人入力'), findsNothing); // マスタ名に負ける
    expect(find.text('職人入力のみ'), findsOneWidget);
    expect(find.text('現場未設定'), findsOneWidget);
  });
}
