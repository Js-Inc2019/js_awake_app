// ============================================================
// test/report_cancel_gate_test.dart — 取り消した日報が画面で取消済と分かるか
//
// 見ているのは「画面が嘘をつくか」の4点:
//   ① 取消済の行が届いたら、取消済と分かる印が出る
//   ② 取消前が承認済みだった行でも「承認済」とは出ない
//   ③ 今日やる仕事の一覧（承認タブ・是正依頼）に取消済が混ざらない
//   ④ 取消済を見る道が実際に通じる（履歴の「取消」→その日→日報の1枚まで）
//
// ★通信はしない。BE の応答を http.Response として作り、実装と同じ
//   runApiCall / 各画面の読み込みへ素通しする（差し替え口は
//   package:http の runWithClient + MockClient ただ1つ。
//   test/widget_test_report_test.dart と同じ方式）。
// ★行の形は js-office-api routes/reports.js の LIST_COLS に合わせて写す
//   （approved / revision_requested / status の3列が同時に載る）。
// ★期待する文言・件数は実装から import せずここへ直書きする
//   （実装を写すと「実装が変わったらテストも変わる」＝何も検査しない）。
// ============================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/screens/home_screen.dart' show ReviewTab;
import 'package:js_awake_app/screens/monthly_history_screen.dart'
    show MonthlyHistoryBody, JsReportTile, JsStatChip, JsReportDetailSheet;
import 'package:js_awake_app/screens/revision_inbox_screen.dart'
    show RevisionInboxBody, RevisionInboxScreen, ReportDetailSheet;
import 'package:js_awake_app/utils/report_cancel_gate.dart';

// ── BE の行の写し ──────────────────────────────────────────────
// 取消は status だけを 'cancelled' にし、approved と revision_requested は
// 落とさない（js-office-api routes/reports.js の PATCH /reports/:id/cancel が
// "UPDATE reports SET status = 'cancelled'" ただ1文であること）。
// その形をそのまま作る＝取り違えの起きる材料を検査へ持ち込む。
Map<String, dynamic> _row({
  required String id,
  required String date,
  bool approved = false,
  bool revision = false,
  String status = 'open',
  String content = '作業内容',
}) =>
    <String, dynamic>{
      'report_id': id,
      'user_id': 'u1',
      'report_date': date,
      'work_content': content,
      'worker_name': '職人太郎',
      'is_sent': true,
      'approved': approved,
      'revision_requested': revision,
      'status': status,
    };

/// /reports と /attendance/break-requests に答え、他の GET は空 JSON を返す通信。
MockClient _reportsClient(List<Map<String, dynamic>> rows) =>
    MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/attendance/break-requests')) {
        return http.Response(jsonEncode({'requests': const []}), 200,
            request: req, headers: {'content-type': 'application/json'});
      }
      if (path.endsWith('/reports')) {
        return http.Response(jsonEncode({'reports': rows}), 200,
            request: req, headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 200,
          request: req, headers: {'content-type': 'application/json'});
    });

/// 絞り込みチップの「ラベル → 数字」。数えた値をそのまま突き合わせる。
Map<String, int> _chipCounts(WidgetTester tester) => {
      for (final c in tester.widgetList<JsStatChip>(find.byType(JsStatChip)))
        c.label: c.count,
    };

