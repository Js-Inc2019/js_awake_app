// ============================================================
// lib/services/api_result.dart - Service層の標準戻り値型
//
// ★存在理由:
//   Service ごとに戻り値が bool / Map<String,dynamic> / null / 例外 と
//   バラバラだったため、呼び手は「false は失敗か？ null は未取得か？
//   それとも 0 件か？」を毎回推測するしかなかった。推測は嘘の表示を生む
//   （「取得できていない」が「0件」「該当なし」に化ける）。
//   ApiResult は 成否・HTTPステータス・データ・エラー文言 の4つを常に揃えて返し、
//   呼び手が推測しなくて済むようにする。
//
//   typedef ApiResult<T> = ({bool ok, int statusCode, T? data, String? errorMessage});
//
//   ・ok           成功したか。true のときだけ data を信じてよい。
//   ・statusCode   実際の HTTP ステータス。通信そのものが成立しなかった場合のみ 0。
//   ・data         成功時の本体。失敗時は必ず null。
//   ・errorMessage 失敗時の説明。成功時は必ず null。
// ============================================================
//
// ── 規約（Service 実装側が必ず守ること）──────────────────────
//
// 1. 通信例外・timeout
//      ok: false / statusCode: 0 / data: null /
//      errorMessage: 'サーバーに接続できません: $e'
//    ★statusCode:0 は「サーバまで届かなかった」ことの印。
//      非200（サーバは応答した）と混同させないために予約している。
//
// 2. 非200
//      ok: false / statusCode: 実値 / data: null /
//      errorMessage: BE の error フィールドを優先。取れなければ本文の先頭200文字。
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
// ── 呼び手側の読み方 ────────────────────────────────────────
//   final r = await auth.verifyPin(...);
//   if (r.ok) { use(r.data!); }
//   else if (r.statusCode == 0) { /* 圏外・サーバ停止 */ }
//   else { showError(r.errorMessage); }
// ============================================================

/// Service層の標準戻り値。詳細な規約は本ファイル冒頭のコメントを参照。
typedef ApiResult<T> = ({
  bool ok,
  int statusCode,
  T? data,
  String? errorMessage,
});
