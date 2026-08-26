// ============================================================
// lib/utils/session_lockout.dart - 締め出し（サーバが「もう入れない」と言った時）の唯一の窓口
//
// ★存在理由（実際に起きていた事故）:
//   BE は退職・無効化・役割変更を 401 + code（RETIRED / ACCOUNT_DISABLED /
//   ROLE_CHANGED …）で正しく返しているのに、FE は code を見ずにトークンだけ捨てて
//   ログイン画面へ戻していた。結果、本人には理由が1文字も出ない。
//   「どの code なら戻すか」「どの通信は戻してはいけないか」「どんな文言を出すか」を
//   画面ごとに書くと必ずどれかがズレるため、判定・文言・保存・遷移をこの1本に閉じる。
//
// ★理由は【端末に保存】してから戻す（画面の引数では渡さない）。
//   引数で渡すと、締め出し直後にアプリが落ちた／閉じられた場合に理由が消える。
//   prefs に置けば、次に起動してログイン画面が開いた時に必ず読める。
//   読んだら消す（＝一度読ませたら残さない）。
//
// ★保存に失敗しても締め出しは必ず実行する。
//   保存失敗で締め出しが止まると、入れてはいけない人が入れる新しい障害になる。
// ============================================================

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart' show NavigatorState;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

// ============================================================
// 戻る先の Navigator（注入）
// ============================================================

/// 締め出しで戻る先の Navigator を引く窓口。
///
/// ★ここで services/fcm_service.dart（アプリ唯一の navigatorKey の置き場）を
///   import すると utils → services → screens の逆流になり、api_result.dart を
///   読むだけで全画面を巻き込む。参照だけを main() から差す形にする。
///   差し忘れは test/session_lockout_wiring_test.dart が機械で検出する。
/// ★既定は null（＝遷移しない）。それでも理由の保存と資格情報の破棄は走る。
NavigatorState? Function() lockoutNavigatorLookup = () => null;

// ============================================================
// 名簿と文言（判定の正はここだけ）
// ============================================================

/// 保存された締め出し理由の prefs キー。
const String kLockoutReasonKey = 'session_lockout_reason';

/// 戻す対象のコードと、本人に見せる文言。
///
/// ★文言は業務標準の名詞で言い切る（会話体にしない）。
/// ★RETIRED の文言は BE の error 文字列と同一
///   （js-office-api middleware/auth.js・routes/auth.js の RETIRED 分岐）。
///   同じ出来事を2つの言い方で説明しないため。
const Map<String, String> kLockoutMessages = {
  'NO_TOKEN':
      '認証情報がありません。もう一度ログインしてください。',
  'TOKEN_EXPIRED':
      '認証の有効期限が切れました。もう一度ログインしてください。',
  'LEGACY_TOKEN':
      'アプリの認証方式が更新されました。もう一度ログインしてください。',
  'ACCOUNT_DISABLED':
      'アカウントが無効化されています。会社のご担当者にご確認ください。',
  'RETIRED':
      'この会社での登録が終了しました。詳しくは会社のご担当者にご確認ください。',
  'ROLE_CHANGED':
      '役割が変更されました。もう一度ログインしてください。',
  'PERMISSION_CHANGED':
      '権限が変更されました。もう一度ログインしてください。',
  'MEMBERSHIP_INVALID':
      '所属情報が無効です。もう一度ログインしてください。',
  'NO_USER':
      '利用者情報を確認できません。もう一度ログインしてください。',
};

/// 戻さないコード（明示）。
///
/// ★挙動は「未知のコード」と同じ（戻さない）。それでも名簿として書いておくのは、
///   この5つが「戻す側に足してはいけないもの」として検討済みだと残すため。
///   入力ミス（INVALID_PIN）・照合失敗（USER_NOT_FOUND / DEVICE_NOT_FOUND）・
///   端末側の事情（DEVICE_DISABLED / ANCHOR_MISMATCH）であり、
///   その場の画面でやり直せる＝画面ごと戻すと逆に手が止まる。
const Set<String> kNonLockoutCodes = {
  'INVALID_PIN',
  'USER_NOT_FOUND',
  'DEVICE_DISABLED',
  'DEVICE_NOT_FOUND',
  'ANCHOR_MISMATCH',
};

