// ============================================================
// test/comp_off_flow_test.dart — 代休を取る受け皿（画面側）の検査
//
// ★何を縛るか:
//   ① 候補は【全部】出る（先頭を既定にしない・並べ替えない）
//   ② 日を選んで取れる（選んだ日がそのまま送られる）
//   ③ 「選ばない」でも取れて、BE が返す注意がそのまま出る（画面で書き写さない）
//   ④ 取れる代休が0のときは黙って閉じず理由を出す
//   ⑤ 断られたら BE の文言をそのまま出す（言い換え・丸めをしない）
//   ⑥ 入口が2つでも、通る部品と書く口は1本
//   ⑦ 既存の「本日休み」は従来どおり（代休を足しても壊れていない）
//
// ★実 HTTP は叩かない。lib 側の差し替え口（compOffServiceFactory）に
//   ReportsService を継承した手書き Fake を挿す。FIELD には provider が無く
//   画面が Service を直接 new するため、この1本だけが注入口になる
//   （test/share_send_confirm_test.dart 冒頭が書いている制約への答え）。
//
// ★期待する文言は実装から import せずここへ直書きする（実装を写すと何も検査しない）。
// ============================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/screens/rest_day_screen.dart';
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';
import 'package:js_awake_app/widgets/comp_off_dialog.dart';

// ── 画面の実文言（lib の実文字列をここへ写す）────────────────────
const String kDialogTitle   = '代休で休む';
const String kUndecidedRow  = '選ばない';
const String kClose         = '閉じる';
const String kNoneTitle     = '取れる代休がありません';
const String kFailTitle     = '代休を登録できませんでした';
const String kDoneTitle     = '代休を登録しました';

// ── BE が返す文（js-office-api の routes/rest_days.js の実文字列を写したもの）──
const String kNotice = '対象の出勤日は事務が決めます';
const String kExpiredMsg = '2026-02-07 の代休は 2026-03-31 で期限が切れています';

const String kRestDate = '2026-04-10';

/// 送った内容を記録する Fake。★BE の応答の形は実物に合わせて写す。
class _FakeSvc extends ReportsService {
  _FakeSvc({
    this.candidates = const [],
    this.availableFails = false,
    this.takeFails = false,
  }) : super.forTest();

  final List<CompOffCandidate> candidates;
  final bool availableFails;
  final bool takeFails;

  // 呼ばれた記録（何を渡したかを見る口）
  String? askedAsOf;
  String? sentRestDate;
  String? sentSourceWorkDate;
  bool?   sentUndecided;
  String? sentPortion;
  int     takeCalls = 0;

  @override
  Future<ApiResult<CompOffAvailable>> getCompOffAvailable({String? asOf}) async {
    askedAsOf = asOf;
    if (availableFails) {
      return apiFailure<CompOffAvailable>(
          statusCode: 0, errorMessage: 'サーバーに接続できません: 検査');
    }
    return apiSuccess<CompOffAvailable>(
      statusCode: 200,
      data: CompOffAvailable(
        asOf: asOf,
        remainingDays: candidates.fold(0.0, (s, c) => s + c.remainingDays),
        candidates: candidates,
        undecidedNotice: kNotice,
      ),
    );
  }

  @override
  Future<ApiResult<CompOffTaken>> takeCompOff({
    required String restDate,
    String? sourceWorkDate,
    bool undecided = false,
    String portion = 'full',
  }) async {
    takeCalls++;
    sentRestDate = restDate;
    sentSourceWorkDate = sourceWorkDate;
    sentUndecided = undecided;
    sentPortion = portion;
    if (takeFails) {
      return apiFailure<CompOffTaken>(
          statusCode: 409, errorMessage: kExpiredMsg, errorCode: 'COMP_OFF_EXPIRED');
    }
    return apiSuccess<CompOffTaken>(
      statusCode: 201,
      data: CompOffTaken(
        restDate: restDate,
        pairedWorkDate: sourceWorkDate,
        pairedUndecided: undecided,
        takenDays: portion == 'full' ? 1.0 : 0.5,
        notice: undecided ? kNotice : null,
      ),
    );
  }
}

CompOffCandidate _cand(String src, {double remain = 1.0, String? expires = '2026-12-31'}) =>
    CompOffCandidate(
        id: 'l_$src', sourceWorkDate: src, remainingDays: remain, expiresAt: expires);

/// 受け皿を1枚ポンプして開く（部品だけを見る土台）。
Future<void> _openFlow(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showCompOffFlow(ctx, restDate: kRestDate),
            child: const Text('開く'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('開く'));
  await tester.pumpAndSettle();
}

