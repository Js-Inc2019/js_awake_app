// ============================================================
// lib/services/api_result.dart - Service層の標準戻り値型
//
// ★存在理由:
//   Service ごとに戻り値が bool / Map<String,dynamic> / null / 例外 と
//   バラバラだったため、呼び手は「false は失敗か？ null は未取得か？
//   それとも 0 件か？」を毎回推測するしかなかった。推測は嘘の表示を生む
//   （「取得できていない」が「0件」「該当なし」に化ける）。
//   ApiResult は 成否・HTTPステータス・データ・エラー文言・エラーコード を
//   常に揃えて返し、呼び手が推測しなくて済むようにする。
//
//   typedef ApiResult<T> =
//     ({bool ok, int statusCode, T? data, String? errorMessage, String? errorCode});
//
//   ・ok           成功したか。true のときだけ data を信じてよい。
//   ・statusCode   実際の HTTP ステータス。通信そのものが成立しなかった場合のみ 0。
//   ・data         成功時の本体。失敗時は必ず null。
//   ・errorMessage 失敗時の説明。成功時は必ず null。
//   ・errorCode    失敗時の BE 側エラーコード（応答の code フィールド）。無ければ null。
//
// ★非200 は utils/session_lockout.dart を必ず通す（締め出しの受け皿）。
//   サーバが「退職済み」「無効化済み」と答えているのに黙ってログイン画面へ
//   戻していたのは、非200 の分岐が code を見ずに素通ししていたため。
//   通し忘れは test/session_lockout_wiring_test.dart が機械で検出する。
// ============================================================
//
// ── 規約（Service 実装側が必ず守ること）──────────────────────
//
// 1. 通信例外・timeout
//      ok: false / statusCode: 0 / data: null /
//      errorMessage: 'サーバーに接続できません: $e' / errorCode: null
//    ★statusCode:0 は「サーバまで届かなかった」ことの印。
//      非200（サーバは応答した）と混同させないために予約している。
//
// 2. 非200
//      ok: false / statusCode: 実値 / data: null /
//      errorMessage: BE の error フィールドを優先。取れなければ本文の先頭200文字。
//      errorCode:    BE の code フィールド。無ければ null。
//    ★勝手に「エラーが発生しました」等へ丸めない。サーバが理由を言っているなら
//      その理由を運ぶ（丸めると原因が現場で追えなくなる）。
//
// 3. jsonDecode は 200 系の中でだけ行う。
//    ★非200 の本文を同じ経路で decode すると、HTML のエラーページ等で例外が飛び、
//      「サーバは 403 と答えた」が「通信できなかった」に化ける。
//    ★200 系で decode に失敗した場合は ok:false / statusCode:実値 とする。
//      statusCode を 0 に倒さない（サーバは確かに応答している）。
//
// 4. 非200・例外は必ず debugPrint で可視化する。握り潰さない。
//    ★出してよいのは メソッド名・statusCode・応答本文の先頭200文字 まで。
//    ★headers / token / Authorization は絶対に出さない。
//      リクエスト body も出さない（PIN・招待コード等の秘匿値を含むため）。
//      200 系の応答本文も出さない（token を含む経路があるため）。
//
// 5. timeout は既定 15 秒。これと違う値を使うメソッドは引数または実装で明示する。
//    ★移設元の画面が持っていた秒数は挙動の一部。丸めない。
//
// 6. errorCode は「BE が言っているコードをそのまま運ぶ」だけ。FE で意味を作らない。
//    ★UI の文言分岐（ALREADY_RESTED → 「すでに休みで登録されています」など）は
//      呼び手が statusCode + errorCode の組で決める。Service は判断しない。
//    ★成功時は必ず null。
//
// ── 呼び手側の読み方 ────────────────────────────────────────
//   final r = await auth.verifyPin(...);
//   if (r.ok) { use(r.data!); }
//   else if (r.statusCode == 0) { /* 圏外・サーバ停止 */ }
//   else if (r.errorCode == 'ALREADY_RESTED') { /* BE が理由を言っている */ }
//   else { showError(r.errorMessage); }
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../utils/session_lockout.dart';

/// Service層の標準戻り値。詳細な規約は本ファイル冒頭のコメントを参照。
typedef ApiResult<T> = ({
  bool ok,
  int statusCode,
  T? data,
  String? errorMessage,
  String? errorCode,
});

