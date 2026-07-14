// ============================================================
// lib/services/share_service.dart - 会社間報告サービス
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../config/constants.dart';

class ShareService {
  static final ShareService _instance = ShareService._internal();

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
        Uri.parse('$kApiBaseUrl/shares/send'),
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
        Uri.parse('$kApiBaseUrl/shares/inbox'),
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
        Uri.parse('$kApiBaseUrl/shares/outbox'),
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
        Uri.parse('$kApiBaseUrl/shares/$shareId/read'),
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

  /// 改ざんチェック（手動）
  /// 戻り値の 'status' は必ず次の3値のいずれか。呼び出し側はこれで分岐する:
  ///   'ok'       … 確認成功・改ざんなし
  ///   'tampered' … 確認成功・改ざん検知
  ///   'error'    … 確認失敗（通信断・非200・不正レスポンス）
  /// ※ 確認失敗を 'ok'（正常）に混同させないため、成功時のみ 'ok'/'tampered' を返す。
  Future<Map<String, dynamic>> checkTamper(String shareId) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/shares/check-tamper'),
        headers: headers,
        body: jsonEncode({'share_id': shareId}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final tampered = data['is_tampered'];
        // 200 でも is_tampered が bool でなければ判定不能 → 安全側で error 扱い
        if (tampered is bool) {
          return {
            'status':      tampered ? 'tampered' : 'ok',
            'is_tampered': tampered,
            'message':     (data['message'] as String?) ??
                (tampered ? '改ざんが検知されました' : '正常です'),
          };
        }
        return {'status': 'error', 'message': '確認結果を取得できませんでした'};
      }

      return {
        'status':  'error',
        'message': (data['error'] as String?) ?? 'エラーが発生しました',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 改ざん通知一覧取得
  // ============================================================

  Future<Map<String, dynamic>> getTamperNotifications() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/shares/notifications'),
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