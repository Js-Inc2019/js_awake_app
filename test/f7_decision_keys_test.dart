// ============================================================
// test/f7_decision_keys_test.dart
//   便 F7 の3つを機械で固定する。
//
// ★何を守るか（すべて二者比較。「出ない」だけで合格にしない）:
//   (1) 振替の候補の取り込み（ReportsService.substituteCandidatesFromBody）が
//       rest_date_reason_code / rest_date_reason を捨てずに渡す。
//   (2) 送り手と受け手をつなげる: BE の本文（JSON の文字列）→ 本物の取り込み →
//       登録の画面、の順に通して「休む日そのものの断り」の分かれに入る。
//       ★前の検査は偽の口で値を直に渡していたので、取り込みが捨てても通っていた。
//   (3) 承認のカード: 鍵が true・false・キー無しでボタンの押せる／押せないと
//       理由の行が出し分かれる。
//   (4) 許可を得た日報の印の語（カードと承認の日の画面の人の行）。
//   (5) 承認待ちの数から、承認を押せない行を除く。
//
// ★画面は立てる（test/substitute_register_test.dart と同じ）。差し替え口のある
//   画面は偽の口を渡し、PendingApprovalCard は組み立て時に通信しない
//   （写真は押したときだけ取りに行く）のでそのまま立てる。
// ★掟: 期待値（語・真偽）はこのファイル内で組み立てる。実装の定数は import しない。
// ============================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/core/permitted_report_labels.dart'
    show permittedReportMarkOrNull;
import 'package:js_awake_app/screens/approval_day_screen.dart'
    show ApprovalDayScreen;
import 'package:js_awake_app/screens/home_screen.dart'
    show
        PendingApprovalCard,
        approvalDenyLines,
        canApproveReport,
        canRequestRevisionReport,
        countApprovablePending;
import 'package:js_awake_app/screens/substitute_register_screen.dart'
    show SubstituteRegisterScreen;
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';

// ── 画面・BE の実文言（lib と BE の実文字列をここへ写した）─────────────
const String kRegisterGo = 'この内容で登録する';
const String kWorkHead = '代わりに出勤する日';
// BE js-office-api routes/rest_days.js の TEXT_PAST_OUT_OF_WEEK を写した形の文。
// ★中身が何であれ【そのまま】出ることを見るので、文そのものはこの本の中の値。
const String kPastOutOfWeek = '今週より前の日は選べません';
// BE js-office-api routes/reports.js の PERMITTED_REPORT_ADMIN_ONLY / SELF_REVISION_FORBIDDEN。
const String kAdminOnly = 'この日報は事務のみ承認できます';
const String kSelfRevision = '自分の日報には差戻できません';
const String kMarkFix = '振替の出勤日の日報（許可あり）';
const String kMarkMissing = '日報漏れの日報（許可あり）';

/// BE の GET /rest-days/substitute/candidates の本文（JSON の文字列）。
///   ★形は BE の res.json({...}) と同じ並び・同じキー。
String _candidatesBody({
  String? reasonCode,
  String? reason,
  bool withReasonKeys = true,
}) =>
    jsonEncode({
      'rest_date': '2026-06-13',
      'rest_date_is_workday': true,
      if (withReasonKeys) 'rest_date_reason_code': reasonCode,
      if (withReasonKeys) 'rest_date_reason': reason,
      'holiday_def_configured': true,
      'days': [
        {
          'date': '2026-06-07', 'dow': 0, 'selectable': true,
          'reason_code': null, 'reason': null,
        },
        {
          'date': '2026-06-14', 'dow': 0, 'selectable': true,
          'reason_code': null, 'reason': null,
        },
      ],
    });

/// 候補の口だけ差し替える。★返す Map は【本物の取り込み】を通したもの。
///   値を直に組み立てない（それをすると取り込みが捨てても通ってしまう）。
class _BodySvc extends ReportsService {
  _BodySvc(this.body) : super.forTest();
  final String body;

  @override
  Future<ApiResult<Map<String, dynamic>>> getSubstituteWorkDateCandidates(
      String restDate) async {
    return apiSuccess<Map<String, dynamic>>(
      statusCode: 200,
      data: ReportsService.substituteCandidatesFromBody(body),
    );
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

/// 承認待ちの1行（BE の GET /reports の行の形）。
Map<String, dynamic> _row({
  String id = 'r1',
  bool? canApprove,
  bool? canRevision,
  String? approveReason,
  String? revisionReason,
  String? confirmType,
  bool keys = true,
}) =>
    {
      'report_id': id,
      'worker_name': '山田 太郎',
      'report_date': '2026-09-24',
      'work_content': '配線',
      'is_sent': true,
      'approved': false,
      'revision_requested': false,
      'site_id': 's1',
      'confirm_type': confirmType,
      if (keys) ...{
        'can_approve': canApprove ?? true,
        'cannot_approve_code': null,
        'cannot_approve_reason': approveReason,
        'can_request_revision': canRevision ?? true,
        'cannot_request_revision_code': null,
        'cannot_request_revision_reason': revisionReason,
      },
    };

Future<void> _pumpCard(WidgetTester tester, Map<String, dynamic> r) =>
    _pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: PendingApprovalCard(report: r, onActionSuccess: () {}),
        ),
      ),
    );

