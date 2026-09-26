// ============================================================
// test/substitute_view_test.dart
//   振替休日の「見る側」を機械で固定する。
//
// ★画面のうち CalendarTab は立てない（initState から実HTTPへ行くため）。この線引きは
//   test/calendar_day_sheet_test.dart・test/share_send_confirm_test.dart・
//   test/report_status_style_test.dart の冒頭に既に書かれている家風。
//   【公開した純関数】と【公開部品】を直接叩く:
//     splitSubstituteRows / substituteStateLabel / substituteRegisteredLine /
//     jpMonthDay / jpMonthDayOfIso / parseSubstituteRefId /
//     kSubstituteNoticeTypes / restReasonLabel / CalendarDayInfo.restLine /
//     CalendarDaySheet（箱の入口）
//
// ★2026-09-20 に【立てられる画面が増えた】。SubstituteListScreen /
//   SubstituteDetailScreen / PunchScreen に、外から口を差し替える任意の引数を
//   1つずつ足したため（【Q70】＝1 の裁定）。既定は今までどおり ReportsService() なので
//   本番の道は1文字も変わっていない。差し替えを渡すのはこの本だけ。
//   ★これで前の便に測れていなかった4つ（(8)〜(11)）が測れるようになった。
//     測れないまま出すのは、直したつもりで直っていない形なので、先に口を足した。
//
// ★掟: 期待値（語・並び・真偽）はこのファイル内で組み立てる。実装の定数は import しない。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/screens/home_screen.dart'
    show CalendarDayInfo, CalendarDaySheet, restReasonLabel;
import 'package:js_awake_app/screens/notification_list_screen.dart'
    show kSubstituteNoticeTypes, parseSubstituteRefId;
import 'package:js_awake_app/screens/punch_screen.dart' show PunchScreen;
import 'package:js_awake_app/screens/substitute_detail_screen.dart'
    show SubstituteDetailScreen;
import 'package:js_awake_app/screens/substitute_list_screen.dart'
    show
        SubstituteListScreen,
        jpMonthDay,
        jpMonthDayOfIso,
        splitSubstituteRows,
        substituteRegisteredLine,
        substituteStateLabel;
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';

/// BE の GET /rest-days/my/substitutes が返す行の写し。
///   ★change_blocked / created_at は BE の別便（2026-09-20）で足された列。
///     既定では【入れない】＝古いサーバーの姿。入れたい検査だけが渡す。
Map<String, dynamic> _row({
  required String id,
  required String restDate,
  String? pairedWorkDate,
  bool pendingAgreement = false,
  bool settled = true,
  bool actionNeeded = false,
  String? proposedAt,
  String? proposedByName,
  bool? changeBlocked,
  String? createdAt,
}) => {
      'id': id,
      'rest_date': restDate,
      'reason': 'substitute',
      'portion': 'full',
      'paired_work_date': pairedWorkDate,
      'paired_undecided': false,
      'pending_agreement': pendingAgreement,
      'proposed_at': proposedAt,
      'agreed_at': settled ? '2026-06-02T00:00:00.000Z' : null,
      'change_requested_rest_date': null,
      'change_deadline': null,
      'change_from_date': null,
      'change_settled_at': null,
      'settled': settled,
      'action_needed': actionNeeded,
      'proposed_by_name': proposedByName,
      if (changeBlocked != null) 'change_blocked': changeBlocked,
      if (createdAt != null) 'created_at': createdAt,
    };

