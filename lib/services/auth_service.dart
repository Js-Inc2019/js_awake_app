// ============================================================
// lib/services/auth_service.dart - 認証サービス
// トークン管理・ログイン処理
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();

  // ✅ HerokuのURLに変更
  static const String API_URL =
      'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  // ============================================================
  // トークン取得
  // ============================================================

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // ============================================================
  // ユーザーID取得
  // ============================================================

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  // ============================================================
  // 会社ID取得（v2追加）
  // ============================================================

  Future<String?> getCompanyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('company_id');
  }

  // ============================================================
  // ロール取得（v2追加）
  // ============================================================

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role') ?? prefs.getString('role');
  }

  // ============================================================
  // ユーザー名取得（v2追加）
  // ============================================================

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name');
  }

  // ============================================================
  // ログイン済みか確認
  // ============================================================

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ============================================================
  // 職人かどうか確認
  // ============================================================

  Future<bool> isWorker() async {
    final role = await getRole();
    return role == 'worker';
  }

  // ============================================================
  // 職長かどうか確認
  // ============================================================

  Future<bool> isBoss() async {
    final role = await getRole();
    return role == 'boss';
  }

  // ============================================================
  // 事務かどうか確認
  // ============================================================

  Future<bool> isOfficeAdmin() async {
    final role = await getRole();
    return role == 'admin_office' || role == 'admin_exec';
  }

  // ============================================================
  // PINでログイン
  // ============================================================

  Future<Map<String, dynamic>> loginWithPin(String pin) async {
    try {
      debugPrint('🔍 ログイン試行: PIN=$pin');
      debugPrint('🔍 API URL: $API_URL/auth/verify-pin');

      final response = await http.post(
        Uri.parse('$API_URL/auth/verify-pin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pin': pin,
          'device_name': 'JS_App_Device',
          'device_type': 'smartphone',
        }),
      ).timeout(const Duration(seconds: 15));

      debugPrint('🔍 ステータスコード: ${response.statusCode}');
      debugPrint('🔍 レスポンス: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token    = data['token']      as String?;
        final userId   = data['user_id']    as String?;
        final role     = data['role']       as String?;
        final companyId = data['company_id'] as String?;
        final userName = data['name']       as String?;

        if (token != null && userId != null) {
          // SharedPreferencesに保存
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token',  token);
          await prefs.setString('user_id',     userId);
          await prefs.setString('user_role',    role     ?? 'worker');
          await prefs.setString('company_id',  companyId ?? '');
          await prefs.setString('user_name',   userName  ?? '');
          await prefs.setInt('experience_months',
              (data['experience_months'] as num?)?.toInt() ?? 0);
          await prefs.setInt('foreman_years',
              (data['foreman_years'] as num?)?.toInt() ?? 0);

          debugPrint('✅ ログイン成功: role=$role, company_id=$companyId');

          return {
            'success':    true,
            'message':    'ログインに成功しました',
            'token':      token,
            'user_id':    userId,
            'role':       role,
            'company_id': companyId,
            'user_name':  userName,
          };
        }
      } else if (response.statusCode == 401) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final code = data['code'] as String? ?? '';
        return {
          'success':      false,
          'message':      data['error'] ?? 'PINが間違っています',
          'code':         code,
          'role_changed': code == 'ROLE_CHANGED' || code == 'STATUS_CHANGED',
          'remaining':    data['remaining'],
        };
      } else if (response.statusCode == 429) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': false,
          'message': data['error'] ?? 'ロック中です',
          'code':    'PIN_LOCKED',
        };
      }

      return {
        'success': false,
        'message': 'ログインに失敗しました',
        'code': '',
      };
    } catch (e) {
      debugPrint('❌ ログインエラー: $e');
      return {
        'success': false,
        'message': 'サーバーに接続できません。ネットワークを確認してください。',
      };
    }
  }

  // ============================================================
  // ログアウト
  // ============================================================

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
    await prefs.remove('user_role');
    await prefs.remove('company_id');
    await prefs.remove('user_name');
  }

  // ============================================================
  // トークン検証
  // ============================================================

  Future<bool> verifyToken() async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('$API_URL/auth/verify-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // 認証済みAPIリクエスト用ヘッダー取得
  // ============================================================

  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ============================================================
  // PIN変更
  // ============================================================

  String? lastError;

  Future<bool> changePin({required String oldPin, required String newPin}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id') ?? '';
      final res = await http.post(
        Uri.parse('$API_URL/auth/change-pin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_id': deviceId, 'old_pin': oldPin, 'new_pin': newPin}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return true;
      try {
        lastError = (jsonDecode(res.body)['error'] as String?) ?? 'PIN変更失敗';
      } catch (_) {
        lastError = 'PIN変更に失敗しました';
      }
      return false;
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }
}