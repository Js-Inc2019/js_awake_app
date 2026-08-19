// ============================================================
// lib/services/bundles_service.dart - まとめて共有（束）サービス
//
// ★存在理由:
//   BE の routes/bundles.js（8エンドポイント）に対する FIELD 側の窓口。
//   複数日報を1束にして1社以上へ送る／受け取る系統。
//   ★かつて併存していた旧・単発共有（/shares 系）は完全に退役した:
//     ・FE（旧 share_screen.dart + share_service.dart）は本工事で撤去。
//     ・BE も v550 で routes/shares.js ごと撤去し、migrate_v74 で
//       report_shares / share_site_links をテーブルごと DROP した。
//     FIELD の会社間共有はこの /bundles 系ただ一本で、復活する余地はもう無い。
//
// ★規約は api_result.dart 冒頭ただ一つ。全メソッドが runApiCall を通し、
//   ApiResult<T> を返す。timeout は既定15秒（規約5）。
//   FE で意味を作らない＝errorCode は BE の code をそのまま運ぶ（規約6）。
//   文言分岐（REPORT_NOT_OWNED / SELF_SHARE_NOT_ALLOWED / PERMISSION_DENIED 等）は
//   呼び手が statusCode + errorCode の組で決める。
//
// ★このクラスは通信の運び屋。prefs も画面遷移も持たない
//   （profile_service.dart:12-14 と同じ方針）。
//
// ── BE 側の門番（js-office-api HEAD=05e9afe「段階3第2歩=門番統一」で実測）─────
//   門番は2本に統一されている。判定順はどちらも
//     (1) cooperation は無条件 403 COOPERATION_NOT_ALLOWED（bundles.js:388-398）
//     (2) role=='master' は 403（:405-416・信頼設計＝運営はテナント業務を見ない）
//     (3) admin_exec / admin_office は鍵なしで通過
//     (4) boss / worker は鍵で判定
//     (5) それ以外の role（null・未知）は 403（fail-close）
//   ・見る門番 blockShareViewer（:458-481）… can_share_view
//       → GET /inbox（:530）/ GET /outbox（:619）/ GET /receipts（:729）/
//         GET /:bundle_id（:969）
//   ・処理門番 blockShareManager（:483-508）… can_share_view AND can_share_manage
//       → PATCH /receipts/:id/site（:843）/ PATCH /receipts/:id/read（:928）/
//         POST /:bundle_id/confirm（:1179）
//   ・送る … requirePermission('can_share_send')（:149・門番統一の対象外＝据え置き）
//   ★403 応答には required（'can_share_view' / 'can_share_manage'）が載る（:472 / :497）。
//     両方欠けている場合は先に要る方（見る鍵）が返る＝人が1つずつ埋められる順序。
//   ★鍵は JWT に載っていないため BE が membership_id 起点で毎回 DB 直読みする
//     （fetchShareKeys :422-448・status='active' 限定・DB エラー時は拒否側へ倒す）。
//     ＝FE 側で鍵をキャッシュしても最終判定はここ。FE の鍵は「入口を出すかどうか」だけに使う。
//   ★段階3より前は「worker は無条件 403（旧裁定Q17a）」だった。鍵を配れば職長・職人も
//     開ける形に変わっている（:537-540 のコメントが根拠）。
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_result.dart';
import 'auth_service.dart';
import '../config/constants.dart';

class BundlesService {
  static final BundlesService _instance = BundlesService._internal();

  factory BundlesService() {
    return _instance;
  }

  BundlesService._internal();

  final AuthService _auth = AuthService();

  // ============================================================
  // 送信（POST /bundles/send）
  // ============================================================

