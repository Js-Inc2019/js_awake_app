// ============================================================
// lib/services/work_mode_service.dart
//
// ★段4での変更点（URL・body・timeout・判定条件は1文字も変えていない）:
//   ① 独自 record 型（{ok, settings, statusCode, errorMessage} など6種類が
//      メソッドごとに微妙に違う形で並存していた）を ApiResult<T> へ統一。
//      統一前は「weekly/dates が空 = 取れなかった or 休日ゼロ」を ok で
//      区別する、という同じ工夫を各メソッドが別々に再発明していた。
//   ② シングルトンを静的フィールド型（`WorkModeService.instance`）から
//      factory 型（`WorkModeService()`）へ。他8本の Service と揃える。
//   ③ 手組みの Authorization ヘッダを AuthService.getAuthHeaders() へ集約。
//      ★これに伴い GET 系にも 'Content-Type: application/json' が付く。
//        body を持たない GET に Content-Type が付くだけで BE の挙動は変わらない
//        （Express は本文が無ければパースしない）。
//      ★「トークンが空ならリクエストを出さない」ガードは統一前のまま維持する
//        （空 Bearer を BE へ投げない）。getAuthHeaders() は空でも 'Bearer ' を
//        作ってしまうため、ガードは _auth.getToken() で先に行う。
// ============================================================
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'api_result.dart';
import 'auth_service.dart';
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

/// 会社休日カレンダー（GET /attendance/holidays/my）。
/// weekly: {"0".."6": 'legal'|'scheduled'} / dates: {"YYYY-MM-DD": 'legal'|'scheduled'}
class CompanyHolidays {
  const CompanyHolidays({required this.weekly, required this.dates});
  final Map<String, String> weekly;
  final Map<String, String> dates;
}

/// 当日（業務日）の勤怠行（GET /attendance/today）。
class TodayAttendance {
  const TodayAttendance({
    required this.record,
    required this.punchedIn,
    required this.punchedOut,
    required this.standardBreakMin,
    required this.legalBreak6h,
    required this.legalBreak8h,
  });
  final Map<String, dynamic>? record;
  final bool punchedIn;
  final bool punchedOut;
  final int? standardBreakMin;
  final int legalBreak6h;
  final int legalBreak8h;
}

class WorkModeService {
  static final WorkModeService _instance = WorkModeService._internal();

  factory WorkModeService() => _instance;

  WorkModeService._internal();

  final AuthService _auth = AuthService();

  static const _keyMode = 'work_mode';
  static const _keyDeemedStart = 'deemed_start';
  static const _keyDeemedEnd = 'deemed_end';
  static const _keyBreakMinutes = 'break_minutes';
  static const _keyCheckedIn = 'work_checked_in';
  static const _keyCheckInTime = 'work_check_in_time';

  /// リクエスト前のトークン確認。空なら「出さずに失敗」を返す（統一前と同じ）。
  /// 戻りが null＝トークンあり。非 null＝そのまま返すべき失敗。
  Future<ApiResult<T>?> _requireToken<T>() async {
    final token = await _auth.getToken() ?? '';
    if (token.isEmpty) {
      return apiFailure<T>(statusCode: 0, errorMessage: 'トークンがありません');
    }
    return null;
  }

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

  // ★checkIn() は撤去した（呼び手ゼロ）。
  //   併せて撤去した sendAttendance() が組んでいた POST /attendance/checkin は
  //   BE の全ルート（server.js のマウント解決後177本）に存在せず、呼ばれれば 404 になる
  //   死んだ呼び出しだった。実打刻は POST /attendance/punch（punch()）ただ一つ。

