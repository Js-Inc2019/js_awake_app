// ============================================================
// lib/services/tamper_service.dart - 改ざん事件簿サービス
//
// BE: routes/tamper.js（段2で新設）。
//   ・GET   /tamper/incidents/:incident_id        … 事件の詳細
//   ・PATCH /tamper/incidents/:incident_id/status … 対処（状態遷移）
//   門番は admin_exec または can_audit 保持者。権限が無ければ 403、
//   自社が当事者でない事件は 404（存在を漏らさない）。
//
// ★(c)束の掟: 全HTTPは runApiCall + ApiResult<T> 経由。ヘッダは AuthService の
//   集約関数 getAuthHeaders() のみ（手書き Authorization を作らない）。
//   非200・通信断は runApiCall が statusCode / errorCode に載せて返すため、
//   本ファイルに try/catch は置かない（沈黙障害を作らない）。
//
// ★遷移規則は BE が真実源（open→investigating / open→resolved /
//   investigating→resolved・resolved は終着で 409 ALREADY_RESOLVED）。
//   本サービスは規則を持たず、呼び手が statusCode + errorCode で文言を決める
//   （api_result.dart 冒頭の規約6）。
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_result.dart';
import 'auth_service.dart';
import '../config/constants.dart';

class TamperService {
  static final TamperService _instance = TamperService._internal();

  factory TamperService() {
    return _instance;
  }

  TamperService._internal();

  final AuthService _auth = AuthService();

  // ============================================================
  // 事件の詳細
  //   応答: { success, incident: {...} }
  //   incident のキー: incident_id / status / target_type / bundle_id / report_id /
  //     sender_company_id / sender_company_name / bundle_title /
  //     worker_name / report_date / site_name / work_content / gps_address /
  //     detected_at / detected_by / detected_by_name / detected_via /
  //     hash_before / hash_after / resolved_by / resolved_by_name / resolved_at /
  //     resolution_note
  //   ★BE(v550・migrate_v74)で旧・単発共有が器ごと退役した。これに伴い:
  //     ・receiver_company_name は応答から【消えた】（まとめ共有は受信社が複数社ありうる）。
  //     ・target_type は常に 'bundle' の固定値（'share' はもう返らない）。
  //     ・share_id は列ごと撤去され応答に載らない。
  //     ・detected_via は 'bundle_view' のみ（'manual_check' の生成元は退役済み）。
  //   404=自社が当事者でない or 不在、403=監査権限なし（呼び手が出し分ける）。
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> getIncidentDetail(
      String incidentId) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'TamperService.getIncidentDetail',
      () => http.get(
        Uri.parse('$kApiBaseUrl/tamper/incidents/$incidentId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => apiJsonMap(body)?['incident'] as Map<String, dynamic>?,
    );
  }

  // ============================================================
  // 対処（状態遷移）
  //   body = { status, resolution_note? }
  //   ★resolutionNote が null のときは body に積まない。
  //     BE は「未指定＝既存値を維持」と解釈するため、null を送って
  //     既存のメモを消してしまわないようにする。
  //   応答: { success, incident: {...更新後...} }
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> updateIncidentStatus(
    String incidentId, {
    required String status,
    String? resolutionNote,
  }) async {
    final headers = await _auth.getAuthHeaders();
    final body = <String, dynamic>{'status': status};
    if (resolutionNote != null) body['resolution_note'] = resolutionNote;

    return runApiCall<Map<String, dynamic>>(
      'TamperService.updateIncidentStatus',
      () => http.patch(
        Uri.parse('$kApiBaseUrl/tamper/incidents/$incidentId/status'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15)),
      (b) => apiJsonMap(b)?['incident'] as Map<String, dynamic>?,
    );
  }
}
