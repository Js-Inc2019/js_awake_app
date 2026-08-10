// ============================================================
// lib/services/notification_service.dart - 通知通信サービス
//
// ★段4: 戻り値を ApiResult<T> へ統一（規約は api_result.dart 冒頭）。
//   統一前は {success, error, statusCode} の Map 返しで、
//   非200のときだけ statusCode が載る（例外時は載らない）という穴があった。
//   ApiResult は常に statusCode を持ち、通信不成立を 0 で表す。
//   URL・body・timeout は1文字も変えていない。
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_result.dart';
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
  Future<ApiResult<List<dynamic>>> fetchNotifications() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<dynamic>>(
      'NotificationService.fetchNotifications',
      () => http.get(
        Uri.parse('$kApiBaseUrl/notifications'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => (apiJsonMap(body)?['notifications'] as List?) ?? const [],
    );
  }

  // ============================================================
  // 未読件数取得（{success, count:int}）
  // ============================================================
  Future<ApiResult<int>> fetchUnreadCount() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<int>(
      'NotificationService.fetchUnreadCount',
      () => http.get(
        Uri.parse('$kApiBaseUrl/notifications/unread-count'),
        headers: headers,
      ).timeout(const Duration(seconds: 8)),
      (body) => (apiJsonMap(body)?['count'] as num?)?.toInt() ?? 0,
    );
  }

  // ============================================================
  // 既読化（1件）PATCH /notifications/:id/read
  //   ★id 空はリクエストを出さずに失敗を返す（統一前と同じガード）。
  // ============================================================
  Future<ApiResult<Map<String, dynamic>>> markRead(String id) async {
    if (id.isEmpty) {
      return apiFailure<Map<String, dynamic>>(statusCode: 0, errorMessage: 'id なし');
    }
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'NotificationService.markRead',
      () => http.patch(
        Uri.parse('$kApiBaseUrl/notifications/$id/read'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 全既読化 PATCH /notifications/read-all
  // ============================================================
  Future<ApiResult<Map<String, dynamic>>> markAllRead() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'NotificationService.markAllRead',
      () => http.patch(
        Uri.parse('$kApiBaseUrl/notifications/read-all'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 通知設定取得 GET /notification-settings/my
  // {report_remind_enabled, remind_time1('HH:MM'|null),
  //  remind_time2('HH:MM'|null), health_notify_enabled, is_default}
  // ============================================================
  Future<ApiResult<Map<String, dynamic>>> fetchNotificationSettings() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'NotificationService.fetchNotificationSettings',
      () => http.get(
        Uri.parse('$kApiBaseUrl/notification-settings/my'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 通知設定保存 PUT /notification-settings/my
  // remind_time1/2 は null をそのまま送ると「枠OFF」。
  // health_notify_enabled は本画面の対象外のため送らない（BEはマージUPSERTで既存値保持）。
  //
  // ★打刻のお知らせ（punch_remind_*）はここでは送らない・送れない。
  //   会社が決める統治項目として attendance_settings へ移設済み（BE の v62）。
  //   本人は変更できず、表示用の参照は
  //   WorkModeService.fetchResolvedAttendanceSettings（GET /attendance/settings/resolved）を使う。
  // ============================================================
  Future<ApiResult<Map<String, dynamic>>> saveNotificationSettings({
    required bool reportRemindEnabled,
    required String? remindTime1,
    required String? remindTime2,
  }) async {
    final headers = await _auth.getAuthHeaders();
    final body = <String, dynamic>{
      'report_remind_enabled': reportRemindEnabled,
      'remind_time1': remindTime1, // null = 枠OFF
      'remind_time2': remindTime2, // null = 枠OFF
    };
    return runApiCall<Map<String, dynamic>>(
      'NotificationService.saveNotificationSettings',
      () => http.put(
        Uri.parse('$kApiBaseUrl/notification-settings/my'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }
}
