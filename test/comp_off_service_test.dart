// ============================================================
// test/comp_off_service_test.dart — 代休の2本（サービス層）の検査
//
// 見ているのは「BE の言い分をそのまま運べているか」の5点:
//   ① 候補が複数あるとき、全部・BE の並びのまま渡る（画面で並べ替えない材料になる）
//   ② 「選ばない」の注意文は BE が配る文言がそのまま渡る（画面に書き写さない）
//   ③ 取れる代休が0のとき、空リストで黙らず理由を言い分けられる材料が渡る
//   ④ 断られたとき BE の文言と code がそのまま渡る（言い換え・丸めをしない）
//   ⑤ 送る body が掟どおり（選んだ日と「選ばない」を同時に送らない）
//
// ★通信はしない。BE が返す本文を http.Response として作り、実装と同じ
//   runApiCall に通す＝解析の経路を素通りさせない。
//   応答の形は js-office-api の routes/rest_days.js の代休の2本に合わせて写す。
// ★期待する文言・code は実装から import せずここへ直書きする
//   （実装を写すと何も検査しないため。closing_period_gate_test.dart と同じ流儀）。
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/config/constants.dart';
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/services/reports_service.dart';

// ── BE の応答の写し ────────────────────────────────────────────

/// 候補3件（出勤日の古い順）。BE の compOffCandidateView の形。
const String _availableBody = '{'
    '"person_id":"p_1","as_of":"2026-04-10","remaining_days":3,'
    '"candidates":['
    '{"id":"l_a","source_work_date":"2026-02-07","granted_days":1,"taken_days":0,'
    '"remaining_days":1,"expires_at":"2026-12-31"},'
    '{"id":"l_b","source_work_date":"2026-02-14","granted_days":1,"taken_days":0,'
    '"remaining_days":1,"expires_at":"2026-12-31"},'
    '{"id":"l_c","source_work_date":"2026-02-21","granted_days":1,"taken_days":"0.5",'
    '"remaining_days":"0.5","expires_at":null}'
    '],'
    '"undecided_notice":"対象の出勤日は事務が決めます"}';

/// 候補0件（取れる代休が無い）。
const String _emptyBody = '{'
    '"person_id":"p_1","as_of":"2026-04-10","remaining_days":0,'
    '"candidates":[],"undecided_notice":"対象の出勤日は事務が決めます"}';

/// 「選ばない」で取れたときの 201。
const String _takenUndecidedBody = '{'
    '"rest_day":{"id":"rd_1","rest_date":"2026-04-10","reason":"comp_off",'
    '"portion":"full","paired_work_date":null,"paired_undecided":true},'
    '"taken_days":1,'
    '"allocations":[{"ledger_id":"l_a","days":1}],'
    '"notice":"対象の出勤日は事務が決めます"}';

/// 日を選んで取れたときの 201（notice はキーごと無い）。
const String _takenPairedBody = '{'
    '"rest_day":{"id":"rd_2","rest_date":"2026-04-10","reason":"comp_off",'
    '"portion":"am_half","paired_work_date":"2026-02-14","paired_undecided":false},'
    '"taken_days":"0.5",'
    '"allocations":[{"ledger_id":"l_b","days":0.5}]}';

/// 断られたとき（BE の文言と code）。
const String _expiredBody = '{'
    '"error":"2026-02-07 の代休は 2026-03-31 で期限が切れています",'
    '"code":"COMP_OFF_EXPIRED","expires_at":"2026-03-31"}';
const String _insufficientBody = '{'
    '"error":"残っている代休が足りません（必要 1.0日 / 2026-04-10 時点の残り 0.5日）",'
    '"code":"INSUFFICIENT_COMP_OFF","required_days":1,"remaining_days":0.5}';
const String _noneBody = '{'
    '"error":"2026-04-10 時点で取れる代休がありません（期限切れの代休は取れません）",'
    '"code":"NO_COMP_OFF","required_days":1,"remaining_days":0}';
const String _alreadyBody = '{'
    '"error":"2026-04-10 には既に休みが登録されています","code":"ALREADY_RESTED"}';