ElevatedButton _button(WidgetTester tester, String label) =>
    tester.widget<ElevatedButton>(find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ElevatedButton),
    ));

void main() {
  // ══════════════════════════════════════════════════════════
  // (1) 取り込みが2つのキーを渡す
  // ══════════════════════════════════════════════════════════
  group('(1) 振替の候補の取り込み', () {
    test('rest_date_reason_code と rest_date_reason を BE の値のまま渡す', () {
      final m = ReportsService.substituteCandidatesFromBody(_candidatesBody(
          reasonCode: 'past_out_of_week', reason: kPastOutOfWeek));
      expect(m['rest_date_reason_code'], 'past_out_of_week');
      expect(m['rest_date_reason'], kPastOutOfWeek);
      // ★既存のキーも今までどおり。
      expect(m['rest_date'], '2026-06-13');
      expect(m['rest_date_is_workday'], isTrue);
      expect(m['holiday_def_configured'], isTrue);
      expect((m['days'] as List).length, 2);
    });

    test('対照: 断りが無い回（null）は null のまま＝キーはある', () {
      final m = ReportsService.substituteCandidatesFromBody(_candidatesBody());
      expect(m.containsKey('rest_date_reason_code'), isTrue);
      expect(m['rest_date_reason_code'], isNull);
      expect(m['rest_date_reason'], isNull);
    });

    test('rest_date_has_report の文（日付入り）も言い換えない', () {
      const text = '6月13日には日報があります';
      final m = ReportsService.substituteCandidatesFromBody(_candidatesBody(
          reasonCode: 'rest_date_has_report', reason: text));
      expect(m['rest_date_reason_code'], 'rest_date_has_report');
      expect(m['rest_date_reason'], text);
    });

    test('キーを持たない古い応答は null（落とさない）', () {
      final m = ReportsService.substituteCandidatesFromBody(
          _candidatesBody(withReasonKeys: false));
      expect(m['rest_date_reason_code'], isNull);
      expect(m['rest_date_reason'], isNull);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (2) 本物の取り込みを通して、画面の「休む日そのものの断り」に入る
  // ══════════════════════════════════════════════════════════
  group('(2) 送り手と受け手をつなげる', () {
    testWidgets('★BE の本文に past_out_of_week → 候補も登録のボタンも出ず、BE の文が出る',
        (tester) async {
      await _pump(
        tester,
        SubstituteRegisterScreen(
          restDate: '2026-06-13',
          service: _BodySvc(_candidatesBody(
              reasonCode: 'past_out_of_week', reason: kPastOutOfWeek)),
        ),
      );
      expect(find.text(kPastOutOfWeek), findsOneWidget,
          reason: 'BE の文が出ていない（取り込みが捨てている）');
      expect(find.text(kRegisterGo), findsNothing,
          reason: '登録のボタンを出している（押すと 409）');
      expect(find.text(kWorkHead), findsNothing, reason: '候補を並べている');
    });

    testWidgets('対照: BE の本文が null なら候補も登録のボタンも出る', (tester) async {
      await _pump(
        tester,
        SubstituteRegisterScreen(
          restDate: '2026-06-13',
          service: _BodySvc(_candidatesBody()),
        ),
      );
      expect(find.text(kRegisterGo), findsOneWidget);
      expect(find.text(kWorkHead), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (3) 承認のカード
  // ══════════════════════════════════════════════════════════
  group('(3) 承認のカードの出し分け', () {
    test('鍵の読み: true・false・キー無し（キー無しは押せる扱い）', () {
      expect(canApproveReport(_row()), isTrue);
      expect(canApproveReport(_row(canApprove: false)), isFalse);
      expect(canApproveReport(_row(keys: false)), isTrue);
      expect(canRequestRevisionReport(_row()), isTrue);
      expect(canRequestRevisionReport(_row(canRevision: false)), isFalse);
      expect(canRequestRevisionReport(_row(keys: false)), isTrue);
    });

    test('理由の行: 理由ありは「頭：理由」・null は頭の語だけ・押せるなら無し', () {
      expect(approvalDenyLines(_row()), isEmpty);
      expect(approvalDenyLines(_row(keys: false)), isEmpty);
      expect(
          approvalDenyLines(_row(
              canApprove: false,
              approveReason: kAdminOnly,
              canRevision: false,
              revisionReason: kAdminOnly)),
          ['承認できません：$kAdminOnly', '修正依頼できません：$kAdminOnly']);
      expect(approvalDenyLines(_row(canApprove: false)), ['承認できません']);
      expect(approvalDenyLines(_row(canRevision: false)), ['修正依頼できません']);
    });

    testWidgets('鍵が true → 2つとも押せて、理由の行は出ない', (tester) async {
      await _pumpCard(tester, _row());
      expect(_button(tester, '承認').onPressed, isNotNull);
      expect(_button(tester, '修正依頼').onPressed, isNotNull);
      expect(find.textContaining('できません'), findsNothing);
    });

    testWidgets('キー無し（古いサーバ）→ 今までどおり2つとも押せる', (tester) async {
      await _pumpCard(tester, _row(keys: false));
      expect(_button(tester, '承認').onPressed, isNotNull);
      expect(_button(tester, '修正依頼').onPressed, isNotNull);
      expect(find.textContaining('できません'), findsNothing);
    });

    testWidgets('★承認だけ false → 承認は灰色で残して押せず、下に理由。修正依頼は押せる',
        (tester) async {
      await _pumpCard(
          tester, _row(canApprove: false, approveReason: kAdminOnly));
      // ボタンは消さない（灰色で残す）。
      expect(find.text('承認'), findsOneWidget);
      expect(_button(tester, '承認').onPressed, isNull);
      expect(_button(tester, '修正依頼').onPressed, isNotNull);
      expect(find.text('承認できません：$kAdminOnly'), findsOneWidget);
      expect(find.textContaining('修正依頼できません'), findsNothing);
    });

    testWidgets('★修正依頼だけ false・理由が null → 頭の語だけ', (tester) async {
      await _pumpCard(tester, _row(canRevision: false));
      expect(_button(tester, '承認').onPressed, isNotNull);
      expect(find.text('修正依頼'), findsOneWidget);
      expect(_button(tester, '修正依頼').onPressed, isNull);
      expect(find.text('修正依頼できません'), findsOneWidget);
    });

    testWidgets('2つとも false → 理由の行が2行（承認 → 修正依頼の順）', (tester) async {
      await _pumpCard(
          tester,
          _row(
              canApprove: false,
              approveReason: kAdminOnly,
              canRevision: false,
              revisionReason: kSelfRevision));
      expect(_button(tester, '承認').onPressed, isNull);
      expect(_button(tester, '修正依頼').onPressed, isNull);
      final a = tester.getTopLeft(find.text('承認できません：$kAdminOnly'));
      final b = tester.getTopLeft(find.text('修正依頼できません：$kSelfRevision'));
      expect(a.dy < b.dy, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (4) 許可を得た日報の印
  // ══════════════════════════════════════════════════════════
  group('(4) 許可を得た日報の印', () {
    test('語は事務アプリと同じ・通常の日報と表に無い値は null', () {
      expect(permittedReportMarkOrNull('attendance_fix'), kMarkFix);
      expect(permittedReportMarkOrNull('report_missing'), kMarkMissing);
      expect(permittedReportMarkOrNull(null), isNull);
      expect(permittedReportMarkOrNull(''), isNull);
      expect(permittedReportMarkOrNull('comp_off'), isNull);
    });

    testWidgets('カード: attendance_fix に印・通常の日報には出ない', (tester) async {
      await _pumpCard(tester, _row(confirmType: 'attendance_fix'));
      expect(find.text(kMarkFix), findsOneWidget);
      await _pumpCard(tester, _row());
      expect(find.text(kMarkFix), findsNothing);
      expect(find.text(kMarkMissing), findsNothing);
    });

    testWidgets('承認の日の画面の人の行: 許可ありの人にだけ印', (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      await _pump(
        tester,
        ApprovalDayScreen(
          date: DateTime(2026, 9, 24),
          reports: [
            {..._row(id: 'a', confirmType: 'report_missing'), 'worker_name': '甲'},
            {..._row(id: 'b'), 'worker_name': '乙'},
          ],
        ),
      );
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('乙'), findsOneWidget);
      expect(find.text(kMarkMissing), findsOneWidget);
      expect(find.text(kMarkFix), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (5) 承認待ちの数
  // ══════════════════════════════════════════════════════════
  group('(5) 承認待ちの数', () {
    test('押せない行（can_approve が false）は数えない・キー無しは数える', () {
      final rows = [
        _row(id: '1'),
        _row(id: '2', canApprove: false, approveReason: kAdminOnly),
        _row(id: '3', keys: false),
        // ★承認待ちでない行は、押せても数えない（今の条件は変えない）。
        {..._row(id: '4'), 'approved': true},
        {..._row(id: '5'), 'revision_requested': true},
      ];
      expect(countApprovablePending(rows), 2);
    });

    test('対照: 修正依頼だけ押せない行は承認待ちに数える', () {
      expect(countApprovablePending([_row(canRevision: false)]), 1);
    });
  });
}
