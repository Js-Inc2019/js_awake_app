// lib/services/work_mode_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/work_mode.dart';

const String _API_URL = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

class WorkModeService {
  static final WorkModeService instance = WorkModeService._();
  WorkModeService._();

  static const _kSessions = 'work_sessions';
  static const _kActiveId = 'active_session_id';

  Future<List<WorkSession>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kSessions);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => WorkSession.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  Future<WorkSession?> loadToday() async {
    final all   = await loadAll();
    final today = DateTime.now();
    try {
      return all.lastWhere((s) =>
          s.date.year  == today.year &&
          s.date.month == today.month &&
          s.date.day   == today.day);
    } catch (_) { return null; }
  }

  Future<String?> getActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kActiveId);
  }

  Future<void> _saveAll(List<WorkSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessions, jsonEncode(sessions.map((s) => s.toJson()).toList()));
  }

  Future<WorkSession> startDeemed() async {
    final now     = DateTime.now();
    final session = WorkSession(mode: WorkModeType.deemed, date: now);
    final all     = await loadAll();
    all.removeWhere((s) =>
        s.date.year == now.year && s.date.month == now.month && s.date.day == now.day);
    all.add(session);
    await _saveAll(all);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActiveId);
    await _sendToAPI(session);
    return session;
  }

  Future<WorkSession> clockIn() async {
    final now     = DateTime.now();
    final session = WorkSession(mode: WorkModeType.actual, date: now, clockIn: now);
    final all     = await loadAll();
    all.removeWhere((s) =>
        s.date.year == now.year && s.date.month == now.month && s.date.day == now.day);
    all.add(session);
    await _saveAll(all);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveId, session.id);
    await _sendToAPI(session);
    return session;
  }

  Future<WorkSession?> clockOut() async {
    final now    = DateTime.now();
    final all    = await loadAll();
    final prefs  = await SharedPreferences.getInstance();
    final active = prefs.getString(_kActiveId);
    final idx    = all.indexWhere((s) => s.id == active);
    if (idx < 0) return null;
    final old     = all[idx];
    final updated = WorkSession(
      id: old.id, mode: old.mode, date: old.date,
      clockIn: old.clockIn, clockOut: now,
    );
    all[idx] = updated;
    await _saveAll(all);
    await prefs.remove(_kActiveId);
    await _updateAPI(updated);
    return updated;
  }

  Future<void> _sendToAPI(WorkSession s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      await http.post(
        Uri.parse('$_API_URL/work_sessions'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'work_mode': s.mode.name,
          'work_date': s.date.toIso8601String().substring(0, 10),
          'clock_in':  s.clockInLabel,
          'clock_out': s.mode == WorkModeType.deemed ? '17:00' : null,
          'is_deemed': s.mode == WorkModeType.deemed,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) { debugPrint('WorkMode API 失敗: $e'); }
  }

  Future<void> _updateAPI(WorkSession s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      await http.patch(
        Uri.parse('$_API_URL/work_sessions/${s.id}'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'clock_out': s.clockOutLabel,
          'duration_minutes': s.workDuration?.inMinutes,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) { debugPrint('WorkMode API 更新失敗: $e'); }
  }
}