  Future<void> resetCheckIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCheckedIn, false);
    await prefs.remove(_keyCheckInTime);
  }

  /// GET /work_settings/my の生の結果（ApiResult 標準）。
  Future<ApiResult<WorkModeSettings>> fetchSettingsFromServer() async {
    final guard = await _requireToken<WorkModeSettings>();
    if (guard != null) return guard;
    final headers = await _auth.getAuthHeaders();
    return runApiCall<WorkModeSettings>(
      'WorkModeService.fetchSettingsFromServer',
      () => http.get(
        Uri.parse('$_apiBase/work_settings/my'),
        headers: headers,
      ).timeout(const Duration(seconds: 10)),
      (body) {
        final data = apiJsonMap(body) ?? <String, dynamic>{};
        return WorkModeSettings.fromJson(
            (data['setting'] ?? data['settings']) as Map<String, dynamic>? ?? data);
      },
    );
  }

  /// 勤務設定を「サーバ優先・失敗時はローカル」で取る。
  /// ★これは通信メソッドではなく方針メソッド。ApiResult を返さないのは、
  ///   呼び手（punch_screen）が常に非 null の設定を必要とし、統一前から
  ///   「取れなければローカル値で描く」という約束で動いているため。
  ///   通信の成否を見たい呼び手は fetchSettingsFromServer() を直接使う。
  Future<WorkModeSettings> fetchFromServer() async {
    final r = await fetchSettingsFromServer();
    final settings = r.data;
    if (r.ok && settings != null) {
      await save(settings);
      return settings;
    }
    return load();
  }

  // ── 解決済み勤怠設定（/attendance 系のためこのサービスに置く）───────────
  // GET /attendance/settings/resolved → person→department→global を項目ごとにマージ済みの1件。
  // BE: routes/attendance.js の GET /settings/resolved（services/attendanceSettings.js が解決）。
  // 打刻のお知らせ（punch_remind_*）は会社が決める統治項目で、本人は変更できない。
  //   この画面はそれを「読むだけ」＝表示用にここから取る。
  Future<ApiResult<Map<String, dynamic>>> fetchResolvedAttendanceSettings() async {
    final guard = await _requireToken<Map<String, dynamic>>();
    if (guard != null) return guard;
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'WorkModeService.fetchResolvedAttendanceSettings',
      () => http.get(
        Uri.parse('$_apiBase/attendance/settings/resolved'),
        headers: headers,
      ).timeout(const Duration(seconds: 10)),
      apiJsonMap,
    );
  }

  // ── 会社休日カレンダー（/attendance 系のためこのサービスに置く）─────────
  // GET /attendance/holidays/my
  // BE: routes/attendance.js の GET /attendance/holidays/my（employee 限定・cooperation は 403 COOPERATION_FORBIDDEN）。
  // ★data が null かどうかで「取れなかった」と「休日ゼロ」を区別できる。
  Future<ApiResult<CompanyHolidays>> fetchCompanyHolidays() async {
    final guard = await _requireToken<CompanyHolidays>();
    if (guard != null) return guard;
    final headers = await _auth.getAuthHeaders();
    return runApiCall<CompanyHolidays>(
      'WorkModeService.fetchCompanyHolidays',
      () => http.get(
        Uri.parse('$_apiBase/attendance/holidays/my'),
        headers: headers,
      ).timeout(const Duration(seconds: 10)),
      (body) {
        final data = apiJsonMap(body);
        return CompanyHolidays(
          weekly: _asStringMap(data?['weekly']),
          dates:  _asStringMap(data?['dates']),
        );
      },
    );
  }

  // GET /attendance/holidays/jp?year=YYYY → { dates: {"YYYY-MM-DD": 祝日名}, year, count }
  // BE: routes/attendance.js の GET /attendance/holidays/jp。★/holidays/my の dates は値が 'legal'|'scheduled' だが、
  //     こちらの dates は値が【祝日名の文字列】。用途が違うので混同しないこと
  //     （こちらは文字色＝朱の判定にのみ使い、会社の休業設定とは無関係）。
  // 取得は年単位（月ではない）。失敗時は呼び出し側が祝日色なしで描画を続行できる。
  Future<ApiResult<Map<String, String>>> fetchJpHolidays(int year) async {
    final guard = await _requireToken<Map<String, String>>();
    if (guard != null) return guard;
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, String>>(
      'WorkModeService.fetchJpHolidays',
      () => http.get(
        Uri.parse('$_apiBase/attendance/holidays/jp?year=$year'),
        headers: headers,
      ).timeout(const Duration(seconds: 10)),
      (body) => _asStringMap(apiJsonMap(body)?['dates']),
    );
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

  /// 当日（業務日）の勤怠行を取る。
  /// shiftType は 'day'|'night'。BE は未指定＝day 互換（routes/attendance.js の GET /today）
  /// なので、送っていない旧クライアントの挙動は変わらない。
  /// 不正値はここで 'day' に倒す（BE へ想定外の値を投げない）。
  Future<ApiResult<TodayAttendance>> fetchToday({String shiftType = 'day'}) async {
    final guard = await _requireToken<TodayAttendance>();
    if (guard != null) return guard;
    final shift = shiftType == 'night' ? 'night' : 'day';
    final headers = await _auth.getAuthHeaders();
    return runApiCall<TodayAttendance>(
      'WorkModeService.fetchToday',
      () => http.get(
        Uri.parse('$_apiBase/attendance/today?shift_type=$shift'),
        headers: headers,
      ).timeout(const Duration(seconds: 10)),
      (body) {
        final data = apiJsonMap(body);
        return TodayAttendance(
          record:           data?['record']             as Map<String, dynamic>?,
          punchedIn:        data?['punched_in']         as bool? ?? false,
          punchedOut:       data?['punched_out']        as bool? ?? false,
          standardBreakMin: data?['standard_break_min'] as int?,
          legalBreak6h:    (data?['legal_break_6h_min'] as int?) ?? 45,
          legalBreak8h:    (data?['legal_break_8h_min'] as int?) ?? 60,
        );
      },
    );
  }

  /// POST /attendance/punch。data は応答の record。
  /// shift_type は BE が受ける（'day'|'night'・省略時 day）。
  /// 夜勤は BE 側 businessDateForShift で始業日に寄せられ、出勤/退勤が同一行に収まる。
  Future<ApiResult<Map<String, dynamic>>> punch(String type,
      {double? lat, double? lng, String? addr, String shiftType = 'day'}) async {
    final guard = await _requireToken<Map<String, dynamic>>();
    if (guard != null) return guard;
    final payload = <String, dynamic>{'type': type, 'shift_type': shiftType};
    if (lat  != null) payload['lat']  = lat;
    if (lng  != null) payload['lng']  = lng;
    if (addr != null) payload['addr'] = addr;
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'WorkModeService.punch',
      () => http.post(
        Uri.parse('$_apiBase/attendance/punch'),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10)),
      (body) => apiJsonMap(body)?['record'] as Map<String, dynamic>?,
    );
  }

  /// POST /attendance/break-request
  /// N6: shift_type は BE が受ける（'day'|'night'）。同日に日勤/夜勤の2行が並存しうるため、
  ///   これが無いと申告が両方の行へ二重適用される。BE 側は未指定・不正値とも 'day' に倒す
  ///   ＝送っていない旧クライアントの挙動は不変。不正値はここでも 'day' に倒す。
  Future<ApiResult<Map<String, dynamic>>> breakRequest({
    required int breakMinutes,
    required String reason,
    String? workDate,
    String shiftType = 'day',
  }) async {
    final guard = await _requireToken<Map<String, dynamic>>();
    if (guard != null) return guard;
    final payload = <String, dynamic>{
      'break_minutes': breakMinutes,
      'reason':        reason,
      'shift_type':    shiftType == 'night' ? 'night' : 'day',
      if (workDate != null) 'work_date': workDate,
    };
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'WorkModeService.breakRequest',
      () => http.post(
        Uri.parse('$_apiBase/attendance/break-request'),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10)),
      apiJsonMap,
    );
  }

  // ─── 休憩申告の確認・修正側（職長・事務/boss が使う）────────────────────
  //   BE は承認制から申告制へ転換済み:
  //     GET  /attendance/break-requests?month=YYYY-MM  (routes/attendance.js)
  //     POST /attendance/break-request/:id/amend       (routes/attendance.js)
  //   ★旧 /break-requests/pending・/approve・/reject は BE から撤去済み。
  //     呼べない道を「嘘の記号」として残さないため、当メソッド群も削除済み。
  //   権限は MONTHLY_ROLES(admin_office/admin_exec/boss) で、権限不足は 403。

  /// GET /attendance/break-requests?month=YYYY-MM
  /// 応答 {month, requests:[…]} の各行は BE の SELECT 列（routes/attendance.js の GET /attendance/break-requests）そのまま:
  ///   id / person_id / membership_id / work_date('YYYY-MM-DD') / break_override_min /
  ///   break_override_reason / break_override_status / break_override_req_at / person_name
  Future<ApiResult<List<Map<String, dynamic>>>> fetchBreakRequests({required String month}) async {
    final guard = await _requireToken<List<Map<String, dynamic>>>();
    if (guard != null) return guard;
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<Map<String, dynamic>>>(
      'WorkModeService.fetchBreakRequests',
      () => http.get(
        Uri.parse('$_apiBase/attendance/break-requests?month=$month'),
        headers: headers,
      ).timeout(const Duration(seconds: 10)),
      (body) => ((apiJsonMap(body)?['requests'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  /// POST /attendance/break-request/:id/amend   body:{ break_minutes }
  /// 申告された休憩の分数を管理側が修正する。理由・申告時刻は BE 側で保持される
  /// （routes/attendance.js の POST /attendance/break-request/:id/amend）。
  Future<ApiResult<Map<String, dynamic>>> amendBreakRequest(String id, int breakMinutes) async {
    final guard = await _requireToken<Map<String, dynamic>>();
    if (guard != null) return guard;
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'WorkModeService.amendBreakRequest',
      () => http.post(
        Uri.parse('$_apiBase/attendance/break-request/$id/amend'),
        headers: headers,
        body: jsonEncode({'break_minutes': breakMinutes}),
      ).timeout(const Duration(seconds: 10)),
      apiJsonMap,
    );
  }

  // ─── 打刻漏れの申告（打刻のお知らせ通知からの導線）──────────────────────
  //   POST /attendance/forgot-punch-declare  body { side, shift_type, work_date }
  //     201 = 受理   {declared:true, id}
  //     200 = 二度目 {already_declared:true, id}  ★エラーではない（袋小路にしない）
  //     409 code=ALREADY_PUNCHED
  //     400 code=INVALID_SIDE / INVALID_SHIFT_TYPE / INVALID_WORK_DATE
  //     403 code=ATTENDANCE_EMPLOYEE_ONLY
  //   3値はすべて必須。省略すると 400 になるため、呼び手が欠けた値を埋めて
  //   （＝別の日を黙って申告して）しまわないよう、正規化は呼び手側で行う。
  //   ★201 と 200 はどちらも ok:true。「二度目」は statusCode == 200 で判別する
  //     （統一前の alreadyDeclared フィールドと同じ意味・同じ判定式）。
  //   ★409/400/403 の code は errorCode に載る（呼び手の文言分岐の根拠）。
  Future<ApiResult<Map<String, dynamic>>> declareForgotPunch({
    required String side,
    required String shiftType,
    required String workDate,
  }) async {
    final guard = await _requireToken<Map<String, dynamic>>();
    if (guard != null) return guard;
    final payload = <String, dynamic>{
      'side':       side,
      'shift_type': shiftType,
      'work_date':  workDate,
    };
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'WorkModeService.declareForgotPunch',
      () => http.post(
        Uri.parse('$_apiBase/attendance/forgot-punch-declare'),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10)),
      apiJsonMap,
    );
  }

  // ── 月次集計（GET /attendance/monthly-summary）───────────────────────────
  //   ★段6で2画面の重複を1本へ畳んだ:
  //       home_screen.dart（_StaffMonthlySheet・person_id = widget.personId）
  //       monthly_stats_screen.dart（自分の集計・person_id = prefs 'user_id'）
  //     URL・クエリ2キー・15秒・応答をそのまま Map で使う点まで完全一致。
  //     違うのは person_id の出所だけ＝呼び手が引数で渡す形にして吸収する。
  //   ★他メソッドと違い _requireToken ガードを付けていない。移設元の2画面は
  //     どちらもガードを持たず、token が空でも送って BE の 401 を受け、
  //     「認証の有効期限が切れました」を出す作りだったため
  //     （monthly_stats_screen.dart）。ここでガードを足すと同じ状況が
  //     statusCode:0＝「ネットワークエラー」に化ける＝現行の文言が変わる。
  //   ★集計値の計算・判定は一切しない（数字の出所は BE ただ一つ）。
  Future<ApiResult<Map<String, dynamic>>> fetchMonthlySummary({
    required String personId,
    required String month,
  }) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'WorkModeService.fetchMonthlySummary',
      () => http.get(
        Uri.parse(
            '$_apiBase/attendance/monthly-summary?person_id=$personId&month=$month'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ── 勤怠の確認事項（GET /attendance/confirmations?status=pending）─────────
  //   BE: routes/attendance.js の GET /attendance/confirmations。
  //   ★職長も開ける。見えるのは主体が職人・職長の行だけで、事務・社長の分は
  //     BE 側で落ちる（FE では絞らない＝同じ事実を2系統で持たない）。
  //   応答 {confirmations:[…]} の各行は BE の SELECT 列そのまま。使う主なキー:
  //     id / confirm_type / person_name / work_date('YYYY-MM-DD') / created_at /
  //     raw_value / status / punch_in / punch_out /
  //     can_resolve(真偽) / cannot_resolve_reason(英字コード or null)
  //   ★どのキーも「必ずある」とは思わずに読むこと（BE の列が増減しても画面が落ちない）。
  //     職長が受け取る行は全て can_resolve=false・
  //     cannot_resolve_reason='BOSS_CONFIRMATION_FORBIDDEN' になる。
  //   confirm_type は forgot_punch / comp_off / overtime_or_forgot の3種。
  //   返り得る code:
  //     403 FORBIDDEN … 一覧を開けない役割（職人）。errorCode にそのまま載る。
  //     401 系        … 締め出しの受け皿（runApiCall が session_lockout へ通す）。
  //   ★status は既定 'pending'。決着済みを見る画面は無いので呼び手は既定のまま使う。
  //   ★このアプリは【見るだけ】。決着（POST .../resolve）は事務と社長の仕事なので
  //     対応するメソッドを置かない（置くと呼べてしまう＝嘘の記号になる）。
  Future<ApiResult<List<Map<String, dynamic>>>> fetchAttendanceConfirmations({
    String status = 'pending',
  }) async {
    final guard = await _requireToken<List<Map<String, dynamic>>>();
    if (guard != null) return guard;
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<Map<String, dynamic>>>(
      'WorkModeService.fetchAttendanceConfirmations',
      () => http.get(
        Uri.parse('$_apiBase/attendance/confirmations?status=$status'),
        headers: headers,
      ).timeout(const Duration(seconds: 10)),
      (body) => ((apiJsonMap(body)?['confirmations'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}
