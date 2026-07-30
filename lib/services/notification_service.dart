// ============================================================
// lib/services/notification_service.dart - 通知通信サービス
// 既存service流儀（AuthService().getAuthHeaders / kApiBaseUrl / timeout /
// 非200は {success:false, error, statusCode} で返す）に準拠。
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../config/constants.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final AuthService _auth = AuthService();

  // ============================================================
  // 通知一覧取得（BEは最新50件・{success, notifications:[...]}を返す）
  // 各行: id, type, title, body, ref_id, is_read, created_at(timestamptz)
  // ============================================================
  Future<Map<String, dynamic>> fetchNotifications() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/notifications'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {
          'success': true,
          'notifications': (data['notifications'] as List?) ?? [],
        };
      }
      return {
        'success': false,
        'error': data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 未読件数取得（{success, count:int}）
  // ============================================================
  Future<Map<String, dynamic>> fetchUnreadCount() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/notifications/unread-count'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {
          'success': true,
          'count': (data['count'] as num?)?.toInt() ?? 0,
        };
      }
      return {
        'success': false,
        'error': data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 既読化（1件）PATCH /notifications/:id/read
  // ============================================================
  Future<Map<String, dynamic>> markRead(String id) async {
    if (id.isEmpty) return {'success': false, 'error': 'id なし'};
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.patch(
        Uri.parse('$kApiBaseUrl/notifications/$id/read'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return {'success': true};
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': false,
        'error': data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 全既読化 PATCH /notifications/read-all
  // ============================================================
  Future<Map<String, dynamic>> markAllRead() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.patch(
        Uri.parse('$kApiBaseUrl/notifications/read-all'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return {'success': true};
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': false,
        'error': data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 通知設定取得 GET /notification-settings/my
  // {report_remind_enabled, remind_time1('HH:MM'|null),
  //  remind_time2('HH:MM'|null), health_notify_enabled, is_default}
  // ============================================================
  Future<Map<String, dynamic>> fetchNotificationSettings() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/notification-settings/my'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {'success': true, 'settings': data};
      }
      return {
        'success': false,
        'error': data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 通知設定保存 PUT /notification-settings/my
  // remind_time1/2 は null をそのまま送ると「枠OFF」。
  // health_notify_enabled は本画面の対象外のため送らない（BEはマージUPSERTで既存値保持）。
  //
  // 打刻のお知らせ（punch_remind_*）: BE は出勤側/退勤側それぞれに
  //   enabled(bool) / mode('after'|'at') / after_min(int) / at('HH:00'|null) を持つ。
  //   ★どちらの値が有効かは mode だけが決める。'after' のときは at を、
  //     'at' のときは after_min を BE は読まない（選ばれていない側は前回値として残るだけ）。
  //   ★mode='at' で at が null だと BE が 400 を返す（'at' に既定値が無いため）。
  //     呼び出し側は mode='at' のとき必ず時刻を渡すこと。
  // ============================================================
  Future<Map<String, dynamic>> saveNotificationSettings({
    required bool reportRemindEnabled,
    required String? remindTime1,
    required String? remindTime2,
    // 打刻のお知らせ（省略時は送らない＝BE のマージUPSERTで既存値を保持）
    bool? punchRemindInEnabled,
    String? punchRemindInMode,
    int? punchRemindInAfterMin,
    String? punchRemindInAt,
    bool? punchRemindOutEnabled,
    String? punchRemindOutMode,
    int? punchRemindOutAfterMin,
    String? punchRemindOutAt,
  }) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final body = <String, dynamic>{
        'report_remind_enabled': reportRemindEnabled,
        'remind_time1': remindTime1, // null = 枠OFF
        'remind_time2': remindTime2, // null = 枠OFF
      };
      // 打刻のお知らせは「渡されたときだけ」載せる。
      //   ★_at は null が正当な値（mode='after' のとき）なので、
      //     mode が渡されているかどうかで「この節を編集した」と判断する。
      if (punchRemindInMode != null) {
        body['punch_remind_in_enabled']   = punchRemindInEnabled;
        body['punch_remind_in_mode']      = punchRemindInMode;
        body['punch_remind_in_after_min'] = punchRemindInAfterMin;
        body['punch_remind_in_at']        = punchRemindInAt;
      }
      if (punchRemindOutMode != null) {
        body['punch_remind_out_enabled']   = punchRemindOutEnabled;
        body['punch_remind_out_mode']      = punchRemindOutMode;
        body['punch_remind_out_after_min'] = punchRemindOutAfterMin;
        body['punch_remind_out_at']        = punchRemindOutAt;
      }
      final response = await http.put(
        Uri.parse('$kApiBaseUrl/notification-settings/my'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {'success': true, 'settings': data};
      }
      return {
        'success': false,
        'error': data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
