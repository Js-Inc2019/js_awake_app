// ============================================================
// test/substitute_actions_test.dart
//   振替休日の【操作】を機械で固定する（同意する・休む日を変える・
//   申し出を取り下げる・この振替を取り消す）。
//
// ★見る側（一覧の節分け・状態の語・通知やカレンダーの入口）は
//   test/substitute_view_test.dart の担当。この本は【押したら何が起きるか】だけを見る。
//   本を分けたのは、あちらが「BE の印をどう読むか」、こちらが「口をどう叩くか」で
//   問いが違うため（家風＝新しい仕掛けには新しい本を立てる）。
//
// ★画面は立てる。前の便で3つの画面に差し替え口（任意の引数 service）を足したので、
//   実 HTTP へ行かせずに押せる。新しい D2 の画面（SubstituteChangeScreen）にも
//   同じ形の口を付けてある。
//
// ★何を守るか（すべて二者比較。「出ない」だけで合格にしない＝出る対照を同じ検査に並べる）:
//   (1) 状態ごとに出る操作が変わる（6つの状態すべて）
//   (2) 同意・申し出・取り下げ・取り消しが、それぞれ【その行の id】で呼ばれる
//   (3) 注意書き（B2）は同意と変更の手前で【毎回】出る（2回目も出る）
//   (4) 候補＝selectable が false の日は押せず、BE の reason がそのまま出る
//   (5) 二度目の確認＝2つチェックするまで「申請する」が押せない
//   (6) 断り＝BE の文がそのまま出て、閉じるまで消えない
//
// ★掟: 期待値（語・真偽・並び）はこのファイル内で組み立てる。実装の定数は import しない。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:js_awake_app/screens/substitute_change_screen.dart'
    show SubstituteChangeScreen;
import 'package:js_awake_app/screens/substitute_detail_screen.dart'
    show SubstituteDetailScreen;
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';

// ── 画面の実文言（lib の実文字列をここへ写した）──────────────────
const String kActAgree    = 'この振替に同意する';
const String kActNotYet   = 'まだ決めない';
const String kActChange   = '休む日を変える';
const String kActWithdraw = '申し出を取り下げる';
const String kActCancel   = 'この振替を取り消す';
const String kNoticeHead  = 'はじめにご確認ください';
const String kNoticeOk    = '確認しました';
const String kNoticeNo    = 'やめる';
const String kCancelTitle = 'この振替を取り消しますか？';
const String kCancelGo    = '取り消す';
const String kCancelBack  = '戻る';
const String kD3Title     = '変更は一度きりです';
const String kD3Go        = '申請する';
const String kD3Check1    = '変更は一度きりであることを確認しました';
const String kD3Check2    = 'この変更を自分の意思で申し出ます';
const String kClose       = '閉じる';
const String kNoAction    = 'この振替は取り消し済みです。行える操作はありません。';

/// BE の GET /rest-days/:id が返す rest_day の写し。
Map<String, dynamic> _detail({
  String id = 'rd_1',
  String restDate = '2026-06-10',
  String pairedWorkDate = '2026-06-08',
  bool pendingAgreement = false,
  bool settled = true,
  String? changeRequestedRestDate,
  String? changeDeadline,
  String? changeSettledAt,
  bool changeBlocked = false,
  String? cancelledAt,
}) => {
      'id': id,
      'person_id': 'p_1',
      'name': '検査 太郎',
      'rest_date': restDate,
      'reason': 'substitute',
      'portion': 'full',
      'paired_work_date': pairedWorkDate,
      'paired_undecided': false,
      'pending_agreement': pendingAgreement,
      'proposed_at': '2026-06-01T00:00:00.000Z',
      'agreed_at': settled ? '2026-06-02T00:00:00.000Z' : null,
      'change_requested_rest_date': changeRequestedRestDate,
      'change_deadline': changeDeadline,
      'change_from_date': null,
      'change_settled_at': changeSettledAt,
      'settled': settled,
      'change_blocked': changeBlocked,
      'created_at': '2026-06-01T00:00:00.000Z',
      // ★取消は BE の列そのもの（時刻）。真偽に潰さない。
      'cancelled_at': cancelledAt,
    };