/// 実装と同じ runApiCall に通すための土台。
///   ★ReportsService はトークンを端末から読むため、サービスのメソッドを直接
///     呼ぶと通信に出てしまう。ここでは解析（parse）と非200の運び方を見るので、
///     runApiCall へ同じ形の応答を渡して確かめる。
Future<ApiResult<T>> _run<T>(
  int status,
  String body,
  T? Function(String) parse, {
  String method = 'GET',
  String path = '/rest-days/comp-off/available',
}) {
  return runApiCall<T>(
    'test',
    () async {
      final req = http.Request(method, Uri.parse('$kApiBaseUrl$path'));
      req.headers['Authorization'] = 'Bearer token-a';
      return http.Response(body, status,
          request: req,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    },
    parse,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('今取れる代休を見る口', () {
    test('① 候補は全部・BE の並びのまま渡る（画面で並べ替える材料にしない）', () async {
      final r = await _run<CompOffAvailable>(
          200, _availableBody, ReportsService.parseCompOffAvailable);
      expect(r.ok, isTrue);
      final d = r.data!;
      expect(d.candidates.length, 3, reason: '候補が欠けている');
      expect(d.candidates.map((c) => c.sourceWorkDate).toList(),
          ['2026-02-07', '2026-02-14', '2026-02-21'],
          reason: 'BE が返した並びが変わっている');
      expect(d.remainingDays, 3);
    });

    test('① numeric が文字列で来ても数として読める（pg の numeric 対策）', () async {
      final r = await _run<CompOffAvailable>(
          200, _availableBody, ReportsService.parseCompOffAvailable);
      expect(r.data!.candidates[2].remainingDays, 0.5,
          reason: '"0.5" を読めていない');
      expect(r.data!.candidates[2].expiresAt, isNull,
          reason: '期限なしを空文字などに化かしている');
    });

    test('② 「選ばない」の注意文は BE の文言がそのまま渡る', () async {
      final r = await _run<CompOffAvailable>(
          200, _availableBody, ReportsService.parseCompOffAvailable);
      expect(r.data!.undecidedNotice, '対象の出勤日は事務が決めます');
    });

    test('③ 取れる代休が0でも ok のまま返る（0件と失敗を混ぜない）', () async {
      final r = await _run<CompOffAvailable>(
          200, _emptyBody, ReportsService.parseCompOffAvailable);
      expect(r.ok, isTrue, reason: '0件を失敗に化かしている');
      expect(r.data!.candidates, isEmpty);
      expect(r.data!.remainingDays, 0);
      expect(r.errorCode, isNull);
    });
  });

  group('代休で休みを作る口', () {
    test('「選ばない」で取れたとき、印と注意がそのまま渡る', () async {
      final r = await _run<CompOffTaken>(
          201, _takenUndecidedBody, ReportsService.parseCompOffTaken,
          method: 'POST', path: '/rest-days/comp-off');
      expect(r.ok, isTrue);
      expect(r.data!.pairedUndecided, isTrue);
      expect(r.data!.pairedWorkDate, isNull);
      expect(r.data!.takenDays, 1);
      expect(r.data!.notice, '対象の出勤日は事務が決めます');
    });

    test('日を選んで取れたとき、注意は出ない（キーが無い＝null のまま）', () async {
      final r = await _run<CompOffTaken>(
          201, _takenPairedBody, ReportsService.parseCompOffTaken,
          method: 'POST', path: '/rest-days/comp-off');
      expect(r.ok, isTrue);
      expect(r.data!.pairedWorkDate, '2026-02-14');
      expect(r.data!.pairedUndecided, isFalse);
      expect(r.data!.takenDays, 0.5, reason: '"0.5" を読めていない');
      expect(r.data!.notice, isNull, reason: '選んだのに注意が出ている');
    });

    test('④ 断られたら BE の文言と code がそのまま渡る（丸めない）', () async {
      for (final c in [
        (_expiredBody, 'COMP_OFF_EXPIRED',
            '2026-02-07 の代休は 2026-03-31 で期限が切れています'),
        (_insufficientBody, 'INSUFFICIENT_COMP_OFF',
            '残っている代休が足りません（必要 1.0日 / 2026-04-10 時点の残り 0.5日）'),
        (_noneBody, 'NO_COMP_OFF',
            '2026-04-10 時点で取れる代休がありません（期限切れの代休は取れません）'),
        (_alreadyBody, 'ALREADY_RESTED', '2026-04-10 には既に休みが登録されています'),
      ]) {
        final r = await _run<CompOffTaken>(
            409, c.$1, ReportsService.parseCompOffTaken,
            method: 'POST', path: '/rest-days/comp-off');
        expect(r.ok, isFalse);
        expect(r.statusCode, 409);
        expect(r.errorCode, c.$2, reason: 'code が運べていない');
        expect(r.errorMessage, c.$3, reason: 'BE の文言が言い換えられている');
        expect(r.data, isNull, reason: '失敗なのに data が入っている');
      }
    });

    test('④ 断られたとき応答本文の材料も捨てない（必要と残りの数）', () async {
      final r = await _run<CompOffTaken>(
          409, _insufficientBody, ReportsService.parseCompOffTaken,
          method: 'POST', path: '/rest-days/comp-off');
      expect(r.errorDetails?['required_days'], 1);
      expect(r.errorDetails?['remaining_days'], 0.5);
    });
  });

  group('⑤ 送る body の形', () {
    test('日を選んだときは paired_undecided を送らない', () {
      final b = ReportsService.compOffBody(
          restDate: '2026-04-10', sourceWorkDate: '2026-02-14');
      expect(b.containsKey('source_work_date'), isTrue);
      expect(b.containsKey('paired_undecided'), isFalse,
          reason: '両方送ると BE が 400 で断る（掟の二重指定）');
    });

    test('「選ばない」のときは source_work_date を送らない', () {
      final b = ReportsService.compOffBody(
          restDate: '2026-04-10', undecided: true);
      expect(b['paired_undecided'], isTrue);
      expect(b.containsKey('source_work_date'), isFalse,
          reason: 'null を送ると「どちらも指定なし」の判定に紛れる');
    });

    test('区分は既定が終日、指定すればそれを送る', () {
      expect(ReportsService.compOffBody(restDate: '2026-04-10', undecided: true)['portion'],
          'full');
      expect(
          ReportsService.compOffBody(
              restDate: '2026-04-10', undecided: true, portion: 'am_half')['portion'],
          'am_half');
    });
  });
}
