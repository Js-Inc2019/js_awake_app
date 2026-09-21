// ============================================================
// test/one_screen_fit_test.dart
//   「本日休み」と「振替で休む」が【1画面に収まる】ことを機械で固定する。
//
// ★なぜこの本を立てるか: ボスの実機で、どちらの画面も少しスクロールしないと
//   全体が見えなかった。目で見て直しただけでは、次に1行増えたときに
//   また同じことが起きる。収まっているかどうかを数で押さえる。
//
// ★検査に使う画面の大きさ（393 × 852 pt）と、上下の帯（59 / 34 pt）の出どころ:
//   ① ボスの実機の機種 = iPhone17,3
//        xcrun devicectl list devices の Model 欄で実測
//        → 「Jphone … connected  iPhone 16 (iPhone17,3)  physical」
//   ② その機種の論理サイズ = Apple の CoreSimulator が持つ機種定義で実測
//        /Library/Developer/CoreSimulator/Profiles/DeviceTypes/
//          iPhone 16.simdevicetype/Contents/Resources/profile.plist
//            modelIdentifier => "iPhone17,3"
//          同ディレクトリ capabilities.plist の ScreenDimensionsCapability
//            main-screen-width => 1179 / main-screen-height => 2556 / scale => 3
//        → 1179 / 3 × 2556 / 3 = 393 × 852 pt
//   ③ 上下の帯（状態表示とホームバー）= 同じ機種のシミュレータで実測
//        iPhone 16（iOS 26.5）を立てて MediaQuery を読んだ実測値:
//          size=Size(393.0, 852.0) dpr=3.0 padding=EdgeInsets(0.0, 59.0, 0.0, 34.0)
//        ★ここを 0 のままにすると、直す前の「本日休み」でも机上では収まってしまい、
//          空振りで合格する（実機では帯のぶんだけ足りなかった）。
//
//   → 中身が使える高さ = 852 − 59（上の帯）− 56（AppBar）− 34（ホームバー）= 703 pt
//
// ★掟: 期待値（語・数）はこのファイル内で組み立てる。実装の定数は import しない。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:js_awake_app/screens/rest_day_screen.dart' show RestDayScreen;
import 'package:js_awake_app/screens/substitute_register_screen.dart'
    show SubstituteRegisterScreen;
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';

// ── 検査に使う画面（上の★の実測値をここへ写した）──────────────────
const double kPhoneW = 393;
const double kPhoneH = 852;
const double kSafeTop = 59;
const double kSafeBottom = 34;

// ── 画面の実文言（lib の実文字列をここへ写した）──────────────────
const String kRestSubmit = '休みを登録する';
const String kSubRegister = 'この内容で登録する';
const String kCompOff = '代休';
const String kSubstitute = '振替';
const String kAnotherDay = '別の日';

// ── 守るべき寸法（ボスの裁定）──────────────────────────────────
const double kMinTapHeight = 44; // 押せる部品は 44pt 以上

/// 候補1行に出る文字（下の _week7() が渡した date と dow から組み立てた）。
const List<String> kRowLabels = [
  '6月7日（日）',
  '6月8日（月）',
  '6月9日（火）',
  '6月10日（水）',
  '6月11日（木）',
  '6月12日（金）',
  '6月13日（土）',
];

class _FakeSvc extends ReportsService {
  _FakeSvc({this.days = const []}) : super.forTest();

  final List<Map<String, dynamic>> days;

  @override
  Future<ApiResult<Map<String, dynamic>>> getSubstituteWorkDateCandidates(
      String restDate) async {
    return apiSuccess<Map<String, dynamic>>(
      statusCode: 200,
      data: {
        'rest_date': restDate,
        'rest_date_is_workday': true,
        'holiday_def_configured': true,
        'days': days,
      },
    );
  }
}