/// BE の events の1行。
Map<String, dynamic> _event(String type) =>
    {'type': type, 'at': '2026-06-01T00:00:00.000Z', 'text': '検査の記録'};

/// BE の GET /:id/change-candidates が返す days[] の1つ。
Map<String, dynamic> _day({
  required String date,
  required int dow,
  bool selectable = true,
  String? reasonCode,
  String? reason,
  String deadline = '2026-06-09',
}) => {
      'date': date,
      'dow': dow,
      'selectable': selectable,
      'reason_code': reasonCode,
      'reason': reason,
      'deadline': deadline,
    };

/// 差し替える口。★実 HTTP へ行かせず、何をどの id で叩いたかを数える。
///   形は test/comp_off_flow_test.dart の _FakeSvc と同じ（super.forTest()）。
class _FakeSvc extends ReportsService {
  _FakeSvc({
    Map<String, dynamic>? detail,
    this.events = const [],
    this.days = const [],
    this.holidayDefConfigured = true,
    this.candidatesFail,
    this.agreeFail,
    this.requestFail,
    this.requestFailDetails,
    this.withdrawFail,
    this.cancelFail,
  }) : _detailRow = detail,
       super.forTest();

  final Map<String, dynamic>? _detailRow;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> days;
  final bool holidayDefConfigured;

  /// 断らせたいときの BE の文（null = 通す）。
  final String? candidatesFail;
  final String? agreeFail;
  final String? requestFail;
  final Map<String, dynamic>? requestFailDetails;
  final String? withdrawFail;
  final String? cancelFail;

  // 何をどの id で叩いたか。
  final List<String> detailCalls = [];
  final List<String> agreeCalls = [];
  final List<String> candidateCalls = [];
  final List<Map<String, String>> requestCalls = [];
  final List<String> withdrawCalls = [];
  final List<String> cancelCalls = [];

