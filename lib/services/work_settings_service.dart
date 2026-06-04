// lib/services/work_settings_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

const String _API_URL = kApiBaseUrl;

class WorkSettingsData {
  final String workMode;      // 'deemed' or 'actual'
  final String deemedStart;   // '08:00'
  final String deemedEnd;     // '17:00'
  final int    breakMinutes;  // 60

  const WorkSettingsData({
    this.workMode     = 'deemed',
    this.deemedStart  = '08:00',
    this.deemedEnd    = '17:00',
    this.breakMinutes = 60,
  });

  factory WorkSettingsData.fromJson(Map<String, dynamic> j) => WorkSettingsData(
    workMode:     j['work_mode']     as String? ?? 'deemed',
    deemedStart:  (j['deemed_start'] as String? ?? '08:00:00').substring(0, 5),
    deemedEnd:    (j['deemed_end']   as String? ?? '17:00:00').substring(0, 5),
    breakMinutes: j['break_minutes'] as int?    ?? 60,
  );

  bool get isDeemed => workMode == 'deemed';
}

class WorkSettingsService {
  static final WorkSettingsService instance = WorkSettingsService._();
  WorkSettingsService._();

  Future<WorkSettingsData> getMySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res   = await http.get(
        Uri.parse('$_API_URL/work_settings/my'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return WorkSettingsData.fromJson(data['setting'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('WorkSettings取得失敗: $e');
    }
    return const WorkSettingsData();
  }

  Future<List<Map<String, dynamic>>> getAllSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res   = await http.get(
        Uri.parse('$_API_URL/work_settings'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['settings'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      }
    } catch (e) {
      debugPrint('WorkSettings一覧取得失敗: $e');
    }
    return [];
  }

  Future<bool> updateSetting({
    required String targetUserId,
    required String workMode,
    required String deemedStart,
    required String deemedEnd,
    required int    breakMinutes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res   = await http.post(
        Uri.parse('$_API_URL/work_settings/$targetUserId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type':  'application/json',
        },
        body: jsonEncode({
          'work_mode':     workMode,
          'deemed_start':  deemedStart,
          'deemed_end':    deemedEnd,
          'break_minutes': breakMinutes,
        }),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('WorkSettings更新失敗: $e');
      return false;
    }
  }
}
