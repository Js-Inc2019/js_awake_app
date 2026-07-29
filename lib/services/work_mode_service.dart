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

  // ── 会社休日カレンダー（/attendance 系のためこのサービスに置く）─────────
  // GET /attendance/holidays/my → { weekly: {"0".."6": 'legal'|'scheduled'},
  //                                 dates:  {"YYYY-MM-DD": 'legal'|'scheduled'} }
  // BE: routes/attendance.js:533（employee 限定・cooperation は 403 COOPERATION_FORBIDDEN）。
  // 戻り値は punch(:149)/breakRequest(:192) と同じ ok 付きレコード流儀。
  // 沈黙障害の禁止: 非200・例外は debugPrint で必ず出し、ok:false で呼び出し側へ返す
  //（weekly/dates は空マップになるため「取れなかった」と「休日ゼロ」を ok で区別できる）。
  Future<({bool ok, Map<String, String> weekly, Map<String, String> dates,
            int statusCode, String? errorMessage})> fetchCompanyHolidays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        debugPrint('attendance/holidays/my: トークンがありません');
        return (ok: false, weekly: <String, String>{}, dates: <String, String>{},
                statusCode: 0, errorMessage: 'トークンがありません');
      }
      final res = await http.get(
        Uri.parse('$_apiBase/attendance/holidays/my'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return (
          ok:         true,
          weekly:     _asStringMap(body['weekly']),
          dates:      _asStringMap(body['dates']),
          statusCode: res.statusCode,
          errorMessage: null,
        );
      }
      debugPrint('attendance/holidays/my 非200: status=${res.statusCode} body=${res.body}');
      return (ok: false, weekly: <String, String>{}, dates: <String, String>{},
              statusCode: res.statusCode, errorMessage: '会社休日を取得できませんでした');
    } catch (e) {
      debugPrint('attendance/holidays/my 取得失敗: $e');
      return (ok: false, weekly: <String, String>{}, dates: <String, String>{},
              statusCode: 0, errorMessage: e.toString());
    }
  }

  // GET /attendance/holidays/jp?year=YYYY → { dates: {"YYYY-MM-DD": 祝日名}, year, count }
  // BE: routes/attendance.js:636。★/holidays/my の dates は値が 'legal'|'scheduled' だが、
  //     こちらの dates は値が【祝日名の文字列】。用途が違うので混同しないこと
  //     （こちらは文字色＝朱の判定にのみ使い、会社の休業設定とは無関係）。
  // 取得は年単位（月ではない）。失敗時は ok:false・dates 空で返し、呼び出し側は
  // 祝日色なしで描画を続行できる。
  Future<({bool ok, Map<String, String> dates, int statusCode, String? errorMessage})>
      fetchJpHolidays(int year) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        debugPrint('attendance/holidays/jp: トークンがありません');
        return (ok: false, dates: <String, String>{}, statusCode: 0, errorMessage: 'トークンがありません');
      }
      final res = await http.get(
        Uri.parse('$_apiBase/attendance/holidays/jp?year=$year'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return (ok: true, dates: _asStringMap(body['dates']),
                statusCode: res.statusCode, errorMessage: null);
      }
      debugPrint('attendance/holidays/jp 非200: year=$year status=${res.statusCode} body=${res.body}');
      return (ok: false, dates: <String, String>{},
              statusCode: res.statusCode, errorMessage: '祝日情報を取得できませんでした');
    } catch (e) {
      debugPrint('attendance/holidays/jp 取得失敗: year=$year $e');
      return (ok: false, dates: <String, String>{}, statusCode: 0, errorMessage: e.toString());
    }
  }

  // JSON の Map を Map<String,String> へ正規化（値が文字列でないキーは捨てる）。
  static Map<String, String> _asStringMap(dynamic v) {
    if (v is! Map) return <String, String>{};
    final out = <String, String>{};
    v.forEach((k, val) {
      if (val is String) out['$k'] = val;
    });
    return out;
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

  // ─── 休憩申告の確認・修正側（職長・事務/boss が使う）────────────────────
  //   BE は承認制から申告制へ転換済み:
  //     GET  /attendance/break-requests?month=YYYY-MM  (routes/attendance.js:1733)
  //     POST /attendance/break-request/:id/amend       (routes/attendance.js:1787)
  //   ★旧 /break-requests/pending・/approve・/reject は BE から撤去済み。
  //     呼べない道を「嘘の記号」として残さないため、当メソッド群も削除した。
  //   権限は MONTHLY_ROLES(admin_office/admin_exec/boss・:1459) で、権限不足は 403。
  //   流儀は上の breakRequest(:276-308) と同一:
  //     ・token は都度 SharedPreferences から取る
  //     ・throw しない（ok 付きレコードで返す）
  //     ・失敗時は statusCode / code / error をそのまま載せて呼び手に判断させる

  /// GET /attendance/break-requests?month=YYYY-MM
  /// 応答 {month, requests:[…]} の各行は BE の SELECT 列（routes/attendance.js:1760-1765）そのまま:
  ///   id / person_id / membership_id / work_date('YYYY-MM-DD') / break_override_min /
  ///   break_override_reason / break_override_status / break_override_req_at / person_name
  Future<({bool ok, List<Map<String, dynamic>> requests, int statusCode, String? errorMessage})>
      fetchBreakRequests({required String month}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        return (ok: false, requests: <Map<String, dynamic>>[], statusCode: 0,
                errorMessage: 'トークンがありません');
      }
      final res = await http.get(
        Uri.parse('$_apiBase/attendance/break-requests?month=$month'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (body['requests'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return (ok: true, requests: list, statusCode: res.statusCode, errorMessage: null);
      }
      String? msg;
      try { msg = (jsonDecode(res.body) as Map<String, dynamic>)['error'] as String?; } catch (_) {}
      return (ok: false, requests: <Map<String, dynamic>>[],
              statusCode: res.statusCode, errorMessage: msg);
    } catch (e) {
      debugPrint('attendance/break-requests 取得失敗: month=$month $e');
      return (ok: false, requests: <Map<String, dynamic>>[], statusCode: 0,
              errorMessage: '通信に失敗しました');
    }
  }

  /// POST /attendance/break-request/:id/amend   body:{ break_minutes }
  /// 申告された休憩の分数を管理側が修正する。理由・申告時刻は BE 側で保持される
  /// （routes/attendance.js:1825-1832）。
  Future<({bool ok, int statusCode, String? errorCode, String? errorMessage})>
      amendBreakRequest(String id, int breakMinutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        return (ok: false, statusCode: 0, errorCode: null, errorMessage: 'トークンがありません');
      }
      final res = await http.post(
        Uri.parse('$_apiBase/attendance/break-request/$id/amend'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'break_minutes': breakMinutes}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return (ok: true, statusCode: res.statusCode, errorCode: null, errorMessage: null);
      }
      String? code;
      String? msg;
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        code = body['code']  as String?;
        msg  = body['error'] as String?;
      } catch (_) {}
      return (ok: false, statusCode: res.statusCode, errorCode: code, errorMessage: msg);
    } catch (e) {
      debugPrint('attendance/break-request/amend 送信失敗: $e');
      return (ok: false, statusCode: 0, errorCode: null, errorMessage: '通信に失敗しました');
    }
  }
}
