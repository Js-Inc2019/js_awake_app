// ============================================================
// lib/services/company_service.dart - 会社・現場管理サービス
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../config/constants.dart';

class CompanyService {
  static final CompanyService _instance = CompanyService._internal();

  factory CompanyService() {
    return _instance;
  }

  CompanyService._internal();

  final AuthService _auth = AuthService();

  // ============================================================
  // 会社一覧取得
  // ============================================================

  Future<Map<String, dynamic>> getCompanies() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/companies'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {
          'success': true,
          'companies': data['companies'] as List<dynamic>,
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 会社間の繋がり一覧取得
  // ============================================================

  Future<Map<String, dynamic>> getRelations() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/companies/relations/list'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {
          'success': true,
          'relations': data['relations'] as List<dynamic>,
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 会社新規登録（admin_execのみ）
  // ============================================================

  Future<Map<String, dynamic>> createCompany({
    required String companyName,
    required String companyCode,
    String? address,
    String? phone,
    String? email,
  }) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/companies'),
        headers: headers,
        body: jsonEncode({
          'company_name': companyName,
          'company_code': companyCode,
          'address': address,
          'phone': phone,
          'email': email,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': '会社を登録しました',
          'company': data['company'],
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 会社名正規化検索（協力申請の申請先選択用）
  // ============================================================

  Future<List<Map<String, dynamic>>> searchCompanies(String query) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final uri = Uri.parse('$kApiBaseUrl/companies/search')
          .replace(queryParameters: {'q': query});
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['companies'] as List? ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ============================================================
  // 会社1件取得（company_id 指定）
  // ============================================================

  Future<Map<String, dynamic>> getCompanyById(String companyId) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$kApiBaseUrl/companies/$companyId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {'success': true, 'company': data['company']};
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }

  // ============================================================
  // 会社間の繋がりを登録（admin_execのみ）
  // ============================================================

  Future<Map<String, dynamic>> addRelation({
    required String companyIdA,
    required String companyIdB,
    String relationType = 'partner',
  }) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/companies/relations/add'),
        headers: headers,
        body: jsonEncode({
          'company_id_a': companyIdA,
          'company_id_b': companyIdB,
          'relation_type': relationType,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': '会社間の繋がりを登録しました',
        };
      }

      return {'success': false, 'message': data['error'] ?? 'エラーが発生しました'};
    } catch (e) {
      return {'success': false, 'message': 'サーバーに接続できません: $e'};
    }
  }
}