void main() {
  setUp(() {
    // AuthService.getToken が読む唯一のキー。無いと通信の手前で止まる。
    SharedPreferences.setMockInitialValues({'auth_token': 'T'});
  });

  // ──────────────────────────────────────────────────────────
  // ① 判定そのもの（lib/utils/report_cancel_gate.dart）
  //    取消は approved も revision_requested も落とさない。よって
  //    「取消済を先に見る」ことだけが承認済への化けを止めている。
  // ──────────────────────────────────────────────────────────
  group('report_cancel_gate — 4状態の決定', () {
    test('取消前が承認済みでも取消済と答える（承認済にしない）', () {
      final r = _row(id: 'a', date: '2026-09-04',
          approved: true, status: 'cancelled');
      expect(isCancelledReport(r), isTrue);
      expect(reportStatusOf(r), 'cancelled');
    });

    test('取消前が差戻しでも取消済と答える', () {
      final r = _row(id: 'b', date: '2026-09-05',
          revision: true, status: 'cancelled');
      expect(reportStatusOf(r), 'cancelled');
    });

    test('承認済・差戻し・未承認の答えは従来どおり', () {
      expect(reportStatusOf(_row(id: 'c', date: '2026-09-01', approved: true)),
          'approved');
      expect(reportStatusOf(_row(id: 'd', date: '2026-09-02', revision: true)),
          'rejected');
      expect(reportStatusOf(_row(id: 'e', date: '2026-09-03')), 'pending');
    });

    test('status のキーが無い行は取消済にしない（知らない値で消さない）', () {
      final r = <String, dynamic>{'approved': true};
      expect(isCancelledReport(r), isFalse);
      expect(reportStatusOf(r), 'approved');
    });

    test('取消済は承認待ちにも差し戻しにも数えない', () {
      final cancelledPending = _row(id: 'f', date: '2026-09-06',
          status: 'cancelled');
      final cancelledRevision = _row(id: 'g', date: '2026-09-07',
          revision: true, status: 'cancelled');
      expect(isPendingApproval(cancelledPending), isFalse);
      expect(isRevisionRequested(cancelledRevision), isFalse);
      // 取消済でなければ従来どおり数える（条件の後半を変えていないこと）
      expect(isPendingApproval(_row(id: 'h', date: '2026-09-08')), isTrue);
      expect(
          isRevisionRequested(
              _row(id: 'i', date: '2026-09-09', revision: true)),
          isTrue);
    });

    test('withReportStatus は元の行を書き換えず、二度通しても答えが変わらない', () {
      final src = _row(id: 'j', date: '2026-09-04',
          approved: true, status: 'cancelled');
      final once = withReportStatus(src);
      final twice = withReportStatus(once);
      expect(src['status'], 'cancelled', reason: '元の行は触らない');
      expect(once['status'], 'cancelled');
      expect(twice['status'], 'cancelled');
      expect(once['approved'], isTrue,
          reason: 'status 以外のキーは1つも落とさない');
    });
  });

  // ──────────────────────────────────────────────────────────
  // ② 日報1枚の見た目（JsReportTile）
  //    通信しない。行をそのまま渡して描かせる。
  // ──────────────────────────────────────────────────────────
  group('JsReportTile — 取消済の印', () {
    Future<void> pumpTile(WidgetTester tester, Map<String, dynamic> r) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ListView(children: [JsReportTile(report: r)])),
        ));

    testWidgets('取消済の行には取消済の印が出る', (tester) async {
      await pumpTile(tester,
          _row(id: 'a', date: '2026-09-04', status: 'cancelled'));
      expect(find.text('取消済'), findsOneWidget, reason: 'バッジ');
      expect(find.text('取消済（日報は残ります）'), findsOneWidget,
          reason: 'カード本体の1行');
    });

    testWidgets('取消前が承認済みだった行でも「承認済」とは出ない', (tester) async {
      await pumpTile(tester,
          _row(id: 'b', date: '2026-09-04', approved: true, status: 'cancelled'));
      expect(find.text('承認済'), findsNothing);
      expect(find.text('取消済'), findsOneWidget);
    });

    testWidgets('取消前が差戻しだった行でも「差戻し」とは出ない', (tester) async {
      await pumpTile(tester,
          _row(id: 'c', date: '2026-09-05', revision: true, status: 'cancelled'));
      expect(find.text('差戻し'), findsNothing);
      expect(find.text('是正依頼を確認'), findsNothing,
          reason: '取り消した日報から是正依頼へ送ると行き止まりになる');
      expect(find.text('取消済'), findsOneWidget);
    });

    testWidgets('取消していない承認済の行は従来どおり承認済と出る', (tester) async {
      await pumpTile(tester,
          _row(id: 'd', date: '2026-09-01', approved: true));
      expect(find.text('承認済'), findsOneWidget);
      expect(find.text('取消済'), findsNothing);
    });

    // ★タップできない行は「押しても何も起きない行」になり、嘘の記号になる。
    //   取消済も必ず開けること、開いた先にも印が出ることを検査で固定する。
    testWidgets('取消済の行はタップで開き、開いた詳細にも取消済の印が出る',
        (tester) async {
      await pumpTile(tester,
          _row(id: 'e', date: '2026-09-04',
              approved: true, status: 'cancelled'));
      await tester.tap(find.byType(JsReportTile));
      await tester.pumpAndSettle();

      final sheet = find.byType(JsReportDetailSheet);
      expect(sheet, findsOneWidget, reason: '取消済でも詳細が開く');
      expect(
          find.descendant(of: sheet, matching: find.text('取消済')),
          findsOneWidget,
          reason: '詳細のバッジ');
      expect(
          find.descendant(
              of: sheet, matching: find.text('取消済（日報は残ります）')),
          findsOneWidget,
          reason: '詳細の1行。バッジだけだと普通の日報に見える');
      expect(
          find.descendant(of: sheet, matching: find.text('承認済')),
          findsNothing,
          reason: '取消前が承認済みでも承認済とは出ない');
    });

    testWidgets('取消済の詳細には押せる操作が1つも無い', (tester) async {
      await pumpTile(tester,
          _row(id: 'f', date: '2026-09-04', status: 'cancelled'));
      await tester.tap(find.byType(JsReportTile));
      await tester.pumpAndSettle();

      final sheet = find.byType(JsReportDetailSheet);
      expect(
          find.descendant(of: sheet, matching: find.byType(ButtonStyleButton)),
          findsNothing,
          reason: '押せてはいけない操作を出さない（読み取り専用）');
      expect(
          find.descendant(of: sheet, matching: find.text('取り消す')),
          findsNothing);
    });

    testWidgets('取消前が差戻しだった行をタップしても是正依頼へは飛ばない',
        (tester) async {
      await pumpTile(tester,
          _row(id: 'g', date: '2026-09-05',
              revision: true, status: 'cancelled'));
      await tester.tap(find.byType(JsReportTile));
      await tester.pumpAndSettle();

      expect(find.byType(JsReportDetailSheet), findsOneWidget,
          reason: '行き先は詳細');
      expect(find.byType(RevisionInboxScreen), findsNothing,
          reason: '是正依頼は取消済を載せていない＝飛ばすと行き止まりになる');
    });
  });

  // ──────────────────────────────────────────────────────────
  // ②-b もう1つの詳細（revision_inbox_screen.dart の ReportDetailSheet）
  //     こちらにも同じ印を出す（画面ごとに言い換えない）。
  //     写真の取得だけが通信するので MockClient を通す。
  // ──────────────────────────────────────────────────────────
  group('ReportDetailSheet — 取消済の印', () {
    testWidgets('取消済の詳細に印が出て、押せる操作が1つも無い', (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: ReportDetailSheet(
                report: _row(id: 'x1', date: '2026-09-04',
                    approved: true, status: 'cancelled'),
              ),
            ),
          ));
          await tester.pumpAndSettle();
        },
        () => _reportsClient(const []),
      );
      expect(find.text('取消済'), findsOneWidget, reason: 'バッジ');
      expect(find.text('取消済（日報は残ります）'), findsOneWidget,
          reason: '1行の印');
      expect(find.text('承認済'), findsNothing);
      expect(find.byType(ButtonStyleButton), findsNothing,
          reason: '押せてはいけない操作を出さない（読み取り専用）');
    });
  });

  // ──────────────────────────────────────────────────────────
  // ③ 月間履歴 — 一覧を分ける／件数に混ぜない／取消済を見る道
  //
  // 使う月の中身（数えた値）:
  //   承認済1（r1）/ 差戻し1（r2）/ 未承認1（r3）
  //   取消済2（r4=取消前は承認済、r5=取消前は差戻し）
  //   → 合計3（承認1+差戻1+未承認1）・取消2
  //   日付は5件とも別の日なので、一覧の日付行は
  //     絞り込みなし＝3行 / 取消＝2行
  // ──────────────────────────────────────────────────────────
  group('月間履歴 — 今日やる仕事と取消済を混ぜない', () {
    final rows = [
      _row(id: 'r1', date: '2026-09-01', approved: true),
      _row(id: 'r2', date: '2026-09-02', revision: true),
      _row(id: 'r3', date: '2026-09-03'),
      _row(id: 'r4', date: '2026-09-04', approved: true, status: 'cancelled'),
      _row(id: 'r5', date: '2026-09-05', revision: true, status: 'cancelled'),
    ];

    Future<void> pumpHistory(WidgetTester tester) => http.runWithClient(
          () async {
            await tester.pumpWidget(const MaterialApp(
              home: Scaffold(body: MonthlyHistoryBody()),
            ));
            await tester.pumpAndSettle();
          },
          () => _reportsClient(rows),
        );

    testWidgets('件数に取消済が混ざらない（合計3・取消2）', (tester) async {
      await pumpHistory(tester);
      final counts = _chipCounts(tester);
      expect(counts['合計'], 3, reason: '生きている日報だけ');
      expect(counts['承認'], 1);
      expect(counts['差戻'], 1);
      expect(counts['未承認'], 1,
          reason: '取消済2件が未承認へ流れ込んでいないこと');
      expect(counts['取消'], 2);
    });

    testWidgets('既定の一覧に取消済の行が出ない', (tester) async {
      await pumpHistory(tester);
      expect(find.text('取消済'), findsNothing);
      expect(find.text('9月4日'), findsNothing);
      expect(find.text('9月5日'), findsNothing);
      expect(find.text('9月1日'), findsOneWidget);
      expect(find.text('9月2日'), findsOneWidget);
      expect(find.text('9月3日'), findsOneWidget);
    });

    testWidgets('「取消」を押すと取消済だけの一覧に切り替わる', (tester) async {
      await pumpHistory(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('9月4日'), findsOneWidget);
      expect(find.text('9月5日'), findsOneWidget);
      expect(find.text('9月1日'), findsNothing);
      expect(find.text('取消済'), findsNWidgets(2),
          reason: '2つの日付行がどちらも取消済と出ること');
      expect(find.text('承認済'), findsNothing,
          reason: '取消前が承認済みだった日でも承認済とは出ない');
      expect(find.text('取消済1件'), findsNWidgets(2),
          reason: '件数も取消済として数える');
    });

    testWidgets('取消済を見る道が日報1枚まで通じる（行き止まりにしない）',
        (tester) async {
      await pumpHistory(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9月4日'));
      await tester.pumpAndSettle();

      expect(find.text('9月4日の日報'), findsOneWidget,
          reason: 'その日の日報の画面へ着く');
      expect(find.text('取消済（日報は残ります）'), findsOneWidget,
          reason: '取り消した1枚がそこに残っていて、取消済と分かる');
      expect(find.text('承認済'), findsNothing,
          reason: '取消前が承認済みでも承認済とは出ない');
      expect(find.text('取り消す'), findsNothing,
          reason: '押しても BE が断るだけの空押しを出さない');
      // その日の画面は件数を2箇所に出す（一番上の合計と、現場ごとの見出し）。
      // 現場が1つ・日報が1枚なので、同じ文字列がちょうど2つ出る。
      expect(find.text('0件・取消済1件'), findsNWidgets(2),
          reason: '件数も生きている日報と取消済を分けて出す');
    });
  });

  // ──────────────────────────────────────────────────────────
  // ④ 今日やる仕事の一覧に取消済が混ざらない
  // ──────────────────────────────────────────────────────────
  group('承認タブ（今日やる仕事）— 取消済を載せない', () {
    testWidgets('取消済だけの月は「対応が必要な報告はありません」', (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(
            home: Scaffold(body: ReviewTab()),
          ));
          await tester.pumpAndSettle();
        },
        () => _reportsClient([
          // 取消前は承認待ちだった1枚と、取消前は差戻しだった1枚。
          _row(id: 'c1', date: '2026-09-04', status: 'cancelled'),
          _row(id: 'c2', date: '2026-09-05',
              revision: true, status: 'cancelled'),
        ]),
      );
      expect(find.text('対応が必要な報告はありません'), findsOneWidget);
    });

    testWidgets('生きている承認待ちだけが数に入る（取消済は足されない）',
        (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(
            home: Scaffold(body: ReviewTab()),
          ));
          await tester.pumpAndSettle();
        },
        () => _reportsClient([
          _row(id: 'p1', date: '2026-09-10'),
          _row(id: 'c1', date: '2026-09-10', status: 'cancelled'),
        ]),
      );
      expect(find.text('1件'), findsOneWidget,
          reason: '同じ日の取消済1件を足して2件にしないこと');
      expect(find.text('承認待ち1'), findsOneWidget);
    });
  });

  // ──────────────────────────────────────────────────────────
  // ⑤ 是正依頼の一覧に取消済が混ざらない
  //    BE の GET /reports?revision_requested=true は取消済を除外しない。
  // ──────────────────────────────────────────────────────────
  group('是正依頼 — 取消済を載せない', () {
    testWidgets('取消済の差戻しは一覧に出ない', (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(
            home: Scaffold(body: RevisionInboxBody()),
          ));
          await tester.pumpAndSettle();
        },
        () => _reportsClient([
          _row(id: 'c2', date: '2026-09-05', content: '取り消した差戻し',
              revision: true, status: 'cancelled'),
        ]),
      );
      expect(find.text('取り消した差戻し'), findsNothing);
    });

    testWidgets('取り消していない差戻しは従来どおり出る', (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(
            home: Scaffold(body: RevisionInboxBody()),
          ));
          await tester.pumpAndSettle();
        },
        () => _reportsClient([
          _row(id: 'v1', date: '2026-09-02', content: '生きている差戻し',
              revision: true),
        ]),
      );
      expect(find.text('生きている差戻し'), findsOneWidget);
    });
  });
}
