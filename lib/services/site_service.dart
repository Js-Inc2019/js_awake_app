// ============================================================
// lib/services/site_service.dart - 現場管理サービス
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../config/constants.dart';

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

  Future<Map<String, dynamic>> getSites() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/sites'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {
          'success': true,
          'sites':   data['sites'] as List<dynamic>,
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 現場新規登録（職長・事務・管理者が可能）
  // ============================================================

  Future<Map<String, dynamic>> createSite({
    required String siteName,
    String? siteCode,
    String? address,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/sites'),
        headers: headers,
        body: jsonEncode({
          'site_name':  siteName,
          'site_code':  siteCode,
          'address':    address,
          'start_date': startDate,
          'end_date':   endDate,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': '現場を登録しました',
          'site':    data['site'],
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 新規登録して site_id を返す（承認ゲートの仮登録導線用）。
  //   ・既存 createSite(Map返し) は後方互換のため不変（呼び出し元: site_select_screen.dart:131）。
  //   ・status は BE がサーバ側で決定（boss→pending）。body に status は送らない。
  //   ・成功=201 の site_id を返す。失敗/非201/通信断は null（呼び出し側でエラー表示）。
  // ============================================================
  Future<String?> createSiteReturningId({
    required String siteName,
    String? address,
    double? lat,
    double? lng,
  }) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/sites'),
        headers: headers,
        body: jsonEncode({
          'site_name': siteName,
          'address':   address,
          'lat':       lat,
          'lng':       lng,
        }),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final site = data['site'] as Map<String, dynamic>?;
        return site?['site_id'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // GPS照合（半径50m以内の登録現場・距離昇順）。GET /sites/match?lat=&lon=。
  //   ・非200 と通信断を「成功(空含む)」と区別する（collapse させない）:
  //       成功 → {'ok': true,  'sites': List<Map>}   （0件でも ok:true）
  //       失敗 → {'ok': false, 'message': String}     （非200/例外）
  //   ・★ BE の query param は 'lon'（routes/sites.js:111 の { lat, lon }）。
  // ============================================================
  Future<Map<String, dynamic>> matchSites(double lat, double lng) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/sites/match?lat=$lat&lon=$lng'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final sites = (data['sites'] as List?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            <Map<String, dynamic>>[];
        return {'ok': true, 'sites': sites};
      }
      String? msg;
      try {
        msg = (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String?;
      } catch (_) {}
      return {'ok': false, 'message': msg ?? 'GPS照合に失敗しました (${response.statusCode})'};
    } catch (e) {
      return {'ok': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 住所→座標（GET /sites/geocode?address=）。matchSites と同じく非200/通信断を
  // 握り潰さず status で区別する（BE: 200→{success,lat,lng} / 404 GEOCODE_NOT_FOUND /
  // 502 GEOCODE_FAILED / 400 ADDRESS_REQUIRED, routes/sites.js:171-208）。
  //   成功        → {'status': 'ok', 'lat': double, 'lng': double}
  //   住所不明     → {'status': 'not_found'}                 （404）
  //   その他非200  → {'status': 'error', 'httpStatus': int}   （502/400等）
  //   通信断/例外  → {'status': 'offline'}
  // ============================================================
  Future<Map<String, dynamic>> geocode(String address) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/sites/geocode?address=${Uri.encodeQueryComponent(address)}'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'status': 'ok',
          'lat': (data['lat'] as num?)?.toDouble(),
          'lng': (data['lng'] as num?)?.toDouble(),
        };
      }
      if (response.statusCode == 404) return {'status': 'not_found'};
      return {'status': 'error', 'httpStatus': response.statusCode};
    } catch (_) {
      return {'status': 'offline'};
    }
  }

  // ============================================================
  // 現場情報更新
  // ============================================================

  Future<Map<String, dynamic>> updateSite({
    required String siteId,
    String? siteName,
    String? siteCode,
    String? address,
    String? startDate,
    String? endDate,
    bool? isActive,
  }) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.put(
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
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': '現場情報を更新しました',
          'site':    data['site'],
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 現場を無効化（削除）
  // ============================================================

  Future<Map<String, dynamic>> deleteSite(String siteId) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$kApiBaseUrl/sites/$siteId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {'success': true, 'message': '現場を無効化しました'};
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }
}