// ============================================================
// lib/services/share_service.dart - 会社間報告サービス
//
// ★段4: 戻り値を ApiResult<T> へ統一（規約は api_result.dart 冒頭）。
//   統一前は {'success': bool, 'message': String} の Map 返しで、
//   HTTP ステータスがどこにも載らず、呼び手は 403（権限なし）と
//   通信断を区別できなかった。URL・body・timeout は1文字も変えていない。
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_result.dart';
import 'auth_service.dart';
import '../config/constants.dart';

/// 受信トレイの取得結果。改ざん件数は shares から導けるが、
/// 呼び手が毎回同じ where を書かずに済むよう統一前と同じ形で持たせる。
class InboxResult {
  const InboxResult({
    required this.shares,
    required this.tamperedShares,
  });

  final List<dynamic> shares;
  final List<dynamic> tamperedShares;

  int get tamperedCount => tamperedShares.length;
}

/// 改ざんチェックの結果。
/// ★「確認できなかった」を「正常」に混ぜないための型。
///   通信失敗・非200 は ApiResult 側の ok:false で表すため、
///   この型は成功時（200）にだけ現れる。
class TamperCheckResult {
  const TamperCheckResult({required this.isTampered, required this.message});

  final bool isTampered;
  final String message;
}

class ShareService {
  static final ShareService _instance = ShareService._internal();

  factory ShareService() {
    return _instance;
  }

  ShareService._internal();

  final AuthService _auth = AuthService();

  // ============================================================
  // 日報を他社に送信する
  // 職長（boss）・事務（admin_office・admin_exec）のみ可能
  //   ★成功は 201。ApiResult は 200系を成功とするため自然に吸収される。
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> sendReport({
    required String reportId,
    required String receiverCompanyId,
    String shareType = 'in_app',
    String? memo,
  }) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'ShareService.sendReport',
      () => http.post(
        Uri.parse('$kApiBaseUrl/shares/send'),
        headers: headers,
        body: jsonEncode({
          'report_id':          reportId,
          'receiver_company_id': receiverCompanyId,
          'share_type':         shareType,
          'memo':               memo,
        }),
      ).timeout(const Duration(seconds: 15)),
      (body) => apiJsonMap(body)?['share'] as Map<String, dynamic>?,
    );
  }

  // ============================================================
  // 受信した日報一覧取得（受信トレイ）
  // ============================================================

  Future<ApiResult<InboxResult>> getInbox() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<InboxResult>(
      'ShareService.getInbox',
      () => http.get(
        Uri.parse('$kApiBaseUrl/shares/inbox'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) {
        final shares = (apiJsonMap(body)?['shares'] as List<dynamic>?) ?? const [];
        // 改ざん検知：is_tamperedがtrueのものを抽出
        return InboxResult(
          shares: shares,
          tamperedShares: shares.where((s) => s['is_tampered'] == true).toList(),
        );
      },
    );
  }

  // ============================================================
  // 送信した日報一覧取得（送信トレイ）
  // ============================================================

  Future<ApiResult<List<dynamic>>> getOutbox() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<dynamic>>(
      'ShareService.getOutbox',
      () => http.get(
        Uri.parse('$kApiBaseUrl/shares/outbox'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => (apiJsonMap(body)?['shares'] as List<dynamic>?) ?? const [],
    );
  }

  // ============================================================
  // 既読にする
  // ============================================================

  Future<ApiResult<Map<String, dynamic>>> markAsRead(String shareId) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'ShareService.markAsRead',
      () => http.put(
        Uri.parse('$kApiBaseUrl/shares/$shareId/read'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 改ざんチェック（手動）
  // ============================================================

  /// 改ざんチェック（手動）。
  /// ★確認失敗を「正常」に混同させない、という統一前からの約束は不変:
  ///   ・通信失敗／非200            → ok:false（data は null）
  ///   ・200 だが is_tampered が bool でない → ok:false（判定不能を正常にしない）
  ///   ・200 かつ bool              → ok:true・data.isTampered で分岐
  Future<ApiResult<TamperCheckResult>> checkTamper(String shareId) async {
    final headers = await _auth.getAuthHeaders();
    final r = await runApiCall<TamperCheckResult>(
      'ShareService.checkTamper',
      () => http.post(
        Uri.parse('$kApiBaseUrl/shares/check-tamper'),
        headers: headers,
        body: jsonEncode({'share_id': shareId}),
      ).timeout(const Duration(seconds: 15)),
      (body) {
        final data = apiJsonMap(body);
        final tampered = data?['is_tampered'];
        // 200 でも is_tampered が bool でなければ判定不能 → 安全側で失敗扱い
        if (tampered is! bool) return null;
        return TamperCheckResult(
          isTampered: tampered,
          message: (data?['message'] as String?) ??
              (tampered ? '改ざんが検知されました' : '正常です'),
        );
      },
    );
    // parse が null を返した＝200 だが判定不能。ok:true のまま返すと
    // 「確認できなかった」が「正常」に化けるため、ここで失敗へ倒す。
    if (r.ok && r.data == null) {
      return apiFailure<TamperCheckResult>(
        statusCode: r.statusCode,
        errorMessage: '確認結果を取得できませんでした',
      );
    }
    return r;
  }

  // ★改ざん通知一覧の取得（GET /shares/notifications）は退役した。呼び手ゼロ。
  //   FIELD の通知一覧は notification_service（GET /notifications）が唯一の窓口で、
  //   改ざん通知もその中に含まれて届く。ここに2本目の窓口を残す理由が無い。
}
