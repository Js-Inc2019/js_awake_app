// ============================================================
// lib/services/site_service.dart - 現場管理サービス
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class SiteService {
  static final SiteService _instance = SiteService._internal();
  static const String API_URL =
      'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

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
        Uri.parse('$API_URL/sites'),
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
        Uri.parse('$API_URL/sites'),
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
        Uri.parse('$API_URL/sites/$siteId'),
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
  // GPS座標照合（半径50m以内の現場を返す）
  // ============================================================

  Future<List<Map<String, dynamic>>> matchSites(double lat, double lng) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$API_URL/sites/match?lat=$lat&lon=$lng'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['sites'] as List? ?? []).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // 現場を無効化（削除）
  // ============================================================

  Future<Map<String, dynamic>> deleteSite(String siteId) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$API_URL/sites/$siteId'),
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