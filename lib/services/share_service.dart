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

// ★InboxResult / TamperCheckResult は退役（呼び手だった inbox_screen.dart ごと撤去）。
//   InboxResult.tamperedShares は shares を is_tampered == true で絞る作りだったが、
//   BE の GET /shares/inbox は is_tampered を返さない（返すのは share_status と
//   is_updated）。つまり常に空＝「改ざん0件」を名乗り続ける嘘の記号だった。
//   改ざんの真実源は事件簿（TamperService・GET /tamper/incidents/:id）ただ一つ。

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

  // ★共有トレイの導線（getInbox / getOutbox / markAsRead）は全退役。閲覧画面だった
  //   inbox_screen.dart の撤去で呼び手が0になったため。FIELD に残る共有機能は
  //   送信（sendReport）のみ。受信の閲覧・既読は OFFICE の受信トレイが担う。

  // ★改ざんチェック（POST /shares/check-tamper）は退役した。呼び手だった
  //   inbox_screen.dart（import 0・route 0 の到達不能画面）ごと撤去したため。
  //   なお BE 側の門番は段2で can_audit 基準へ変わっており、FIELD の主利用者
  //   （worker）は元より実行できない。

  // ★改ざん通知一覧の取得（GET /shares/notifications）も退役済み。
  //   改ざん通知は BE の services/notify.js 経由で汎用のお知らせ
  //   （GET /notifications・type='tamper_detected' / 'tamper_status_changed'・
  //     ref_id=incident_id）として届く。FIELD の通知の窓口は
  //   notification_service ただ一つ。
  //   事件の詳細取得と対処（状態変更）は TamperService
  //   （GET /tamper/incidents/:id・PATCH /tamper/incidents/:id/status）が窓口。
}
