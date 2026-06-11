// ============================================================
// lib/services/auth_service.dart - 認証サービス
// トークン管理・ログイン処理
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();

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
    return prefs.getString('role');
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
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/auth/verify-pin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pin': pin,
          'device_name': 'JS_App_Device',
          'device_type': 'smartphone',
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token       = data['token']        as String?;
        final userId      = data['user_id']      as String?;
        final role        = data['role']         as String?;
        final companyId   = data['company_id']   as String?;
        final companyName = data['company_name'] as String?;
        final userName    = data['name']         as String?;
        final workerId    = data['worker_id']    as String?;

        if (token != null && userId != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token',   token);
          await prefs.setString('user_id',      userId);
          await prefs.setString('role',         role        ?? 'worker');
          await prefs.setString('company_id',   companyId   ?? '');
          await prefs.setString('company_name', companyName ?? '');
          await prefs.setString('user_name',    userName    ?? '');
          if (workerId != null && workerId.isNotEmpty) {
            await prefs.setString('worker_id', workerId);
          }
          return {
            'success':      true,
            'message':      'ログインに成功しました',
            'token':        token,
            'user_id':      userId,
            'role':         role,
            'company_id':   companyId,
            'company_name': companyName,
            'user_name':    userName,
            'worker_id':    workerId,
          };
        }
      } else if (response.statusCode == 401) {
        return {'success': false, 'message': 'PINが間違っています'};
      }

      return {'success': false, 'message': 'ログインに失敗しました'};
    } catch (e) {
      debugPrint('ログインエラー: $e');
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
    await prefs.setBool('logged_out', true);
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
    await prefs.remove('role');
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
        Uri.parse('$kApiBaseUrl/auth/verify-token'),
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
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }
}