  @override
  Future<ApiResult<Map<String, dynamic>>> getRestDay(String id) async {
    detailCalls.add(id);
    return apiSuccess<Map<String, dynamic>>(
      statusCode: 200,
      data: {'rest_day': _detailRow ?? _detail(id: id), 'events': events},
    );
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> agreeSubstitute(String id) async {
    agreeCalls.add(id);
    return agreeFail == null
        ? apiSuccess<Map<String, dynamic>>(statusCode: 200, data: const {})
        : apiFailure<Map<String, dynamic>>(
            statusCode: 409, errorMessage: agreeFail, errorCode: 'X');
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> getChangeCandidates(String id) async {
    candidateCalls.add(id);
    if (candidatesFail != null) {
      return apiFailure<Map<String, dynamic>>(
          statusCode: 0, errorMessage: candidatesFail);
    }
    return apiSuccess<Map<String, dynamic>>(
      statusCode: 200,
      data: {
        'rest_day_id': id,
        'current_rest_date': '2026-06-10',
        'paired_work_date': '2026-06-08',
        'holiday_def_configured': holidayDefConfigured,
        'days': days,
      },
    );
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> requestSubstituteChange(
      String id, String newDate) async {
    requestCalls.add({'id': id, 'date': newDate});
    return requestFail == null
        ? apiSuccess<Map<String, dynamic>>(statusCode: 200, data: const {})
        : apiFailure<Map<String, dynamic>>(
            statusCode: 409,
            errorMessage: requestFail,
            errorCode: 'X',
            errorDetails: requestFailDetails);
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> withdrawSubstituteChange(
      String id) async {
    withdrawCalls.add(id);
    return withdrawFail == null
        ? apiSuccess<Map<String, dynamic>>(statusCode: 200, data: const {})
        : apiFailure<Map<String, dynamic>>(
            statusCode: 409, errorMessage: withdrawFail, errorCode: 'X');
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> cancelRestDayById(String id) async {
    cancelCalls.add(id);
    return cancelFail == null
        ? apiSuccess<Map<String, dynamic>>(statusCode: 200, data: const {})
        : apiFailure<Map<String, dynamic>>(
            statusCode: 409, errorMessage: cancelFail, errorCode: 'X');
  }
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

/// 1件の画面を開く。
Future<void> _openDetail(WidgetTester tester, _FakeSvc api,
        {String id = 'rd_1'}) =>
    _pump(tester, SubstituteDetailScreen(restDayId: id, service: api));

/// 注意書きを読んで先へ進む（B2 の「確認しました」）。
Future<void> _passNotice(WidgetTester tester) async {
  // ★同意待ちの画面には【出しっぱなしの注意書きの枠】も同じ見出しで出ている。
  //   ダイアログが開いたことは、ダイアログにしか無いボタンで見分ける
  //   （見出しの数で見ると、枠の有無で答えが変わってしまう）。
  expect(find.text(kNoticeOk), findsOneWidget,
      reason: '注意書きが出ないまま先へ進もうとしている');
  expect(find.text(kNoticeHead), findsWidgets);
  await tester.tap(find.text(kNoticeOk));
  await tester.pumpAndSettle();
}

void main() {
  // ══════════════════════════════════════════════════════════
  // (1) 状態ごとに出る操作が変わる
  //   ★6つの状態すべてを1本の検査に並べる。「出ない」だけを見ると、
  //     画面がそもそも描けていない回と区別が付かないので、必ず
  //     【その状態で出るもの】と【出ないもの】を同じ検査の中で並べる。
  // ══════════════════════════════════════════════════════════
  group('(1) 状態ごとの操作', () {
    testWidgets('★同意待ち → 同意する／まだ決めない だけ', (tester) async {
      await _openDetail(tester, _FakeSvc(
          detail: _detail(pendingAgreement: true, settled: false)));

      expect(find.text(kActAgree), findsOneWidget);
      expect(find.text(kActNotYet), findsOneWidget);
      expect(find.text(kActChange), findsNothing, reason: 'まだ同意していないのに変更を出している');
      expect(find.text(kActWithdraw), findsNothing);
      expect(find.text(kActCancel), findsNothing);
    });

    testWidgets('★成立 → 休む日を変える／この振替を取り消す だけ', (tester) async {
      await _openDetail(tester, _FakeSvc(detail: _detail()));

      expect(find.text(kActChange), findsOneWidget);
      expect(find.text(kActCancel), findsOneWidget);
      expect(find.text(kActAgree), findsNothing, reason: '成立済みなのに同意を出している');
      expect(find.text(kActWithdraw), findsNothing,
          reason: '申し出ていないのに取り下げを出している');
    });

    testWidgets('★事務の確認待ち → 申し出を取り下げる だけ', (tester) async {
      await _openDetail(tester, _FakeSvc(
          detail: _detail(
              changeRequestedRestDate: '2026-06-12',
              changeDeadline: '2026-06-09')));

      expect(find.text(kActWithdraw), findsOneWidget);
      expect(find.text(kActChange), findsNothing,
          reason: '申し出中なのに重ねて変更を出している');
      expect(find.text(kActCancel), findsNothing);
      expect(find.text(kActAgree), findsNothing);
    });

    testWidgets('★成立できない → 申し出を取り下げる だけ', (tester) async {
      await _openDetail(tester, _FakeSvc(
          detail: _detail(
              changeRequestedRestDate: '2026-06-12',
              changeDeadline: '2026-06-09',
              changeBlocked: true)));

      expect(find.text('成立できません'), findsOneWidget, reason: '土台: その状態でない');
      expect(find.text(kActWithdraw), findsOneWidget);
      expect(find.text(kActChange), findsNothing);
      expect(find.text(kActCancel), findsNothing);
    });

    testWidgets('★変更済み → この振替を取り消す だけ（変更は一度きりなので変更は出さない）',
        (tester) async {
      await _openDetail(tester, _FakeSvc(
          detail: _detail(changeSettledAt: '2026-06-09T00:00:00.000Z')));

      expect(find.text('変更済み'), findsOneWidget, reason: '土台: その状態でない');
      expect(find.text(kActCancel), findsOneWidget);
      expect(find.text(kActChange), findsNothing,
          reason: '押せば必ず断られるボタンを置いている');
      expect(find.text(kActWithdraw), findsNothing);
    });

    // ★取消の判定は BE の cancelled_at ただ1本（2026-09-20）。
    //   それまでは events の 'cancelled' の行から導いていた。記録から状態を
    //   組み立てる形をやめたことを、ここで名指しで固定する。
    testWidgets('★取消済み → 「取消済み」が出て操作は0個'
        '（対照: 取り消していない行では出ず、操作が出る）', (tester) async {
      final api = _FakeSvc(
        detail: _detail(
            settled: false, cancelledAt: '2026-06-05T00:00:00.000Z'),
        events: [_event('registered'), _event('cancelled')],
      );
      await _openDetail(tester, api);

      expect(find.text('取消済み'), findsOneWidget, reason: '土台: その状態でない');
      expect(find.text(kNoAction), findsOneWidget, reason: '無い理由を言い切っていない');
      expect(find.text(kActAgree), findsNothing);
      expect(find.text(kActChange), findsNothing);
      expect(find.text(kActWithdraw), findsNothing);
      expect(find.text(kActCancel), findsNothing);

      // ★空振りで合格にしない。同じ検査の中で、取り消していない行では出ることを見る。
      await _pump(tester, const SizedBox.shrink());
      await _openDetail(tester,
          _FakeSvc(detail: _detail(), events: [_event('registered')]));
      expect(find.text('取消済み'), findsNothing);
      expect(find.text(kNoAction), findsNothing);
      expect(find.text(kActCancel), findsOneWidget,
          reason: '取り消していないのに操作が出ない＝画面がそもそも描けていない');
    });

    testWidgets('★判定は cancelled_at だけ: 記録に cancelled があっても'
        '列が null なら取消済みにしない', (tester) async {
      // ★記録（events）から状態を組み立てていないことの見張り。
      //   BE が記録の言い回しを変えても、この画面の状態は動かない。
      final api = _FakeSvc(
        detail: _detail(),                       // cancelled_at は null
        events: [_event('registered'), _event('cancelled')],
      );
      await _openDetail(tester, api);

      expect(find.text('取消済み'), findsNothing,
          reason: '記録から取消を導いている（列を見ていない）');
      expect(find.text(kActCancel), findsOneWidget,
          reason: '操作まで消えている');
    });

    testWidgets('★対照: 列が入っていれば、記録に cancelled が無くても取消済み',
        (tester) async {
      final api = _FakeSvc(
        detail: _detail(cancelledAt: '2026-06-05T00:00:00.000Z'),
        events: [_event('registered')],          // 記録には取消が無い
      );
      await _openDetail(tester, api);

      expect(find.text('取消済み'), findsOneWidget,
          reason: '列が入っているのに読んでいない');
      expect(find.text(kNoAction), findsOneWidget);
    });

    testWidgets('★古いサーバー（cancelled_at のキーが無い回）は取消済みを出さない',
        (tester) async {
      // ★端末はサーバーより後に焼かれるので、この道は実際には通らない。
      //   それでも「落ちない・勝手に取消済みにしない」ことは固定しておく
      //   （change_blocked と同じ扱いで揃えた）。
      final old = Map<String, dynamic>.from(_detail())..remove('cancelled_at');
      expect(old.containsKey('cancelled_at'), isFalse, reason: '土台: 古い姿でない');
      await _openDetail(tester, _FakeSvc(detail: old));

      expect(find.text('取消済み'), findsNothing);
      expect(find.text(kActCancel), findsOneWidget, reason: '落ちて何も出ていない');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (2)(3) 押したらその行の id で呼ばれる／注意書きは毎回出る
  // ══════════════════════════════════════════════════════════
  group('(2) その行の id で呼ばれる', () {
    testWidgets('★同意 → 注意書きを読んだあと、その id で同意が呼ばれる', (tester) async {
      final api = _FakeSvc(
          detail: _detail(id: 'rd_A', pendingAgreement: true, settled: false));
      await _openDetail(tester, api, id: 'rd_A');

      await tester.tap(find.text(kActAgree));
      await tester.pumpAndSettle();
      await _passNotice(tester);

      expect(api.agreeCalls, ['rd_A'], reason: 'その行の id で同意が呼ばれていない');
    });

    testWidgets('★対: 注意書きで「やめる」を押すと1回も呼ばれない', (tester) async {
      final api = _FakeSvc(
          detail: _detail(id: 'rd_A', pendingAgreement: true, settled: false));
      await _openDetail(tester, api, id: 'rd_A');

      await tester.tap(find.text(kActAgree));
      await tester.pumpAndSettle();
      expect(find.text(kNoticeNo), findsOneWidget);
      await tester.tap(find.text(kNoticeNo));
      await tester.pumpAndSettle();

      expect(api.agreeCalls, isEmpty, reason: 'やめたのに口を叩いている');
    });

    testWidgets('★注意書きは毎回出る（1度読んでも2度目に省かない）', (tester) async {
      final api = _FakeSvc(
          detail: _detail(id: 'rd_A', pendingAgreement: true, settled: false));
      await _openDetail(tester, api, id: 'rd_A');

      // 1回目：やめる
      await tester.tap(find.text(kActAgree));
      await tester.pumpAndSettle();
      expect(find.text(kNoticeOk), findsOneWidget, reason: '1回目に出ていない');
      await tester.tap(find.text(kNoticeNo));
      await tester.pumpAndSettle();
      expect(find.text(kNoticeOk), findsNothing, reason: '土台: 閉じられていない');

      // 2回目：また出る
      await tester.tap(find.text(kActAgree));
      await tester.pumpAndSettle();
      expect(find.text(kNoticeOk), findsOneWidget,
          reason: '2度目に省いている（賃金の扱いが変わる操作なので毎回読ませる）');
    });

    testWidgets('★休む日を変える → 注意書きのあと、その id で候補の口が呼ばれる',
        (tester) async {
      final api = _FakeSvc(
        detail: _detail(id: 'rd_B'),
        days: [_day(date: '2026-06-11', dow: 4)],
      );
      await _openDetail(tester, api, id: 'rd_B');

      await tester.tap(find.text(kActChange));
      await tester.pumpAndSettle();
      await _passNotice(tester);

      expect(api.candidateCalls, ['rd_B'], reason: 'その行の id で候補を引いていない');
    });

    testWidgets('★申し出を取り下げる → その id で取り下げが呼ばれる（注意書きは挟まない）',
        (tester) async {
      final api = _FakeSvc(
          detail: _detail(
              id: 'rd_C',
              changeRequestedRestDate: '2026-06-12',
              changeDeadline: '2026-06-09'));
      await _openDetail(tester, api, id: 'rd_C');

      await tester.tap(find.text(kActWithdraw));
      await tester.pumpAndSettle();

      expect(api.withdrawCalls, ['rd_C']);
      // ★取り下げは賃金の扱いを変えない（何も成立させない）ので注意書きは挟まない。
      expect(find.text(kNoticeHead), findsNothing);
    });

    testWidgets('★取り消す → 確認してから、その id で取り消しが呼ばれる', (tester) async {
      final api = _FakeSvc(detail: _detail(id: 'rd_D'));
      await _openDetail(tester, api, id: 'rd_D');

      await tester.tap(find.text(kActCancel));
      await tester.pumpAndSettle();

      expect(find.text(kCancelTitle), findsOneWidget, reason: '確認を挟んでいない');
      expect(find.textContaining('会社の休みの日の扱いに戻ります'), findsOneWidget,
          reason: '取り消すと出勤する日がどうなるかを言っていない');

      await tester.tap(find.widgetWithText(TextButton, kCancelGo));
      await tester.pumpAndSettle();
      expect(api.cancelCalls, ['rd_D']);
    });

    testWidgets('★対: 取り消しの確認で「戻る」を押すと1回も呼ばれない', (tester) async {
      final api = _FakeSvc(detail: _detail(id: 'rd_D'));
      await _openDetail(tester, api, id: 'rd_D');

      await tester.tap(find.text(kActCancel));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, kCancelBack));
      await tester.pumpAndSettle();

      expect(api.cancelCalls, isEmpty, reason: '戻ったのに取り消している');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (4) 候補の画面（D2）
  // ══════════════════════════════════════════════════════════
  group('(4) 休む日の候補', () {
    const beReason1 = 'いまの休む日と同じです';
    const beReason2 = 'もともと休みの日です';

    _FakeSvc api7() => _FakeSvc(
          days: [
            _day(date: '2026-06-10', dow: 3,
                selectable: false, reasonCode: 'same_as_current',
                reason: beReason1),
            _day(date: '2026-06-11', dow: 4),
            _day(date: '2026-06-13', dow: 6,
                selectable: false, reasonCode: 'not_workday',
                reason: beReason2),
          ],
        );

    testWidgets('★選べない日は BE の reason がそのまま出て、押しても進まない'
        '（対照: 選べる日は押すと確認へ進む）', (tester) async {
      final api = api7();
      await _pump(tester,
          SubstituteChangeScreen(restDayId: 'rd_1', service: api));

      expect(find.text(beReason1), findsOneWidget,
          reason: 'BE の理由が出ていない（端末で言い換えている）');
      expect(find.text(beReason2), findsOneWidget);
      expect(find.text('出勤する日（変えられません）'), findsOneWidget,
          reason: '変えられない方を出していない');

      // 選べない日を押しても、二度目の確認は出ない。
      await tester.tap(find.text('6月10日（水）'));
      await tester.pumpAndSettle();
      expect(find.text(kD3Title), findsNothing, reason: '選べない日で先へ進めている');

      // ★対照: 選べる日は押すと確認へ進む（空振りで合格にしない）。
      await tester.tap(find.text('6月11日（木）'));
      await tester.pumpAndSettle();
      expect(find.text(kD3Title), findsOneWidget,
          reason: '選べる日でも進めない＝押せる日が1つも無い');
    });

    testWidgets('★選べる日には確認の期限が出る（対照: 選べない日には出ない）',
        (tester) async {
      await _pump(tester,
          SubstituteChangeScreen(restDayId: 'rd_1', service: api7()));
      expect(find.text('確認の期限 6月9日'), findsOneWidget);
    });

    testWidgets('★会社の休みの日が未設定の回は、候補を並べず BE の断りを出す',
        (tester) async {
      const beText = '会社の休みの日が設定されていません。事務にご確認ください';
      final api = _FakeSvc(
        holidayDefConfigured: false,
        days: [
          _day(date: '2026-06-10', dow: 3,
              selectable: false,
              reasonCode: 'holiday_def_not_configured', reason: beText),
        ],
      );
      await _pump(tester,
          SubstituteChangeScreen(restDayId: 'rd_1', service: api));

      expect(find.text(beText), findsOneWidget, reason: 'BE の断りを出していない');
      expect(find.text('もう一度'), findsOneWidget, reason: '袋小路になっている');
      expect(find.text('出勤する日（変えられません）'), findsNothing,
          reason: '選べない候補を並べている');
    });

    testWidgets('★対: 候補が取れなかった回は理由と「もう一度」が出る', (tester) async {
      const beText = 'サーバーに接続できません: 検査';
      await _pump(
          tester,
          SubstituteChangeScreen(
              restDayId: 'rd_1', service: _FakeSvc(candidatesFail: beText)));
      expect(find.text(beText), findsOneWidget);
      expect(find.text('もう一度'), findsOneWidget);
    });

    // ══════════════════════════════════════════════════════
    // ※の3行（モック D2 の原文）
    //   ★1行目の週の両端は【BE が返した days[] の最初と最後】から出す。
    //     端末で週を数え直していないことを、2通りの候補で確かめる
    //     （同じ文が両端の違いでちゃんと変わる＝決め打ちの文字列ではない）。
    // ══════════════════════════════════════════════════════
    const note2 = '※確認の期限は、いまの休む日と新しい休む日の、早い方の前日です。'
        '前の日に変えるほど期限も早まります。';
    const note3 = '※選べるのは申し出の翌日からです。';

    testWidgets('★※の3行がそのまま出る（1行目の週は days[] の両端から）',
        (tester) async {
      final api = _FakeSvc(days: [
        _day(date: '2026-06-07', dow: 0, selectable: false,
            reasonCode: 'not_workday', reason: 'もともと休みの日です'),
        _day(date: '2026-06-11', dow: 4),
        _day(date: '2026-06-13', dow: 6),
      ]);
      await _pump(tester,
          SubstituteChangeScreen(restDayId: 'rd_1', service: api));

      expect(find.text('※休む日を動かせるのは同じ週（6月7日〜6月13日）の中だけです。'),
          findsOneWidget, reason: '1行目が原文どおりでない／両端が違う');
      expect(find.text(note2), findsOneWidget, reason: '2行目が原文どおりでない');
      expect(find.text(note3), findsOneWidget, reason: '3行目が原文どおりでない');
    });

    testWidgets('★対照: days[] の両端が変われば1行目の日付も変わる'
        '（端末で週を数え直していない）', (tester) async {
      final api = _FakeSvc(days: [
        _day(date: '2026-07-05', dow: 0, selectable: false,
            reasonCode: 'not_workday', reason: 'もともと休みの日です'),
        _day(date: '2026-07-09', dow: 4),
        _day(date: '2026-07-11', dow: 6),
      ]);
      await _pump(tester,
          SubstituteChangeScreen(restDayId: 'rd_1', service: api));

      expect(find.text('※休む日を動かせるのは同じ週（7月5日〜7月11日）の中だけです。'),
          findsOneWidget, reason: '両端を変えても文が変わらない＝決め打ちになっている');
      expect(find.text('※休む日を動かせるのは同じ週（6月7日〜6月13日）の中だけです。'),
          findsNothing);
      // 2行目・3行目は候補によらず同じ文（対照）。
      expect(find.text(note2), findsOneWidget);
      expect(find.text(note3), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (5) 二度目の確認（D3）
  // ══════════════════════════════════════════════════════════
  group('(5) 二度目の確認', () {
    Future<_FakeSvc> openD3(WidgetTester tester) async {
      final api = _FakeSvc(days: [_day(date: '2026-06-11', dow: 4)]);
      await _pump(tester,
          SubstituteChangeScreen(restDayId: 'rd_E', service: api));
      await tester.tap(find.text('6月11日（木）'));
      await tester.pumpAndSettle();
      expect(find.text(kD3Title), findsOneWidget);
      return api;
    }

    bool goEnabled(WidgetTester tester) =>
        tester.widget<TextButton>(
            find.widgetWithText(TextButton, kD3Go)).onPressed != null;

    testWidgets('★2つチェックするまで「申請する」は押せない（1つだけでも押せない）',
        (tester) async {
      final api = await openD3(tester);

      expect(goEnabled(tester), isFalse, reason: '何もチェックせずに押せてしまう');

      await tester.tap(find.text(kD3Check1));
      await tester.pumpAndSettle();
      expect(goEnabled(tester), isFalse, reason: '1つだけで押せてしまう');

      await tester.tap(find.text(kD3Check2));
      await tester.pumpAndSettle();
      expect(goEnabled(tester), isTrue, reason: '2つ揃っても押せない');

      // ★対照: 押せるようになってから初めて口が叩かれる。
      expect(api.requestCalls, isEmpty, reason: '押す前に申し出ている');
      await tester.tap(find.text(kD3Go));
      await tester.pumpAndSettle();
      expect(api.requestCalls, [
        {'id': 'rd_E', 'date': '2026-06-11'}
      ], reason: 'その行の id と選んだ日で申し出ていない');
    });

    testWidgets('★本文に いまの日 と 選んだ日 と 期限 と 出勤する日 が出る',
        (tester) async {
      await openD3(tester);
      expect(find.textContaining('休む日を 6月10日 から 6月11日 に変更することを申し出ます'),
          findsOneWidget);
      expect(find.textContaining('6月9日 までに事務の確認がないときに成立します'),
          findsOneWidget);
      expect(find.textContaining('出勤する日（6月8日）は変わりません'), findsOneWidget);
    });

    testWidgets('★対: 「戻る」を押すと申し出ない', (tester) async {
      final api = await openD3(tester);
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(api.requestCalls, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (6) 断りは BE の文がそのまま出て、閉じるまで消えない
  // ══════════════════════════════════════════════════════════
  group('(6) 断りの出し方', () {
    /// 閉じるまで消えないこと（時間で消えるスナックにしていない）を見る。
    Future<void> staysUntilClosed(WidgetTester tester, String beText) async {
      expect(find.text(beText), findsOneWidget, reason: 'BE の文が出ていない');
      expect(find.text(kClose), findsOneWidget, reason: '閉じる道が無い');
      await tester.pump(const Duration(seconds: 6));
      expect(find.text(beText), findsOneWidget, reason: '時間で消えている');
    }

    testWidgets('★同意が断られたら BE の文がそのまま出る（code は出さない）',
        (tester) async {
      const beText = 'ご本人が同意して成立した振替休日です';
      final api = _FakeSvc(
          detail: _detail(pendingAgreement: true, settled: false),
          agreeFail: beText);
      await _openDetail(tester, api);
      await tester.tap(find.text(kActAgree));
      await tester.pumpAndSettle();
      await _passNotice(tester);

      await staysUntilClosed(tester, beText);
      expect(find.text('X'), findsNothing, reason: '英字の code を出している');
    });

    testWidgets('★取り下げが断られたら BE の文がそのまま出る', (tester) async {
      const beText = '取り下げられる申し出がありません';
      final api = _FakeSvc(
          detail: _detail(
              changeRequestedRestDate: '2026-06-12',
              changeDeadline: '2026-06-09'),
          withdrawFail: beText);
      await _openDetail(tester, api);
      await tester.tap(find.text(kActWithdraw));
      await tester.pumpAndSettle();
      await staysUntilClosed(tester, beText);
    });

    testWidgets('★取り消しが断られたら BE の文がそのまま出る', (tester) async {
      const beText = 'この休みは既に取り消されています';
      final api = _FakeSvc(detail: _detail(), cancelFail: beText);
      await _openDetail(tester, api);
      await tester.tap(find.text(kActCancel));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, kCancelGo));
      await tester.pumpAndSettle();
      await staysUntilClosed(tester, beText);
    });

    /// D3 まで進んで「申請する」を押す。
    Future<void> submit(WidgetTester tester, _FakeSvc api) async {
      await _pump(tester,
          SubstituteChangeScreen(restDayId: 'rd_F', service: api));
      await tester.tap(find.text('6月11日（木）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kD3Check1));
      await tester.tap(find.text(kD3Check2));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kD3Go));
      await tester.pumpAndSettle();
    }

    testWidgets('★申し出が断られたら BE の文がそのまま出る', (tester) async {
      const beText = 'すでに休む日の変更を申し出ています';
      await submit(
          tester,
          _FakeSvc(
              days: [_day(date: '2026-06-11', dow: 4)], requestFail: beText));
      await staysUntilClosed(tester, beText);
    });

    testWidgets('★期限切れ: BE の文に期限が入っていれば、期限を重ねて足さない',
        (tester) async {
      // BE の実物は文の中に期限を入れて返す（routes/rest_days.js の
      // SUBSTITUTE_CHANGE_DEADLINE_PASSED）。同じ日付を2回言わない。
      const beText = '変更の期限（6月9日）を過ぎているため、休む日を変更できません';
      await submit(
          tester,
          _FakeSvc(
            days: [_day(date: '2026-06-11', dow: 4)],
            requestFail: beText,
            requestFailDetails: const {'deadline': '2026-06-09'},
          ));
      await staysUntilClosed(tester, beText);
      // ★D2 の※にも「確認の期限は…」という別の文があるので、足した1文だけを名指しで見る。
      expect(find.textContaining('確認の期限は 6月9日 でした。'), findsNothing,
          reason: 'BE の文に入っている期限を重ねて足している');
    });

    testWidgets('★対照: BE の文に期限が入っていない回だけ、期限を別の行で添える',
        (tester) async {
      const beText = '期限を過ぎているため、休む日を変更できません';
      await submit(
          tester,
          _FakeSvc(
            days: [_day(date: '2026-06-11', dow: 4)],
            requestFail: beText,
            requestFailDetails: const {'deadline': '2026-06-09'},
          ));
      expect(find.textContaining(beText), findsOneWidget);
      expect(find.textContaining('確認の期限は 6月9日 でした。'), findsOneWidget,
          reason: '期限が返っているのに、どこにも出ていない');
    });
  });
}
