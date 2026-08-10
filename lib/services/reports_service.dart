// ============================================================
// lib/services/reports_service.dart - 日報通信サービス
//
// ★段4: 戻り値を ApiResult<T> へ統一（規約は api_result.dart 冒頭）。
//   統一前は {'success': bool, 'error': ..., 'statusCode': ..., 'code': ...} の
//   Map 返しで、例外時だけ statusCode と code が欠落する（＝呼び手が
//   「statusCode が無い＝通信失敗」と推測するしかない）作りだった。
//   ApiResult は常に statusCode を持ち、通信不成立を 0 で表す。
//   ★BE の error_code（ALREADY_RESTED / NOT_RESTED 等）は errorCode に載る。
//     呼び手の分岐（rest_day_screen.dart / punch_remind_dialog.dart）は
//     res['code'] → r.errorCode へ読み替えるだけで挙動は不変。
//   URL・body・timeout は1文字も変えていない。
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_result.dart';
import 'auth_service.dart';
import '../config/constants.dart';

/// 日報詳細（report 本体＋active 写真）。
class ReportDetail {
  const ReportDetail({required this.report, required this.photos});
  final dynamic report;
  final List<dynamic> photos;
}

/// 本日休みの状態（GET /rest-days/today）。
class RestDayToday {
  const RestDayToday({
    required this.rested,
    required this.reason,
    required this.portion,
  });
  final bool rested;
  final dynamic reason;

  /// 半休。BE未対応の間は欠落し得るため 'full' 後方互換。
  final String portion;
}

/// 休み登録・更新・取消の結果（rest_date 等）。
class RestDayMutation {
  const RestDayMutation({
    required this.restDate,
    required this.reason,
    required this.cancelled,
  });
  final dynamic restDate;
  final dynamic reason;
  final bool cancelled;
}

class ReportsService {
  static final ReportsService _instance = ReportsService._internal();

  factory ReportsService() {
    return _instance;
  }

  ReportsService._internal();

  final AuthService _auth = AuthService();

  // ============================================================
  // 日報詳細取得（active写真を photos[] 付きで返す）
  // ============================================================

