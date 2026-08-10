// ============================================================
// lib/services/worker_service.dart - 作業員（workers）通信サービス
//
// ★段6で新設。画面が直に叩いていた /workers 系3本をここへ集める。
//   戻り値は ApiResult<T> 統一（規約は api_result.dart 冒頭）。
//
// ★各メソッドの URL・body・timeout・成否判定の正は「移設元の画面コード」。
//   このファイルは移設元と同じリクエストを組むだけで、秒数もキー名も丸めない。
//   移設元は各メソッドのコメントに file:line で残してある（突合用）。
//
// ★このクラスは通信の運び屋であり、保存も遷移も判断もしない。
//   prefs 保存・role 門番・画面遷移は呼び手（画面）の責任のまま残す。
//   （activate の「事務・管理系の招待コードは FIELD で有効化させない」判定は
//     UI の袋小路対策であって通信の判断ではない＝画面に残す）
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_result.dart';
import 'auth_service.dart';
import '../config/constants.dart';

class WorkerService {
  static final WorkerService _instance = WorkerService._internal();

  factory WorkerService() => _instance;

  WorkerService._internal();

  final AuthService _auth = AuthService();

  // ============================================================
  // 招待コードによる有効化（未認証）
  // ============================================================

  /// 移設元: register_screen.dart:75-84（POST /workers/activate・60秒）
  ///
  /// ★60秒は移設元のまま。他の未認証系（30秒/10秒）より長いのは、この経路が
  ///   コールドスタート直後に叩かれることがあるため（丸めない）。
  /// ★invite_code の trim/toUpperCase は移設元が画面側で行っている
  ///   （register_screen.dart:79）。入力の正規化は画面の責任なので
  ///   ここでは受け取った文字列をそのまま送る。
  /// ★deviceName は移設元で `Platform.isAndroid ? 'Android' : 'iPhone'` を
  ///   画面が組み立てている。ここで再実装すると判定が二重になるため引数で受ける。
  /// ★data は応答全体（token / user_id / name / role / company_id を含む）。
  ///   role 門番（admin_office / admin_exec を弾く）は呼び手に残る。
  Future<ApiResult<Map<String, dynamic>>> activate({
    required String inviteCode,
    required String pin,
    required String deviceId,
    required String deviceName,
  }) {
    return runApiCall<Map<String, dynamic>>(
      'WorkerService.activate',
      () => http.post(
        Uri.parse('$kApiBaseUrl/workers/activate'),
        headers: AuthService.jsonHeaders,
        body: jsonEncode({
          'invite_code': inviteCode,
          'pin':         pin,
          'device_id':   deviceId,
          'device_name': deviceName,
        }),
      ).timeout(const Duration(seconds: 60)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 自己登録（仮登録申請・未認証）
  // ============================================================

  /// 移設元: login_screen.dart:637-648（POST /workers/self-register・30秒）
  ///
  /// ★partnerCompanyName / companyCode は移設元が
  ///   「空文字なら null を送る」形にしている（login_screen.dart:643-644）。
  ///   空文字と null は BE にとって別の意味なので、その判定は画面側に残し、
  ///   ここは受け取った null / 非 null をそのまま載せる。
  /// ★成功は 200 と 201 の両方があり得る（移設元 :653）。ApiResult は
  ///   200系を成功とするため自然に吸収される。
  Future<ApiResult<Map<String, dynamic>>> selfRegister({
    required String name,
    required String ownCompanyName,
    required String? partnerCompanyName,
    required String? companyCode,
    required String deviceId,
    required String deviceName,
  }) {
    return runApiCall<Map<String, dynamic>>(
      'WorkerService.selfRegister',
      () => http.post(
        Uri.parse('$kApiBaseUrl/workers/self-register'),
        headers: AuthService.jsonHeaders,
        body: jsonEncode({
          'name':                 name,
          'own_company_name':     ownCompanyName,
          'partner_company_name': partnerCompanyName,
          'company_code':         companyCode,
          'device_id':            deviceId,
          'device_name':          deviceName,
        }),
      ).timeout(const Duration(seconds: 30)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 作業員一覧（会社スコープ・認証必須）
  // ============================================================

  /// 移設元: home_screen.dart:5714-5719（GET /workers?membership_type=employee・15秒）
  ///
  /// ★BE は {"companies":[{is_own, workers:[...]}, ...]} を返す。
  ///   「is_own の会社の workers だけを表示する」のは画面の絞り込み方針なので
  ///   ここでは companies をそのまま返し、選別は呼び手に残す
  ///   （移設元 home_screen.dart:5723-5731 の firstWhere がそれ）。
  /// ★取得できなかった（ok:false）と 0 件（ok:true・空リスト）は
  ///   ApiResult が区別する。空リストへ潰さない。
  Future<ApiResult<List<Map<String, dynamic>>>> getWorkers({
    required String membershipType,
  }) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<Map<String, dynamic>>>(
      'WorkerService.getWorkers',
      () => http.get(
        Uri.parse('$kApiBaseUrl/workers?membership_type=$membershipType'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => ((apiJsonMap(body)?['companies'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}