  /// 自社の複数日報を1束にまとめ、1社以上へ送る。
  /// BE: routes/bundles.js:149-385（成功は 201・門番 requirePermission('can_share_send')）
  ///
  /// ★呼び手は share_send_screen.dart:422（確認画面で「送信する」を押した後）の1箇所のみ。
  ///   共有タブの送信タイル（share_hub_screen.dart:323-）はその画面への導線で、
  ///   ここを直接は叩かない。受信側の2枚（受信トレイ／送信済み）と同じ1本の
  ///   サービスで /bundles 系を閉じている。
  ///
  /// ★[initialAxis] は date / site / worker のみ（bundles.js:29 VALID_AXES）。
  ///   null を送ると BE が 'date' を既定にする（:170）。3値以外は 400 INVALID_AXIS。
  /// ★[reportIds] / [receiverCompanyIds] は非空。空だと 400
  ///   REPORT_IDS_REQUIRED / RECEIVERS_REQUIRED。重複は BE が除去する（:163-164）。
  /// ★自社宛の混入は 400 SELF_SHARE_NOT_ALLOWED、他社/不在の日報混入は
  ///   403 REPORT_NOT_OWNED、送信先不在は 404 RECEIVER_NOT_FOUND。
  ///   どれも「1件でも駄目なら全体を通さない」＝部分送信は起きない。
  /// ★data は {bundle_id, report_count, receiver_count}。
  ///   ★bundle_hash は BE(v550・裁定Q9)で BUNDLE_FIELDS から外れた（応答3経路とも）。
  ///     生ハッシュは配らない方針で、健全性は束詳細の bundle_integrity が畳んで返す。
  Future<ApiResult<Map<String, dynamic>>> sendBundle({
    required List<String> reportIds,
    required List<String> receiverCompanyIds,
    String? initialAxis,
    bool includePhotos = false,
    String? title,
    String? memo,
  }) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'BundlesService.sendBundle',
      () => http.post(
        Uri.parse('$kApiBaseUrl/bundles/send'),
        headers: headers,
        body: jsonEncode({
          'report_ids':           reportIds,
          'receiver_company_ids': receiverCompanyIds,
          'initial_axis':         initialAxis,
          'include_photos':       includePhotos,
          'title':                title,
          'memo':                 memo,
        }),
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 一覧（GET /bundles/inbox・/outbox・/receipts）
  // ============================================================

  /// 自社宛の束一覧（封筒ごと・受信側）。
  /// BE: routes/bundles.js:530-604（門番 blockShareViewer・応答 {success, bundles:[...]}）
  ///
  /// ★既読の数字は全て【枚数】（裁定Q5）。read_count は「読了した日報の件数」で
  ///   分母は my_report_count（＝その束のうち自社宛の日報総数）。report_count は
  ///   束に入っている日報の総数で受信社スコープではない＝read_count の分母ではない。
  ///   混同すると「n枚中m枚」が嘘になる。
  /// ★my_read_count は read_count と同値の過渡期キー（BE 段階3で退役候補）。
  ///   新しい呼び手は read_count を使う。
  /// ★confirmed_count / my_confirmed_at だけは【人数・人単位】（確認は既読と別の事実）。
  /// ★created_at は【束の作成時刻】。GET /receipts の report_created_at
  ///   （日報の提出時刻）とは別の事実。
  /// ★取得失敗（ok:false）と0件（ok:true・空リスト）は ApiResult が区別する。
  ///   空リストへ潰さない。
  Future<ApiResult<List<Map<String, dynamic>>>> getInbox() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<Map<String, dynamic>>>(
      'BundlesService.getInbox',
      () => http.get(
        Uri.parse('$kApiBaseUrl/bundles/inbox'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => ((apiJsonMap(body)?['bundles'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  /// 自社が送信した束一覧（送信側）。受信社ごとの状態が receivers に入る。
  /// BE: routes/bundles.js の GET /bundles/outbox
  ///     （門番 blockShareViewer・応答 {success, bundles:[...]}）
  ///
  /// ★門番は【見る門番】。旧 blockOutboxViewer（can_share_send OR 役職）は
  ///   段階3で退役した＝送る鍵を持たない人でも「自社が誰へ何を送ったか」は見える。
  /// ★1件は {bundle_id, title, initial_axis, include_photos,
  ///   created_at, report_count, receivers:[...]}。receivers[] は
  ///   {receiver_company_id, company_name, bundle_status, received_at,
  ///    read_count, report_count, confirmed_count}。
  ///   ★bundle_hash は BE(v550・裁定Q9)で応答から外れた（判断材料は束詳細の
  ///     bundle_integrity）。receiver_company_id と bundle_status は現役。
  /// ★receivers[].read_count / report_count の数え方は GET /:bundle_id の
  ///   receivers と完全に同一（同じ事実を2画面が別々に数えて食い違わないため）。
  ///   ここでも read_count は【枚数】・confirmed_count は【人数】。
  Future<ApiResult<List<Map<String, dynamic>>>> getOutbox() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<Map<String, dynamic>>>(
      'BundlesService.getOutbox',
      () => http.get(
        Uri.parse('$kApiBaseUrl/bundles/outbox'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => ((apiJsonMap(body)?['bundles'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  /// 受信箱（日報1枚ごとに1行）。自社が受信社の受信明細だけが返る。
  /// BE: routes/bundles.js:729-819（門番 blockShareViewer・応答 {success, receipts:[...]}）
  ///
  /// ★応答キーは18個の白リスト射影（bundles.js:793-812 の map が唯一の真実）:
  ///   receipt_id / bundle_id / report_id / receipt_status / sent_at / read_at /
  ///   sender_company_id / sender_company_name / sender_name / worker_name /
  ///   report_date / site_name / work_content / gps_address / report_created_at /
  ///   link_site_id / link_site_name / is_updated
  /// ★生の content_hash は出ない。原本が送信後に直されたかは is_updated（真偽値）に
  ///   畳んで届く。日報1枚ごとの印は receipt_status + read_at + is_updated の3つから
  ///   画面が組み立てる（日報単位の confirmed は存在しない＝裁定Q10）。
  /// ★site_name（送信社が書いた現場名）と link_site_name（受信社が自社台帳へ
  ///   紐付けた名前）は別物。片方だけでは「うちのどの現場の話か」が決まらない。
  /// ★report_created_at は日報の提出時刻（reports.created_at）。
  /// ★並びは BE が sent_at DESC → report_date DESC → worker_name ASC（:790-791）。
  ///   FE で並べ替え直さない（時系列の根拠を2箇所に持たない）。
  Future<ApiResult<List<Map<String, dynamic>>>> getReceipts() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<List<Map<String, dynamic>>>(
      'BundlesService.getReceipts',
      () => http.get(
        Uri.parse('$kApiBaseUrl/bundles/receipts'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      (body) => ((apiJsonMap(body)?['receipts'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  // ============================================================
  // 受信明細の操作（PATCH /bundles/receipts/:receipt_id/...）
  //   ★どちらも処理門番 blockShareManager（view AND manage）。
  // ============================================================

  /// 受信した日報に自社の現場を紐付ける／解除する。
  /// BE: routes/bundles.js:843-926（応答 {success, message, receipt, site_name}）
  ///
  /// ★[siteId] に null を渡すと解除（BE は site_id / linked_by / linked_at の3列を
  ///   まとめて null に戻す）。キーごと未送信は 400 なので、この実装は null でも
  ///   必ず 'site_id' キーを載せる。ここを「null なら省く」に変えると解除できなくなる。
  /// ★自社 sites に無い site_id は 404（他社現場の存在自体を漏らさないため 403 では
  ///   ない）。受信明細が自社宛でない場合も同じ 404（fetchOwnReceipt）。
  /// ★原本 reports は書き換わらない。紐付けは受信明細側だけの事実で、原本へ書くと
  ///   content_hash が動いて改ざん扱いになる。
  /// ★data は応答全体。receipt は7キー（receipt_id / receipt_status / site_id /
  ///   linked_by / linked_at / read_at / read_by＝config/responseFields.js:268-276）。
  ///   紐付けた現場名は receipt ではなく応答直下の site_name に入る。
  Future<ApiResult<Map<String, dynamic>>> linkReceiptSite({
    required String receiptId,
    required String? siteId,
  }) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'BundlesService.linkReceiptSite',
      () => http.patch(
        Uri.parse('$kApiBaseUrl/bundles/receipts/$receiptId/site'),
        headers: headers,
        body: jsonEncode({'site_id': siteId}),
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  /// 受信した日報を既読にする（日報を開いた時に1枚ずつ呼ぶ）。
  /// BE: routes/bundles.js:928-951（応答 {success, receipt}）
  ///
  /// ★冪等。read_at / read_by は COALESCE で【初回】を保ち、2回目以降は何も動かない。
  ///   よって呼び手は「既読かどうか」を先に判定しなくてよい。
  /// ★receipt_status が 'read' になるのは今が 'sent' のときだけ。
  ///   'updated'（送信後に原本が直された）と 'tampered'（改ざん検知）は既読より
  ///   優先して伝えるべき事実なので上書きされない＝画面は状態をそのまま出せばよい。
  /// ★body は無い（PATCH だが送るものが無い）。
  /// ★data は応答全体。receipt は上記7キー（RECEIPT_FIELDS）。
  Future<ApiResult<Map<String, dynamic>>> markReceiptRead(String receiptId) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'BundlesService.markReceiptRead',
      () => http.patch(
        Uri.parse('$kApiBaseUrl/bundles/receipts/$receiptId/read'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 束1件（GET /bundles/:bundle_id・POST /bundles/:bundle_id/confirm）
  // ============================================================

  /// 束詳細。送信社でも受信社でもなければ 404。
  /// BE: routes/bundles.js:969-1177（門番 blockShareViewer）
  ///
  /// ★data は応答全体 {success, viewer_role, bundle, receivers, items,
  ///   bundle_integrity}（:1141-1158）。viewer_role は 'sender' / 'receiver' で、
  ///   同じ画面がどちら側として開いているかを BE が言い切る＝FE で推測しない。
  /// ★items[] は {report_id, report_date, worker_name, site_name, work_content,
  ///   gps_address, original_hash, sort_order, item_status}。item_status は
  ///   'tampered' / 'updated' / 'ok' の三値で BE が算出済み（:1039-1041）。
  ///   bundle_integrity は 'ok' / 'broken'（:1073）。FE でハッシュを再計算しない。
  /// ★★副作用あり: 受信側が開くと封筒に received_at が入り、原本の書き換えが
  ///   見つかった場合は【この GET の中で】改ざん事件が台帳化されて通知が飛ぶ
  ///   （:1160 / :1076-1114・fail-open）。つまり「一覧の見た目を整えるために
  ///   先読みで全件叩く」ことは絶対にしない。開いた1件だけを叩く。
  /// ★写真は含まれない。include_photos=true の束は呼び手が別途 GET /reports/:id。
  Future<ApiResult<Map<String, dynamic>>> getBundle(String bundleId) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'BundlesService.getBundle',
      () => http.get(
        Uri.parse('$kApiBaseUrl/bundles/$bundleId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  /// 束を「確認しました」にする。自社が受信社の場合のみ（送信社は 404）。
  /// BE: routes/bundles.js:1179-1243（応答 {success, confirmed_at}）
  ///
  /// ★確認は【束単位・人単位】（share_bundle_acks.confirmed_at）。日報1枚ごとの
  ///   既読（markReceiptRead）とは別の事実で、どちらか一方が他方を代替しない。
  /// ★冪等。confirmed_at は初回時刻を保つ（COALESCE）。二度押しても値は動かない。
  /// ★body は無い。data は応答全体（confirmed_at を含む）。
  Future<ApiResult<Map<String, dynamic>>> confirmBundle(String bundleId) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'BundlesService.confirmBundle',
      () => http.post(
        Uri.parse('$kApiBaseUrl/bundles/$bundleId/confirm'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }
}