/// BE が返す7日ぶん（日曜〜土曜）。★並びも文も BE のものをそのまま写す。
List<Map<String, dynamic>> _week7() => [
      {'date': '2026-06-07', 'dow': 0, 'selectable': true,
        'reason_code': null, 'reason': null},
      {'date': '2026-06-08', 'dow': 1, 'selectable': false,
        'reason_code': 'not_holiday', 'reason': '会社の休みの日ではありません'},
      {'date': '2026-06-09', 'dow': 2, 'selectable': false,
        'reason_code': 'not_holiday', 'reason': '会社の休みの日ではありません'},
      {'date': '2026-06-10', 'dow': 3, 'selectable': false,
        'reason_code': 'same_as_rest_date', 'reason': '休む日と同じ日です'},
      {'date': '2026-06-11', 'dow': 4, 'selectable': false,
        'reason_code': 'not_holiday', 'reason': '会社の休みの日ではありません'},
      {'date': '2026-06-12', 'dow': 5, 'selectable': false,
        'reason_code': 'not_holiday', 'reason': '会社の休みの日ではありません'},
      {'date': '2026-06-13', 'dow': 6, 'selectable': true,
        'reason_code': null, 'reason': null},
    ];

/// iPhone17,3 の論理サイズ＋上下の帯で立てる。
Future<void> _pumpPhone(WidgetTester tester, Widget screen) async {
  tester.view.devicePixelRatio = 1.0; // 1pt = 1px にして pt でそのまま測る
  tester.view.physicalSize = const Size(kPhoneW, kPhoneH);
  tester.view.padding =
      const FakeViewPadding(top: kSafeTop, bottom: kSafeBottom);
  tester.view.viewPadding =
      const FakeViewPadding(top: kSafeTop, bottom: kSafeBottom);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

/// 画面の中の唯一の巻物（ScrollView）が、あと何ポイント巻けるか。
///   0.0 = 全部が一度に見えている＝スクロール不要。
double _scrollLeft(WidgetTester tester) {
  final scrollables = tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where((s) => s.position.hasContentDimensions)
      .toList();
  expect(scrollables.length, 1,
      reason: '巻物が1つではない（見る対象を取り違えている）');
  return scrollables.single.position.maxScrollExtent;
}

/// ホームバーの上端＝人の目に入る一番下。ここより下に出たら「見えない」。
const double kVisibleBottom = kPhoneH - kSafeBottom;

void main() {
  // ══════════════════════════════════════════════════════════
  // ① 本日休み（新規登録）
  // ══════════════════════════════════════════════════════════
  group('① 本日休みは1画面に収まる', () {
    testWidgets('★スクロールせずに「$kRestSubmit」が画面の中に丸ごと見える',
        (tester) async {
      await _pumpPhone(tester, RestDayScreen(service: _FakeSvc()));

      // ★空振り防止: 画面が空で通るのを防ぐため、中身が在ることを先に見る。
      for (final t in ['終日', '午前休', '午後休']) {
        expect(find.text(t), findsOneWidget, reason: '区分「$t」が消えている');
      }
      for (final t in ['有給', '欠勤', '会社休業', '私用']) {
        expect(find.text(t), findsOneWidget, reason: '理由「$t」が消えている');
      }
      expect(find.text(kCompOff), findsOneWidget);
      expect(find.text(kSubstitute), findsOneWidget);
      expect(find.text(kRestSubmit), findsOneWidget);

      final left = _scrollLeft(tester);
      final btn =
          tester.getRect(find.widgetWithText(ElevatedButton, kRestSubmit));
      // ignore: avoid_print
      print('［計測］本日休み: はみ出し=$left pt / 主ボタン top=${btn.top} '
          'bottom=${btn.bottom} / 見える下端=$kVisibleBottom');

      expect(left, 0.0,
          reason: 'スクロールしないと全体が見えない（$left pt はみ出し）');
      expect(btn.bottom <= kVisibleBottom, isTrue,
          reason: '主ボタンの下端 ${btn.bottom} が見える下端 $kVisibleBottom より下');
      expect(btn.top >= kSafeTop, isTrue);
    });

    testWidgets('★代休と振替は同じ行に並び、左が代休・右が振替（高さ48）', (tester) async {
      await _pumpPhone(tester, RestDayScreen(service: _FakeSvc()));

      final comp = tester.getRect(
          find.widgetWithText(OutlinedButton, kCompOff).first);
      final sub = tester.getRect(
          find.widgetWithText(OutlinedButton, kSubstitute).first);
      // ignore: avoid_print
      print('［計測］代休ボタン=$comp / 振替ボタン=$sub');

      expect(comp.top, sub.top, reason: '同じ行に並んでいない（上端が違う）');
      expect(comp.height, sub.height, reason: '高さが揃っていない');
      expect(comp.height, 48.0, reason: '主ボタンの高さが 48 ではない');
      expect(comp.right <= sub.left, isTrue,
          reason: '左が代休・右が振替になっていない（代休 ${comp.right} / 振替 ${sub.left}）');

      // アイコンは今までのまま。
      expect(
          find.descendant(
              of: find.widgetWithText(OutlinedButton, kCompOff).first,
              matching: find.byIcon(Icons.event_repeat)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.widgetWithText(OutlinedButton, kSubstitute).first,
              matching: find.byIcon(Icons.swap_horiz)),
          findsOneWidget);
    });

    testWidgets('★「$kAnotherDay」は2つ・高さ44以上・読み上げは左右で見分けられる',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpPhone(tester, RestDayScreen(service: _FakeSvc()));

      expect(find.text(kAnotherDay), findsNWidgets(2),
          reason: '「$kAnotherDay」が2つ並んでいない');

      final rects = tester
          .widgetList<TextButton>(find.widgetWithText(TextButton, kAnotherDay))
          .map((w) => tester.getRect(find.byWidget(w)))
          .toList();
      // ignore: avoid_print
      print('［計測］別の日ボタン=$rects');
      expect(rects.length, 2);
      for (final r in rects) {
        expect(r.height >= kMinTapHeight, isTrue,
            reason: '押せる高さ ${r.height} が $kMinTapHeight pt を下回る');
      }
      expect(rects[0].top, rects[1].top, reason: '同じ行に並んでいない');
      expect(rects[0].right <= rects[1].left, isTrue,
          reason: '左が代休・右が振替になっていない');

      // ★同じ文字のボタンが2つ並ぶので、読み上げではどちらか分かること。
      expect(find.bySemanticsLabel('代休を別の日にする'), findsOneWidget);
      expect(find.bySemanticsLabel('振替を別の日にする'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('★代休の「$kAnotherDay」を押すと代休の日だけが変わる'
        '（対照: 振替の日は動かない／最長の日付でもはみ出さない）', (tester) async {
      await _pumpPhone(tester, RestDayScreen(service: _FakeSvc()));

      final before = _dateLabels(tester);
      expect(before.length, 2, reason: '日付が2つ出ていない');
      expect(before[0], before[1], reason: '既定はどちらも今日のはず');

      await _pickDec31(tester, index: 0); // 左＝代休

      final after = _dateLabels(tester);
      expect(after[0], startsWith('12月31日（'),
          reason: '代休の日が変わっていない（${after[0]}）');
      expect(after[1], before[1],
          reason: '代休を選び直したのに振替の日まで動いた（${after[1]}）');
      // ★最長の日付でも はみ出し（overflow）の警告が出ないこと。
      //   overflow は FlutterError になり、この本が自動で落ちる。
      expect(tester.takeException(), isNull, reason: 'はみ出しの警告が出ている');
    });

    testWidgets('★逆も同じ: 振替の「$kAnotherDay」を押すと振替の日だけが変わる',
        (tester) async {
      await _pumpPhone(tester, RestDayScreen(service: _FakeSvc()));

      final before = _dateLabels(tester);
      await _pickDec31(tester, index: 1); // 右＝振替

      final after = _dateLabels(tester);
      expect(after[1], startsWith('12月31日（'),
          reason: '振替の日が変わっていない（${after[1]}）');
      expect(after[0], before[0],
          reason: '振替を選び直したのに代休の日まで動いた（${after[0]}）');
      expect(tester.takeException(), isNull, reason: 'はみ出しの警告が出ている');
    });

    testWidgets('★対照: 最長の日付にしても1画面に収まったまま', (tester) async {
      await _pumpPhone(tester, RestDayScreen(service: _FakeSvc()));
      await _pickDec31(tester, index: 0);
      await _pickDec31(tester, index: 1);

      final labels = _dateLabels(tester);
      expect(labels[0], startsWith('12月31日（'));
      expect(labels[1], startsWith('12月31日（'));

      final left = _scrollLeft(tester);
      final btn =
          tester.getRect(find.widgetWithText(ElevatedButton, kRestSubmit));
      // ignore: avoid_print
      print('［計測］本日休み(12月31日): はみ出し=$left pt / '
          '主ボタン bottom=${btn.bottom}');
      expect(left, 0.0);
      expect(btn.bottom <= kVisibleBottom, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  // ② 振替で休む（出勤する日を選ぶ）
  // ══════════════════════════════════════════════════════════
  group('② 振替で休むは1画面に収まる', () {
    testWidgets('★スクロールせずに「$kSubRegister」が画面の中に丸ごと見える',
        (tester) async {
      await _pumpPhone(
        tester,
        SubstituteRegisterScreen(
            restDate: '2026-06-10', service: _FakeSvc(days: _week7())),
      );

      // ★はみ出しを先に測る。巻物は画面の外の行を作らないことがあるので、
      //   先に部品を探すと「収まらない」が「部品が無い」に化けて読みにくくなる。
      final left = _scrollLeft(tester);
      // ignore: avoid_print
      print('［計測］振替で休む: はみ出し=$left pt / 見える下端=$kVisibleBottom');

      // ★空振り防止: 7日ぶんの候補が並んでいることを見る。
      expect(find.text('休む日'), findsOneWidget);
      expect(find.text('代わりに出勤する日'), findsOneWidget);
      for (final l in kRowLabels) {
        expect(find.text(l), findsOneWidget, reason: '候補「$l」が並んでいない');
      }
      expect(find.text(kSubRegister), findsOneWidget);

      expect(left, 0.0,
          reason: 'スクロールしないと全体が見えない（$left pt はみ出し）');
      final btn =
          tester.getRect(find.widgetWithText(OutlinedButton, kSubRegister));
      // ignore: avoid_print
      print('［計測］振替で休む: 主ボタン top=${btn.top} bottom=${btn.bottom}');
      expect(btn.bottom <= kVisibleBottom, isTrue,
          reason: '主ボタンの下端 ${btn.bottom} が見える下端 $kVisibleBottom より下');
    });

    testWidgets('★1日の行は押せる高さ $kMinTapHeight pt 以上を保つ', (tester) async {
      await _pumpPhone(
        tester,
        SubstituteRegisterScreen(
            restDate: '2026-06-10', service: _FakeSvc(days: _week7())),
      );

      final heights = <double>[];
      for (final l in kRowLabels) {
        // ★押せる部分＝その日の文字を包んでいる InkWell そのもの。
        final row = find.ancestor(
            of: find.text(l), matching: find.byType(InkWell));
        expect(row, findsOneWidget, reason: '候補「$l」の押せる部分が無い');
        heights.add(tester.getRect(row).height);
      }
      // ignore: avoid_print
      print('［計測］振替で休む: 1日の行の高さ=$heights');
      for (final h in heights) {
        expect(h >= kMinTapHeight, isTrue,
            reason: '押せる高さ $h が $kMinTapHeight pt を下回る');
        // ★上も押さえる。日付の列が狭いと日付が2行に折れて行が 67pt まで伸び、
        //   7日ぶんで 161pt ぶん画面からはみ出す（それが元の不具合だった）。
        expect(h <= 48, isTrue,
            reason: '行が $h pt まで伸びている（日付が2行に折れている）');
      }
    });
  });
}

// ── 道具 ───────────────────────────────────────────────────

/// 代休・振替の主ボタンに出ている日付の文字（左＝代休・右＝振替の順）。
List<String> _dateLabels(WidgetTester tester) {
  final finder = find.textContaining('月', findRichText: false);
  final out = <String>[];
  for (final w in tester.widgetList<Text>(finder)) {
    final t = w.data ?? '';
    if (t.contains('日（') && t.endsWith('）')) out.add(t);
  }
  // 先頭は画面上部の日付表示（本日）。その後ろ2つが代休・振替。
  return out.length >= 3 ? out.sublist(out.length - 2) : out;
}

/// 「別の日」を押して、日付を「12月31日」にする（この年の最長の日付）。
///   ★最長にするのは、半分の幅にはみ出さず入るかを最悪の側で見るため。
Future<void> _pickDec31(WidgetTester tester, {required int index}) async {
  final buttons = find.widgetWithText(TextButton, kAnotherDay);
  expect(buttons, findsNWidgets(2));
  await tester.tap(buttons.at(index));
  await tester.pumpAndSettle();

  // 今月から12月まで、次の月へ送る。★今日の日付に関係なく動くよう数で出す。
  final monthsForward = 12 - DateTime.now().month;
  for (var i = 0; i < monthsForward; i++) {
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('31').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}