/// 行コメントを落としたソース（差し込みをコメントアウトしただけで通らないように）。
///   ★session_lockout_wiring_test.dart の _codeOnly と同じ手。
String _codeOnly(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSvc fake;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    // 差し替えを必ず戻す（他の検査へ漏らさない）。
    compOffServiceFactory = ReportsService.new;
  });

  void install(_FakeSvc f) {
    fake = f;
    compOffServiceFactory = () => fake;
  }

  group('候補の出し方', () {
    testWidgets('① 候補は全部出る・先頭を既定にしない', (tester) async {
      install(_FakeSvc(candidates: [
        _cand('2026-02-07'), _cand('2026-02-14'), _cand('2026-02-21', remain: 0.5),
      ]));
      await _openFlow(tester);

      expect(find.text(kDialogTitle), findsOneWidget, reason: '受け皿が開いていない');
      for (final d in ['2026-02-07', '2026-02-14', '2026-02-21']) {
        expect(find.textContaining('$d の出勤'), findsOneWidget,
            reason: '$d の候補が出ていない（絞り込んでいる）');
      }
      expect(fake.takeCalls, 0, reason: '選ばせる前に送ってしまっている');
    });

    testWidgets('① 残りと期限が候補ごとに読める', (tester) async {
      install(_FakeSvc(candidates: [_cand('2026-02-21', remain: 0.5)]));
      await _openFlow(tester);
      expect(find.textContaining('残り 0.5日'), findsWidgets);
      expect(find.textContaining('期限 2026-12-31'), findsOneWidget);
    });

    testWidgets('① 候補は休む日を基準に引く（今日ではない）', (tester) async {
      install(_FakeSvc(candidates: [_cand('2026-02-07')]));
      await _openFlow(tester);
      expect(fake.askedAsOf, kRestDate,
          reason: '休む日ではない日で候補を引いている（画面と実際がずれる）');
    });
  });

  group('取る', () {
    testWidgets('② 日を選ぶと、その日がそのまま送られる', (tester) async {
      install(_FakeSvc(candidates: [_cand('2026-02-07'), _cand('2026-02-14')]));
      await _openFlow(tester);
      await tester.tap(find.textContaining('2026-02-14 の出勤'));
      await tester.pumpAndSettle();

      expect(fake.sentRestDate, kRestDate);
      expect(fake.sentSourceWorkDate, '2026-02-14', reason: '選んだ日と違う日を送っている');
      expect(fake.sentUndecided, isFalse);
      expect(find.text(kDoneTitle), findsOneWidget);
    });

    testWidgets('② 区分を選ぶとその区分で送られる', (tester) async {
      install(_FakeSvc(candidates: [_cand('2026-02-07')]));
      await _openFlow(tester);
      await tester.tap(find.text('午前休'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('2026-02-07 の出勤'));
      await tester.pumpAndSettle();
      expect(fake.sentPortion, 'am_half');
    });

    testWidgets('③ 「選ばない」で取れて、BE の注意がそのまま出る', (tester) async {
      install(_FakeSvc(candidates: [_cand('2026-02-07')]));
      await _openFlow(tester);
      await tester.tap(find.text(kUndecidedRow));
      await tester.pumpAndSettle();

      expect(fake.sentUndecided, isTrue);
      expect(fake.sentSourceWorkDate, isNull, reason: '「選ばない」なのに日を送っている');
      expect(find.text(kNotice), findsOneWidget,
          reason: 'BE が返した注意が出ていない（画面で書き写している疑い）');
    });
  });

  group('理由を必ず出す', () {
    testWidgets('④ 取れる代休が0のときは黙って閉じない', (tester) async {
      install(_FakeSvc(candidates: const []));
      await _openFlow(tester);
      expect(find.text(kNoneTitle), findsOneWidget, reason: '理由が出ていない');
      expect(find.textContaining('期限'), findsOneWidget, reason: '手掛かりが無い');
      expect(find.text(kClose), findsOneWidget, reason: '閉じる道が無い');
      expect(find.text(kDialogTitle), findsNothing, reason: '選ばせる画面を空で出している');
    });

    testWidgets('④ 候補を取れなかったときも BE の言い分を出す', (tester) async {
      install(_FakeSvc(availableFails: true));
      await _openFlow(tester);
      expect(find.text('代休を確認できませんでした'), findsOneWidget);
      expect(find.textContaining('サーバーに接続できません'), findsOneWidget);
    });

    testWidgets('⑤ 断られたら BE の文言をそのまま出す', (tester) async {
      install(_FakeSvc(candidates: [_cand('2026-02-07')], takeFails: true));
      await _openFlow(tester);
      await tester.tap(find.textContaining('2026-02-07 の出勤'));
      await tester.pumpAndSettle();

      expect(find.text(kFailTitle), findsOneWidget);
      expect(find.text(kExpiredMsg), findsOneWidget,
          reason: 'BE の文言が言い換えられている');
      expect(find.textContaining('COMP_OFF_EXPIRED'), findsNothing,
          reason: '英字の code が画面に出ている');
    });

    testWidgets('閉じるだけなら1件も送らない', (tester) async {
      install(_FakeSvc(candidates: [_cand('2026-02-07')]));
      await _openFlow(tester);
      await tester.tap(find.text(kClose));
      await tester.pumpAndSettle();
      expect(fake.takeCalls, 0);
    });
  });

  group('⑥ 入口は2つ・通る部品は1本', () {
    testWidgets('入口①「本日休み」の画面から同じ受け皿が開く', (tester) async {
      install(_FakeSvc(candidates: [_cand('2026-02-07')]));
      await tester.pumpWidget(const MaterialApp(home: RestDayScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('代休で休む'));
      await tester.pumpAndSettle();
      // 受け皿の中にしか無い行が出れば、同じ部品を通っている。
      expect(find.text(kUndecidedRow), findsOneWidget,
          reason: '「本日休み」の画面が共有の受け皿を通っていない');
      expect(find.textContaining('2026-02-07 の出勤'), findsOneWidget);
    });

    test('入口②「管理・履歴」のカレンダーも同じ受け皿を呼ぶ', () {
      // ★カレンダーは月ぶんの通信を伴うため widget では描けない。
      //   差し込みの有無は文字で見る（session_lockout_wiring_test.dart と同じ手）。
      final src = _codeOnly('lib/screens/home_screen.dart');
      expect(src.contains("import '../widgets/comp_off_dialog.dart';"), isTrue,
          reason: 'カレンダー側が受け皿を輸入していない');
      expect(src.contains('showCompOffFlow(context, restDate: ds)'), isTrue,
          reason: 'カレンダーが選んだ日をそのまま受け皿へ渡していない');
    });

    test('入口①も同じ関数を呼んでいる（別実装を持っていない）', () {
      final src = _codeOnly('lib/screens/rest_day_screen.dart');
      expect(src.contains("import '../widgets/comp_off_dialog.dart';"), isTrue);
      expect(src.contains('showCompOffFlow(context, restDate:'), isTrue);
      // 書く口を画面が直接叩いていないこと（同じ操作を2通りに書かない）。
      expect(src.contains('takeCompOff('), isFalse,
          reason: '画面が受け皿を通さず自分で送っている');
    });

    test('書く口を呼ぶのは受け皿ただ1つ', () {
      final callers = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('reports_service.dart')) continue; // 定義側
        if (_codeOnly(f.path).contains('takeCompOff(')) callers.add(f.path);
      }
      expect(callers.length, 1,
          reason: '書く口を呼ぶ場所が1つではない: ${callers.join(', ')}');
      expect(callers.single.replaceAll(r'\', '/'),
          contains('widgets/comp_off_dialog.dart'));
    });
  });

  group('⑦ 既存の「本日休み」を壊していない', () {
    testWidgets('区分・理由・登録ボタンは従来どおり出る', (tester) async {
      install(_FakeSvc());
      await tester.pumpWidget(const MaterialApp(home: RestDayScreen()));
      await tester.pumpAndSettle();

      for (final t in ['終日', '午前休', '午後休']) {
        expect(find.text(t), findsOneWidget, reason: '区分「$t」が消えている');
      }
      for (final t in ['有給', '欠勤', '会社休業', '私用']) {
        expect(find.text(t), findsOneWidget, reason: '理由「$t」が消えている');
      }
      expect(find.text('休みを登録する'), findsOneWidget, reason: '登録ボタンが消えている');
      expect(find.text('※理由は任意です。有給は事務の確認後に休暇の記録へ反映されます。'),
          findsOneWidget, reason: '従来の注記が消えている');
    });

    testWidgets('修正モードでは代休の入口を出さない（押しても必ず失敗するため）',
        (tester) async {
      install(_FakeSvc());
      await tester.pumpWidget(const MaterialApp(
          home: RestDayScreen(editMode: true, initialReason: 'paid_leave')));
      await tester.pumpAndSettle();

      expect(find.textContaining('代休で休む'), findsNothing);
      expect(find.text('変更を保存'), findsOneWidget, reason: '修正モードが壊れている');
      expect(find.text('休みを取り消す'), findsOneWidget, reason: '取消の道が消えている');
    });
  });
}