/// 送信（GET 以外）の最中に締め出された時に文言へ足す一文。
const String kLockoutDraftNote = '作成中の内容は保存されていません。';

// ============================================================
// 判定（純粋関数・写しを他所に作らない）
// ============================================================

/// 締め出しの対象URLか。
///
/// 判定は【URL】で行う（ラベルは記録用の名前であり、付け替えても通信は変わらない）。
/// 対象外:
///   ・自社BE以外の通信すべて（scheme/host/port が kApiBaseUrl と違う）
///   ・API の土台（/api/v1）の外（/health など）
///   ・/auth/ 配下（ログインそのもの。戻す先が今いる画面になる）
///   ・/workers/activate・/workers/self-register（まだ資格を持たない人の通信）
///   ・/notifications/fcm-token（背景で走るため画面が飛ぶと事故）
/// URL が取れない場合も対象外（自社BEだと確認できないため）。
bool isLockoutTargetUrl(Uri? url) {
  if (url == null) return false;
  final base = Uri.parse(kApiBaseUrl);
  if (url.scheme != base.scheme) return false;
  if (url.host   != base.host)   return false;
  if (url.port   != base.port)   return false;
  if (!url.path.startsWith(base.path)) return false;
  final path = url.path.substring(base.path.length);
  if (path.startsWith('/auth/'))            return false;
  if (path == '/workers/activate')          return false;
  if (path == '/workers/self-register')     return false;
  if (path == '/notifications/fcm-token')   return false;
  return true;
}

/// 締め出すか、そのとき本人に見せる文言は何か。
///
/// ★未知のコードは戻さない（名簿に無いものを勝手に締め出さない）。
///   その場合も BE の理由は ApiResult の errorMessage に載って呼び手へ返るため、
///   通信を出した画面がそのまま表示する（このファイルは何もしない）。
({bool lockOut, String? message}) judgeLockout({
  required Uri? url,
  required String method,
  required String? errorCode,
}) {
  if (!isLockoutTargetUrl(url)) return (lockOut: false, message: null);
  final message = kLockoutMessages[errorCode];
  if (message == null) return (lockOut: false, message: null);
  // GET 以外＝サーバへ書きに行った通信。作成中の内容が消えることを本人に伝える。
  final submitting = method.toUpperCase() != 'GET';
  return (
    lockOut: true,
    message: submitting ? '$message$kLockoutDraftNote' : message,
  );
}

// ============================================================
// 多重発火の鍵
// ============================================================

/// 締め出しを実行中か。await をまたぐ二重実行を止める。
bool _lockoutInFlight = false;

/// 締め出し済みのトークン（＝そのとき送っていた保存済みトークン）。
/// 同じトークンでの2度目は通さない。ログインし直せば別のトークンになるため、
/// 次の締め出しは改めて効く。
/// ★値はメモリ上の比較にだけ使う。ログにも画面にも出さない。
String? _lockedOutToken;

/// 多重発火の鍵を初期状態へ戻す（検査専用）。
///
/// ★鍵はアプリの生存期間ぶん持ち続ける作りなので、検査を1本ずつ独立させるには
///   ここで戻すしかない。本体からは呼ばない。
@visibleForTesting
void resetLockoutGuardForTest() {
  _lockoutInFlight = false;
  _lockedOutToken  = null;
}

/// リクエストが送った Authorization の中身。無ければ空文字。
String _sentToken(http.BaseRequest? request) {
  final raw = request?.headers['Authorization'] ?? '';
  return raw.startsWith('Bearer ') ? raw.substring(7) : raw;
}

// ============================================================
// 実行
// ============================================================

