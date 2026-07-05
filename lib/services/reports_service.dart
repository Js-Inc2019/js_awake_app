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
}
