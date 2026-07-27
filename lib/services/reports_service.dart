// ============================================================
// lib/services/reports_service.dart - 日報通信サービス
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../config/constants.dart';

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

  Future<Map<String, dynamic>> getReportDetail(String reportId) async {
    if (reportId.isEmpty) {
      return {'success': false, 'error': 'report_id なし'};
    }

    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/reports/$reportId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {
          'success': true,
          'report':  data['report'],
          'photos':  (data['photos'] as List?) ?? [],
        };
      }

      return {
        'success':    false,
        'error':      data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 承認（職長・事務・管理者）。originType指定時のみ body で送る。
  // ============================================================

  Future<Map<String, dynamic>> approveReport(String reportId,
      {String? originType}) async {
    if (reportId.isEmpty) {
      return {'success': false, 'error': 'report_id なし'};
    }

    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.patch(
        Uri.parse('$kApiBaseUrl/reports/$reportId/approve'),
        headers: headers,
        body: originType != null
            ? jsonEncode({'origin_type': originType})
            : null,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {'success': true};
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success':    false,
        'error':      data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 現場の紐づけ（後付け）。PATCH /reports/:id/site。
  // siteId=null は「対象なし」（現状維持相当）。BE側は content_hash 再計算＋
  // 'edited' イベント追記で改ざん検知に抵触させない実装（reports.js:1287-）。
  // ============================================================

  Future<Map<String, dynamic>> linkReportToSite(
      String reportId, String? siteId) async {
    if (reportId.isEmpty) {
      return {'success': false, 'error': 'report_id なし'};
    }

    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.patch(
        Uri.parse('$kApiBaseUrl/reports/$reportId/site'),
        headers: headers,
        body: jsonEncode({'site_id': siteId}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {'success': true};
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success':    false,
        'error':      data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 差戻し（修正依頼）。revision_targets はUIが決めた配列をそのまま送る。
  // ============================================================

  Future<Map<String, dynamic>> requestRevision(
      String reportId, List<String> revisionTargets,
      {String reason = ''}) async {
    if (reportId.isEmpty) {
      return {'success': false, 'error': 'report_id なし'};
    }

    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.put(
        Uri.parse('$kApiBaseUrl/reports/$reportId/request-revision'),
        headers: headers,
        body: jsonEncode({
          'reason':           reason,
          'revision_targets': revisionTargets,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true};
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success':    false,
        'error':      data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 日報一覧取得（会社スコープ・BEは {success, reports:[...]} を返す）
  // ============================================================

  Future<Map<String, dynamic>> getReports({int limit = 50}) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/reports?limit=$limit'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {
          'success': true,
          'reports': (data['reports'] as List?) ?? [],
        };
      }

      return {
        'success':    false,
        'error':      data['error'] ?? 'エラー',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 本日休み（rest_days）— GET/POST/PATCH/DELETE の4本。
  // 非200は握り潰さず success:false + statusCode + code(BE error_code) を返す。
  // ============================================================

  // GET /rest-days/today → { rested: bool, reason: string|null }
  Future<Map<String, dynamic>> getRestDayToday() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/rest-days/today'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {
          'success': true,
          'rested':  data['rested'] == true,
          'reason':  data['reason'],
        };
      }
      return {
        'success':    false,
        'error':      data['error'] ?? 'エラー',
        'code':       data['code'],
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // POST /rest-days body {reason?} → 201 成功 / 409 ALREADY_RESTED
  Future<Map<String, dynamic>> createRestDay({String? reason}) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/rest-days'),
        headers: headers,
        body: jsonEncode({'reason': reason}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) {
        return {
          'success':   true,
          'rest_date': data['rest_date'],
          'reason':    data['reason'],
        };
      }
      return {
        'success':    false,
        'error':      data['error'] ?? 'エラー',
        'code':       data['code'],
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // PATCH /rest-days/today body {reason} → 200 成功 / 404 NOT_RESTED
  Future<Map<String, dynamic>> updateRestDay({String? reason}) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.patch(
        Uri.parse('$kApiBaseUrl/rest-days/today'),
        headers: headers,
        body: jsonEncode({'reason': reason}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {
          'success':   true,
          'rest_date': data['rest_date'],
          'reason':    data['reason'],
        };
      }
      return {
        'success':    false,
        'error':      data['error'] ?? 'エラー',
        'code':       data['code'],
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // DELETE /rest-days/today → 200 成功 / 404 NOT_RESTED
  Future<Map<String, dynamic>> deleteRestDay() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$kApiBaseUrl/rest-days/today'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {
          'success':   true,
          'rest_date': data['rest_date'],
          'cancelled': data['cancelled'] == true,
        };
      }
      return {
        'success':    false,
        'error':      data['error'] ?? 'エラー',
        'code':       data['code'],
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
