// ============================================================
// lib/services/work_mode_service.dart
// ============================================================
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

const String _apiBase = kApiBaseUrl;

enum WorkModeType { deemed, actual }

class WorkModeSettings {
  final WorkModeType mode;
  final String deemedStart;
  final String deemedEnd;
  final int breakMinutes;
  const WorkModeSettings({
    this.mode = WorkModeType.deemed,
    this.deemedStart = '08:00',
    this.deemedEnd = '17:00',
    this.breakMinutes = 120,
  });
  static WorkModeSettings fromJson(Map<String, dynamic> j) => WorkModeSettings(
    mode: j['work_mode'] == 'actual' || j['mode'] == 'actual'
        ? WorkModeType.actual : WorkModeType.deemed,
    deemedStart:  j['deemed_start']  as String? ?? '08:00',
    deemedEnd:    j['deemed_end']    as String? ?? '17:00',
    breakMinutes: j['break_minutes'] as int?    ?? 60,
  );
  static const WorkModeSettings defaults = WorkModeSettings();
}

class WorkModeService {
  static final WorkModeService instance = WorkModeService._();
  WorkModeService._();
  static const _keyMode = 'work_mode';
  static const _keyDeemedStart = 'deemed_start';
  static const _keyDeemedEnd = 'deemed_end';
  static const _keyBreakMinutes = 'break_minutes';
  static const _keyCheckedIn = 'work_checked_in';
  static const _keyCheckInTime = 'work_check_in_time';

  Future<WorkModeSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_keyMode) == 'actual'
        ? WorkModeType.actual : WorkModeType.deemed;
    return WorkModeSettings(
      mode: mode,
      deemedStart:  prefs.getString(_keyDeemedStart)  ?? '08:00',
      deemedEnd:    prefs.getString(_keyDeemedEnd)    ?? '17:00',
      breakMinutes: prefs.getInt(_keyBreakMinutes)    ?? 60,
    );
  }

  Future<void> save(WorkModeSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, settings.mode.name);
    await prefs.setString(_keyDeemedStart, settings.deemedStart);
    await prefs.setString(_keyDeemedEnd, settings.deemedEnd);
    await prefs.setInt(_keyBreakMinutes, settings.breakMinutes);
  }

  Future<bool> isCheckedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCheckedIn) ?? false;
  }

  Future<void> checkIn() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setBool(_keyCheckedIn, true);
    await prefs.setString(_keyCheckInTime, now.toIso8601String());
    await _sendAttendance('checkin', now);
  }

  Future<void> resetCheckIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCheckedIn, false);
    await prefs.remove(_keyCheckInTime);
  }

  Future<WorkModeSettings> fetchFromServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) return await load();
      final res = await http.get(
        Uri.parse('$_apiBase/work_settings/my'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final settings = WorkModeSettings.fromJson(
            (data['setting'] ?? data['settings']) as Map<String, dynamic>? ?? data);
        await save(settings);
        return settings;
      }
    } catch (e) {
      debugPrint('work_mode fetchFromServer失敗: $e');
    }
    return await load();
  }

  Future<void> _sendAttendance(String type, DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) return;
      await http.post(
        Uri.parse('$_apiBase/attendance/$type'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: '{"time":"${time.toUtc().toIso8601String()}"}',
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('attendance $type 送信失敗: $e');
    }
  }

  Future<({Map<String, dynamic>? record, bool punchedIn, bool punchedOut,
            int? standardBreakMin, int legalBreak6h, int legalBreak8h})?> fetchToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) return null;
      final res = await http.get(
        Uri.parse('$_apiBase/attendance/today'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return (
          record:           body['record']           as Map<String, dynamic>?,
          punchedIn:        body['punched_in']        as bool? ?? false,
          punchedOut:       body['punched_out']       as bool? ?? false,
          standardBreakMin: body['standard_break_min'] as int?,
          legalBreak6h:    (body['legal_break_6h_min'] as int?) ?? 45,
          legalBreak8h:    (body['legal_break_8h_min'] as int?) ?? 60,
        );
      }
      return null;
    } catch (e) {
      debugPrint('attendance/today 取得失敗: $e');
      return null;
    }
  }

  Future<({bool ok, Map<String, dynamic>? record, int statusCode, String? errorCode, String? errorMessage})>
      punch(String type, {double? lat, double? lng, String? addr,
                          String shiftType = 'day'}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        return (ok: false, record: null, statusCode: 0, errorCode: null, errorMessage: 'トークンがありません');
      }
      // shift_type は BE の POST /attendance/punch が受ける（'day'|'night'・省略時 day）。
      // 夜勤は BE 側 businessDateForShift で始業日に寄せられ、出勤/退勤が同一行に収まる。
      final payload = <String, dynamic>{'type': type, 'shift_type': shiftType};
      if (lat  != null) payload['lat']  = lat;
      if (lng  != null) payload['lng']  = lng;
      if (addr != null) payload['addr'] = addr;
      final res = await http.post(
        Uri.parse('$_apiBase/attendance/punch'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        return (
          ok:           true,
          record:       body['record'] as Map<String, dynamic>?,
          statusCode:   res.statusCode,
          errorCode:    null,
          errorMessage: null,
        );
      }
      return (
        ok:           false,
        record:       null,
        statusCode:   res.statusCode,
        errorCode:    body['code']  as String?,
        errorMessage: body['error'] as String?,
      );
    } catch (e) {
      debugPrint('attendance/punch 送信失敗: $e');
      return (ok: false, record: null, statusCode: 0, errorCode: null, errorMessage: '通信に失敗しました');
    }
  }

  Future<({bool ok, int statusCode, String? errorCode, String? errorMessage})>
      breakRequest({required int breakMinutes, required String reason, String? workDate}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        return (ok: false, statusCode: 0, errorCode: null, errorMessage: 'トークンがありません');
      }
      final payload = <String, dynamic>{
        'break_minutes': breakMinutes,
        'reason':        reason,
        if (workDate != null) 'work_date': workDate,
      };
      final res = await http.post(
        Uri.parse('$_apiBase/attendance/break-request'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        return (ok: true, statusCode: res.statusCode, errorCode: null, errorMessage: null);
      }
      return (
        ok:           false,
        statusCode:   res.statusCode,
        errorCode:    body['code']  as String?,
        errorMessage: body['error'] as String?,
      );
    } catch (e) {
      debugPrint('attendance/break-request 送信失敗: $e');
      return (ok: false, statusCode: 0, errorCode: null, errorMessage: '通信に失敗しました');
    }
  }
}
