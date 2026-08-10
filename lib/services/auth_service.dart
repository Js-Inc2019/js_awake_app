// ============================================================
// lib/services/auth_service.dart - 認証サービス
//
// 役割は2つだけ:
//   ① prefs に入っている認証情報の読み出し（getToken / getUserId / ...）
//   ② 認証系エンドポイントへの HTTP 呼び出し（戻り値は ApiResult 統一）
//
// ★このクラスは「通信の運び屋」であり、保存も遷移も判断もしない。
//   prefs への保存・画面遷移・fail-open の可否は呼び手（画面）の責任のまま残す。
//   ここで保存まで抱えると、画面ごとに異なる保存内容（worker_id を返す経路と
//   返さない経路など）を吸収しきれず、静かに値が欠ける。
//
// ★各メソッドの URL・body・timeout・成否判定の正は「移設元の画面コード」。
//   このファイルは移設元と同じリクエストを組むだけで、秒数もキー名も丸めない。
//   移設元は各メソッドのコメントに file:line で残してある（段5の呼び替え時の突合用）。
//
// ★段4/段5 の予定:
//   ・段4: 他 Service を同じ ApiResult へ揃える
//   ・段5: 画面の直 http 呼び出しを本クラスの呼び出しへ置き換える
//   現時点では画面は未変更＝本クラスの新メソッドはまだ呼び手ゼロ。
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../utils/device_id.dart';
import 'api_result.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  // ============================================================
  // ヘッダー
  // ============================================================

  /// 未認証API用の共通ヘッダー。
  /// ★移設元の画面はいずれも {'Content-Type': 'application/json'} だけを送っていた
  ///   （verify-device / verify-pin / select-membership / logout / recover-by-code）。
  ///   同じものを1か所に置いて、画面ごとの書き写しを無くす。
  static const Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json',
  };

  /// 認証済みAPI用ヘッダー（prefs の auth_token を載せる）。
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }

  /// 呼び出しごとに token が異なる経路（verify-token / consent）用。
  /// ★これらは「prefs の token」ではなく「その場で受け取った token」を使う
  ///   （consent は login_screen.dart・recovery_screen.dart の data['token']、
  ///     verify-token は getToken() で読み出した現在のトークン）。
  ///   getAuthHeaders() で代用すると別のトークンを送ることになる。
  /// ★旧・初回PIN設定APIもこの経路だったが、BE ごと退役したため利用者から外れた。
  static Map<String, String> _bearerHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  // ============================================================
  // prefs 読み出し
  // ============================================================

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  Future<String?> getCompanyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('company_id');
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    // 二重キー統一: 顔（role）は 'user_role' に一本化
    return prefs.getString('user_role');
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name');
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<bool> isWorker() async {
    final role = await getRole();
    return role == 'worker';
  }

  Future<bool> isBoss() async {
    final role = await getRole();
    return role == 'boss';
  }

  Future<bool> isOfficeAdmin() async {
    final role = await getRole();
    return role == 'admin_office' || role == 'admin_exec';
  }

  // ============================================================
  // 共通の送信・応答処理
  //   ★段4で api_result.dart の runApiCall() へ集約した。以前は本クラスに
  //     同じ規約の実装（_run / _clip / _errorMessageFrom / _asJsonMap）を
  //     持っていたが、他8本の Service も同じものを必要とし、写した先から
  //     必ず規約が痩せる（statusCode の積み忘れ・非200での二次例外など、
  //     統一前の各 Service が実際にそうなっていた）。実装は1か所だけに置く。
  //   ★同時に errorCode（BE の code）を運ぶようになった。auth 系は
  //     NO_TOKEN / TOKEN_EXPIRED / COOPERATION_PENDING など code を多用するため、
  //     呼び手（段5）はこれで分岐できる。
  // ============================================================

  Future<ApiResult<T>> _run<T>(
    String label,
    Future<http.Response> Function() send,
    T? Function(String body) parse,
  ) =>
      runApiCall<T>('AuthService.$label', send, parse);

  // ============================================================
  // 認証系エンドポイント
  // ============================================================

  /// サーバのウォームアップ（Heroku のコールドスタート対策）。
  /// 移設元: login_screen.dart:168（GET kHealthUrl・15秒）
  ///
  /// ★移設元 _warmUpServer（login_screen.dart:165-175）は本リクエストを
  ///   「最大3回・失敗時は2秒待って再試行」というループで包んでいる。
  ///   ループは呼び手側の再試行方針なので本メソッドには入れない
  ///   （ApiResult は1リクエスト＝1結果の型）。段5で画面から呼び替える際は
  ///   このループを画面側に残すこと。ここだけ差し替えると再試行が消える。
  /// ★data は応答本文そのまま（/health は JSON とは限らないため decode しない）。
  ///   移設元も本文は見ておらず、200 かどうかだけを見ている。
  Future<ApiResult<String>> warmUp() {
    return _run<String>(
      'warmUp',
      () => http.get(Uri.parse(kHealthUrl))
          .timeout(const Duration(seconds: 15)),
      (body) => body,
    );
  }

  /// 保存済みトークンの検証。
  /// 移設元: login_screen.dart:221-228（POST /auth/verify-token・10秒）
  ///
  /// ★単一の顔の掟: body の device_id は必須（未送信は 400 DEVICE_ID_REQUIRED）。
  /// ★token は prefs の auth_token、device_id は utils/device_id.dart の getDeviceId()。
  ///   移設元の _getDeviceId()（login_screen.dart:141-143）は
  ///   `return getDeviceId();` そのものなので同一。
  /// ★data はサーバ応答全体。user / status / consent_agreed_at / consent_version を
  ///   含むため、呼び手はそこから必要な値を取る（移設元 :234-261 と同じ形）。
  /// ★「token が空なら呼ばない」ガードは呼び手側に残る（移設元 login_screen.dart:217）。
  ///   ここでは判断せず、持っているトークンでそのまま問い合わせる。
  Future<ApiResult<Map<String, dynamic>>> verifyToken() async {
    final token    = await getToken() ?? '';
    final deviceId = await getDeviceId();
    return _run<Map<String, dynamic>>(
      'verifyToken',
      () => http.post(
        Uri.parse('$kApiBaseUrl/auth/verify-token'),
        headers: _bearerHeaders(token),
        body: jsonEncode({'device_id': deviceId}),
      ).timeout(const Duration(seconds: 10)),
      apiJsonMap,
    );
  }

  /// 端末アンカーによるサイレント復帰の照会。
  /// 移設元: login_screen.dart:339-342（既定8秒）/ login_screen.dart:453-456（10秒）
  ///
  /// ★同じリクエストを2か所が別の秒数で叩いていた。既定を8秒とし、
  ///   10秒側は呼び出し時に timeout を明示する（丸めて片方の挙動を消さない）。
  /// ★device_id はクエリ文字列。移設元は素の文字列連結だが、Uri の
  ///   queryParameters を使ってもエンコード結果は同じ（device_id は
  ///   ANDROID_ID / UUID / '<id>-field' ＝ 予約文字を含まない）。
  Future<ApiResult<Map<String, dynamic>>> verifyDevice(
    String deviceId, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return _run<Map<String, dynamic>>(
      'verifyDevice',
      () => http.get(
        Uri.parse('$kApiBaseUrl/auth/verify-device?device_id=$deviceId'),
        headers: jsonHeaders,
      ).timeout(timeout),
      apiJsonMap,
    );
  }

  /// PIN ログイン。
  /// 移設元: login_screen.dart:552-561（POST /auth/verify-pin・10秒）
  ///
  /// ★deviceName は移設元で `Platform.isAndroid ? 'Android' : 'iPhone'` を
  ///   画面が組み立てている。ここで再実装すると判定が二重になるため引数で受ける。
  /// ★data は応答全体（requires_selection / role / token / worker_id 等を含む）。
  Future<ApiResult<Map<String, dynamic>>> verifyPin({
    required String pin,
    required String deviceId,
    required String deviceName,
    required String deviceType,
  }) {
    return _run<Map<String, dynamic>>(
      'verifyPin',
      () => http.post(
        Uri.parse('$kApiBaseUrl/auth/verify-pin'),
        headers: jsonHeaders,
        body: jsonEncode({
          'pin':         pin,
          'device_id':   deviceId,
          'device_name': deviceName,
          'device_type': deviceType,
        }),
      ).timeout(const Duration(seconds: 10)),
      apiJsonMap,
    );
  }

  /// 複数所属からの所属選択（pre_auth_token → 本ログイン）。
  /// 移設元: login_screen.dart:802-809 / membership_select_screen.dart:77-86
  ///         （どちらも POST /auth/select-membership・10秒・body 2キー・完全一致）
  ///
  /// ★2画面の実装を突合したうえで共通形にした。URL・headers・body・timeout・
  ///   成否判定（200のみ成功）まで差分は無い。
  /// ★401 = pre_auth 失効（TOKEN_EXPIRED）。時間切れダイアログを出すか、
  ///   画面内エラーに留めるかは画面ごとに違うので、ここでは判断せず
  ///   statusCode をそのまま返して呼び手に委ねる。
  Future<ApiResult<Map<String, dynamic>>> selectMembership({
    required String preAuthToken,
    required String membershipId,
  }) {
    return _run<Map<String, dynamic>>(
      'selectMembership',
      () => http.post(
        Uri.parse('$kApiBaseUrl/auth/select-membership'),
        headers: jsonHeaders,
        body: jsonEncode({
          'pre_auth_token': preAuthToken,
          'membership_id':  membershipId,
        }),
      ).timeout(const Duration(seconds: 10)),
      apiJsonMap,
    );
  }

  /// 同意証跡のサーバ刻印（既存ユーザー救済）。
  /// 移設元: login_screen.dart:950-957 / recovery_screen.dart:168-175
  ///         （どちらも POST /auth/consent・8秒・完全一致）
  ///
  /// ★consentToken は「その場で受け取った data['token']」。prefs 保存前に呼ばれる
  ///   経路があるため引数で受ける（移設元 login_screen.dart:946 / recovery_screen.dart:164）。
  /// ★consentVersion も引数。画面側の _kCurrentConsentVersion がバージョンの正であり、
  ///   ここに定数を作ると同じ値が2か所に増えて必ず片方が古くなる。
  /// ★移設元は失敗を握り潰す fail-open（`catch (_) {}`）だが、それは
  ///   「刻印に失敗しても次回ログインで再試行できる」という呼び手側の判断。
  ///   本メソッドは結果をそのまま返し、無視するかどうかは呼び手に委ねる。
  Future<ApiResult<Map<String, dynamic>>> consent({
    required String consentToken,
    required String consentVersion,
  }) {
    return _run<Map<String, dynamic>>(
      'consent',
      () => http.post(
        Uri.parse('$kApiBaseUrl/auth/consent'),
        headers: _bearerHeaders(consentToken),
        body: jsonEncode({'consent_version': consentVersion}),
      ).timeout(const Duration(seconds: 8)),
      apiJsonMap,
    );
  }

  /// 明示ログアウト（サーバ側の端末アンカー白紙化）。
  /// 移設元: profile_screen.dart:377-381（POST /auth/logout・5秒）
  ///
  /// ★BE は device_id 受領時に白紙化する。冪等・常時200。
  /// ★移設元は「通信失敗でもローカルログアウトは絶対にブロックしない」方針で
  ///   結果を一切見ていない（袋小路禁止）。その判断は呼び手に残すため、
  ///   ここでは結果をそのまま返すだけにする。
  /// ★device_id が空のときに呼ばないガードも呼び手側（移設元 :375）。
  Future<ApiResult<Map<String, dynamic>>> logout(String deviceId) {
    return _run<Map<String, dynamic>>(
      'logout',
      () => http.post(
        Uri.parse('$kApiBaseUrl/auth/logout'),
        headers: jsonHeaders,
        body: jsonEncode({'device_id': deviceId}),
      ).timeout(const Duration(seconds: 5)),
      apiJsonMap,
    );
  }

  /// 会社コード＋作業員ID＋PIN による端末復旧。
  /// 移設元: recovery_screen.dart:65-74（POST /auth/recover-by-code・30秒）
  ///
  /// ★30秒は移設元のまま。他の認証系より長いのは、この経路が
  ///   コールドスタート直後に叩かれることがあるため（丸めない）。
  Future<ApiResult<Map<String, dynamic>>> recoverByCode({
    required String companyCode,
    required String workerId,
    required String pin,
    required String deviceId,
  }) {
    return _run<Map<String, dynamic>>(
      'recoverByCode',
      () => http.post(
        Uri.parse('$kApiBaseUrl/auth/recover-by-code'),
        headers: jsonHeaders,
        body: jsonEncode({
          'company_code': companyCode,
          'worker_id':    workerId,
          'pin':          pin,
          'device_id':    deviceId,
        }),
      ).timeout(const Duration(seconds: 30)),
      apiJsonMap,
    );
  }
}