/// BE の GET /rest-days/:id が返す rest_day の写し。
///   ★一覧の行とはキーが違う（person_id と氏名が付き、action_needed は付かない）。
Map<String, dynamic> _detail({
  required String id,
  required String restDate,
  String? pairedWorkDate,
  bool pendingAgreement = false,
  bool settled = true,
  String? changeRequestedRestDate,
  String? changeDeadline,
  String? changeSettledAt,
  bool? changeBlocked,
  String? createdAt,
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
      if (changeBlocked != null) 'change_blocked': changeBlocked,
      if (createdAt != null) 'created_at': createdAt,
    };

/// 差し替える口。★実 HTTP へ行かせず、何を何回叩いたかも数える。
///   形は test/comp_off_flow_test.dart の _FakeSvc と同じ（super.forTest()）。
class _FakeSvc extends ReportsService {
  _FakeSvc({
    this.rows = const [],
    this.truncated = false,
    this.listFails = false,
    this.listError,
    this.detail,
    this.events = const [],
  }) : super.forTest();

  final List<Map<String, dynamic>> rows;
  final bool truncated;
  final bool listFails;
  final String? listError;
  final Map<String, dynamic>? detail;
  final List<Map<String, dynamic>> events;

  // 何を何回叩いたか。★「1回だけ」と「1回も叩かない」を数で見るため。
  int listCalls = 0;
  int monthCalls = 0;          // 対照: 月の口 /rest-days/my
  final List<String> detailCalls = [];

  @override
  Future<ApiResult<Map<String, dynamic>>> getMySubstitutes() async {
    listCalls++;
    if (listFails) {
      return apiFailure<Map<String, dynamic>>(
          statusCode: 0, errorMessage: listError);
    }
    return apiSuccess<Map<String, dynamic>>(
      statusCode: 200,
      data: {'rows': rows, 'truncated': truncated},
    );
  }

  @override
  Future<ApiResult<List<Map<String, dynamic>>>> getRestDaysMy(String month,
      {List<String> closingDates = const <String>[]}) async {
    monthCalls++;
    return apiSuccess<List<Map<String, dynamic>>>(
        statusCode: 200, data: const []);
  }

  /// 打刻の画面が開いた直後に読む口。★実 HTTP へ行かせないために塞ぐ。
  ///   休みではない＝今までどおりの姿（この本が見るのは要対応の行だけ）。
  @override
  Future<ApiResult<RestDayToday>> getRestDayToday() async =>
      apiSuccess<RestDayToday>(
        statusCode: 200,
        data: const RestDayToday(rested: false, reason: null, portion: 'full'),
      );

  @override
  Future<ApiResult<Map<String, dynamic>>> getRestDay(String id) async {
    detailCalls.add(id);
    return apiSuccess<Map<String, dynamic>>(
      statusCode: 200,
      data: {
        'rest_day': detail ?? _detail(id: id, restDate: '2026-06-10'),
        'events': events,
      },
    );
  }
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

/// 画面を立てる。★物理サイズを広く取り、縦に長い中身でも下が切れないようにする。
Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  // ══════════════════════════════════════════════════════════
  group('(1) 一覧の節分け（あなたの番が上・これからが下）', () {
    test('★action_needed だけで分かれ、どちらも BE の順のまま', () {
      final rows = [
        _row(id: 'a', restDate: '2026-06-01', actionNeeded: true,
            pendingAgreement: true, settled: false),
        _row(id: 'b', restDate: '2026-06-02'),
        _row(id: 'c', restDate: '2026-06-03', actionNeeded: true),
        _row(id: 'd', restDate: '2026-06-04'),
      ];
      final p = splitSubstituteRows(rows);
      expect(p.yours.map((r) => r['id']).toList(), ['a', 'c'],
          reason: 'あなたの番の中身か並びが違う');
      expect(p.upcoming.map((r) => r['id']).toList(), ['b', 'd'],
          reason: 'これからの振替の中身か並びが違う');
    });

    test('★対: 0件なら両方とも空（端末で行を作らない）', () {
      final p = splitSubstituteRows(const []);
      expect(p.yours, isEmpty);
      expect(p.upcoming, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════
  group('(2) 行の状態は BE の印だけで決まる', () {
    test('同意待ち', () {
      expect(
          substituteStateLabel(_row(
              id: 'x', restDate: '2026-06-01',
              pendingAgreement: true, settled: false, actionNeeded: true)),
          '同意待ち');
    });
    test('★成立できません（BE が返す change_blocked を読むだけ）', () {
      expect(
          substituteStateLabel(_row(
              id: 'x', restDate: '2026-06-01',
              actionNeeded: true, changeBlocked: true)),
          '成立できません');
    });
    test('★対: 残りは成立', () {
      expect(
          substituteStateLabel(
              _row(id: 'x', restDate: '2026-06-01', changeBlocked: false)),
          '成立');
    });

    // ★差集合の導き方をやめたことを、ここで名指しで固定する。
    //   それまでは「action_needed が true かつ pending_agreement でない」で
    //   導いていた。答えは同じでも、同じ判定が BE と端末の2箇所に並ぶ形だった。
    test('★古いサーバー（change_blocked が無い回）は「成立できません」を出さない', () {
      // action_needed だけが true ＝ 以前の差集合なら「成立できません」になった行。
      final old = _row(id: 'x', restDate: '2026-06-01', actionNeeded: true);
      expect(old.containsKey('change_blocked'), isFalse,
          reason: '土台: 古いサーバーの姿になっていない');
      expect(substituteStateLabel(old), '成立',
          reason: '印が無いのに端末が「成立できません」を組み立てている');
    });
    test('★対: change_blocked が false なら、action_needed が true でも出さない', () {
      expect(
          substituteStateLabel(_row(
              id: 'x', restDate: '2026-06-01',
              actionNeeded: true, pendingAgreement: true, settled: false,
              changeBlocked: false)),
          '同意待ち');
    });
  });

  // ══════════════════════════════════════════════════════════
  group('(3) 「誰がいつ登録したか」の1行', () {
    test('★事務が持ちかけた行は氏名と日付が出る', () {
      expect(
          substituteRegisteredLine(_row(
              id: 'x', restDate: '2026-06-10',
              proposedAt: '2026-06-01T03:00:00.000Z',
              proposedByName: '山田')),
          '事務 山田 さんが 6月1日 に登録');
    });
    test('★氏名がまだ返らない回でも落とさず名前なしで出す', () {
      expect(
          substituteRegisteredLine(_row(
              id: 'x', restDate: '2026-06-10',
              proposedAt: '2026-06-01T03:00:00.000Z')),
          '事務が 6月1日 に登録');
    });
    test('★自分で立てた行は created_at の日付で「M月D日 に自分で登録」', () {
      expect(
          substituteRegisteredLine(_row(
              id: 'x', restDate: '2026-06-10',
              createdAt: '2026-06-03T03:00:00.000Z')),
          '6月3日 に自分で登録');
    });
    test('★対: created_at が無い回（古いサーバー）は日付を書かず「自分で登録」だけ', () {
      // ★端末で今日から作ると嘘の日付になる。作らない。
      final old = _row(id: 'x', restDate: '2026-06-10');
      expect(old.containsKey('created_at'), isFalse,
          reason: '土台: 古いサーバーの姿になっていない');
      expect(substituteRegisteredLine(old), '自分で登録');
    });
    test('★対: created_at が日時として読めない回も日付を書かない', () {
      expect(
          substituteRegisteredLine(
              _row(id: 'x', restDate: '2026-06-10', createdAt: 'こわれた')),
          '自分で登録');
    });
    test('★対: 持ちかけの行は created_at があっても proposed_at の日付を使う', () {
      expect(
          substituteRegisteredLine(_row(
              id: 'x', restDate: '2026-06-10',
              proposedAt: '2026-06-01T03:00:00.000Z',
              proposedByName: '山田',
              createdAt: '2026-05-20T03:00:00.000Z')),
          '事務 山田 さんが 6月1日 に登録');
    });
  });

  // ══════════════════════════════════════════════════════════
  group('(4) 日付の出し方', () {
    test('YYYY-MM-DD → M月D日（先頭ゼロなし）', () {
      expect(jpMonthDay('2026-06-01'), '6月1日');
      expect(jpMonthDay('2026-12-25'), '12月25日');
    });
    test('★形が違うものは化けさせずそのまま返す', () {
      expect(jpMonthDay('こわれた'), 'こわれた');
      expect(jpMonthDay(null), '—');
    });
    test('ISO の日時 → JST の M月D日', () {
      // 2026-06-01T15:00Z = JST 2026-06-02 00:00
      expect(jpMonthDayOfIso('2026-06-01T15:00:00.000Z'), '6月2日');
      expect(jpMonthDayOfIso('こわれた'), '—');
    });
  });

  // ══════════════════════════════════════════════════════════
  group('(5) 通知の ref_id の解析', () {
    // （元）★職人に届く4種類が名簿に在る
    // →再（2026-09-26・便F11）: 便B14c で2種類（substitute_agree_remind・
    //   substitute_change_withdrawn）増えて6種類。
    test('★職人に届く6種類が名簿に在る', () {
      expect(kSubstituteNoticeTypes, {
        'substitute_registered',
        'substitute_change_confirmed',
        'substitute_change_auto_settled',
        'substitute_change_blocked',
        'substitute_agree_remind',
        'substitute_change_withdrawn',
      });
    });
    test('★便B14c の2種類の ref_id（type:<id>）から id が取れる', () {
      expect(parseSubstituteRefId('substitute_agree_remind:rd_123'), 'rd_123');
      expect(parseSubstituteRefId('substitute_change_withdrawn:rd_123'), 'rd_123');
    });
    test('★type:<id> の形から id が取れる', () {
      expect(parseSubstituteRefId('substitute_registered:rd_123'), 'rd_123');
    });
    test('★type:<id>:<日付など> でも id は最初の区切りの次だけ', () {
      expect(
          parseSubstituteRefId('substitute_change_blocked:rd_123:2026-06-01'),
          'rd_123');
    });
    test('★対: 解析できない形は null（推測で埋めない）', () {
      expect(parseSubstituteRefId('substitute_registered'), isNull,
          reason: '区切りが無いのに id を作っている');
      expect(parseSubstituteRefId('substitute_registered:'), isNull,
          reason: '空の id を通している');
      expect(parseSubstituteRefId(''), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════
  group('(6) カレンダーの休みの理由', () {
    test('★英字の鍵が日本語で出る（既にこのアプリが使っている言い方）', () {
      expect(restReasonLabel('paid_leave'), '有給');
      expect(restReasonLabel('absence'), '欠勤');
      expect(restReasonLabel('company_closed'), '会社休業');
      expect(restReasonLabel('personal'), '私用');
      expect(restReasonLabel('comp_off'), '代休');
      expect(restReasonLabel('substitute'), '振替休日');
    });
    test('★対: 知らない理由は英字のまま出す（黙って消さない）', () {
      expect(restReasonLabel('brand_new_reason'), 'brand_new_reason');
    });
    test('★1行の実物: 英字が出ていない', () {
      final info = CalendarDayInfo(
        date: DateTime(2026, 6, 10),
        restPortion: 'full',
        restReason: 'substitute',
      );
      expect(info.restLine.contains('substitute'), isFalse,
          reason: '英字の理由がそのまま出ている');
      expect(info.restLine.contains('振替休日'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  group('(7) カレンダーの箱の入口', () {
    testWidgets('★振替の日の箱には「振替休日を開く」が出て、押すと呼ばれる',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(CalendarDaySheet(
        info: CalendarDayInfo(
          date: DateTime(2026, 6, 10),
          restPortion: 'full',
          restReason: 'substitute',
        ),
        maxHeight: 600,
        substituteId: 'rd_123',
        onOpenSubstitute: () => tapped++,
      )));
      await tester.pumpAndSettle();

      expect(find.text('振替休日を開く'), findsOneWidget);
      await tester.tap(find.text('振替休日を開く'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });

    testWidgets('★対: 振替と関係の無い日の箱には出ない', (tester) async {
      await tester.pumpWidget(_wrap(CalendarDaySheet(
        info: CalendarDayInfo(
          date: DateTime(2026, 6, 10),
          restPortion: 'full',
          restReason: 'paid_leave',
        ),
        maxHeight: 600,
      )));
      await tester.pumpAndSettle();
      expect(find.text('振替休日を開く'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (8) 一覧の画面そのもの ― 0件・取れなかった回・叩く回数
  //   ★前の便では測れていなかった（画面が実 HTTP へ行くため）。
  //     差し替え口を足したので、ここから先は画面を立てて見る。
  // ══════════════════════════════════════════════════════════
  group('(8) 一覧の画面', () {
    testWidgets('★0件のときは黙らず「いまは振替休日はありません」と出す', (tester) async {
      final api = _FakeSvc(rows: const []);
      await _pump(tester, SubstituteListScreen(service: api));

      expect(find.text('いまは振替休日はありません'), findsOneWidget,
          reason: '0件を黙って空の画面にしている');
      expect(find.text('もう一度'), findsNothing,
          reason: '取れているのに失敗の顔を出している');
    });

    testWidgets('★対: 取れなかった回は理由と「もう一度」が出る（0件に倒さない）',
        (tester) async {
      const beError = 'サーバーに接続できません: 検査';
      final api = _FakeSvc(listFails: true, listError: beError);
      await _pump(tester, SubstituteListScreen(service: api));

      expect(find.text(beError), findsOneWidget,
          reason: 'BE が返した理由を丸めている');
      expect(find.text('もう一度'), findsOneWidget,
          reason: 'やり直す道が無い');
      expect(find.text('いまは振替休日はありません'), findsNothing,
          reason: '取れていないのに「無い」と言い切っている');
    });

    testWidgets('★理由が無い回でも黙らない（端末の言葉で理由を出す）', (tester) async {
      final api = _FakeSvc(listFails: true);
      await _pump(tester, SubstituteListScreen(service: api));
      expect(find.text('振替休日を取得できませんでした'), findsOneWidget);
      expect(find.text('もう一度'), findsOneWidget);
    });

    testWidgets('★一覧の口をちょうど1回だけ叩く（対照: 月の口は1回も叩かない）',
        (tester) async {
      final api = _FakeSvc(rows: [
        _row(id: 'a', restDate: '2026-06-10', pairedWorkDate: '2026-06-08',
            changeBlocked: false),
      ]);
      await _pump(tester, SubstituteListScreen(service: api));

      expect(api.listCalls, 1,
          reason: '開いただけで一覧の口を1回より多く/少なく叩いている');
      expect(api.monthCalls, 0,
          reason: '月で切る別の口（/rest-days/my）まで叩いている');
      expect(api.detailCalls, isEmpty,
          reason: '押していないのに1件の口を叩いている');
    });

    testWidgets('★天井で切れた回は「一部です」と言う（これで全部と言い切らない）',
        (tester) async {
      final api = _FakeSvc(
        rows: [_row(id: 'a', restDate: '2026-06-10', changeBlocked: false)],
        truncated: true,
      );
      await _pump(tester, SubstituteListScreen(service: api));
      expect(find.textContaining('ここに出ているのは一部です'), findsOneWidget);
    });

    testWidgets('★対: 切れていない回はその断りを出さない', (tester) async {
      final api = _FakeSvc(
        rows: [_row(id: 'a', restDate: '2026-06-10', changeBlocked: false)],
      );
      await _pump(tester, SubstituteListScreen(service: api));
      expect(find.textContaining('ここに出ているのは一部です'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (9) 1件の画面 ― events の text はそのまま／注意書きは同意待ちのときだけ
  // ══════════════════════════════════════════════════════════
  group('(9) 1件の画面', () {
    testWidgets('★events の text は BE の文がそのまま出る（端末で書き換えない）',
        (tester) async {
      const t1 = '事務 山田 さんが持ちかけた';
      const t2 = 'ご本人が 6月12日 への変更を申し出た';
      final api = _FakeSvc(
        detail: _detail(id: 'rd_1', restDate: '2026-06-10'),
        events: const [
          {'type': 'registered', 'at': '2026-06-01T00:00:00.000Z', 'text': t1},
          {'type': 'change_requested', 'at': '2026-06-05T00:00:00.000Z', 'text': t2},
        ],
      );
      await _pump(tester,
          SubstituteDetailScreen(restDayId: 'rd_1', service: api));

      expect(find.text(t1), findsOneWidget, reason: 'BE の文が書き換えられている');
      expect(find.text(t2), findsOneWidget, reason: 'BE の文が書き換えられている');
      expect(api.detailCalls, ['rd_1'],
          reason: 'その id で1件の口を叩いていない');
    });

    testWidgets('★対: 記録が0件なら「記録はありません」と言う（黙らない）',
        (tester) async {
      final api = _FakeSvc(detail: _detail(id: 'rd_1', restDate: '2026-06-10'));
      await _pump(tester,
          SubstituteDetailScreen(restDayId: 'rd_1', service: api));
      expect(find.text('記録はありません'), findsOneWidget);
    });

    // ── モック B2 の注意書き ───────────────────────────────
    const noticeHead = 'はじめにご確認ください';
    const noticeNote1 = '※同意するまで、この振替は成立しません。';
    const noticeNote2 = '※実際の取り扱いは、雇用契約書および就業規則の定めによります。';

    testWidgets('★同意待ちのときだけ注意書きが出る（本文は原文のまま）',
        (tester) async {
      final api = _FakeSvc(
        detail: _detail(
            id: 'rd_1', restDate: '2026-06-10',
            pendingAgreement: true, settled: false),
      );
      await _pump(tester,
          SubstituteDetailScreen(restDayId: 'rd_1', service: api));

      expect(find.text(noticeHead), findsOneWidget, reason: '見出しが出ていない');
      // 本文は太字を挟むので Text.rich。文の全体を1本の文字列として突き合わせる。
      expect(
          find.textContaining(
              '振替休日は、出勤する日と休む日を前もって入れ替えるしくみです。'
              '入れ替えた出勤日は通常の労働日となり、休日の割増賃金は発生しません。'),
          findsOneWidget,
          reason: '本文が原文と1文字でも違う');
      expect(find.text(noticeNote1), findsOneWidget);
      expect(find.text(noticeNote2), findsOneWidget);
      expect(find.text('同意待ち'), findsOneWidget, reason: '土台: 同意待ちの状態でない');
    });

    testWidgets('★対: 成立した行には出さない（決まった話を蒸し返さない）',
        (tester) async {
      final api = _FakeSvc(
        detail: _detail(id: 'rd_1', restDate: '2026-06-10'),
      );
      await _pump(tester,
          SubstituteDetailScreen(restDayId: 'rd_1', service: api));

      expect(find.text(noticeHead), findsNothing);
      expect(find.text(noticeNote1), findsNothing);
      expect(find.text(noticeNote2), findsNothing);
      expect(find.text('成立'), findsOneWidget, reason: '土台: 成立の状態でない');
    });

    testWidgets('★対: 成立できない行にも出さない（同意待ちではないため）',
        (tester) async {
      final api = _FakeSvc(
        detail: _detail(
            id: 'rd_1', restDate: '2026-06-10',
            changeRequestedRestDate: '2026-06-12',
            changeDeadline: '2026-06-09',
            changeBlocked: true),
      );
      await _pump(tester,
          SubstituteDetailScreen(restDayId: 'rd_1', service: api));

      expect(find.text(noticeHead), findsNothing);
      expect(find.text('成立できません'), findsOneWidget, reason: '土台: その状態でない');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (10) 二者比較 ― 同じ1件は、どの入口から開いても同じに見える
  //   ★「一覧から開いた回」と「通知から開いた回」。以前は一覧から印を
  //     引数で持ち込んでいたので、通知から開くと「成立できません」が消えていた。
  //     いまは1件の口が返す change_blocked だけを読むので、入口で変わらない。
  // ══════════════════════════════════════════════════════════
  group('(10) 入口で状態が変わらない', () {
    /// 「成立できない」1件。一覧の行と1件の口の両方を同じ真実で返す。
    _FakeSvc blockedApi() => _FakeSvc(
          rows: [
            _row(id: 'rd_b', restDate: '2026-06-10',
                pairedWorkDate: '2026-06-08',
                actionNeeded: true, changeBlocked: true,
                proposedAt: '2026-06-01T00:00:00.000Z',
                proposedByName: '山田'),
          ],
          detail: _detail(
              id: 'rd_b', restDate: '2026-06-10',
              pairedWorkDate: '2026-06-08',
              changeRequestedRestDate: '2026-06-12',
              changeDeadline: '2026-06-09',
              changeBlocked: true),
        );

    testWidgets('★一覧から開いた回 → 「成立できません」が出る', (tester) async {
      final api = blockedApi();
      await _pump(tester, SubstituteListScreen(service: api));
      // 一覧の行にも同じ語が出ている（土台）。
      expect(find.text('成立できません'), findsOneWidget);

      await tester.tap(find.text('成立できません'));
      await tester.pumpAndSettle();

      expect(api.detailCalls, ['rd_b'], reason: '一覧からその1件へ進んでいない');
      expect(find.text('成立できません'), findsOneWidget,
          reason: '1件の画面で状態が消えている');
      expect(find.text('確認の期限'), findsOneWidget, reason: '土台: 1件の画面が出ていない');
    });

    testWidgets('★対照: 通知から直に開いた回 → 同じ「成立できません」が出る',
        (tester) async {
      // 通知・カレンダーの道は restDayId だけを渡して開く（一覧を通らない）。
      final api = blockedApi();
      await _pump(tester,
          SubstituteDetailScreen(restDayId: 'rd_b', service: api));

      expect(api.detailCalls, ['rd_b']);
      expect(find.text('成立できません'), findsOneWidget,
          reason: '一覧を通らないと状態が出ない＝入口で食い違っている');
      expect(find.text('確認の期限'), findsOneWidget);
    });

    testWidgets('★対: change_blocked が false なら、どちらの入口でも出さない',
        (tester) async {
      final api = _FakeSvc(
        detail: _detail(
            id: 'rd_ok', restDate: '2026-06-10',
            changeRequestedRestDate: '2026-06-12',
            changeDeadline: '2026-07-09',
            changeBlocked: false),
      );
      await _pump(tester,
          SubstituteDetailScreen(restDayId: 'rd_ok', service: api));
      expect(find.text('成立できません'), findsNothing);
      expect(find.text('事務の確認待ち'), findsOneWidget);
    });

    testWidgets('★対: 古いサーバー（change_blocked が無い回）は出さない・落ちない',
        (tester) async {
      final api = _FakeSvc(
        detail: _detail(
            id: 'rd_old', restDate: '2026-06-10',
            changeRequestedRestDate: '2026-06-12',
            changeDeadline: '2026-06-09'),
      );
      await _pump(tester,
          SubstituteDetailScreen(restDayId: 'rd_old', service: api));
      expect(find.text('成立できません'), findsNothing,
          reason: '印が無いのに端末が組み立てている');
      expect(find.text('事務の確認待ち'), findsOneWidget,
          reason: '落ちて何も出ていない');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (11) 要対応の行（打刻の画面）
  //   ★件数も遷移先も親から下ろした値だけ。この行が見るのはその値だけで、
  //     数え方を自分で持たない。
  // ══════════════════════════════════════════════════════════
  group('(11) 要対応の行', () {
    // ★打刻の画面は端末の保存（SharedPreferences）も読む。検査では実体が無いので
    //   空の中身を渡しておく（Flutter が用意している差し替え）。これが無いと
    //   読み込みが終わらず、画面が spinner のまま止まる。
    setUp(() => SharedPreferences.setMockInitialValues(const {}));

    Widget punch({
      int substituteCount = 0,
      bool substituteTruncated = false,
      VoidCallback? onOpen,
    }) =>
        PunchScreen(
          reports: _FakeSvc(),
          shiftType: 'day',
          onShiftTypeChanged: (_) {},
          substituteCount: substituteCount,
          substituteTruncated: substituteTruncated,
          onOpenSubstitutes: onOpen,
        );

    testWidgets('★0件なら行そのものを出さない（無いものは見せない）', (tester) async {
      await _pump(tester, punch());
      expect(find.text('振替休日'), findsNothing);

      // ★空振りで合格にしない。画面が spinner のまま止まっていても
      //   「出ていない」は成り立ってしまうので、同じ検査の中で
      //   【1件あれば出る】ことを並べて見る（出ない理由が件数であることの証）。
      await _pump(tester, punch(substituteCount: 1));
      expect(find.text('振替休日'), findsOneWidget,
          reason: '1件あっても出ない＝画面がそもそも描けていない');
    });

    testWidgets('★1件以上で出て、押すと渡された遷移が呼ばれる', (tester) async {
      var tapped = 0;
      await _pump(tester, punch(substituteCount: 2, onOpen: () => tapped++));

      expect(find.text('振替休日'), findsOneWidget);
      expect(find.text('2'), findsWidgets, reason: '件数が出ていない');
      await tester.tap(find.text('振替休日'));
      await tester.pumpAndSettle();
      expect(tapped, 1, reason: '押しても何も起きない行になっている');
    });

    testWidgets('★天井で切れた回は数の後ろに + が付く（嘘の数を出さない）',
        (tester) async {
      await _pump(tester,
          punch(substituteCount: 1000, substituteTruncated: true));
      expect(find.text('振替休日'), findsOneWidget);
      expect(find.textContaining('1000+'), findsOneWidget,
          reason: '切れているのに言い切った数を出している');
    });

    testWidgets('★対: 切れていない回は + が付かない', (tester) async {
      await _pump(tester, punch(substituteCount: 3));
      expect(find.textContaining('3+'), findsNothing);
      expect(find.text('3'), findsWidgets);
    });
  });
}
