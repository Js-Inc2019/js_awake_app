// ============================================================
// test/report_status_style_test.dart — 状態の色と語が1本に揃っているか
//
// 見ているのは3点:
//   ① 対応表そのもの（lib/utils/report_status_style.dart）が4状態に
//      正しい色と語を返す。特に取消済が専用色で、未承認と別の色であること。
//   ② 共有の送信候補の1行に状態の印（左の縦帯＋2段目の語）が出る。
//      承認済には何も足さない。行は消えず・押せて・チェックも外れない。
//   ③ 送れない日報の件数を数える式と、下部バーの真上に出る注意帯。
//   ④ 対応表の【外】で日報の状態から色を手書きしていないこと。
//      これは次に誰かが手書きを足したら落ちる鳴子で、ソースを直接読む。
//      同じ手（Directory('lib') を舐めて名簿と突き合わせる）は
//      test/session_lockout_wiring_test.dart の「runApiCall を通らない通信」に前例がある。
//
// ★期待する色・文言はすべてここへ直書きする（実装から import しない）。
//   実装を写すと「実装が変わったらテストも変わる」＝何も検査しない。
//   色は 16進の生の値で書く。トークン名で書くと、トークンの値が
//   差し替わったときに気付けない。
//
// ★画面（ShareSendScreen）は立てない。ReportsService 等のシングルトンを
//   直接触るため widget テストで実HTTPを避けられない（この線引きは
//   test/share_send_confirm_test.dart の冒頭に既に書かれている）。
//   代わりに公開部品 ShareCandidateRow / ShareSendCautionBanner を
//   直接組む。monthly_history_screen.dart の JsReportTile を
//   test/report_cancel_gate_test.dart が直接組んでいるのと同じ手。
// ============================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:js_awake_app/screens/share_send_screen.dart'
    show
        ShareCandidateRow,
        ShareSendBlockedCounts,
        ShareSendCautionBanner,
        shareSendBlockedCounts;
import 'package:js_awake_app/utils/report_status_style.dart';

// ── BE の行の写し ──────────────────────────────────────────────
// 取消は status だけを 'cancelled' にし、approved と revision_requested は
// 落とさない（js-office-api routes/reports.js の PATCH /reports/:id/cancel が
// "UPDATE reports SET status = 'cancelled'" ただ1文であること）。
// 送信候補の一覧 GET /reports は approved と status の両方を載せる（同 LIST_COLS）。
Map<String, dynamic> _row({
  required String id,
  bool approved = false,
  bool revisionRequested = false,
  String status = 'open',
  String siteName = '現場A',
}) =>
    <String, dynamic>{
      'report_id': id,
      'report_date': '2026-06-10',
      'worker_name': '職人太郎',
      'site_name': siteName,
      'approved': approved,
      'revision_requested': revisionRequested,
      'status': status,
    };

// 期待する色（16進の生の値。トークン名では書かない）
const int _kCancelled = 0xFFA98FC0; // 藤
const int _kApproved = 0xFF6FD6B4;
const int _kRejected = 0xFFE05252;
const int _kPending = 0xFFE0603A; // 橙。未承認はこの1色に統一した

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// 幅4の縦帯を、指定の色で探す。
Finder _bandOfColor(int argb) => find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      if (w.constraints?.maxWidth != 4.0) return false;
      final d = w.decoration;
      return d is BoxDecoration && d.color?.toARGB32() == argb;
    });

/// 幅4の縦帯（色を問わない）。
Finder get _anyBand => find.byWidgetPredicate((w) =>
    w is Container &&
    w.constraints?.maxWidth == 4.0 &&
    w.decoration is BoxDecoration);

