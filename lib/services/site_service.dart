// ============================================================
// lib/services/site_service.dart - 現場管理サービス
//
// ★段4: 戻り値を ApiResult<T> へ統一（規約は api_result.dart 冒頭）。
//   統一前はこのファイルの中だけで4流儀が並存していた:
//     ・{'success': bool, 'message': ...}      （getSites / createSite / updateSite / deleteSite）
//     ・String?（失敗は null）                  （createSiteReturningId）
//     ・{'ok': bool, 'sites'/'message'}         （matchSites）
//     ・{'status': 'ok'|'not_found'|'error'|'offline'} （geocode）
//   後ろ2つは「非200と通信断を潰さない」ために独自に作られたもので、
//   ApiResult が同じ区別を statusCode で表せる（404→statusCode:404 /
//   通信断→statusCode:0）ため役目を終えた。
//   URL・body・timeout は1文字も変えていない。
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_result.dart';
import 'auth_service.dart';
import '../config/constants.dart';

/// 住所→座標の結果。BE は {success, lat, lng} を返す。
class GeocodeResult {
  const GeocodeResult({required this.lat, required this.lng});
  final double? lat;
  final double? lng;
}

class SiteService {
  static final SiteService _instance = SiteService._internal();

  factory SiteService() {
    return _instance;
  }

  SiteService._internal();

  final AuthService _auth = AuthService();

  // ============================================================
  // 現場一覧取得（自社の現場のみ）
  // ============================================================

  Future<ApiResult<List<dynamic>>> getSites() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<dynamic>>(
      'SiteService.getSites',
      () => http.get(
        Uri.parse('$kApiBaseUrl/sites'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => (apiJsonMap(body)?['sites'] as List<dynamic>?) ?? const [],
    );
  }

  // ============================================================
  // 現場新規登録（職長・事務・管理者が可能）
  //   ★成功は 201。ApiResult は 200系を成功とするため自然に吸収される。
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> createSite({
    required String siteName,
    String? siteCode,
    String? address,
    String? startDate,
    String? endDate,
  }) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'SiteService.createSite',
      () => http.post(
        Uri.parse('$kApiBaseUrl/sites'),
        headers: headers,
        body: jsonEncode({
          'site_name':  siteName,
          'site_code':  siteCode,
          'address':    address,
          'start_date': startDate,
          'end_date':   endDate,
        }),
      ).timeout(const Duration(seconds: 15)),
      (body) => apiJsonMap(body)?['site'] as Map<String, dynamic>?,
    );
  }

  // ============================================================
  // 新規登録して site_id を返す（承認ゲートの仮登録導線用）。
  //   ・status は BE がサーバ側で決定（boss→pending）。body に status は送らない。
  //   ・★統一前は失敗も成功も String? で返し、null が「失敗」なのか
  //     「201 だが site_id が無い」のか区別できなかった。ApiResult で分かれる。
  // ============================================================
  Future<ApiResult<String>> createSiteReturningId({
    required String siteName,
    String? address,
    double? lat,
    double? lng,
  }) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<String>(
      'SiteService.createSiteReturningId',
      () => http.post(
        Uri.parse('$kApiBaseUrl/sites'),
        headers: headers,
        body: jsonEncode({
          'site_name': siteName,
          'address':   address,
          'lat':       lat,
          'lng':       lng,
        }),
      ).timeout(const Duration(seconds: 15)),
      (body) {
        final site = apiJsonMap(body)?['site'] as Map<String, dynamic>?;
        return site?['site_id'] as String?;
      },
    );
  }

  // ============================================================
  // GPS照合（半径500m以内・近い順最大5件の登録現場）。GET /sites/match?lat=&lon=。
  //   ・★ BE の query param は 'lon'（routes/sites.js:111 の { lat, lon }）。
  //   ・0件（sites: []）は ok:true・data 空リスト。「取れなかった」は ok:false。
  // ============================================================
  Future<ApiResult<List<Map<String, dynamic>>>> matchSites(double lat, double lng) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<Map<String, dynamic>>>(
      'SiteService.matchSites',
      () => http.get(
        Uri.parse('$kApiBaseUrl/sites/match?lat=$lat&lon=$lng'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => ((apiJsonMap(body)?['sites'] as List?) ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList(),
    );
  }

  // ============================================================
  // 住所→座標（GET /sites/geocode?address=）。
  // BE: 200→{success,lat,lng} / 404 GEOCODE_NOT_FOUND / 502 GEOCODE_FAILED /
  //     400 ADDRESS_REQUIRED（routes/sites.js:171-208）。
  //   ★統一前の 'not_found' / 'error' / 'offline' は ApiResult で表せる:
  //       住所不明    → ok:false・statusCode:404
  //       その他非200 → ok:false・statusCode:実値
  //       通信断      → ok:false・statusCode:0
  // ============================================================
  Future<ApiResult<GeocodeResult>> geocode(String address) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<GeocodeResult>(
      'SiteService.geocode',
      () => http.get(
        Uri.parse('$kApiBaseUrl/sites/geocode?address=${Uri.encodeQueryComponent(address)}'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) {
        final data = apiJsonMap(body);
        return GeocodeResult(
          lat: (data?['lat'] as num?)?.toDouble(),
          lng: (data?['lng'] as num?)?.toDouble(),
        );
      },
    );
  }

  // ============================================================
  // 現場情報更新
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> updateSite({
    required String siteId,
    String? siteName,
    String? siteCode,
    String? address,
    String? startDate,
    String? endDate,
    bool? isActive,
  }) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'SiteService.updateSite',
      () => http.put(
        Uri.parse('$kApiBaseUrl/sites/$siteId'),
        headers: headers,
        body: jsonEncode({
          'site_name':  siteName,
          'site_code':  siteCode,
          'address':    address,
          'start_date': startDate,
          'end_date':   endDate,
          'is_active':  isActive,
        }),
      ).timeout(const Duration(seconds: 15)),
      (body) => apiJsonMap(body)?['site'] as Map<String, dynamic>?,
    );
  }

  // ============================================================
  // 現場を無効化（削除）
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> deleteSite(String siteId) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'SiteService.deleteSite',
      () => http.delete(
        Uri.parse('$kApiBaseUrl/sites/$siteId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }
}
