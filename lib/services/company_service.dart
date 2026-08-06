// ============================================================
// lib/services/company_service.dart - 会社・現場管理サービス
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
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
      // 沈黙解除: 非200を可視化（認証ヘッダ・トークンは出さない。
      // body先頭のみ・statusCodeのみ）。戻り値(空リスト)は不変。
      final bodyHead = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      debugPrint('searchCompanies 非200: status=${response.statusCode} body=$bodyHead');
      return [];
    } catch (e) {
      // 沈黙解除: 例外を可視化（認証情報は含めない）。戻り値(空リスト)は不変。
      debugPrint('searchCompanies 例外: $e');
      return [];
    }
  }

  // ============================================================
  // 自社の同僚氏名一覧取得（相乗り氏名サジェスト用）
  //   GET /workers/colleagues（パラメータ無し・会社スコープはBEのJWT由来）。
  //   応答 {"success":true,"names":[...]} の names(List<String>) を返す。
  //   非200/例外は空リスト＋debugPrint（秘匿値は出さない・searchCompaniesと同流儀）。
  // ============================================================

  Future<List<String>> getColleagues() async {
    try {
      final headers = await _auth.getAuthHeaders();
      final uri = Uri.parse('$kApiBaseUrl/workers/colleagues');
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['names'] as List? ?? [])
            .map((e) => (e as String).trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      // 沈黙解除: 非200を可視化（認証ヘッダ・トークンは出さない。
      // body先頭のみ・statusCodeのみ）。戻り値(空リスト)は不変。
      final bodyHead = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      debugPrint('getColleagues 非200: status=${response.statusCode} body=$bodyHead');
      return [];
    } catch (e) {
      // 沈黙解除: 例外を可視化（認証情報は含めない）。戻り値(空リスト)は不変。
      debugPrint('getColleagues 例外: $e');
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
}