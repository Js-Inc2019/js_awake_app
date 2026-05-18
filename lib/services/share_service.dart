// ============================================================
// lib/services/share_service.dart - 会社間報告サービス
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ShareService {
  static final ShareService _instance = ShareService._internal();
  static const String API_URL =
      'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

  factory ShareService() {
    return _instance;
  }

  ShareService._internal();

  final AuthService _auth = AuthService();

  // ============================================================
  // 日報を他社に送信する
  // 職長（boss）・事務（admin_office・admin_exec）のみ可能
  // ============================================================

  Future<Map<String, dynamic>> sendReport({
    required String reportId,
    required String receiverCompanyId,
    String shareType = 'in_app',
    String? memo,
  }) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.post(
        Uri.parse('$API_URL/shares/send'),
        headers: headers,
        body: jsonEncode({
          'report_id':          reportId,
          'receiver_company_id': receiverCompanyId,
          'share_type':         shareType,
          'memo':               memo,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': '日報を送信しました',
          'share':   data['share'],
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 受信した日報一覧取得（受信トレイ）
  // ============================================================

  Future<Map<String, dynamic>> getInbox() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$API_URL/shares/inbox'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final shares = data['shares'] as List<dynamic>;

        // 改ざん検知：is_tamperedがtrueのものを抽出
        final tamperedShares = shares
            .where((s) => s['is_tampered'] == true)
            .toList();

        return {
          'success':          true,
          'shares':           shares,
          'tampered_count':   tamperedShares.length,
          'tampered_shares':  tamperedShares,
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 送信した日報一覧取得（送信トレイ）
  // ============================================================

  Future<Map<String, dynamic>> getOutbox() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$API_URL/shares/outbox'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {
          'success': true,
          'shares':  data['shares'] as List<dynamic>,
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 既読にする
  // ============================================================

  Future<Map<String, dynamic>> markAsRead(String shareId) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.put(
        Uri.parse('$API_URL/shares/$shareId/read'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {'success': true, 'message': '既読にしました'};
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 改ざんチェック（手動）
  // ============================================================

  Future<Map<String, dynamic>> checkTamper(String shareId) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.post(
        Uri.parse('$API_URL/shares/check-tamper'),
        headers: headers,
        body: jsonEncode({'share_id': shareId}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {
          'success':     true,
          'is_tampered': data['is_tampered'] as bool,
          'message':     data['message'] as String,
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 改ざん通知一覧取得
  // ============================================================

  Future<Map<String, dynamic>> getTamperNotifications() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$API_URL/shares/notifications'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {
          'success':       true,
          'notifications': data['notifications'] as List<dynamic>,
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }
}