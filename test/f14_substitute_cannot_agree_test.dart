// ============================================================
// test/f14_substitute_cannot_agree_test.dart
//   便F14（ボス裁定【Q113】＝１・見本 claude/substitute_cannot_agree_mock_v1.html【Q116】＝１）を機械で固定する。
//   事務が持ちかけた振替休日に、ご本人が同意できない回（BE の can_agree が false・便B18）の見え方。
//
//   (a) C1  1件の画面: ［この振替に同意する］が押せない灰色・理由の行・※の行・［まだ決めない］が無い・間の実測
//   (b) C1  同意の口が符号付きで断った回は、窓を閉じた後に1件の口をもう一度引く（符号の無い失敗は引かない）
//   (c) P1  ホームの同意待ちの枠の2行と間・getRestDayToday の読み分け
//   (d) K2・K3  カレンダーの箱の文（CalendarDayInfo を手で組む回と、CalendarTab を BE の行の形から通す回）
//   (e)     押せない理由の1行（DenyReasonLine）の形と、承認の理由の行（ApprovalDenyLines）が同じ部品で出ること
//
// ★どれも二者比較（同意できない回と、同意できる回＝true・null・鍵なし）。
// ★本物のテーマ（AppTheme.dark）の下で測る（前例 test/f13_substitute_pending_test.dart）。
// ★色は 16進の生の値・文は一字一句で書く（定数を import して比べない）。
// ★差し替え口は今ある形だけ（SubstituteDetailScreen の service・PunchScreen の reports・
//   package:http の runWithClient＋MockClient）。
// ★BE の形は便B18 の約束（指示 AO3_F14 の【約束】）に合わせてここに直書きする。
// ============================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/core/theme/app_theme.dart';
import 'package:js_awake_app/screens/home_screen.dart'
    show CalendarTab, CalendarDaySheet, CalendarDayInfo, ApprovalDenyLines, approvalDenyLine;
import 'package:js_awake_app/screens/punch_screen.dart';
import 'package:js_awake_app/screens/substitute_detail_screen.dart';
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';
import 'package:js_awake_app/widgets/deny_reason_line.dart';

// ── 期待する色（16進の生の値）──────────────────────────────
const int _kOutlineStrong = 0xFF3A4048; // 押せないボタンの線
const int _kFaint = 0xFF635F55;         // 押せないボタンの字
const int _kAccent = 0xFF6FD6B4;        // 押せるボタンの線と字
const int _kSupport = 0xFF7B7567;       // 理由の行の印と字

// ── 文（一字一句）─────────────────────────────────────────
const String _reason = '10月18日の日報がありません';
const String _denyLine = '同意できません：10月18日の日報がありません';
const String _note = '※事務へご連絡ください。事務がこの振替を取り消します。';
const String _p1Second = '同意すると、今日は休みになります。';
const String _p1Contact = '休むときは、事務へご連絡ください。';

/// 差し替える口。★何を何回叩いたかを数える。
class _Fake extends ReportsService {
  _Fake({
    this.detail = const {},
    this.detailAfter,
    this.agreeResult,
    this.today,
  }) : super.forTest();

  /// getRestDay の rest_day に足すキー（can_agree ほか）。
  final Map<String, dynamic> detail;

  /// 2回目以降の getRestDay に足すキー（読み直しで灰色になることを見る）。
  final Map<String, dynamic>? detailAfter;
  final ApiResult<Map<String, dynamic>>? agreeResult;
  final RestDayToday? today;

  final List<String> detailCalls = [];
  int agreeCalls = 0;

  @override
  Future<ApiResult<RestDayToday>> getRestDayToday() async => apiSuccess<RestDayToday>(
        statusCode: 200,
        data: today ??
            const RestDayToday(rested: false, reason: null, portion: 'full'),
      );

