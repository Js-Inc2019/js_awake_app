// ============================================================
// test/calendar_day_sheet_test.dart
//   カレンダー（管理・履歴タブの1つ目 = CalendarTab）の
//   ①高さの配り方 ②既定パネルが切れないこと ③せり上がる箱
//   を機械で固定する。
//
// 直していたのは次の形:
//   グリッドがマス48固定で自分の高さを先に取り、下の選択日パネルは
//   残りを受けていた。6週の月では月ナビ＋グリッド＋区切り線で縦を使い切り、
//   パネルの取り分がほぼ消えて中身が切れていた。
//   ボス裁定 Q16=3 でこれを逆にした（パネルの取り分を先に確保し、
//   余りをマスへ配る。マスの下限は36）。
//
// ★画面（CalendarTab）は立てない。initState から _loadMonth が走って
//   実HTTPへ行くため。この線引きは test/share_send_confirm_test.dart と
//   test/report_status_style_test.dart の冒頭に既に書かれている流儀。
//   代わりに ①純関数（calendarHeightsFor / calendarSheetKeptRows /
//   calendarSheetMaxHeight / calendarRowCountOf）と ②公開部品
//   （CalendarDayPanel / CalendarDaySheet / showCalendarDaySheet）を直接叩く。
//
// ★色は 16進の生の値で書く。トークン名で書くとトークンの値が差し替わった
//   ときに気付けない（report_status_style_test.dart と同じ理由・同じ値）。
//
// ★既知の罠: 受け皿を MaterialApp(home:) へ直に置くと
//   「No Material widget found」で落ちる。必ず Scaffold を挟む
//   （report_status_style_test.dart の _wrap と同じ形にしてある）。
// ============================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:js_awake_app/screens/home_screen.dart'
    show
        CalendarDayInfo,
        CalendarDayPanel,
        CalendarDaySheet,
        CalendarHeights,
        calendarHeightsFor,
        calendarRowCountOf,
        calendarSheetKeptRows,
        calendarSheetMaxHeight,
        kCalendarCellMargin,
        kCalendarGridPaddingV,
        kCalendarMaxCellHeight,
        kCalendarMinCellHeight,
        kCalendarPanelPaddingV,
        kCalendarPanelReservedHeight,
        kCalendarWeekHeaderHeight,
        showCalendarDaySheet;
import 'package:js_awake_app/utils/report_status_style.dart';

// 期待する色（16進の生の値。トークン名では書かない）
const int _kCancelled = 0xFFA98FC0; // 藤
const int _kApproved = 0xFF6FD6B4;
const int _kRejected = 0xFFE05252;
const int _kPending = 0xFFE0603A; // 橙

// BE の行の写し（report_status_style_test.dart の _row と同じ形）。
Map<String, dynamic> _row({
  required String id,
  bool approved = false,
  bool revisionRequested = false,
  String status = 'open',
  String date = '2026-06-10',
}) =>
    <String, dynamic>{
      'report_id': id,
      'report_date': date,
      'worker_name': '職人太郎',
      'site_name': '現場A',
      'work_content': '配線',
      'approved': approved,
      'revision_requested': revisionRequested,
      'status': status,
    };

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

/// この木の中に在る、枠線の色の一覧（BoxDecoration の Border から拾う）。
Set<int> _borderColors(WidgetTester tester) {
  final out = <int>{};
  for (final e in tester.allWidgets) {
    if (e is! Container) continue;
    final d = e.decoration;
    if (d is! BoxDecoration) continue;
    final b = d.border;
    if (b is! Border) continue;
    final c = b.top.color;
    out.add(c.toARGB32());
  }
  return out;
}