/// 非200 の応答を受けて、締め出すべきなら理由を保存してログイン画面へ戻す。
///
/// 戻り値は「締め出しとして扱ったか」。呼び手はこの値を使わなくてよい
/// （ApiResult の中身は締め出しの有無で変えない）。
///
/// ★このメソッドは例外を投げない。runApiCall の非200分岐から呼ばれるため、
///   ここで投げると「サーバは401と答えた」が「通信できなかった」に化ける。
Future<bool> applyLockoutForResponse({
  required http.BaseRequest? request,
  required String? errorCode,
}) async {
  try {
    final verdict = judgeLockout(
      url:       request?.url,
      method:    request?.method ?? 'GET',
      errorCode: errorCode,
    );
    if (!verdict.lockOut) return false;

    // ── 多重発火の鍵。await を1つも挟まずに同期で落とす ──────────
    if (_lockoutInFlight) return true;
    final token = _sentToken(request);
    if (_lockedOutToken == token) return true;
    _lockoutInFlight = true;
    _lockedOutToken  = token;
    // ────────────────────────────────────────────────

    try {
      await saveLockoutReason(verdict.message!);
      await _discardCredentials();
      _backToLogin();
    } finally {
      _lockoutInFlight = false;
    }
    return true;
  } catch (e) {
    // 判定・保存・遷移のどこで転んでも、呼び手の応答処理は壊さない。
    debugPrint('[session_lockout] 締め出し処理に失敗: $e');
    return false;
  }
}

/// 認証系（/auth/ 配下＝対象外URL）で締め出しコードを受け取った時に、理由だけ残す。
///
/// ★遷移はしない。この経路を通るのはログイン画面自身で、戻る先が今いる画面になる。
/// ★文言の正は kLockoutMessages ただ一つ（画面側に写しを作らない）。
/// 戻り値は「理由を残したか」。
Future<bool> recordLockoutReason(String? errorCode) async {
  final message = kLockoutMessages[errorCode];
  if (message == null) return false;
  await saveLockoutReason(message);
  return true;
}

/// 理由を端末へ保存する。失敗しても投げない（掟: 保存失敗で締め出しを止めない）。
Future<void> saveLockoutReason(String message) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLockoutReasonKey, message);
  } catch (e) {
    debugPrint('[session_lockout] 理由の保存に失敗（締め出しは続行）: $e');
  }
}

/// 保存された理由を読み、読んだら消す。無ければ null。
Future<String?> takeLockoutReason() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final reason = prefs.getString(kLockoutReasonKey);
    if (reason == null || reason.isEmpty) return null;
    await prefs.remove(kLockoutReasonKey);
    return reason;
  } catch (e) {
    debugPrint('[session_lockout] 理由の読み出しに失敗: $e');
    return null;
  }
}

/// 保存された理由を捨てる（手動ログアウトなど、前回の理由を持ち越さない場面用）。
Future<void> clearLockoutReason() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kLockoutReasonKey);
  } catch (e) {
    debugPrint('[session_lockout] 理由の消去に失敗: $e');
  }
}

/// 締め出し時の資格情報の始末。
///
/// ★消すのは auth_token だけ（ログイン画面の 401/403 分岐と同じ範囲）。
///   logged_out を立てるのは、戻った先で生体認証を新たに要求させないため
///   （＝理由の赤い帯を読める画面へ直行させる）。
Future<void> _discardCredentials() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.setBool('logged_out', true);
  } catch (e) {
    debugPrint('[session_lockout] 資格情報の破棄に失敗（遷移は続行）: $e');
  }
}

/// ログイン画面へ戻す。Navigator が無ければ何もしない（理由は保存済み）。
void _backToLogin() {
  try {
    final nav = lockoutNavigatorLookup();
    if (nav == null) {
      debugPrint('[session_lockout] Navigator 未設定のため遷移しない（理由は保存済み）');
      return;
    }
    nav.pushNamedAndRemoveUntil('/login', (_) => false);
  } catch (e) {
    debugPrint('[session_lockout] ログイン画面への遷移に失敗: $e');
  }
}