  @override
  Future<ApiResult<Map<String, dynamic>>> getRestDay(String id) async {
    final extra = (detailCalls.isNotEmpty && detailAfter != null) ? detailAfter! : detail;
    detailCalls.add(id);
    return apiSuccess<Map<String, dynamic>>(
      statusCode: 200,
      data: {
        'rest_day': {
          'id': id,
          'rest_date': '2026-10-21',
          'paired_work_date': '2026-10-18',
          'pending_agreement': true,
          'cancelled_at': null,
          ...extra,
        },
        'events': const <Map<String, dynamic>>[],
      },
    );
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> agreeSubstitute(String id) async {
    agreeCalls++;
    return agreeResult ??
        apiSuccess<Map<String, dynamic>>(statusCode: 200, data: const {'pending_agreement': false});
  }
}

Future<void> _pumpThemed(WidgetTester tester, Widget screen,
    {Size size = const Size(1200, 2600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: screen));
  await tester.pumpAndSettle();
}

Color _textColorOf(WidgetTester tester, Finder of) {
  final rich = tester.widget<RichText>(
      find.descendant(of: of, matching: find.byType(RichText)).first);
  return rich.text.style!.color!;
}

Finder _agreeBtn() => find.widgetWithText(OutlinedButton, 'この振替に同意する');

void main() {
  // ══════════════════════════════════════════════════════════
  // (a) C1 1件の画面
  // ══════════════════════════════════════════════════════════
  group('(a) C1 1件の画面', () {
    Widget detail(_Fake f) =>
        SubstituteDetailScreen(key: UniqueKey(), restDayId: 'rd-1', service: f);

    testWidgets('★can_agree が false → 押せない灰色・理由の行・※の行・［まだ決めない］が無い・押せる高さ44以上',
        (tester) async {
      await _pumpThemed(tester, detail(_Fake(detail: const {
        'can_agree': false,
        'cannot_agree_code': 'SUBSTITUTE_WORK_DATE_NO_REPORT',
        'cannot_agree_reason': _reason,
      })));
      final btn = tester.widget<OutlinedButton>(_agreeBtn());
      expect(btn.onPressed, isNull, reason: '同意できないのに押せる');
      final side = btn.style!.side!.resolve(<WidgetState>{WidgetState.disabled})!;
      expect(side.color.toARGB32(), _kOutlineStrong, reason: '線が灰色でない');
      expect(_textColorOf(tester, _agreeBtn()).toARGB32(), _kFaint, reason: '字が灰色でない');
      expect(find.text(_denyLine), findsOneWidget);
      expect(find.widgetWithText(DenyReasonLine, _denyLine), findsOneWidget);
      expect(find.text(_note), findsOneWidget);
      expect(find.text('まだ決めない'), findsNothing, reason: '決めることが無いのに［まだ決めない］がある');
      final size = tester.getSize(_agreeBtn());
      // ignore: avoid_print
      print('C1 の灰色の［この振替に同意する］の大きさ（AppTheme.dark）: $size');
      expect(size.height, greaterThanOrEqualTo(44));
      // 押しても何も叩かない。
      await tester.tap(_agreeBtn(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    for (final c in <String, Map<String, dynamic>>{
      'true': const {'can_agree': true, 'cannot_agree_code': null, 'cannot_agree_reason': null},
      'null': const {'can_agree': null},
      '鍵なし': const {},
    }.entries) {
      testWidgets('★対照: can_agree が ${c.key} → 今のまま（押せる・accent・［まだ決めない］がある・理由の行と※の行が無い）',
          (tester) async {
        await _pumpThemed(tester, detail(_Fake(detail: c.value)));
        final btn = tester.widget<OutlinedButton>(_agreeBtn());
        expect(btn.onPressed, isNotNull);
        final side = btn.style!.side!.resolve(<WidgetState>{})!;
        expect(side.color.toARGB32(), _kAccent);
        expect(_textColorOf(tester, _agreeBtn()).toARGB32(), _kAccent);
        expect(find.text('まだ決めない'), findsOneWidget);
        expect(find.byType(DenyReasonLine), findsNothing);
        expect(find.text(_note), findsNothing);
      });
    }

    testWidgets('★間の実測: ボタンの下端→理由の行 10・理由の行→※の行 0・※の行→「記録」20（見本 C1）',
        (tester) async {
      await _pumpThemed(tester, detail(_Fake(detail: const {
        'can_agree': false,
        'cannot_agree_reason': _reason,
      })));
      final b = tester.getRect(_agreeBtn());
      final r = tester.getRect(find.byType(DenyReasonLine));
      final n = tester.getRect(find.text(_note));
      final k = tester.getRect(find.text('記録'));
      // ignore: avoid_print
      print('C1 の間: ボタン→理由 ${r.top - b.bottom}・理由→※ ${n.top - r.bottom}・※→記録 ${k.top - n.bottom}');
      expect(r.top - b.bottom, closeTo(10, 0.01));
      expect(n.top - r.bottom, closeTo(0, 0.01));
      expect(k.top - n.bottom, closeTo(20, 0.01));
    });

    testWidgets('★理由が空のときは頭の語だけ（同意できません）', (tester) async {
      await _pumpThemed(tester, detail(_Fake(detail: const {
        'can_agree': false,
        'cannot_agree_reason': '  ',
      })));
      expect(find.text('同意できません'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (b) C1 断られたら読み直す
  // ══════════════════════════════════════════════════════════
  group('(b) C1 同意の口が断った回の読み直し', () {
    // ★whileOpen（2026-10-04・便F14続）: 断りの窓が開いている間に確かめること（読み直す順＝窓を閉じた後）。
    Future<void> agreeAndClose(WidgetTester tester, {void Function()? whileOpen}) async {
      await tester.tap(_agreeBtn());
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認しました'));
      await tester.pumpAndSettle();
      expect(find.text('同意できませんでした'), findsOneWidget, reason: '断りの窓が出ていない');
      whileOpen?.call();
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
    }

    testWidgets('★符号付きの断り → 窓を閉じた後に1件の口をもう一度引き、灰色になる', (tester) async {
      final f = _Fake(
        detail: const {'can_agree': true},
        detailAfter: const {'can_agree': false, 'cannot_agree_reason': _reason},
        agreeResult: apiFailure<Map<String, dynamic>>(
          statusCode: 409,
          errorMessage: _reason,
          errorCode: 'SUBSTITUTE_WORK_DATE_NO_REPORT',
        ),
      );
      await _pumpThemed(tester, SubstituteDetailScreen(restDayId: 'rd-1', service: f));
      expect(f.detailCalls.length, 1);
      await agreeAndClose(tester, whileOpen: () {
        expect(f.detailCalls.length, 1, reason: '断りの窓を閉じる前に読み直している');
      });
      expect(f.agreeCalls, 1);
      expect(f.detailCalls.length, 2, reason: '断りの後に読み直していない');
      expect(tester.widget<OutlinedButton>(_agreeBtn()).onPressed, isNull,
          reason: '読み直した後も押せる');
      expect(find.text(_denyLine), findsOneWidget);
    });

    testWidgets('★今の8つの符号（例 ALREADY_AGREED）でも読み直す', (tester) async {
      final f = _Fake(
        agreeResult: apiFailure<Map<String, dynamic>>(
          statusCode: 409,
          errorMessage: 'この振替休日には既に同意済みです',
          errorCode: 'ALREADY_AGREED',
        ),
      );
      await _pumpThemed(tester, SubstituteDetailScreen(restDayId: 'rd-1', service: f));
      await agreeAndClose(tester, whileOpen: () {
        expect(f.detailCalls.length, 1, reason: '断りの窓を閉じる前に読み直している');
      });
      expect(f.detailCalls.length, 2);
    });

    testWidgets('★対照: 符号の無い失敗（通信の失敗）→ 読み直さない', (tester) async {
      final f = _Fake(
        agreeResult: apiFailure<Map<String, dynamic>>(statusCode: 0, errorMessage: '通信できませんでした'),
      );
      await _pumpThemed(tester, SubstituteDetailScreen(restDayId: 'rd-1', service: f));
      await agreeAndClose(tester);
      expect(f.agreeCalls, 1);
      expect(f.detailCalls.length, 1, reason: '符号の無い失敗で読み直している');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (c) P1 ホームの同意待ちの枠
  // ══════════════════════════════════════════════════════════
  group('(c) P1 ホームの同意待ちの枠', () {
    setUp(() => SharedPreferences.setMockInitialValues(const {}));

    Widget punch(_Fake f) => PunchScreen(
          key: UniqueKey(),
          reports: f,
          shiftType: 'day',
          onShiftTypeChanged: (_) {},
        );

    testWidgets('★同意できない → 2行が一字一句・「同意すると、今日は休みになります。」が無い・間 8・0・8', (tester) async {
      await _pumpThemed(tester, punch(_Fake(
        today: const RestDayToday(
          rested: false, reason: null, portion: 'full',
          pendingSubstituteRestDayId: 'rd-9',
          pendingSubstituteCanAgree: false,
          pendingSubstituteCannotAgreeReason: _reason,
        ),
      )));
      expect(find.text(_denyLine), findsOneWidget);
      expect(find.text(_p1Contact), findsOneWidget);
      expect(find.text(_p1Second), findsNothing);
      final first = tester.getRect(find.text('今日は、事務から持ちかけられた振替休日の休む日です。'));
      final deny = tester.getRect(find.text(_denyLine));
      final contact = tester.getRect(find.text(_p1Contact));
      final open = tester.getRect(find.widgetWithText(OutlinedButton, '振替休日を開く'));
      // ignore: avoid_print
      print('P1 の間: 1行目→理由 ${deny.top - first.bottom}・理由→連絡 ${contact.top - deny.bottom}・連絡→ボタン ${open.top - contact.bottom}');
      expect(deny.top - first.bottom, closeTo(8, 0.01));
      expect(contact.top - deny.bottom, closeTo(0, 0.01));
      expect(open.top - contact.bottom, closeTo(8, 0.01));
      // 2行の色と大きさは今の2行目と同じ（textSupport 系の _label・12）。
      final s1 = tester.widget<Text>(find.text(_denyLine)).style!;
      final s2 = tester.widget<Text>(find.text(_p1Contact)).style!;
      expect(s1.fontSize, 12);
      expect(s2.fontSize, 12);
      expect(s1.color, s2.color);
    });

    for (final c in <String, RestDayToday>{
      'true': const RestDayToday(
          rested: false, reason: null, portion: 'full',
          pendingSubstituteRestDayId: 'rd-9', pendingSubstituteCanAgree: true),
      '鍵なし（既定）': const RestDayToday(
          rested: false, reason: null, portion: 'full', pendingSubstituteRestDayId: 'rd-9'),
    }.entries) {
      testWidgets('★対照: ${c.key} → 今の文のまま', (tester) async {
        await _pumpThemed(tester, punch(_Fake(today: c.value)));
        expect(find.text(_p1Second), findsOneWidget);
        expect(find.text(_p1Contact), findsNothing);
        expect(find.textContaining('同意できません'), findsNothing);
        // 今の2行目の色と同じ色であることの比較の相手。
        expect(tester.widget<Text>(find.text(_p1Second)).style!.fontSize, 12);
      });
    }

    testWidgets('★同意できない2行の色は、今の2行目の色と同じ', (tester) async {
      await _pumpThemed(tester, punch(_Fake(
        today: const RestDayToday(
            rested: false, reason: null, portion: 'full', pendingSubstituteRestDayId: 'rd-9'),
      )));
      final now = tester.widget<Text>(find.text(_p1Second)).style!.color;
      await tester.pumpWidget(const SizedBox());
      await _pumpThemed(tester, punch(_Fake(
        today: const RestDayToday(
          rested: false, reason: null, portion: 'full',
          pendingSubstituteRestDayId: 'rd-9', pendingSubstituteCanAgree: false,
          pendingSubstituteCannotAgreeReason: _reason),
      )));
      expect(tester.widget<Text>(find.text(_denyLine)).style!.color, now);
      expect(tester.widget<Text>(find.text(_p1Contact)).style!.color, now);
      // ★16進の生の値でも見る（2026-10-04・便F14続・(e) と同じ形）。
      expect(tester.widget<Text>(find.text(_denyLine)).style!.color!.toARGB32(), _kSupport);
      expect(tester.widget<Text>(find.text(_p1Contact)).style!.color!.toARGB32(), _kSupport);
    });
  });

  group('(c) getRestDayToday の読み分け', () {
    setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'T'}));

    Future<RestDayToday?> read(Map<String, dynamic> body) => http.runWithClient(
          () async => (await ReportsService().getRestDayToday()).data,
          () => MockClient((req) async => http.Response(jsonEncode(body), 200,
              request: req, headers: {'content-type': 'application/json'})),
        );
    const base = {'rested': false, 'reason': null, 'portion': 'full',
        'pending_substitute_rest_day_id': 'rd-1'};

    test('★false → 同意できない・理由はそのまま', () async {
      final t = await read({...base, 'pending_substitute_can_agree': false,
          'pending_substitute_cannot_agree_code': 'SUBSTITUTE_WORK_DATE_NO_REPORT',
          'pending_substitute_cannot_agree_reason': _reason});
      expect(t!.pendingSubstituteCanAgree, isFalse);
      expect(t.pendingSubstituteCannotAgreeReason, _reason);
    });
    test('★true → 同意できる', () async {
      final t = await read({...base, 'pending_substitute_can_agree': true,
          'pending_substitute_cannot_agree_code': null, 'pending_substitute_cannot_agree_reason': null});
      expect(t!.pendingSubstituteCanAgree, isTrue);
      expect(t.pendingSubstituteCannotAgreeReason, isNull);
    });
    test('★キーなし（便B18 より前の BE）→ 同意できる扱い', () async {
      final t = await read(base);
      expect(t!.pendingSubstituteCanAgree, isTrue);
      expect(t.pendingSubstituteCannotAgreeReason, isNull);
    });
    test('★null → 同意できる扱い', () async {
      final t = await read({...base, 'pending_substitute_can_agree': null});
      expect(t!.pendingSubstituteCanAgree, isTrue);
    });
    test('★理由が空 → 空の文字のまま（行は頭の語だけになる）', () async {
      final t = await read({...base, 'pending_substitute_can_agree': false,
          'pending_substitute_cannot_agree_reason': ''});
      expect(t!.pendingSubstituteCanAgree, isFalse);
      expect(t.pendingSubstituteCannotAgreeReason, '');
      expect(denyReasonText('同意できません', t.pendingSubstituteCannotAgreeReason), '同意できません');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (d) K2・K3 カレンダーの箱
  // ══════════════════════════════════════════════════════════
  group('(d) K2・K3 CalendarDayInfo（手で組む）', () {
    test('★同意できない回の文 → 「振替休日：同意待ち（同意できません：…）」', () {
      final k2 = CalendarDayInfo(
          date: DateTime(2026, 10, 21),
          substitutePendingRest: true,
          substitutePendingRestDenyText: _denyLine);
      expect(k2.substitutePendingLine, '振替休日：同意待ち（同意できません：10月18日の日報がありません）');
      final k3 = CalendarDayInfo(
          date: DateTime(2026, 10, 18),
          substitutePendingWork: true,
          substitutePendingWorkDenyText: _denyLine);
      expect(k3.substitutePendingLine, '振替休日：同意待ち（同意できません：10月18日の日報がありません）');
    });
    test('★対照: 文を渡さない（同意できる）→ 今の2つの文', () {
      expect(CalendarDayInfo(date: DateTime(2026, 10, 21), substitutePendingRest: true)
          .substitutePendingLine, '振替休日：同意待ち（同意すると、この日は休みになります）');
      expect(CalendarDayInfo(date: DateTime(2026, 10, 18), substitutePendingWork: true)
          .substitutePendingLine, '振替休日：同意待ち（同意すると、この日は出勤する日になります）');
    });
  });

  group('(d) K2・K3 CalendarTab（BE の行の形から通す）', () {
    final now = DateTime.now();
    String ymd(int d) =>
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
    String mdOf(int d) => '${now.month}月$d日';
    // 同意できない（理由あり）・同意できる・鍵なし・同意できない（理由が null）の4組。
    // （2026-10-04・便F14続で足した4組）can_agree が null・同意できない（理由が空の文字）・
    //   /my だけ同意できない形・/my/substitutes だけ同意できない形。
    //   ★日は 1〜28 の中で、上の8日（3・5・10・12・17・19・24・26）と重ねない（ある日に休む日と出勤する日の
    //     両方が当たると K2 の文が先に出る＝CalendarDayInfo の substitutePendingLine）。
    //   ★分けた2組は、同じ行（同じ id・休む日・出勤する日）を両方の口に返し、鍵（can_agree・
    //     cannot_agree_reason）だけを片方の口で同意できない形にする。K2 は GET /rest-days/my の行の鍵だけ、
    //     K3 は GET /rest-days/my/substitutes の行の鍵だけで文が変わることを二者比較で見る。
    final restN = ymd(3), workN = ymd(5);
    final restT = ymd(10), workT = ymd(12);
    final restK = ymd(17), workK = ymd(19);
    final restE = ymd(24), workE = ymd(26);
    final restU = ymd(6), workU = ymd(7);    // can_agree が null
    final restB = ymd(8), workB = ymd(9);    // 理由が空の文字
    final restA = ymd(13), workA = ymd(14);  // /my だけ同意できない
    final restS = ymd(20), workS = ymd(21);  // /my/substitutes だけ同意できない
    final reasonN = '${mdOf(5)}の日報がありません';

    Map<String, dynamic> row(String id, String rest, String work, Map<String, dynamic> keys) =>
        {'id': id, 'rest_date': rest, 'paired_work_date': work, 'reason': 'substitute',
         'portion': 'full', 'pending_agreement': true, 'settled': false, 'action_needed': true,
         ...keys};
    final keysN = {'can_agree': false, 'cannot_agree_code': 'SUBSTITUTE_WORK_DATE_NO_REPORT',
        'cannot_agree_reason': reasonN};
    const keysT = {'can_agree': true, 'cannot_agree_code': null, 'cannot_agree_reason': null};
    const keysE = {'can_agree': false, 'cannot_agree_code': 'SUBSTITUTE_WORK_DATE_NO_REPORT',
        'cannot_agree_reason': null};

    const keysU = {'can_agree': null, 'cannot_agree_code': null, 'cannot_agree_reason': null};
    const keysB = {'can_agree': false, 'cannot_agree_code': 'SUBSTITUTE_WORK_DATE_NO_REPORT',
        'cannot_agree_reason': ''};

    MockClient cal() => MockClient((req) async {
          final path = req.url.path;
          Object body = const {};
          final rows = [
            row('rd-n', restN, workN, keysN),
            row('rd-t', restT, workT, keysT),
            row('rd-k', restK, workK, const {}),
            row('rd-e', restE, workE, keysE),
            row('rd-u', restU, workU, keysU),
            row('rd-b', restB, workB, keysB),
          ];
          if (path.endsWith('/rest-days/my/substitutes')) {
            body = {'rows': [
              ...rows,
              row('rd-a', restA, workA, keysT),  // /my だけ同意できない組（こちらは同意できる形）
              row('rd-s', restS, workS, keysN),  // /my/substitutes だけ同意できない組
            ], 'truncated': false};
          } else if (path.endsWith('/rest-days/my')) {
            body = {'days': [
              ...rows,
              row('rd-a', restA, workA, keysN),
              row('rd-s', restS, workS, keysT),
            ]};
          } else if (path.endsWith('/attendance/holidays/my')) {
            body = {'weekly': const {}, 'dates': {workN: 'legal', workT: 'legal', workK: 'legal', workE: 'legal',
                workU: 'legal', workB: 'legal', workA: 'legal', workS: 'legal'}};
          } else if (path.endsWith('/reports')) {
            body = {'reports': const []};
          }
          return http.Response(jsonEncode(body), 200,
              request: req, headers: {'content-type': 'application/json'});
        });

    setUp(() =>
        SharedPreferences.setMockInitialValues({'auth_token': 'T', 'company_id': 'C1'}));

    Future<void> pumpCal(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        // ★本物のテーマ（AppTheme.dark）の下で組む（2026-10-04・便F14続）。大きさと runWithClient は今のまま。
        await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const Scaffold(body: CalendarTab())));
        await tester.pumpAndSettle();
      }, cal);
    }

    Finder cellOf(int d) => find
        .ancestor(of: find.text('$d'), matching: find.byType(GestureDetector))
        .first;

    Future<String?> lineOf(WidgetTester tester, int d) async {
      await http.runWithClient(() async {
        await tester.tap(cellOf(d));
        await tester.pumpAndSettle();
      }, cal);
      final sheet = find.byType(CalendarDaySheet);
      final hits = find.descendant(
          of: sheet,
          matching: find.byWidgetPredicate(
              (w) => w is Text && (w.data ?? '').startsWith('振替休日：同意待ち')));
      // ★1つの検査で開くのは1日だけ（シートを閉じる手を持たない）。
      return hits.evaluate().isEmpty ? null : (hits.evaluate().first.widget as Text).data;
    }

    final cases = <(String, int, String)>[
      ('K2 同意できない', 3, '振替休日：同意待ち（同意できません：$reasonN）'),
      ('K3 同意できない', 5, '振替休日：同意待ち（同意できません：$reasonN）'),
      ('K2 true', 10, '振替休日：同意待ち（同意すると、この日は休みになります）'),
      ('K3 true', 12, '振替休日：同意待ち（同意すると、この日は出勤する日になります）'),
      ('K2 鍵なし', 17, '振替休日：同意待ち（同意すると、この日は休みになります）'),
      ('K3 鍵なし', 19, '振替休日：同意待ち（同意すると、この日は出勤する日になります）'),
      ('K2 理由 null', 24, '振替休日：同意待ち（同意できません）'),
      ('K3 理由 null', 26, '振替休日：同意待ち（同意できません）'),
      // （2026-10-04・便F14続で足した）
      ('K2 can_agree null', 6, '振替休日：同意待ち（同意すると、この日は休みになります）'),
      ('K3 can_agree null', 7, '振替休日：同意待ち（同意すると、この日は出勤する日になります）'),
      ('K2 理由が空の文字', 8, '振替休日：同意待ち（同意できません）'),
      ('K3 理由が空の文字', 9, '振替休日：同意待ち（同意できません）'),
      ('K2 /my だけ同意できない → 同意できない文', 13, '振替休日：同意待ち（同意できません：$reasonN）'),
      ('K3 /my だけ同意できない → 今の文', 14, '振替休日：同意待ち（同意すると、この日は出勤する日になります）'),
      ('K2 /my/substitutes だけ同意できない → 今の文', 20, '振替休日：同意待ち（同意すると、この日は休みになります）'),
      ('K3 /my/substitutes だけ同意できない → 同意できない文', 21, '振替休日：同意待ち（同意できません：$reasonN）'),
    ];
    for (final c in cases) {
      testWidgets('★${c.$1}: ${c.$2}日の箱の文 → ${c.$3}', (tester) async {
        await pumpCal(tester);
        expect(await lineOf(tester, c.$2), c.$3);
      });
    }
  });

  // ══════════════════════════════════════════════════════════
  // (e) 押せない理由の1行
  // ══════════════════════════════════════════════════════════
  group('(e) DenyReasonLine と ApprovalDenyLines', () {
    testWidgets('★DenyReasonLine の形: 印 info_outline・14・textSupport・間 6・字 12・行の高さ 1.6・textSupport',
        (tester) async {
      // ★本物のテーマ（AppTheme.dark）の下で組む（2026-10-04・便F14続）。
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark,
          home: const Scaffold(body: DenyReasonLine('同意できません：理由'))));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.info_outline);
      expect(icon.size, 14);
      expect(icon.color!.toARGB32(), _kSupport);
      final gap = tester.getRect(find.byType(Text)).left - tester.getRect(find.byType(Icon)).right;
      expect(gap, closeTo(6, 0.01));
      final st = tester.widget<Text>(find.text('同意できません：理由')).style!;
      expect(st.fontSize, 12);
      expect(st.height, 1.6);
      expect(st.color!.toARGB32(), _kSupport);
    });

    test('★denyReasonText と approvalDenyLine は同じ文（頭の語だけ／「頭：理由」）', () {
      expect(denyReasonText('同意できません', null), '同意できません');
      expect(denyReasonText('同意できません', ' '), '同意できません');
      expect(denyReasonText('同意できません', 3), '同意できません');
      expect(denyReasonText('同意できません', ' 理由 '), '同意できません：理由');
      for (final r in <Object?>[null, '', '  ', 1, '理由']) {
        expect(approvalDenyLine('承認できません', r), denyReasonText('承認できません', r));
      }
    });

    testWidgets('★承認の理由の行は DenyReasonLine で出て、前の間は 8 のまま', (tester) async {
      // ★本物のテーマ（AppTheme.dark）の下で組む（2026-10-04・便F14続）。
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark,
          home: const Scaffold(
              body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 40),
        ApprovalDenyLines(report: {
          'can_approve': false,
          'cannot_approve_reason': '理由A',
          'can_request_revision': true,
        }),
      ]))));
      expect(find.widgetWithText(DenyReasonLine, '承認できません：理由A'), findsOneWidget);
      final top = tester.getRect(find.byType(DenyReasonLine)).top;
      final start = tester.getRect(find.byType(ApprovalDenyLines)).top;
      expect(top - start, closeTo(8, 0.01));
    });
  });
}