void main() {
  // ─────────────────────────────────────────────────────────
  // ① 対応表そのもの
  // ─────────────────────────────────────────────────────────
  group('reportStatusStyleForState — 状態から色と語', () {
    test('取消済は藤色で語は取消済', () {
      final s = reportStatusStyleForState('cancelled');
      expect(s.color.toARGB32(), _kCancelled);
      expect(s.label, '取消済');
    });

    test('承認済は緑で語は承認済', () {
      final s = reportStatusStyleForState('approved');
      expect(s.color.toARGB32(), _kApproved);
      expect(s.label, '承認済');
    });

    test('差戻しは赤で語は差戻し', () {
      final s = reportStatusStyleForState('rejected');
      expect(s.color.toARGB32(), _kRejected);
      expect(s.label, '差戻し');
    });

    test('未承認は橙で語は未承認', () {
      final s = reportStatusStyleForState('pending');
      expect(s.color.toARGB32(), _kPending);
      expect(s.label, '未承認');
    });

    // ★これが今回いちばん見たい点。直す前は取消済と未承認が同じ温グレーで、
    //   色だけでは見分けが付かなかった。
    test('取消済と未承認は違う色になった（同じ灰を共有していない）', () {
      expect(reportStatusStyleForState('cancelled').color,
          isNot(reportStatusStyleForState('pending').color));
    });

    test('4状態の色は互いに全部違う', () {
      final colors = <String>['cancelled', 'approved', 'rejected', 'pending']
          .map((s) => reportStatusStyleForState(s).color.toARGB32())
          .toSet();
      expect(colors.length, 4);
    });

    test('4状態の語は互いに全部違う', () {
      final labels = <String>['cancelled', 'approved', 'rejected', 'pending']
          .map((s) => reportStatusStyleForState(s).label)
          .toSet();
      expect(labels.length, 4);
    });

    // 知らない値で落ちない・取消済へ倒さない（生きている日報を消す方向の嘘を作らない）。
    test('知らない状態は未承認へ倒す（取消済へ倒さない）', () {
      for (final s in <String>['open', 'locked', '', 'unknown']) {
        expect(reportStatusStyleForState(s).label, '未承認', reason: s);
        expect(reportStatusStyleForState(s).color.toARGB32(), _kPending,
            reason: s);
      }
    });

    test('対応表のキーは4つだけ', () {
      expect(kReportStatusStyles.keys.toSet(),
          <String>{'cancelled', 'approved', 'rejected', 'pending'});
    });
  });

  group('reportStatusStyleOf — 行から直接引く', () {
    test('取消前が承認済みの行でも取消済の色と語になる', () {
      final s = reportStatusStyleOf(
          _row(id: 'r1', approved: true, status: 'cancelled'));
      expect(s.label, '取消済');
      expect(s.color.toARGB32(), _kCancelled);
    });

    test('取消前が差戻し中の行でも取消済になる', () {
      final s = reportStatusStyleOf(
          _row(id: 'r2', revisionRequested: true, status: 'cancelled'));
      expect(s.label, '取消済');
    });

    test('承認済・差戻し・未承認は従来どおり', () {
      expect(reportStatusStyleOf(_row(id: 'a', approved: true)).label, '承認済');
      expect(
          reportStatusStyleOf(_row(id: 'b', revisionRequested: true)).label,
          '差戻し');
      expect(reportStatusStyleOf(_row(id: 'c')).label, '未承認');
    });
  });

  // ─────────────────────────────────────────────────────────
  // ② 送信候補の1行に印が出る
  // ─────────────────────────────────────────────────────────
  group('ShareCandidateRow — 候補行の状態の印', () {
    Future<void> pumpRow(WidgetTester tester, Map<String, dynamic> r,
        {bool checked = false,
        VoidCallback? onTap,
        ValueChanged<bool?>? onChanged}) async {
      await tester.pumpWidget(_wrap(ShareCandidateRow(
        report: r,
        checked: checked,
        onChanged: onChanged ?? (_) {},
        onTap: onTap ?? () {},
      )));
    }

    testWidgets('取消済の行には藤色の縦帯と取消済の語が出る', (tester) async {
      await pumpRow(tester, _row(id: 'r1', approved: true, status: 'cancelled'));
      expect(_bandOfColor(_kCancelled), findsOneWidget, reason: '左の縦帯');
      expect(find.text('取消済'), findsOneWidget, reason: '2段目の語');
    });

    testWidgets('未承認の行には橙の縦帯と未承認の語が出る', (tester) async {
      await pumpRow(tester, _row(id: 'r2'));
      expect(_bandOfColor(_kPending), findsOneWidget);
      expect(find.text('未承認'), findsOneWidget);
    });

    testWidgets('差戻し中の行には赤の縦帯と差戻しの語が出る', (tester) async {
      await pumpRow(tester, _row(id: 'r3', revisionRequested: true));
      expect(_bandOfColor(_kRejected), findsOneWidget);
      expect(find.text('差戻し'), findsOneWidget);
    });

    // ★承認済＝送れる行。ここに印を足すと印の意味が薄まる。
    testWidgets('承認済の行には縦帯も語も出ない', (tester) async {
      await pumpRow(tester, _row(id: 'r4', approved: true));
      expect(_anyBand, findsNothing, reason: '帯なし');
      expect(find.text('承認済'), findsNothing, reason: '語なし');
      expect(find.text('取消済'), findsNothing);
      expect(find.text('未承認'), findsNothing);
      expect(find.text('差戻し'), findsNothing);
    });

    // ★行は一覧から消さない。消すと「条件に合う日報が無い」という別の嘘になる。
    testWidgets('取消済でも日付・職人・現場名はそのまま並ぶ（行を消さない）',
        (tester) async {
      await tester.pumpWidget(_wrap(ShareCandidateRow(
        report: _row(id: 'r5', status: 'cancelled', siteName: '現場ZZ'),
        checked: false,
        onChanged: (_) {},
        onTap: () {},
      )));
      expect(find.text('2026-06-10'), findsOneWidget);
      expect(find.text('職人太郎'), findsOneWidget);
      expect(find.text('現場ZZ'), findsOneWidget);
    });

    // ★取消済でもタップで開ける（押しても何も起きない行を作らない）。
    testWidgets('取消済の行もタップでプレビューが呼ばれる', (tester) async {
      var tapped = 0;
      await pumpRow(tester, _row(id: 'r6', status: 'cancelled'),
          onTap: () => tapped++);
      await tester.tap(find.text('2026-06-10'));
      await tester.pump();
      expect(tapped, 1);
    });

    // ★チェックは画面が勝手に外さない。外すかどうかは人が決める。
    testWidgets('取消済でもチェック済みのまま描ける（勝手に外さない）',
        (tester) async {
      await pumpRow(tester, _row(id: 'r7', status: 'cancelled'), checked: true);
      final box = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(box.value, isTrue);
      expect(box.onChanged, isNotNull, reason: '押せる状態のまま');
    });

    testWidgets('取消済のチェックは人の操作で外せる', (tester) async {
      bool? got;
      await pumpRow(tester, _row(id: 'r8', status: 'cancelled'),
          checked: true, onChanged: (v) => got = v);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(got, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────
  // ③ 送れない件数の数えと注意帯
  // ─────────────────────────────────────────────────────────
  group('shareSendBlockedCounts — 送れない日報の数え', () {
    test('承認済だけなら0件', () {
      final c = shareSendBlockedCounts([
        _row(id: 'a', approved: true),
        _row(id: 'b', approved: true),
      ]);
      expect(c.total, 0);
      expect(c.cancelled, 0);
      expect(c.rejected, 0);
      expect(c.pending, 0);
    });

    test('取消済・差戻し・未承認を状態ごとに数える', () {
      final c = shareSendBlockedCounts([
        _row(id: 'a', approved: true),
        _row(id: 'b', status: 'cancelled'),
        _row(id: 'c', approved: true, status: 'cancelled'),
        _row(id: 'd', revisionRequested: true),
        _row(id: 'e'),
      ]);
      expect(c.cancelled, 2, reason: '承認済だった取消済も取消済として数える');
      expect(c.rejected, 1);
      expect(c.pending, 1);
      expect(c.total, 4);
    });

    // ★BE の承認ゲートと同じ集合であること。
    //   js-office-api routes/bundles.js は
    //   `r.approved !== true || r.status === 'cancelled'` を送れない行として数える。
    test('BE が断る行の数と一致する（approved!=true または 取消済）', () {
      final rows = <Map<String, dynamic>>[
        _row(id: 'a', approved: true),
        _row(id: 'b', approved: true, status: 'cancelled'),
        _row(id: 'c', revisionRequested: true),
        _row(id: 'd'),
        _row(id: 'e', status: 'cancelled'),
      ];
      final beWouldReject = rows
          .where((r) => r['approved'] != true || r['status'] == 'cancelled')
          .length;
      expect(shareSendBlockedCounts(rows).total, beWouldReject);
    });

    test('空の選択は0件', () {
      expect(shareSendBlockedCounts(const []).total, 0);
    });
  });

  group('ShareSendCautionBanner — 下部バーの真上の注意帯', () {
    const beSentence = '承認済みの日報のみ送信できます。'
        '未承認・差戻し中の日報は承認を受けてから、'
        '取消済みの日報は選択から外してから送信してください';

    testWidgets('件数と、承認済みだけが送れる旨がその場で読める', (tester) async {
      await tester.pumpWidget(_wrap(const ShareSendCautionBanner(
        counts:
            ShareSendBlockedCounts(cancelled: 2, rejected: 1, pending: 3),
      )));
      expect(find.text('選択中に 取消済2件・差戻し1件・未承認3件 が含まれています'),
          findsOneWidget);
      expect(find.text(beSentence), findsOneWidget);
    });

    test('0件の状態は並びに書かない', () {
      const b = ShareSendCautionBanner(
        counts: ShareSendBlockedCounts(cancelled: 1, rejected: 0, pending: 0),
      );
      expect(b.countsLine, '選択中に 取消済1件 が含まれています');
    });

    test('未承認だけのときも数を丸めない', () {
      const b = ShareSendCautionBanner(
        counts: ShareSendBlockedCounts(cancelled: 0, rejected: 0, pending: 12),
      );
      expect(b.countsLine, '選択中に 未承認12件 が含まれています');
    });
  });

  // ─────────────────────────────────────────────────────────
  // ④ 対応表の外に手書きが残っていないことの鳴子
  //
  // ★ソースを直接読む理由: 手書きの割り当ては「どこかの画面にだけ残る」形で
  //   増える。増えたことは画面を1枚ずつ開かないと分からないので、
  //   増えた瞬間に落ちる仕掛けをここに置く。
  //   同じ手（Directory('lib') を舐めて名簿と突き合わせる）は
  //   test/session_lockout_wiring_test.dart に前例がある。
  // ─────────────────────────────────────────────────────────
  group('④ 対応表の外に手書きの状態色が無い', () {
    // 日報の4状態を指す印。機械のキーと、画面に出る語の両方を見る。
    final stateMark = RegExp(
        "承認待ち|差し戻し|差戻し|差戻|未承認|取消済|承認済"
        "|'cancelled'|'approved'|'rejected'|'pending'");
    // 状態の色として使われうるトークン。
    final colorRef = RegExp(r'FieldTokens\.'
        r'(statusSuccess|statusWarning|statusError|statusCancelled'
        r'|textSupport|accent)');

    // 承知している例外と、その本数。名簿に無いファイルは0本でなければならない。
    // ★本数まで書くのが要点。ファイル名だけ許すと、同じファイルに手書きを
    //   何本足しても素通りしてしまう。
    const knownOutside = <String, int>{
      // 対応表そのもの。ここに4状態ぶんの割り当てが並ぶのが正しい姿。
      'lib/utils/report_status_style.dart': 4,
      // 会社連携の申請の状態（'active' / 'rejected' / 審査中）。日報ではない。
      //   語も '承認済み' / '却下' / '審査中' で、日報の4語と1つも一致しない
      //   （lib/screens/company_link_screen.dart の _statusLabel）。
      'lib/screens/company_link_screen.dart': 1,
      // ホームの要対応行（_AttentionRow）の2本。日報の状態から色を出しているが、
      //   1枚の日報に付けるバッジではなく件数の行の左に立てる2pxの帯なので、
      //   寄せるかどうかの裁定を待っている。理由は同ファイルのコメントに書いた。
      'lib/screens/punch_screen.dart': 2,
    };

    // Windows は path の区切りが円記号になる。名簿はスラッシュで書いてあるので、
    // 引く前に揃える（揃えないと Windows でだけ名簿に当たらない）。
    String slashPath(File f) => f.path.replaceAll(r'\', '/');

    // 行コメントだけを落とす。コメントアウトで検査を黙らせないため。
    List<String> codeLines(File f) => f
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .toList();

    test('状態と色を同じ行に並べた箇所は名簿の本数を超えない', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final hits = codeLines(f)
            .where((l) => stateMark.hasMatch(l) && colorRef.hasMatch(l))
            .length;
        if (hits == 0) continue;
        final allowed = knownOutside[slashPath(f)] ?? 0;
        if (hits > allowed) {
          offenders.add('${slashPath(f)}: $hits本'
              '（名簿で承知しているのは $allowed本）');
        }
      }
      expect(offenders, isEmpty,
          reason: '対応表(lib/utils/report_status_style.dart)を通さずに'
              '日報の状態から色を決めている箇所がある:\n${offenders.join('\n')}');
    });

    // 寄せた画面が、あとから手書きへ戻されないようにする。
    test('対応表へ寄せた画面は対応表を import している', () {
      const joined = <String>[
        'lib/screens/monthly_history_screen.dart',
        'lib/screens/share_send_screen.dart',
        'lib/screens/revision_inbox_screen.dart',
        'lib/screens/approval_day_screen.dart',
      ];
      for (final path in joined) {
        final src = codeLines(File(path)).join('\n');
        expect(src.contains('report_status_style.dart'), isTrue,
            reason: '$path が対応表を import していない'
                '（状態の色を手書きへ戻した疑い）');
      }
    });

    // 名簿が古びて嘘にならないようにする。寄せたのに名簿へ残すと落ちる。
    test('名簿に載せた画面は、まだ対応表を import していない', () {
      const notJoined = <String>[
        'lib/screens/punch_screen.dart',
        'lib/screens/home_screen.dart',
      ];
      for (final path in notJoined) {
        final src = codeLines(File(path)).join('\n');
        expect(src.contains('report_status_style.dart'), isFalse,
            reason: '$path は対応表へ寄せたのに名簿へ残っている'
                '（名簿から外してこの検査を直すこと）');
      }
    });
  });
}