void main() {
  // ─────────────────────────────────────────────────────────
  // ① 月の行数（4週・5週・6週）
  // ─────────────────────────────────────────────────────────
  group('calendarRowCountOf — 月の行数', () {
    // 実在する月から3種類とも見つかること。数を先に決め打ちしない。
    final byRows = <int, DateTime>{};
    for (var y = 2024; y <= 2030; y++) {
      for (var m = 1; m <= 12; m++) {
        final d = DateTime(y, m, 1);
        byRows.putIfAbsent(calendarRowCountOf(d), () => d);
      }
    }

    test('4週・5週・6週の月がそれぞれ実在する', () {
      expect(byRows.keys.toSet().containsAll(<int>{4, 5, 6}), isTrue,
          reason: '見つかった行数: ${byRows.keys.toList()..sort()}');
    });

    test('日曜始まりで数えている（2026年2月は日曜始まり28日でちょうど4週）', () {
      expect(DateTime(2026, 2, 1).weekday % 7, 0, reason: '2026-02-01 は日曜');
      expect(calendarRowCountOf(DateTime(2026, 2, 1)), 4);
    });

    test('行数は4〜6の範囲に収まる（7年ぶん全部）', () {
      for (var y = 2024; y <= 2030; y++) {
        for (var m = 1; m <= 12; m++) {
          final n = calendarRowCountOf(DateTime(y, m, 1));
          expect(n, inInclusiveRange(4, 6), reason: '$y-$m');
        }
      }
    });
  });

  // ─────────────────────────────────────────────────────────
  // ② 高さの配り方（ボス裁定 Q16=3）
  // ─────────────────────────────────────────────────────────
  group('calendarHeightsFor — 余りをマスへ配る', () {
    // 「その行数でパネルの取り分がちょうど確保できる高さ」。
    //   free / rows - 余白 = 下限36 になる点。
    double justEnough(int rows) =>
        rows * (kCalendarMinCellHeight + kCalendarCellMargin) +
        kCalendarGridPaddingV +
        kCalendarWeekHeaderHeight +
        1 + // 区切り線
        kCalendarPanelReservedHeight;

    test('マスの高さは下限36を下回らない（どの行数・どの高さでも）', () {
      for (final rows in <int>[4, 5, 6]) {
        for (var avail = 120.0; avail <= 1200.0; avail += 7) {
          final h = calendarHeightsFor(available: avail, rowCount: rows);
          expect(h.cellHeight, greaterThanOrEqualTo(kCalendarMinCellHeight),
              reason: 'rows=$rows avail=$avail');
        }
      }
    });

    test('マスの高さは上限を超えない（定数で照合）', () {
      for (final rows in <int>[4, 5, 6]) {
        for (var avail = 120.0; avail <= 1200.0; avail += 7) {
          final h = calendarHeightsFor(available: avail, rowCount: rows);
          expect(h.cellHeight, lessThanOrEqualTo(kCalendarMaxCellHeight),
              reason: 'rows=$rows avail=$avail');
        }
      }
    });

    // ★生の数で照合する。定数だけを見ていると、定数の値が黙って差し替わった
    //   ときに気付けない（色を16進で書いてあるのと同じ理由）。
    //   36＝ボス裁定 Q16=3 の下限 / 56＝ボス裁定 Q18=2 の上限。
    test('4週・5週・6週のどれでも、マスの高さは36以上56以下に収まる', () {
      for (final rows in <int>[4, 5, 6]) {
        for (var avail = 100.0; avail <= 1600.0; avail += 3) {
          final h = calendarHeightsFor(available: avail, rowCount: rows);
          expect(h.cellHeight, greaterThanOrEqualTo(36.0),
              reason: 'rows=$rows avail=$avail');
          expect(h.cellHeight, lessThanOrEqualTo(56.0),
              reason: 'rows=$rows avail=$avail');
        }
      }
    });

    test('下限36・上限56という値そのものを固定し、両端に実際に届く', () {
      expect(kCalendarMinCellHeight, 36.0);
      expect(kCalendarMaxCellHeight, 56.0);
      // 高さをたっぷり与えれば上限に、削れば下限に、実際に当たる。
      expect(calendarHeightsFor(available: 2000, rowCount: 4).cellHeight, 56.0);
      expect(calendarHeightsFor(available: 150, rowCount: 6).cellHeight, 36.0);
    });

    // ★上限を上げてもパネルの取り分は痩せない。上限に当たる高さでは、
    //   パネルは確保ぶんより必ず大きくなる（先に引いてから割っているため）。
    test('上限に当たる高さでも、パネルの取り分は確保ぶんを下回らない', () {
      for (final rows in <int>[4, 5, 6]) {
        for (var avail = 600.0; avail <= 1600.0; avail += 7) {
          final h = calendarHeightsFor(available: avail, rowCount: rows);
          if (h.cellHeight != 56.0) continue;
          expect(h.panelHeight,
              greaterThanOrEqualTo(kCalendarPanelReservedHeight - 0.0001),
              reason: 'rows=$rows avail=$avail');
        }
      }
    });

    test('グリッド＋区切り線＋パネルで、配られた高さを使い切る（余りも不足も出ない）', () {
      for (final rows in <int>[4, 5, 6]) {
        for (var avail = 400.0; avail <= 1000.0; avail += 11) {
          final h = calendarHeightsFor(available: avail, rowCount: rows);
          expect(h.gridHeight + 1 + h.panelHeight, closeTo(avail, 0.0001),
              reason: 'rows=$rows avail=$avail');
        }
      }
    });

    // ★これが今回いちばん見たい点。以前はここが逆で、6週の月でパネルが潰れていた。
    test('4週・5週・6週のどれでも、足りている高さではパネルの取り分が先に確保される', () {
      for (final rows in <int>[4, 5, 6]) {
        final floor = justEnough(rows);
        for (var avail = floor; avail <= floor + 400; avail += 3) {
          final h = calendarHeightsFor(available: avail, rowCount: rows);
          expect(h.panelHeight,
              greaterThanOrEqualTo(kCalendarPanelReservedHeight - 0.0001),
              reason: 'rows=$rows avail=$avail');
        }
      }
    });

    test('6週の月は5週より、5週は4週より、確保に要る高さが大きい', () {
      expect(justEnough(6), greaterThan(justEnough(5)));
      expect(justEnough(5), greaterThan(justEnough(4)));
    });

    // 下限に当たった月は、これまで通りグリッドが先に取る形へ落ちてよい（裁定どおり）。
    test('高さが足りない月ではマスが36に張り付き、パネルが確保ぶんを下回る', () {
      final h = calendarHeightsFor(
          available: justEnough(6) - 40, rowCount: 6);
      expect(h.cellHeight, kCalendarMinCellHeight);
      expect(h.panelHeight, lessThan(kCalendarPanelReservedHeight));
    });

    test('マスの高さは固定値ではない（同じ行数でも高さで変わる）', () {
      final a = calendarHeightsFor(available: justEnough(6), rowCount: 6);
      final b =
          calendarHeightsFor(available: justEnough(6) + 30, rowCount: 6);
      expect(a.cellHeight, isNot(b.cellHeight));
    });

    test('行数0でも落ちない（下限のマスを返す）', () {
      final h = calendarHeightsFor(available: 500, rowCount: 0);
      expect(h.cellHeight, kCalendarMinCellHeight);
      expect(h, isA<CalendarHeights>());
    });
  });

  // ─────────────────────────────────────────────────────────
  // ③ (c) せり上がる箱の高さの上限＝カレンダーの行が見えたまま残る
  //   通常は上2週。使える高さが足りないときだけ1週へ減らす（ボス裁定 Q19=3）。
  //   1週より下には減らさない＝箱が画面全部を覆うことは無い。
  // ─────────────────────────────────────────────────────────
  group('calendarSheetMaxHeight — 残す週で高さを決める', () {
    test('画面の高さから、上2週の下端までを引いた値になる', () {
      const screen = 800.0;
      const gridTop = 160.0;
      const cell = 44.0;
      final maxH = calendarSheetMaxHeight(
          screenHeight: screen, gridTop: gridTop, cellHeight: cell);
      const keepBottom = gridTop +
          kCalendarGridPaddingV +
          kCalendarWeekHeaderHeight +
          2 * (cell + kCalendarCellMargin);
      expect(screen - maxH, closeTo(keepBottom, 0.0001));
      expect(maxH, lessThan(screen));
    });

    test('マスが低い月ほど、箱に使える高さは大きくなる', () {
      final low = calendarSheetMaxHeight(
          screenHeight: 800, gridTop: 160, cellHeight: 36);
      final high = calendarSheetMaxHeight(
          screenHeight: 800, gridTop: 160, cellHeight: 48);
      expect(low, greaterThan(high));
    });

    // ★ボス裁定 Q19=3。返す高さに下限を置いて「上2週を残す」という約束を
    //   黙って破る形はやめ、残す週のほうを1週へ減らして箱を広げる。
    test('高さが足りているうちは2週のまま', () {
      expect(
          calendarSheetKeptRows(
              screenHeight: 800, gridTop: 160, cellHeight: 44),
          2);
    });

    test('高さが足りないときは残す週が2週から1週へ減り、1週ぶんは必ず残る', () {
      const screen = 800.0, gridTop = 700.0, cell = 48.0;
      expect(
          calendarSheetKeptRows(
              screenHeight: screen, gridTop: gridTop, cellHeight: cell),
          1);
      final maxH = calendarSheetMaxHeight(
          screenHeight: screen, gridTop: gridTop, cellHeight: cell);
      const keepBottom1 = gridTop +
          kCalendarGridPaddingV +
          kCalendarWeekHeaderHeight +
          1 * (cell + kCalendarCellMargin);
      expect(screen - maxH, closeTo(keepBottom1, 0.0001));
    });

    test('残す週を減らすと、箱に使える高さは実際に広がる', () {
      const screen = 800.0, gridTop = 620.0, cell = 48.0;
      // 減らさない設定（2週で固定）との差を測る。
      final fixedTwo = calendarSheetMaxHeight(
          screenHeight: screen,
          gridTop: gridTop,
          cellHeight: cell,
          keepRows: 2,
          minKeepRows: 2);
      final auto = calendarSheetMaxHeight(
          screenHeight: screen, gridTop: gridTop, cellHeight: cell);
      expect(
          calendarSheetKeptRows(
              screenHeight: screen, gridTop: gridTop, cellHeight: cell),
          1);
      expect(auto, greaterThan(fixedTwo),
          reason: '1週へ減らしたぶんだけ広がる');
    });

    // ★1週より下には減らさない。ここが崩れると箱が画面全部を覆う。
    test('どんな画面の高さ・どんな位置・どんなマスでも残す週は1週を下回らない', () {
      for (var screen = 200.0; screen <= 1200.0; screen += 17) {
        for (var top = 0.0; top <= screen; top += 13) {
          for (final cell in <double>[36, 44, 56]) {
            expect(
                calendarSheetKeptRows(
                    screenHeight: screen, gridTop: top, cellHeight: cell),
                greaterThanOrEqualTo(1),
                reason: 'screen=$screen top=$top cell=$cell');
          }
        }
      }
    });

    test('どんな高さでも箱は画面全部を覆わない（1週ぶんの下端より下だけ）', () {
      for (var screen = 200.0; screen <= 1200.0; screen += 17) {
        for (var top = 0.0; top <= screen; top += 13) {
          for (final cell in <double>[36, 44, 56]) {
            final maxH = calendarSheetMaxHeight(
                screenHeight: screen, gridTop: top, cellHeight: cell);
            final room1 = screen -
                (top +
                    kCalendarGridPaddingV +
                    kCalendarWeekHeaderHeight +
                    1 * (cell + kCalendarCellMargin));
            expect(maxH, lessThanOrEqualTo(room1 < 0 ? 0.0 : room1),
                reason: 'screen=$screen top=$top cell=$cell');
            expect(maxH, greaterThanOrEqualTo(0),
                reason: 'screen=$screen top=$top cell=$cell');
          }
        }
      }
    });

    test('画面より高い値は返さない', () {
      final maxH = calendarSheetMaxHeight(
          screenHeight: 150, gridTop: 140, cellHeight: 48);
      expect(maxH, lessThanOrEqualTo(150));
    });
  });

  // ─────────────────────────────────────────────────────────
  // ④ (a)(f) 既定のパネルが切れずに1枚で読める
  // ─────────────────────────────────────────────────────────
  group('CalendarDayPanel — 既定の要約', () {
    CalendarDayInfo info({
      String? jp,
      String? companyHoliday,
      String? rest,
      String? restReason,
      List<Map<String, dynamic>> reports = const <Map<String, dynamic>>[],
    }) =>
        CalendarDayInfo(
          date: DateTime(2026, 6, 10),
          jpHolidayName: jp,
          companyHolidayType: companyHoliday,
          restPortion: rest,
          restReason: restReason,
          reports: reports,
        );

    // 一番背が高くなる組み合わせ（休みが2行 ＋ 日報の行 ＋ 祝日名つきの見出し）。
    final tallest = info(
      jp: '海の日',
      companyHoliday: 'legal',
      rest: 'full',
      restReason: '私用',
      reports: [
        _row(id: 'a', approved: true),
        _row(id: 'b', status: 'cancelled'),
      ],
    );

    /// パネルの中身（スクロールの中の Column）の実測の高さ。
    Future<double> contentHeight(WidgetTester tester, CalendarDayInfo i,
        {double boxHeight = kCalendarPanelReservedHeight}) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 360,
        height: boxHeight,
        child: CalendarDayPanel(info: i),
      )));
      final col = find
          .descendant(
              of: find.byType(CalendarDayPanel), matching: find.byType(Column))
          .first;
      return tester.getSize(col).height;
    }

    testWidgets('中身は確保した高さに収まる（一番背が高い日でも）', (tester) async {
      final h = await contentHeight(tester, tallest);
      expect(h + kCalendarPanelPaddingV * 2,
          lessThanOrEqualTo(kCalendarPanelReservedHeight));
      expect(tester.takeException(), isNull, reason: 'はみ出しが起きていない');
    });

    testWidgets('4週・5週・6週それぞれで配られた取り分に収まる', (tester) async {
      double justEnough(int rows) =>
          rows * (kCalendarMinCellHeight + kCalendarCellMargin) +
          kCalendarGridPaddingV +
          kCalendarWeekHeaderHeight +
          1 +
          kCalendarPanelReservedHeight;

      for (final rows in <int>[4, 5, 6]) {
        final alloc =
            calendarHeightsFor(available: justEnough(rows), rowCount: rows);
        final h = await contentHeight(tester, tallest,
            boxHeight: alloc.panelHeight);
        expect(h + kCalendarPanelPaddingV * 2,
            lessThanOrEqualTo(alloc.panelHeight + 0.0001),
            reason: '$rows週');
        expect(tester.takeException(), isNull, reason: '$rows週ではみ出し');
      }
    });

    // (f) 休みが両方なしの日は1行にまとめる。
    testWidgets('休みが両方なしの日は1行にまとまる', (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 360,
        height: kCalendarPanelReservedHeight,
        child: CalendarDayPanel(info: info()),
      )));
      expect(find.text('会社休み・自分の休み：なし'), findsOneWidget);
      expect(find.text('会社休み：なし'), findsNothing);
      expect(find.text('自分の休み：なし'), findsNothing);
    });

    testWidgets('会社休みだけの日は2行になる', (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 360,
        height: kCalendarPanelReservedHeight,
        child: CalendarDayPanel(info: info(companyHoliday: 'scheduled')),
      )));
      expect(find.text('会社休み・自分の休み：なし'), findsNothing);
      expect(find.text('会社休み（所定休日）'), findsOneWidget);
      expect(find.text('自分の休み：なし'), findsOneWidget);
    });

    testWidgets('自分の休みだけの日も2行になる', (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 360,
        height: kCalendarPanelReservedHeight,
        child: CalendarDayPanel(info: info(rest: 'am_half')),
      )));
      expect(find.text('会社休み：なし'), findsOneWidget);
      expect(find.text('自分の休み：午前休'), findsOneWidget);
    });

    // 祝日名は行を増やさず見出しへ畳む（(a) の「1枚で読める量」を守るため）。
    testWidgets('祝日名は見出しに畳まれ、行を増やさない', (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 360,
        height: kCalendarPanelReservedHeight,
        child: CalendarDayPanel(info: info(jp: '海の日')),
      )));
      expect(find.text('6月10日（水）・祝日：海の日'), findsOneWidget);
    });

    // 取消済は行を増やさず日報の行の後ろへ足す。件数は生きている日報だけ。
    testWidgets('日報の行は生きている件数を出し、取消済を同じ行へ足す', (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 360,
        height: kCalendarPanelReservedHeight,
        child: CalendarDayPanel(
            info: info(reports: [
          _row(id: 'a', approved: true),
          _row(id: 'b'),
          _row(id: 'c', status: 'cancelled'),
        ])),
      )));
      expect(find.text('日報：2件・取消済1件'), findsOneWidget);
    });

    testWidgets('日報が無い日は「日報：なし」', (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 360,
        height: kCalendarPanelReservedHeight,
        child: CalendarDayPanel(info: info()),
      )));
      expect(find.text('日報：なし'), findsOneWidget);
    });

    // ★旧パネルに在ったボタン2つは、要約からは外してシートへ移した。
    testWidgets('要約にはボタンを置かない（0タップで読める量に絞る）', (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 360,
        height: kCalendarPanelReservedHeight,
        child: CalendarDayPanel(
            info: info(reports: [_row(id: 'a', approved: true)])),
      )));
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('代休で休む'), findsNothing);
      expect(find.text('日報を確認'), findsNothing);
    });
  });

  // ─────────────────────────────────────────────────────────
  // ⑤ (b)(e)(g) せり上がる箱の中身
  // ─────────────────────────────────────────────────────────
  group('CalendarDaySheet — その日の全部', () {
    CalendarDayInfo withReports(List<Map<String, dynamic>> rs) =>
        CalendarDayInfo(date: DateTime(2026, 6, 10), reports: rs);

    final fourStates = <Map<String, dynamic>>[
      _row(id: 'a', approved: true),
      _row(id: 'b', revisionRequested: true),
      _row(id: 'c'),
      _row(id: 'd', approved: true, status: 'cancelled'),
    ];

    testWidgets('4状態の語がそのまま出る（対応表の語と一致）', (tester) async {
      await tester.pumpWidget(_wrap(CalendarDaySheet(
        info: withReports(fourStates),
        maxHeight: 600,
      )));
      for (final s in <String>['approved', 'rejected', 'pending', 'cancelled']) {
        expect(find.text(reportStatusStyleForState(s).label), findsOneWidget,
            reason: s);
      }
      expect(find.text('承認済'), findsOneWidget);
      expect(find.text('差戻し'), findsOneWidget);
      expect(find.text('未承認'), findsOneWidget);
      expect(find.text('取消済'), findsOneWidget);
    });

    testWidgets('4状態の色がそのまま出る（対応表の色と一致・16進で照合）',
        (tester) async {
      await tester.pumpWidget(_wrap(CalendarDaySheet(
        info: withReports(fourStates),
        maxHeight: 600,
      )));
      final seen = _borderColors(tester);
      for (final argb in <int>[_kApproved, _kRejected, _kPending, _kCancelled]) {
        expect(seen.contains(argb), isTrue,
            reason: '0x${argb.toRadixString(16)} が箱の中に無い');
      }
      // 対応表がその16進を返していること（箱と表が同じ色を指している）。
      expect(reportStatusStyleForState('approved').color.toARGB32(), _kApproved);
      expect(reportStatusStyleForState('rejected').color.toARGB32(), _kRejected);
      expect(reportStatusStyleForState('pending').color.toARGB32(), _kPending);
      expect(
          reportStatusStyleForState('cancelled').color.toARGB32(), _kCancelled);
    });

    testWidgets('取消済の日報も箱に並ぶ（一覧から消さない）', (tester) async {
      await tester.pumpWidget(_wrap(CalendarDaySheet(
        info: withReports([_row(id: 'z', status: 'cancelled')]),
        maxHeight: 600,
      )));
      expect(find.text('取消済'), findsOneWidget);
      expect(find.text('日報：なし・取消済1件'), findsOneWidget);
    });

    // (e) 少ない日に大きな空箱を出さない。
    testWidgets('中身が少ない日は上限いっぱいまで伸びない', (tester) async {
      await tester.pumpWidget(_wrap(Align(
        alignment: Alignment.bottomCenter,
        child: CalendarDaySheet(
          info: CalendarDayInfo(date: DateTime(2026, 6, 10)),
          maxHeight: 600,
        ),
      )));
      final h = tester.getSize(find.byType(CalendarDaySheet)).height;
      expect(h, lessThan(600), reason: '空の日に600の箱を出さない');
    });

    testWidgets('中身が多い日は上限で止まる', (tester) async {
      await tester.pumpWidget(_wrap(Align(
        alignment: Alignment.bottomCenter,
        child: CalendarDaySheet(
          info: withReports(
              List.generate(20, (i) => _row(id: 'r$i', approved: true))),
          maxHeight: 400,
        ),
      )));
      final h = tester.getSize(find.byType(CalendarDaySheet)).height;
      expect(h, lessThanOrEqualTo(400));
    });

    testWidgets('日報がある日は「日報を確認」の導線が残る', (tester) async {
      var opened = 0;
      await tester.pumpWidget(_wrap(CalendarDaySheet(
        info: withReports([_row(id: 'a', approved: true)]),
        maxHeight: 600,
        onOpenDayReports: () => opened++,
      )));
      await tester.tap(find.text('日報を確認'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('休みが無い日は「代休で休む」が出て、在る日は出ない', (tester) async {
      await tester.pumpWidget(_wrap(CalendarDaySheet(
        info: CalendarDayInfo(date: DateTime(2026, 6, 10)),
        maxHeight: 600,
        onCompOff: () {},
      )));
      expect(find.text('代休で休む'), findsOneWidget);

      await tester.pumpWidget(_wrap(CalendarDaySheet(
        info: CalendarDayInfo(
            date: DateTime(2026, 6, 10), restPortion: 'full'),
        maxHeight: 600,
        onCompOff: () {},
      )));
      expect(find.text('代休で休む'), findsNothing);
    });
  });

  // ─────────────────────────────────────────────────────────
  // ⑥ (d) 閉じ方が3つとも効く
  //   ★開き方は画面と同じ showCalendarDaySheet を呼ぶ。ここで引数を
  //     書き写すと「本物と同じ開き方」を検査したことにならない。
  // ─────────────────────────────────────────────────────────
  group('showCalendarDaySheet — 閉じ方は3つ', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showCalendarDaySheet(
                  ctx,
                  info: CalendarDayInfo(
                    date: DateTime(2026, 6, 10),
                    reports: [_row(id: 'a', approved: true)],
                  ),
                  maxHeight: 400,
                ),
                child: const Text('ひらく'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ひらく'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDaySheet), findsOneWidget);
    }

    testWidgets('✕ で閉じる', (tester) async {
      await open(tester);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDaySheet), findsNothing);
    });

    testWidgets('見えているカレンダー（暗幕）を押すと閉じる', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDaySheet), findsNothing);
    });

    testWidgets('下スワイプで閉じる', (tester) async {
      await open(tester);
      await tester.drag(find.text('6月10日（水）'), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDaySheet), findsNothing);
    });
  });

  // ─────────────────────────────────────────────────────────
  // ⑦ (g) 対応表の外に手書きの色を足していない
  //   ★同じ手（Directory('lib') を舐めて名簿と突き合わせる）は
  //     test/report_status_style_test.dart と
  //     test/session_lockout_wiring_test.dart に前例がある。
  // ─────────────────────────────────────────────────────────
  group('対応表の外に手書きの状態色を足していない', () {
    final stateMark = RegExp(
        "承認待ち|差し戻し|差戻し|差戻|未承認|取消済|承認済"
        "|'cancelled'|'approved'|'rejected'|'pending'");
    final colorRef = RegExp(r'FieldTokens\.'
        r'(statusSuccess|statusWarning|statusError|statusCancelled'
        r'|textSupport|accent)');

    // 承知している例外と、その本数。名簿に無いファイルは0本でなければならない。
    // ★home_screen.dart はこの名簿に載っていない＝カレンダーの改修で
    //   手書きの色を1本も足していないことが、ここで機械に固定される。
    const kKnownOutsideStatusTable = <String, int>{
      'lib/utils/report_status_style.dart': 4,
      'lib/screens/company_link_screen.dart': 1,
      'lib/screens/punch_screen.dart': 2,
    };

    String slashPath(File f) => f.path.replaceAll(r'\', '/');
    List<String> codeLines(File f) => f
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .toList();

    int hitsIn(File f) => codeLines(f)
        .where((l) => stateMark.hasMatch(l) && colorRef.hasMatch(l))
        .length;

    test('名簿の本数を超えるファイルが無い', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final hits = hitsIn(f);
        if (hits == 0) continue;
        final allowed = kKnownOutsideStatusTable[slashPath(f)] ?? 0;
        if (hits > allowed) {
          offenders.add('${slashPath(f)}: $hits本（名簿は $allowed本）');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('home_screen.dart は0本（カレンダーで手書きの色を足していない）', () {
      expect(hitsIn(File('lib/screens/home_screen.dart')), 0);
    });

    // ★シートの語と色は JsReportTile 経由で対応表から来る。
    //   home_screen.dart が対応表を直接 import していないことは、
    //   test/report_status_style_test.dart の名簿の前提でもある
    //   （あちらが「名簿に載せた画面はまだ対応表を import していない」を見ている）。
    test('home_screen.dart は対応表を直接 import していない（名簿と矛盾させない）', () {
      final src = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(src.contains("import '../utils/report_status_style.dart'"), isFalse);
    });

    // 語と色の出どころ（JsReportTile）は対応表を import し続けていること。
    test('シートが使う JsReportTile の側は対応表を import している', () {
      final src =
          File('lib/screens/monthly_history_screen.dart').readAsStringSync();
      expect(src.contains('report_status_style.dart'), isTrue);
    });
  });
}
