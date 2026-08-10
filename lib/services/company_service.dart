// ============================================================
// lib/services/company_service.dart - 会社・現場管理サービス
//
// ★段4: 戻り値を ApiResult<T> へ統一（規約は api_result.dart 冒頭）。
//   統一前は同じクラスの中に3流儀が同居していた:
//     ・{'success': bool, 'message': ...} の Map 返し（getCompanies / getCompanyById 他）
//     ・失敗を空リストへ潰す（searchCompanies / getColleagues）
//   後者は「0件」と「取れなかった」が同じ [] になり、呼び手が区別できなかった。
//   URL・body・timeout は1文字も変えていない。
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_result.dart';
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

  Future<ApiResult<List<dynamic>>> getCompanies() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<dynamic>>(
      'CompanyService.getCompanies',
      () => http.get(
        Uri.parse('$kApiBaseUrl/companies'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => (apiJsonMap(body)?['companies'] as List<dynamic>?) ?? const [],
    );
  }

  // ★会社新規登録（POST /companies・admin_exec のみ）は退役した。
  //   FIELD は職人アプリで、会社を作る画面が無い（作れるのは OFFICE 側）。
  //   呼び手ゼロのまま残すと「FIELD からも会社を作れる」と読めてしまう。

  // ============================================================
  // 会社名正規化検索（協力申請の申請先選択用）
  // ============================================================

  Future<ApiResult<List<Map<String, dynamic>>>> searchCompanies(String query) async {
    final headers = await _auth.getAuthHeaders();
    final uri = Uri.parse('$kApiBaseUrl/companies/search')
        .replace(queryParameters: {'q': query});
    return runApiCall<List<Map<String, dynamic>>>(
      'CompanyService.searchCompanies',
      () => http.get(uri, headers: headers).timeout(const Duration(seconds: 10)),
      (body) => ((apiJsonMap(body)?['companies'] as List?) ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList(),
    );
  }

  // ============================================================
  // 自社の同僚氏名一覧取得（相乗り氏名サジェスト用）
  //   GET /workers/colleagues（パラメータ無し・会社スコープはBEのJWT由来）。
  //   応答 {"success":true,"names":[...]} の names(List<String>) を返す。
  // ============================================================

  Future<ApiResult<List<String>>> getColleagues() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<String>>(
      'CompanyService.getColleagues',
      () => http.get(
        Uri.parse('$kApiBaseUrl/workers/colleagues'),
        headers: headers,
      ).timeout(const Duration(seconds: 10)),
      (body) => ((apiJsonMap(body)?['names'] as List?) ?? [])
          .map((e) => (e as String).trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  // ============================================================
  // 会社1件取得（company_id 指定）
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> getCompanyById(String companyId) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'CompanyService.getCompanyById',
      () => http.get(
        Uri.parse('$kApiBaseUrl/companies/$companyId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => apiJsonMap(body)?['company'] as Map<String, dynamic>?,
    );
  }

  // ============================================================
  // 協力申請（company-links）— 段6で company_link_screen から移設
  // ============================================================

  /// 自分の協力申請一覧。
  /// 移設元: company_link_screen.dart:37-40（GET /company-links/my・15秒）
  ///
  /// ★応答 {"links":[...]} の links を返す。取得失敗（ok:false）と
  ///   0件（ok:true・空リスト）は ApiResult が区別する。空リストへ潰さない。
  Future<ApiResult<List<Map<String, dynamic>>>> getMyCompanyLinks() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<Map<String, dynamic>>>(
      'CompanyService.getMyCompanyLinks',
      () => http.get(
        Uri.parse('$kApiBaseUrl/company-links/my'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => ((apiJsonMap(body)?['links'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  /// 協力申請の送信。
  /// 移設元: company_link_screen.dart:74-78（POST /company-links/request・15秒）
  ///
  /// ★移設元は成功を 201 に限っていた（:80）。200 等を成功へ広げると
  ///   「申請を送信しました」の条件が変わるため、その判定は呼び手が
  ///   statusCode で行う（ここでは丸めない）。
  Future<ApiResult<Map<String, dynamic>>> requestCompanyLink(
      String companyId) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'CompanyService.requestCompanyLink',
      () => http.post(
        Uri.parse('$kApiBaseUrl/company-links/request'),
        headers: headers,
        body: jsonEncode({'company_id': companyId}),
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }
}