  Future<ApiResult<ReportDetail>> getReportDetail(String reportId) async {
    if (reportId.isEmpty) {
      return apiFailure<ReportDetail>(statusCode: 0, errorMessage: 'report_id なし');
    }
    final headers = await _auth.getAuthHeaders();
    return runApiCall<ReportDetail>(
      'ReportsService.getReportDetail',
      () => http.get(
        Uri.parse('$kApiBaseUrl/reports/$reportId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) {
        final data = apiJsonMap(body);
        return ReportDetail(
          report: data?['report'],
          photos: (data?['photos'] as List?) ?? const [],
        );
      },
    );
  }

  // ============================================================
  // 承認（職長・事務・管理者）。originType指定時のみ body で送る。
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> approveReport(String reportId,
      {String? originType}) async {
    if (reportId.isEmpty) {
      return apiFailure<Map<String, dynamic>>(statusCode: 0, errorMessage: 'report_id なし');
    }
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'ReportsService.approveReport',
      () => http.patch(
        Uri.parse('$kApiBaseUrl/reports/$reportId/approve'),
        headers: headers,
        body: originType != null
            ? jsonEncode({'origin_type': originType})
            : null,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 現場の紐づけ（後付け）。PATCH /reports/:id/site。
  // siteId=null は「対象なし」（現状維持相当）。BE側は content_hash 再計算＋
  // 'edited' イベント追記で改ざん検知に抵触させない実装（reports.js:1287-）。
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> linkReportToSite(
      String reportId, String? siteId) async {
    if (reportId.isEmpty) {
      return apiFailure<Map<String, dynamic>>(statusCode: 0, errorMessage: 'report_id なし');
    }
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'ReportsService.linkReportToSite',
      () => http.patch(
        Uri.parse('$kApiBaseUrl/reports/$reportId/site'),
        headers: headers,
        body: jsonEncode({'site_id': siteId}),
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 差戻し（修正依頼）。revision_targets はUIが決めた配列をそのまま送る。
  //   ★統一前からここだけ 200系判定だった（>=200 && <300）。ApiResult の
  //     既定と一致するため判定は不変。
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> requestRevision(
      String reportId, List<String> revisionTargets,
      {String reason = ''}) async {
    if (reportId.isEmpty) {
      return apiFailure<Map<String, dynamic>>(statusCode: 0, errorMessage: 'report_id なし');
    }
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'ReportsService.requestRevision',
      () => http.put(
        Uri.parse('$kApiBaseUrl/reports/$reportId/request-revision'),
        headers: headers,
        body: jsonEncode({
          'reason':           reason,
          'revision_targets': revisionTargets,
        }),
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 日報一覧取得（会社スコープ・BEは {success, reports:[...]} を返す）
  // ============================================================

  // GET /reports?date=YYYY-MM&limit=300 — 月指定で取得する（承認タブの日付一覧用）。
  // 既存 getReports は limit のみで直近50件しか取れず、承認待ちが51件目以降に
  // あると見えなかった。月指定でその構造的な取りこぼしを解消する。
  Future<ApiResult<List<dynamic>>> getReportsByMonth(String month, {int limit = 300}) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<dynamic>>(
      'ReportsService.getReportsByMonth',
      () => http.get(
        Uri.parse('$kApiBaseUrl/reports?date=$month&limit=$limit'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => (apiJsonMap(body)?['reports'] as List?) ?? const [],
    );
  }

  Future<ApiResult<List<dynamic>>> getReports({int limit = 50}) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<dynamic>>(
      'ReportsService.getReports',
      () => http.get(
        Uri.parse('$kApiBaseUrl/reports?limit=$limit'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => (apiJsonMap(body)?['reports'] as List?) ?? const [],
    );
  }

  // ============================================================
  // 本日休み（rest_days）— GET/POST/PATCH/DELETE の4本。
  // 非200は握り潰さず statusCode + errorCode(BE の code) を載せて返す。
  // ============================================================

  // GET /rest-days/my?month=YYYY-MM → { days: [ {rest_date,reason,portion} ] }
  // 本人の月次の休み一覧（カレンダー表示用・BE routes/rest_days.js:276）。
  // 取消済(cancelled_at)は BE 側で除外済み＝返るのは「いま有効な休み」だけ。
  Future<ApiResult<List<Map<String, dynamic>>>> getRestDaysMy(String month) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<Map<String, dynamic>>>(
      'ReportsService.getRestDaysMy',
      () => http.get(
        Uri.parse('$kApiBaseUrl/rest-days/my?month=$month'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => ((apiJsonMap(body)?['days'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  // GET /rest-days/today → { rested: bool, reason: string|null }
  Future<ApiResult<RestDayToday>> getRestDayToday() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<RestDayToday>(
      'ReportsService.getRestDayToday',
      () => http.get(
        Uri.parse('$kApiBaseUrl/rest-days/today'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) {
        final data = apiJsonMap(body);
        return RestDayToday(
          rested:  data?['rested'] == true,
          reason:  data?['reason'],
          portion: (data?['portion'] as String?) ?? 'full',
        );
      },
    );
  }

  // POST /rest-days body {reason?, portion} → 201 成功 / 409 ALREADY_RESTED
  // portion（full/am_half/pm_half）は BE 並行実装中＝未対応の間は無視されるだけで害なし。
  //   ★409 の code は errorCode に載る（呼び手が「すでに休みで登録されています」を出す根拠）。
  Future<ApiResult<RestDayMutation>> createRestDay({String? reason, String portion = 'full'}) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<RestDayMutation>(
      'ReportsService.createRestDay',
      () => http.post(
        Uri.parse('$kApiBaseUrl/rest-days'),
        headers: headers,
        body: jsonEncode({'reason': reason, 'portion': portion}),
      ).timeout(const Duration(seconds: 15)),
      _parseRestDayMutation,
    );
  }

  // PATCH /rest-days/today body {reason, portion} → 200 成功 / 404 NOT_RESTED
  Future<ApiResult<RestDayMutation>> updateRestDay({String? reason, String portion = 'full'}) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<RestDayMutation>(
      'ReportsService.updateRestDay',
      () => http.patch(
        Uri.parse('$kApiBaseUrl/rest-days/today'),
        headers: headers,
        body: jsonEncode({'reason': reason, 'portion': portion}),
      ).timeout(const Duration(seconds: 15)),
      _parseRestDayMutation,
    );
  }

  // DELETE /rest-days/today → 200 成功 / 404 NOT_RESTED
  Future<ApiResult<RestDayMutation>> deleteRestDay() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<RestDayMutation>(
      'ReportsService.deleteRestDay',
      () => http.delete(
        Uri.parse('$kApiBaseUrl/rest-days/today'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      _parseRestDayMutation,
    );
  }

  static RestDayMutation? _parseRestDayMutation(String body) {
    final data = apiJsonMap(body);
    return RestDayMutation(
      restDate:  data?['rest_date'],
      reason:    data?['reason'],
      cancelled: data?['cancelled'] == true,
    );
  }
}