/// 応答本文の先頭200文字（規約2・4のログとエラー文言用）。
String apiClipBody(String body) =>
    body.length <= 200 ? body : '${body.substring(0, 200)}…';

/// 失敗の ApiResult を組む（data は規約どおり必ず null）。
/// リクエストを出す前に失敗が確定している場合（トークン未保持など）にも使う。
ApiResult<T> apiFailure<T>({
  required int statusCode,
  String? errorMessage,
  String? errorCode,
}) =>
    (
      ok: false,
      statusCode: statusCode,
      data: null,
      errorMessage: errorMessage,
      errorCode: errorCode,
    );

/// 成功の ApiResult を組む。
ApiResult<T> apiSuccess<T>({required int statusCode, T? data}) => (
      ok: true,
      statusCode: statusCode,
      data: data,
      errorMessage: null,
      errorCode: null,
    );

/// 規約1-6 の唯一の実装。全 Service の HTTP メソッドはこれを通す。
///
/// ★同じ try/catch を Service ごとに書き写すと、必ずどれかが規約から外れる
///   （実際、統一前は「例外を空リストへ潰す」「非200で jsonDecode して二次例外」
///     「statusCode を積み忘れる」が Service ごとに混在していた）。
///   規約の実装はこの1関数だけに置く。
///
/// [label] debugPrint 用の識別子（'ReportsService.getReports' など）。
/// [send]  リクエストを実行する処理。timeout はこの中で指定する（規約5）。
/// [parse] 200系の本文を T へ変換する。本文が空なら null を返してよい。
Future<ApiResult<T>> runApiCall<T>(
  String label,
  Future<http.Response> Function() send,
  T? Function(String body) parse,
) async {
  try {
    final res = await send();
    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        return apiSuccess<T>(statusCode: res.statusCode, data: parse(res.body));
      } catch (e) {
        // 本文は出さない（token を含み得るため）。長さだけ残す。
        debugPrint(
            '[$label] 応答の解析に失敗 (status=${res.statusCode}, 本文長=${res.body.length}): $e');
        return apiFailure<T>(
          statusCode: res.statusCode,
          errorMessage: '応答の解析に失敗しました',
        );
      }
    }
    debugPrint('[$label] 非200 (status=${res.statusCode}): ${apiClipBody(res.body)}');
    final err = _decodeError(res.body);
    // 締め出し（退職・無効化・役割変更など、サーバが「もう入れない」と言った応答）。
    // ★どの code で戻すか・どのURLは戻さないか・何と表示するかの判定は
    //   utils/session_lockout.dart ただ一つが持つ。ここは通すだけで判断しない。
    // ★戻り値は使わない。締め出しの有無で ApiResult の中身は変えない
    //   （呼び手が受け取る errorMessage / errorCode はサーバの言い分のまま）。
    await applyLockoutForResponse(request: res.request, errorCode: err.code);
    return apiFailure<T>(
      statusCode: res.statusCode,
      errorMessage: err.message ?? apiClipBody(res.body),
      errorCode: err.code,
    );
  } catch (e) {
    debugPrint('[$label] 通信失敗: $e');
    return apiFailure<T>(
      statusCode: 0,
      errorMessage: 'サーバーに接続できません: $e',
    );
  }
}

/// 非200 本文から BE の error / code を取り出す。JSON でなければ両方 null。
({String? message, String? code}) _decodeError(String body) {
  if (body.isEmpty) return (message: '(応答本文なし)', code: null);
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final err  = decoded['error'];
      final code = decoded['code'];
      return (
        message: (err is String && err.isNotEmpty) ? err : null,
        code:    (code is String && code.isNotEmpty) ? code : null,
      );
    }
  } catch (_) {
    // JSON でない（HTML のエラーページ等）→ 呼び出し元が本文先頭を使う
  }
  return (message: null, code: null);
}

/// JSON オブジェクトを返すエンドポイント用の parse。
/// 本文が空なら null（204 等でも例外にしない）。
Map<String, dynamic>? apiJsonMap(String body) {
  if (body.isEmpty) return null;
  return jsonDecode(body) as Map<String, dynamic>;
}
