// ============================================================
// J's Awake App v1.1.1 — main.dart 完全版
// 株式会社J's 電気工事業 日報アプリ
// v1.1.1変更点：プレビュー画面に写真表示追加
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pending_approval_screen.dart';
import 'screens/register_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    if (dart.library.html) 'stub/notifications_stub.dart';
import 'package:geocoding/geocoding.dart'
    if (dart.library.html) 'stub/geocoding_stub.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/field_tokens.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'services/api_result.dart';
import 'services/reports_service.dart';
import 'utils/business_date.dart';
import 'utils/session_lockout.dart';
// 便BJ：場所を測れなかった時の字（ホームの現在地の帯）と符号の表・写真の置き場・ログアウトの掃除の後の口。
import 'core/report_place_labels.dart';
import 'core/report_send_texts.dart';
import 'utils/report_photo_store.dart';
import 'utils/personal_data_cleanup.dart';
import 'utils/saved_shift_type.dart';
import 'utils/today_marks.dart';

// ★API のベースURLは config/constants.dart の kApiBaseUrl 一本。
//   別名 `API_URL` は段6で退役した（同じ値に2つの名前があると、
//   どちらを直せばよいかが読み手に伝わらない）。

// boss PINフォールバック引き継ぎフラグ（インメモリ・ワンショット）
bool bossPinOk = false;

// ============================================================
// エントリーポイント
// ============================================================

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  unawaited(FcmService().init());
  await dotenv.load(fileName: '.env');
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
  if (!kIsWeb) {
    await NotificationManager.instance.initialize();
  }
  // 締め出し（退職・無効化など）でログイン画面へ戻すための Navigator を差す。
  // ★キーの置き場は FcmService（MaterialApp の navigatorKey と同一）。
  //   utils/session_lockout.dart 側から services を import すると依存が逆流するため、
  //   参照だけをここで渡す。差し忘れは test/session_lockout_wiring_test.dart が検出する。
  lockoutNavigatorLookup = () => FcmService.navigatorKey.currentState;
  // ログアウト・締め出し・期限切れの掃除（utils/personal_data_cleanup.dart）の後に、写真の置き場の掃除と
  // 未送信の数の読み直しをする口を差す（便BJ）。★utils から main.dart を読み込むと依存が逆流するため、
  //   上の lockoutNavigatorLookup と同じく参照だけをここで渡す。差し忘れは test/bj_field_test.dart が検出する。
  afterPersonalDataCleared = ReportStore.instance.afterPersonalDataCleared;
  // 写真の置き場の掃除（便BJ・見本 v1 の ③）。起動より前に作られ、未送信の日報のどれも指していない写真を消す。
  //   ★待たない（起動を遅らせない）。起動の後に撮った写真は消さない（before）。
  unawaited(ReportStore.instance.sweepPhotos(before: DateTime.now()));
  runApp(const JsAwakeApp());
}

// ============================================================
// アプリルート
// ============================================================

class JsAwakeApp extends StatelessWidget {
  const JsAwakeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: FcmService.navigatorKey,
      title: "J's FIELD",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const LoginScreen(),
      routes: {
        '/login':   (_) => const LoginScreen(),
        '/gate':    (_) => const GateScreen(),
        '/register':(_) => const RegisterScreen(),
        '/pending': (_) => const PendingApprovalScreen(),
      },
    );
  }
}

// ============================================================
// Enum: 交通手段
// ============================================================

enum TransportType {
  none('未選択',  Icons.help_outline),
  train('電車',   Icons.train),
  car('車',       Icons.directions_car),
  bus('バス',     Icons.directions_bus),
  bike('自転車',  Icons.pedal_bike),
  walk('徒歩',    Icons.directions_walk),
  other('その他', Icons.more_horiz);

  const TransportType(this.label, this.icon);
  final String   label;
  final IconData icon;
}

// ============================================================
// データモデル
// ============================================================

class WorkerReportItem {
  WorkerReportItem({
    required this.name,
    required this.transport,
    this.transportTypes,
    this.parkingFee,
    List<String>? parkingPhotoPaths,
    this.workContent = '',
    List<String>? workPhotoPaths,
    this.gpsAddress = '',
    // 場所を測れなかった時の符号（便BJ・'no_permission'|'gps_disabled'|'gps_error'・測れた時は null）。
    //   BE: POST /reports の gps_fail_reason（reports.gps_fail_reason・v94）。送る時は gps_address を空にする（reportBodyFor）。
    this.gpsFailReason,
    // 提出時点の座標（BE: POST /reports の gps_lat / gps_lon → appendEvent の監査イベント）。
    // null = 測位できていない＝送らない（既存の siteId と同じ流儀）。
    this.gpsLat,
    this.gpsLon,
    this.originType = 'home',
    this.siteId,
    this.shiftType = 'day',   // 'day'|'night'（BE: shift_type・省略時'day'扱い）
    // v57(FIELD): 経費スナップショット（提出時点の値。後で単価が変わっても書き換わらない）
    this.transportDistanceKm,
    this.transportFuelCost,
    this.transportFare,
    this.transportToll,
    this.transportBreakdown,
    // v57(FIELD): 相乗り相手（構造化・work_content連結を廃止した真実源）
    this.carpoolCompany,
    this.carpoolName,
    DateTime? timestamp,
    this.isActive = true,
    String? id,
    this.apiReportId,
    // 持ち主（作った時にログインしていた人の 'user_id'・便BJ・ボスの裁定【Q140】）。null なら ReportStore が入れる。
    this.ownerUserId,
  }) : parkingPhotoPaths = parkingPhotoPaths ?? const [],
       workPhotoPaths    = workPhotoPaths    ?? const [],
       timestamp = timestamp ?? DateTime.now(),
       id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final String name;
  final TransportType transport;
  final List<String>? transportTypes;
  final String? parkingFee;
  final List<String> parkingPhotoPaths; // 駐車(parking)：複数
  final String workContent;
  final List<String> workPhotoPaths;    // 作業(site)：複数
  final String gpsAddress;
  final String? gpsFailReason; // 測れなかった時の符号（null＝測れた・送る時は gps_address を空にする）
  final double? gpsLat;   // 提出時点の緯度（null=未測位＝送らない）
  final double? gpsLon;   // 提出時点の経度（同上）
  final String originType;
  final String? siteId;   // 作業現場（null=対象なし／未選択）
  final String shiftType; // 'day'|'night'（業務日の夜勤補正とBE送出に使用）
  // v57(FIELD): 経費スナップショット（提出時点の合計＋内訳。ルート検索結果由来）
  final double? transportDistanceKm;
  final int? transportFuelCost;
  final int? transportFare;
  final int? transportToll;
  final List<Map<String, dynamic>>? transportBreakdown;
  // v57(FIELD): 相乗り相手（会社名・氏名。二重真実を作らないため work_content には連結しない）
  final String? carpoolCompany;
  final String? carpoolName;
  final DateTime timestamp;
  bool isActive;
  String? apiReportId;
  // 持ち主（便BJ・【Q140】）。★送るのは持ち主が今ログインしている人と同じ日報だけ（ReportStore.retryPending）。
  //   ログアウト・締め出し・期限切れでも箱からは消さない＝同じ人がログインし直した時に送る。
  String? ownerUserId;
  // 送り先（サーバ）が受け付けなかった時の、送り先の答えの字（便BJ・見本 v2 の ⑬・ボスの裁定【Q142】）。
  //   null＝受け付けなかった答えは来ていない。★送り先が答えるたびに書き直す（受け付けない答え＝その字・ほかの答え＝null・
  //   通信が届かなかった時は前の値のまま）。送った後の画面の「提出できません（…）」に使う（ReportStore.pendingRefusedMessage）。
  String? refusedMessage;

  // 後方互換：表示/エクスポート系は先頭1枚を参照（読み取り専用）
  String? get parkingPhotoPath => parkingPhotoPaths.isNotEmpty ? parkingPhotoPaths.first : null;
  String? get workPhotoPath    => workPhotoPaths.isNotEmpty    ? workPhotoPaths.first    : null;

  // 旧形式(単数String)や欠落は読み捨て（クラッシュ防止・袋小路防止）
  static List<String> _readPaths(dynamic v) =>
      v is List ? v.whereType<String>().toList() : const [];

  String get timeLabel {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Map<String, dynamic> toJson() => {
    'id':               id,
    'name':             name,
    'transport':        transport.name,
    'transportTypes':   transportTypes,
    'parkingFee':       parkingFee,
    'parkingPhotoPaths': parkingPhotoPaths,
    'workContent':      workContent,
    'workPhotoPaths':   workPhotoPaths,
    'gpsAddress':       gpsAddress,
    'gpsFailReason':    gpsFailReason,
    'gpsLat':           gpsLat,
    'gpsLon':           gpsLon,
    'originType':       originType,
    'siteId':           siteId,
    'shiftType':        shiftType,
    'transportDistanceKm': transportDistanceKm,
    'transportFuelCost':   transportFuelCost,
    'transportFare':       transportFare,
    'transportToll':       transportToll,
    'transportBreakdown':  transportBreakdown,
    'carpoolCompany':      carpoolCompany,
    'carpoolName':         carpoolName,
    'timestamp':        timestamp.toIso8601String(),
    'isActive':         isActive,
    'apiReportId':      apiReportId,
    'ownerUserId':      ownerUserId,
    'refusedMessage':   refusedMessage,
  };

  static WorkerReportItem fromJson(Map<String, dynamic> j) => WorkerReportItem(
    id:               j['id'] as String?,
    name:             j['name'] as String? ?? '',
    transport:        TransportType.values.firstWhere(
      (t) => t.name == j['transport'], orElse: () => TransportType.train),
    transportTypes:   (j['transportTypes'] as List?)?.cast<String>(),
    parkingFee:       j['parkingFee']       as String?,
    parkingPhotoPaths: _readPaths(j['parkingPhotoPaths']),
    workContent:      j['workContent']      as String? ?? '',
    workPhotoPaths:   _readPaths(j['workPhotoPaths']),
    gpsAddress:       j['gpsAddress']       as String? ?? '',
    // 便BJ より前の箱の行（欠落）と、表に無い字は null（サーバの 400 で箱に残り続けないため）。
    gpsFailReason:    kGpsFailReasonLabels.containsKey(j['gpsFailReason'])
        ? j['gpsFailReason'] as String
        : null,
    // 旧形式JSON（欠落）は null 読み捨て＝オフライン再送待ちの行も壊さない
    gpsLat:           (j['gpsLat'] as num?)?.toDouble(),
    gpsLon:           (j['gpsLon'] as num?)?.toDouble(),
    originType:       j['originType']       as String? ?? 'home',
    siteId:           j['siteId']           as String?,
    // 旧形式JSON（shiftType欠落）・不正値は 'day' にフォールバック（BEの400回避・クラッシュ防止）
    shiftType:        j['shiftType'] == 'night' ? 'night' : 'day',
    // v57(FIELD): 旧形式JSON（欠落）は null 読み捨て（クラッシュ防止）
    transportDistanceKm: (j['transportDistanceKm'] as num?)?.toDouble(),
    transportFuelCost:   (j['transportFuelCost'] as num?)?.toInt(),
    transportFare:       (j['transportFare'] as num?)?.toInt(),
    transportToll:       (j['transportToll'] as num?)?.toInt(),
    transportBreakdown:  (j['transportBreakdown'] as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    carpoolCompany:      j['carpoolCompany'] as String?,
    carpoolName:         j['carpoolName'] as String?,
    timestamp:        j['timestamp'] != null
        ? DateTime.tryParse(j['timestamp'] as String) ?? DateTime.now()
        : DateTime.now(),
    isActive: j['isActive'] as bool? ?? true,
  )..apiReportId = j['apiReportId'] as String?
   // 便BJ より前の箱の行は null（ReportStore.retryPending が、名前で今の人の物か見て入れる）。
   ..ownerUserId = j['ownerUserId'] as String?
   // 便BJ より前の箱の行は null（受け付けなかった答えは来ていない）。
   ..refusedMessage = j['refusedMessage'] as String?;
}

// ============================================================
// SharedPreferences キー
// ============================================================

class _K {
  static const reports        = 'worker_reports_history';
  // 'registered_worker_names'（氏名の名簿）は便BJ で作りごと撤去した（書き足すだけで、どこにも出なかった）。
  //   前の端末に残った鍵は、ログアウトの掃除（utils/personal_data_cleanup.dart）が消す。
  static const notifHours     = 'notification_hours';
  static const pendingReports = 'pending_reports';
  // 読めなかった未送信の箱の元の字（便BJ・検分 a251 の N3）。★掃除では消さない（未送信の箱と同じ扱い）。
  static const unreadablePending = 'pending_reports_unreadable';
}

/// 未送信の箱の字を端末の保存へ書く口（便BJ・検分 a251 の N4）。★検査だけが差し替える（本体からは替えない）。
///   わけ: 端末へ書けなかった時（shared_preferences は手元の写しを先に替え、その後で端末へ書く＝書き込みが投げても
///   写しは替わっている）の動きを、検査で確かめるため。
@visibleForTesting
Future<bool> Function(SharedPreferences prefs, String key, String value) pendingBoxWriter =
    _writePrefsString;

Future<bool> _writePrefsString(SharedPreferences prefs, String key, String value) =>
    prefs.setString(key, value);

// ============================================================
// ReportStore
// ============================================================

class ReportStore {
  static final ReportStore instance = ReportStore._();
  ReportStore._();

  // ── 便BJ（見本 claude/field_report_fix_mock_v1.html の ①・③ と、見本の「見た目が変わらない直し」の1つめ・ボスの裁定【Q140】）──
  //   元: 送れなかった日報だけを箱（pending_reports）へ入れ、送り直しは先に箱を空にしてから送っていた
  //       （途中でアプリが止まると、まだ送っていない日報が消える）。残りの数は呼ばれた時に数えるだけで、
  //       送った後の画面は送った直後の成否のまま変わらなかった。
  //   →再（2026-10-14・便BJ）:
  //   ・日報は先に箱へ入れてから送り、送れた1件ずつ箱から外す（箱に入った後は、どこで止まっても消えない）。
  //   ・箱の読み書きは1本の列に並べる（同時に読んで書くと、片方の書き込みが消える）。
  //   ・送っている途中の日報は、ほかの送り直しが拾わない（同じ日報を2回送らない）。
  //   ・送るのは持ち主（ownerUserId）が今ログインしている人の日報だけ。ほかの人の日報は箱に残す（【Q140】）。
  //   ・今の人の残りの数を pendingOwnCount で知らせる（送った後の画面の頭の字はこの数で決める）。
  //   ・送り直しで読めなかった写真は除いて送り、除いた数を droppedPhotoCount で知らせる（黙って落とさない）。
  //   →再（2026-10-14・便BJ・検分 a251）:
  //   ・持ち主は、1件ずつ送る直前にも見る（取った後に人が替わった時、前の人の日報を次の人の資格で送らない）。
  //   ・箱へ書けなかった時は、端末の手元の写しの箱からも外してから投げる（すぐ後の送り直しが送ると、
  //     もう一度押して作った2枚目と二重になる）。送れた後に箱から外せなかった時は「送れた」として返す。
  //   ・箱の中の読めない行は消さずに書き戻し、箱そのものが読めない時は元の字を別の鍵へ写して残す（黙って消さない）。
  //   ・送れた日報の写真は、箱に残るほかの日報が指していない物だけ消す。

  /// 今ログインしている人の、端末に残っている未送信の日報の数（0＝送った後の画面は「報告完了」）。
  ///   ★書き直すのは、箱を書き換えた後と refreshPendingCount を呼んだ時だけ。
  final ValueNotifier<int> pendingOwnCount = ValueNotifier<int>(0);

  /// 送り直しで読めずに除いた写真の数。★シェルが「写真 N枚を送れませんでした」と知らせてから 0 に戻す。
  final ValueNotifier<int> droppedPhotoCount = ValueNotifier<int>(0);

  /// 今の人の未送信の日報のうち、送り先が受け付けなかった物の、送り先の答えの字（箱の並びで最初の1件・無ければ null）。
  ///   ★送った後の画面が「提出できません（…）」を出すのに使う（見本 v2 の ⑬・ボスの裁定【Q142】）。
  ///   書き直すのは pendingOwnCount と同じ時（refreshPendingCount）。
  final ValueNotifier<String?> pendingRefusedMessage = ValueNotifier<String?>(null);

  // 箱の読み書きの列（前の読み書きが終わってから次を始める）。★列の中から列を呼ばない（待ち合って止まる）。
  Future<void> _boxTail = Future<void>.value();
  Future<T> _withBox<T>(Future<T> Function() body) {
    final run = _boxTail.then((_) => body());
    _boxTail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  // 今送っている途中の日報の id。★箱の列の中で取る（取った日報は、ほかの送り直しが拾わない＝同じ日報を2回送らない）。
  //   外すのは送り終えた時（_sendOne の finally・_sendOne は投げない）だけ。送り直しの終わり（retryPending の finally）で外すのは、
  //   取ったのに回らなかった日報の印だけ（元: 取った id を全部外していた＝1件目の後にほかの送り直しが取り直して送っている
  //   途中の日報の印まで外し、3本目の送り直しが同じ日報をもう一度送る道があった・検分 a253 の S1）。
  final Set<String> _inFlight = <String>{};

  Future<List<WorkerReportItem>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_K.reports);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => WorkerReportItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  Future<void> saveAll(List<WorkerReportItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_K.reports, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  /// 日報を1件出す。返り＝今送れたか（false＝箱に残った＝あとで送り直す）。
  ///   ★箱へ入れるまでに失敗したら投げる（日報は端末に残っていない＝呼び手が「送れませんでした」を出し、
  ///     もう一度押せる）。箱へ入った後は投げない（送れなくても箱に残る＝2枚目を作らせない）。
  Future<bool> addReport(WorkerReportItem item) async {
    final prefs = await SharedPreferences.getInstance();
    // 持ち主は空の字にしない（分からない時は null のまま＝印の無い前の物と同じく、名前で今の人の物かを見る・検分 a253 の N1）。
    final me = prefs.getString('user_id') ?? '';
    item.ownerUserId ??= me.isEmpty ? null : me;
    final all = await loadAll();
    all.add(item);
    await saveAll(all);
    // ここで箱に入る（この後は、どこで止まっても日報は端末に残る）。箱の列の中で、送る役も取る。
    //   ★送る役は書く前に取る（書けなかった時に、ほかの送り直しが手元の写しの箱から拾わない）。
    //   ★書けなかった時は、手元の写しの箱からも外してから投げる（shared_preferences は、端末へ書く前に
    //     手元の写しを替える＝外さないと、すぐ後の送り直しが送り、もう一度押して作った2枚目と二重になる）。
    await _withBox(() async {
      _inFlight.add(item.id);
      try {
        final box = await _loadPending();
        if (!box.any((e) => e.id == item.id)) box.add(item);
        await _savePendingAll(box);
      } catch (_) {
        _inFlight.remove(item.id);
        try {
          final box = await _loadPending();
          box.removeWhere((x) => x.id == item.id);
          await _savePendingAll(box);
        } catch (e) {
          debugPrint('書けなかった日報を箱から外せませんでした: $e');
        }
        rethrow;
      }
    });
    try {
      return await _sendOne(item);
    } catch (e) {
      debugPrint('API送信失敗: $e');
      return false;
    } finally {
      await refreshPendingCount();
    }
  }

  // 1件を送り、送れたら箱から外して写真を消す。返り＝送れたか。★投げない。
  //   ★呼ぶ前に、箱の列の中で送る役を取っておく（_inFlight に入れる）。ここでは取らない。
  Future<bool> _sendOne(WorkerReportItem item) async {
    try {
      // 認証ヘッダは ReportsService（AuthService.getAuthHeaders）が組む。
      // 本文と写真の組み方は、下の reportBodyFor・reportPhotosFor（このファイル）に在る。
      final body = reportBodyFor(item);
      final photos = await reportPhotosFor(item);
      final dropped =
          item.workPhotoPaths.length + item.parkingPhotoPaths.length - photos.length;
      if (photos.isNotEmpty) body['photos'] = photos;
      // 送る直前（資格は createReport の頭で読む）に、持ち主が今ログインしている人かを見る（【Q140】）。
      //   元: 持ち主は、送り直しが箱から取る時に1回だけ見ていた（1件ずつ通信を待つ間にログアウトして別の人が
      //   ログインすると、2件目から前の人の日報を次の人の資格で送った）。
      //   →再（2026-10-14・便BJ・検分 a251 の S1）: 1件ごとに、ここで見る。違えば送らずに箱に残す。
      final prefs = await SharedPreferences.getInstance();
      final me = prefs.getString('user_id') ?? '';
      if (me.isEmpty || item.ownerUserId != me) return false;
      final response = await ReportsService().createReport(body);
      final resBody = response.data;
      // 成功は 200 または 201（移設前と同じ）。それ以外・通信不成立・本文が
      // 読めなかった場合はすべて「未送信」＝箱に残す。
      if (!(response.ok &&
          resBody != null &&
          (response.statusCode == 200 || response.statusCode == 201))) {
        // 送り先が答えた時は、受け付けなかったか（その字）を日報に書き留める（見本 v2 の ⑬・【Q142】）。
        //   通信が届かなかった時（statusCode 0）は書き直さない（前の答えのまま）。
        if (response.statusCode != 0) await _noteAnswer(item, refusedMessageOf(response));
        return false;
      }
      item.apiReportId = resBody['report_id'] as String?;
      if (dropped > 0) droppedPhotoCount.value += dropped;
      // ★ここから先は、何で止まっても「送れた」として返す（サーバに届いている）。
      //   元: 箱から外す所で投げると false＝箱に残り、次の送り直しで同じ日報をもう一度送った。
      //   →再（2026-10-14・便BJ・検分 a251 の N3）: 外せなかった時は写真も消さずに残す（端末の箱と写真を食い違わせない）。
      Set<String> stillUsed;
      try {
        stillUsed = await _withBox(() async {
          final box = await _loadPending();
          box.removeWhere((e) => e.id == item.id);
          await _savePendingAll(box);
          return <String>{
            for (final e in box) ...[...e.workPhotoPaths, ...e.parkingPhotoPaths],
          };
        });
      } catch (e) {
        debugPrint('送れた日報を箱から外せませんでした（送れた事として返す）: $e');
        return true;
      }
      // 写真は、箱に残るほかの日報が指していない物だけ消す（名前で見比べる・検分 a251 の N2）。
      final usedKeys = stillUsed.map(reportPhotoKey).toSet();
      await deleteReportPhotos([...item.workPhotoPaths, ...item.parkingPhotoPaths]
          .where((p) => !usedKeys.contains(reportPhotoKey(p))));
      return true;
    } catch (e) {
      debugPrint('API送信失敗: $e');
      return false;
    } finally {
      _inFlight.remove(item.id);
    }
  }

  // 箱の行のうち、このアプリが読めなかった行（元の形のまま）。★消さずに、箱を書く時に後ろへ戻す。
  //   元: 箱の読み取りで1つでも投げると、箱を空として扱い、次に書く時に箱の中身が全部黙って消えた。
  //   →再（2026-10-14・便BJ・検分 a251 の N3）: 読めた行だけを日報として扱い、読めない行は書き戻す。
  //   ★読むのも書くのも箱の列の中（_withBox）なので、読んだ時の行がそのまま次の書き込みに戻る
  //     （pendingCount は列の外で読むが、同じ箱を読むので同じ行になる）。
  List<Object?> _unreadableRows = const <Object?>[];

  // ★端末が「書けなかった」と答えた時（false）も投げる（投げずに進むと、箱に入っていない日報を入った事にする・検分 a253 の N6）。
  Future<void> _savePendingAll(List<WorkerReportItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await pendingBoxWriter(prefs, _K.pendingReports,
        jsonEncode([...items.map((e) => e.toJson()), ..._unreadableRows]));
    if (!ok) throw StateError('未送信の箱を端末に書けませんでした');
  }

  Future<List<WorkerReportItem>> _loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_K.pendingReports);
    if (raw == null) {
      _unreadableRows = const <Object?>[];
      return [];
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      decoded = null;
    }
    if (decoded is! List) {
      // 箱そのものが読めない：元の字を別の鍵（_K.unreadablePending）へ写して残し、空の箱として続ける
      //   （次に箱を書く時に元の字が上書きされて消えないように）。
      await _keepUnreadableBox(prefs, raw);
      _unreadableRows = const <Object?>[];
      return [];
    }
    final items = <WorkerReportItem>[];
    final bad = <Object?>[];
    for (final e in decoded) {
      try {
        items.add(WorkerReportItem.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        debugPrint('未送信の箱の1行を読めませんでした（消さずに残す）: $err');
        bad.add(e);
      }
    }
    _unreadableRows = bad;
    return items;
  }

  // 読めない箱の元の字を、_K.unreadablePending（字の並び）の後ろへ足す。★投げない。
  Future<void> _keepUnreadableBox(SharedPreferences prefs, String raw) async {
    try {
      final kept = prefs.getStringList(_K.unreadablePending) ?? const <String>[];
      if (!kept.contains(raw)) {
        await prefs.setStringList(_K.unreadablePending, [...kept, raw]);
      }
      debugPrint('未送信の箱を読めませんでした（元の字を ${_K.unreadablePending} に残した）');
    } catch (e) {
      debugPrint('読めない箱の元の字を残せませんでした: $e');
    }
  }

  /// 今の人の箱の日報を、1件ずつ送り直す（送れた1件ずつ箱から外す）。★投げない。
  ///   ★持ち主の印の無い日報（便BJ より前に箱へ入った物）は、名前（name）が今の人の 'user_name' と同じ時だけ、
  ///     今の人の物として印を付けて送る。違えば箱に残す（別の人の日報を、今の人の資格で送らない＝【Q140】）。
  Future<void> retryPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final me = prefs.getString('user_id') ?? '';
      final myName = prefs.getString('user_name') ?? '';
      if (me.isEmpty) return;
      final mine = await _withBox(() async {
        final box = await _loadPending();
        var changed = false;
        for (final e in box) {
          if (e.ownerUserId == null && myName.isNotEmpty && e.name == myName) {
            e.ownerUserId = me;
            changed = true;
          }
        }
        if (changed) await _savePendingAll(box);
        // 今の人の日報のうち、ほかが送っている途中でない物を、列の中で取る。
        final picked = box
            .where((e) => e.ownerUserId == me && !_inFlight.contains(e.id))
            .toList();
        _inFlight.addAll(picked.map((e) => e.id));
        return picked;
      });
      final visited = <String>{};
      try {
        for (final item in mine) {
          visited.add(item.id);
          await _sendOne(item);
        }
      } finally {
        // 回らなかった日報（途中で止まった時）の印だけを外す（回った日報の印は _sendOne の finally が外した）。
        _inFlight.removeAll(mine.map((e) => e.id).where((id) => !visited.contains(id)));
      }
    } catch (e) {
      debugPrint('送り直しに失敗: $e');
    } finally {
      await refreshPendingCount();
    }
  }

  // 送り先の答え（受け付けなかった字・ほかの答えは null）を、箱の同じ日報に書き留める（変わる時だけ書く）。★投げない。
  Future<void> _noteAnswer(WorkerReportItem item, String? refused) async {
    if (item.refusedMessage == refused) return;
    item.refusedMessage = refused;
    try {
      await _withBox(() async {
        final box = await _loadPending();
        var changed = false;
        for (final e in box) {
          if (e.id == item.id && e.refusedMessage != refused) {
            e.refusedMessage = refused;
            changed = true;
          }
        }
        if (changed) await _savePendingAll(box);
      });
    } catch (e) {
      debugPrint('送り先の答えを箱に書き留められませんでした: $e');
    }
  }

  // 今の人の、箱に残っている日報。今の人が分からない時（'user_id' が無い・空）は、持ち主の分からない日報（ownerUserId が null）
  //   を数える（検分 a254 の Y1＝今の人が分からないまま日報を出すと、送らずに箱へ残る。その時に数が 0 だと、送った後の画面が
  //   「報告完了」と事実と違う字を出す）。
  Future<List<WorkerReportItem>> _ownPending() async {
    final prefs = await SharedPreferences.getInstance();
    final me = prefs.getString('user_id') ?? '';
    final box = await _loadPending();
    if (me.isEmpty) return box.where((e) => e.ownerUserId == null).toList();
    return box.where((e) => e.ownerUserId == me).toList();
  }

  /// 今の人の、箱に残っている日報の数（今の人が分からない時は、持ち主の分からない日報の数）。
  Future<int> pendingCount() async => (await _ownPending()).length;

  /// pendingOwnCount と pendingRefusedMessage を箱の今の姿に合わせる。★投げない（読めなければ今の値のまま）。
  Future<void> refreshPendingCount() async {
    try {
      final mine = await _ownPending();
      pendingOwnCount.value = mine.length;
      String? refused;
      for (final e in mine) {
        if (e.refusedMessage != null) {
          refused = e.refusedMessage;
          break;
        }
      }
      pendingRefusedMessage.value = refused;
    } catch (e) {
      debugPrint('未送信の数を読めませんでした: $e');
    }
  }

  /// 写真の置き場の中で、箱のどの日報（持ち主を問わない）も指していない写真を消す（★投げない）。
  ///   before が在れば、それより前に作られた写真だけ（起動の後に撮った写真を消さない）。
  Future<void> sweepPhotos({DateTime? before}) async {
    try {
      final keep = <String>{
        for (final e in await _withBox(_loadPending)) ...[
          ...e.workPhotoPaths,
          ...e.parkingPhotoPaths,
        ],
      };
      await sweepReportPhotos(keep: keep, before: before);
    } catch (e) {
      debugPrint('写真の置き場の掃除に失敗: $e');
    }
  }

  /// ログアウト・締め出し・期限切れの掃除（utils/personal_data_cleanup.dart）の後に呼ばれる口（main() で差す）。
  ///   箱は残す（【Q140】）。写真は箱が指す物だけを残す。今の人が居なくなったので数を読み直す（0 になる）。
  ///   →再（2026-10-14・便BJ・検分 a251 の N8）: 送り直しで除いた写真の数も 0 に戻す（前の人の数を次の人に出さない）。
  Future<void> afterPersonalDataCleared() async {
    droppedPhotoCount.value = 0;
    await sweepPhotos();
    await refreshPendingCount();
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_K.reports);
  }

  Future<List<WorkerReportItem>> loadToday() async {
    final all   = await loadAll();
    final today = DateTime.now();
    return all.where((r) =>
      r.timestamp.year  == today.year &&
      r.timestamp.month == today.month &&
      r.timestamp.day   == today.day,
    ).toList();
  }
}

// ============================================================
// 日報の本文と写真（ReportStore._sendOne・今日の日報の送る前の確かめ・後から出す日報が使う）
//   便F8b-1（2026-10-08）で、_sendToAPI（便BJ で _sendOne に替わった）の中に直に書いてあった組み方を、字のまま関数へ出した。
//   鍵の並び・値の形・条件は1つも変えていない（送る字は1バイトも同じ）。
//   ★なぜ出したか：事務の許可が出た過去の日の日報を出す画面（次の便）が、同じ組み方を使うため。
// ============================================================

/// 日報の本文（写真は入れない）。通信しない・端末の保存を読まない・今の時刻を読まない（item が持つ時刻だけを使う）。
Map<String, dynamic> reportBodyFor(WorkerReportItem item) {
  final body = <String, dynamic>{
    'worker_name':   item.name,
    'worker_company': '',
    // 業務日：端末TZ非依存のJST固定。夜勤かつJST 0:00-11:59は始業日=前日
    //（BE js-office-api/utils/businessDate.js の businessDateForShift と同一ルール）
    'report_date':   businessDateForShift(item.shiftType, item.timestamp),
    'shift_type':    item.shiftType,
    'clock_in_time': '${item.timeLabel}:00',
    'transport_type':      item.transport.name,
    'transport_types_json': item.transportTypes,
    'parking_fee':         item.parkingFee != null ? double.tryParse(item.parkingFee!) : null,
    // 場所を測れなかった時（gpsFailReason が在る時）は、住所の欄を空にする（便BJ・サーバは理由と住所の字の両方は断る）。
    'gps_address':         item.gpsFailReason != null ? '' : item.gpsAddress,
    'origin_type':         item.originType,
    'work_content':        item.workContent,
    // v57(FIELD): 経費スナップショット（提出時点の合計）。null は 0 で埋めず null のまま送る。
    'transport_distance_km': item.transportDistanceKm,
    'transport_fuel_cost':   item.transportFuelCost,
    'transport_fare':        item.transportFare,
    'transport_toll':        item.transportToll,
    'transport_breakdown':   item.transportBreakdown,
    // v57(FIELD): 相乗り相手（構造化・空欄は null）。BE:reports.carpool_company/carpool_name
    'carpool_company':       item.carpoolCompany,
    'carpool_name':          item.carpoolName,
  };
  // 作業現場：選択時のみ site_id を送る（「対象なし」=null は送信しない＝BE側 NULL）
  if (item.siteId != null) body['site_id'] = item.siteId;
  // 提出座標：測位できているときだけ送る（site_id と同じ流儀）。
  // BE 受け口は routes/reports.js の appendEvent（gps_lat / gps_lon）。
  // ★reports 表の列でも content_hash の対象でもない＝既存ハッシュに影響しない。
  //   →再（2026-10-14・便BJ・検分 a251 の N9）: 場所を測れなかった時（gpsFailReason が在る時）は送らない
  //   （その時の座標は、前に測った時の値が残っている物＝この日報の場所ではない）。
  if (item.gpsFailReason == null) {
    if (item.gpsLat != null) body['gps_lat'] = item.gpsLat;
    if (item.gpsLon != null) body['gps_lon'] = item.gpsLon;
  }
  // 場所を測れなかった時の印（便BJ・BE: reports.gps_fail_reason・v94）。理由を符号で送る。
  //   ★測れた時（印が無い時）は鍵を足さない＝送る字は便BJ より前と1バイトも同じ。
  if (item.gpsFailReason != null) body['gps_fail_reason'] = item.gpsFailReason;
  return body;
}

/// 送り先の答えが「受け付けない」（送り直しても同じ答えになる）時の、送り先の字。受け付けないでなければ null
///   （便BJ・見本 v2 の ⑬・ボスの裁定【Q142】）。
///   受け付けない＝4xx のうち、資格（401）・待ち時間（408）・回数の制限（429）と、締め出しの符号（utils/session_lockout.dart の
///   kLockoutMessages＝ログインし直せば送れる）を除いた物。字は送り先の本文の error（JSON の字の値の時だけ・空白を除いて空なら
///   「理由不明」）。使うかどうかの決め方（本文の error が字か）は、後から出す日報の「提出できません」の枠
///   （lib/screens/late_report_screen.dart の errorDetails['error']）と同じ。出す字はこちらは error の字そのもの
///   （runApiCall は JSON の error をそのまま errorMessage に入れるので、ふだんは同じ字になる）。
///   通信しない・端末の保存を読まない。
String? refusedMessageOf(ApiResult<dynamic> r) {
  final s = r.statusCode;
  if (s < 400 || s >= 500 || s == 401 || s == 408 || s == 429) return null;
  if (kLockoutMessages.containsKey(r.errorCode)) return null;
  final err = r.errorDetails?['error'];
  final m = err is String ? err.trim() : '';
  return m.isEmpty ? '理由不明' : m;
}

/// 後から出す日報の口（POST /reports/permitted）が「送らないで」と断る鍵（便F8b-2）。
///   サーバの名簿は js-office-api の routes/reports.js の report_date の断りと PERMITTED_TIME_PLACE_KEYS
///   （日付はサーバが許可から決める・時刻と場所はその日に居なかったので送らない）。
///   ★値が null でも断られる（サーバは鍵が在るかで見る）ので、値を空にせず鍵ごと除く。
const List<String> kPermittedReportRefusedKeys = [
  'report_date',
  'clock_in_time',
  'clock_out_time',
  'gps_address',
  'gps_lat',
  'gps_lon',
  // →再（2026-10-14・便BJ）: サーバの PERMITTED_TIME_PLACE_KEYS に gps_fail_reason が足された（便BI）。
  //   場所を持たない日報なので、場所の印も送らない。
  'gps_fail_reason',
];

/// 後から出す日報の本文（写真は入れない・便F8b-2）。
///   reportBodyFor(item) の答えから kPermittedReportRefusedKeys の鍵を除き、confirmation_id を足す。
///   ほかの鍵と値は reportBodyFor のまま（同じ組み方を2通りに書かない）。
///   通信しない・端末の保存を読まない。
Map<String, dynamic> permittedReportBodyFor(WorkerReportItem item,
    {required String confirmationId}) {
  final body = reportBodyFor(item);
  for (final k in kPermittedReportRefusedKeys) {
    body.remove(k);
  }
  body['confirmation_id'] = confirmationId;
  return body;
}

/// 日報に付ける写真の並び（作業が先・駐車場が後）。読めなかった写真は飛ばす（今の動きのまま）。
///   →再（2026-10-14・便BJ・検分 a251 の N1）: 置き場の写真は、名前で今の置き場の道に当ててから読む
///   （lib/utils/report_photo_store.dart の resolveReportPhotoPath）。
Future<List<Map<String, dynamic>>> reportPhotosFor(WorkerReportItem item) async {
  // photos:[{photo_type,base64}] 配列で送信（site→作業 / parking→駐車・生base64＝BE互換）
  final photos = <Map<String, dynamic>>[];
  for (final p in item.workPhotoPaths) {
    try {
      final path = await resolveReportPhotoPath(p);
      photos.add({'photo_type': 'site', 'base64': base64Encode(await File(path).readAsBytes())});
    } catch (e) {
      debugPrint('作業写真エンコード失敗: $e');
    }
  }
  for (final p in item.parkingPhotoPaths) {
    try {
      final path = await resolveReportPhotoPath(p);
      photos.add({'photo_type': 'parking', 'base64': base64Encode(await File(path).readAsBytes())});
    } catch (e) {
      debugPrint('駐車写真エンコード失敗: $e');
    }
  }
  return photos;
}

// ============================================================
// NotificationManager
// ============================================================

class NotificationManager {
  static final NotificationManager instance = NotificationManager._();
  NotificationManager._();

  final _plugin = FlutterLocalNotificationsPlugin();
  List<int> _hours = [12, 17];

  Future<void> initialize() async {
    if (kIsWeb) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          FcmService().handleNotificationTap(data);
        } catch (_) {}
      },
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_K.notifHours);
    if (saved != null && saved.isNotEmpty) {
      _hours = saved.map((h) => int.tryParse(h) ?? 12).toList();
    }
    await _scheduleAll();
  }

  List<int> get hours => List.unmodifiable(_hours);

  Future<void> setHours(List<int> newHours) async {
    if (kIsWeb) return;
    _hours = newHours.where((h) => h >= 0 && h < 24).toList()..sort();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_K.notifHours, _hours.map((h) => h.toString()).toList());
    await _scheduleAll();
  }

  Future<void> _scheduleAll() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancelAll();
      for (final hour in _hours) {
        final now  = tz.TZDateTime.now(tz.local);
        var target = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
        if (target.isBefore(now)) target = target.add(const Duration(days: 1));
        await _plugin.zonedSchedule(
          hour,
          '📋 日報の時間です',
          "J's Awake App — 本日の報告を送信してください",
          target,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'js_daily_report', '日報リマインダー',
              channelDescription: '日報の提出をお知らせします',
              importance: Importance.high,
              priority:   Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (_) {
    }
  }

  // 退勤忘れリマインダー（実勤務モード用）— 18:00以降に日報未送信の場合
  static const int _overtimeNotifId = 200;

  Future<void> scheduleOvertimeReminder() async {
    if (kIsWeb) return;
    try {
      final now    = tz.TZDateTime.now(tz.local);
      var   target = tz.TZDateTime(tz.local, now.year, now.month, now.day, 18);
      if (target.isBefore(now)) target = target.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        _overtimeNotifId,
        '⚠️ 退勤報告を忘れていませんか？',
        '本日の日報がまだ送信されていません。アプリを開いて報告してください。',
        target,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'js_overtime_check', '退勤忘れリマインダー',
            channelDescription: '実勤務モード時の退勤忘れをお知らせします',
            importance: Importance.max,
            priority:   Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
    }
  }

  Future<void> cancelOvertimeReminder() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(_overtimeNotifId);
    } catch (_) {
    }
  }
}

// ============================================================
// SpeechExtractResult
// ============================================================

class SpeechExtractResult {
  const SpeechExtractResult({
    this.name, this.transport, this.parkingFee, this.warning,
  });
  final String?        name;
  final TransportType? transport;
  final String?        parkingFee;
  final String?        warning;
}

// ============================================================
// SpeechManager
// ============================================================

class SpeechManager {
  final _speech = SpeechToText();
  bool _initialized = false;
  Future<bool>? _initFuture;
  VoidCallback? _onSessionDone;
  void Function(String errorMsg)? _onPermanentError;

  Future<bool> ensureReady() async {
    _initFuture ??= initialize();
    final ok = await _initFuture!;
    if (!ok) _initFuture = null; // 失敗はキャッシュしない → 設定許可後に再試行可能
    return ok;
  }

  Future<bool> initialize() async {
    _initialized = await _speech.initialize(
      debugLogging: false,
      onStatus: (status) {
        debugPrint('SpeechManager status: $status');
        if (status == 'notListening' || status == 'done') {
          _onSessionDone?.call();
        }
      },
      onError: (error) {
        debugPrint('SpeechManager error: ${error.errorMsg} permanent=${error.permanent}');
        if (error.errorMsg == 'error_busy') return;
        if (error.errorMsg == 'error_no_match') return;
        if (error.errorMsg == 'error_speech_timeout') return;
        if (error.permanent) _onPermanentError?.call(error.errorMsg);
      },
    );
    return _initialized;
  }

  bool get isAvailable => _initialized && _speech.isAvailable;
  bool get isListening => _speech.isListening;
  Future<bool> get hasPermission => _speech.hasPermission;

  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    VoidCallback? onSessionDone,
    void Function(String errorMsg)? onPermanentError,
  }) async {
    _onSessionDone    = onSessionDone;
    _onPermanentError = onPermanentError;
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) =>
          onResult(r.recognizedWords, r.finalResult),
      localeId:  'ja_JP',
      listenFor: const Duration(seconds: 60),
      pauseFor:  const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        autoPunctuation: false,
        enableHapticFeedback: false,
      ),
    );
  }

  Future<void> stop() async {
    _onSessionDone    = null;
    _onPermanentError = null;
    await _speech.stop();
  }

  Future<void> cancel() async {
    _onSessionDone    = null;
    _onPermanentError = null;
    await _speech.cancel();
  }

  SpeechExtractResult extractInfo(String text) {
    String?        name;
    TransportType? transport;
    String?        parkingFee;
    String?        warning;

    final namePatterns = [
      RegExp(r'([^\s　、。「」]{2,6}?)(?:は|が)(?:電車|車|バス|自転車|徒歩)'),
      RegExp(r'([^\s　、。「」]{2,6}?)(?:さん|くん|ちゃん)'),
      RegExp(r'^([^\s　、。「」]{2,6}?)(?:は|が)'),
    ];
    for (final p in namePatterns) {
      final m = p.firstMatch(text);
      if (m?.group(1) != null) { name = m!.group(1); break; }
    }

    if (text.contains('電車') || text.contains('鉄道') || text.contains('地下鉄')) {
      transport = TransportType.train;
    } else if (text.contains('自転車') || text.contains('チャリ')) {
      transport = TransportType.bike;
    } else if (text.contains('バス')) {
      transport = TransportType.bus;
    } else if (text.contains('徒歩') || text.contains('歩き') || text.contains('歩い')) {
      transport = TransportType.walk;
    } else if (text.contains('車') || text.contains('自動車') || text.contains('クルマ')) {
      transport = TransportType.car;
    }

    final feeM = RegExp(r'(\d{2,6})\s*(?:円|えん)').firstMatch(text);
    if (feeM != null) parkingFee = feeM.group(1);

    if (parkingFee != null && transport != null && transport != TransportType.car) {
      warning    = '${transport.label}では駐車料金は不要です。自動的に削除しました。';
      parkingFee = null;
    }

    return SpeechExtractResult(
      name: name, transport: transport, parkingFee: parkingFee, warning: warning,
    );
  }
}

// ============================================================
// GPS + 住所変換
// ============================================================

// status の値は次の3つのみ（呼び出し側はこれで「住所」「座標」「取得不能」を区別する）:
//   'ok'             … 住所文字列の構築に成功
//   'address_failed' … 座標フォールバック（逆ジオコーディング不成立）
//   'gps_failed'     … 権限なし / GPS無効 / 位置取得そのものの失敗
// failReason（便BJ）は 'gps_failed' の時だけの理由の符号（サーバの reports.gps_fail_reason と1対1）：
//   'no_permission' … 権限なし / 'gps_disabled' … GPS無効 / 'gps_error' … 位置取得そのものの失敗。ほかの時は null。
//   ★address の字（ホームの現在地の帯に出す字）は lib/core/report_place_labels.dart の3つの定数。
Future<({String address, double? lat, double? lon, String status, String? failReason})> fetchGpsAddress() async {
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return (address: kGpsFailTextNoPermission, lat: null, lon: null, status: 'gps_failed', failReason: 'no_permission');
    }
    if (permission == LocationPermission.denied) {
      return (address: kGpsFailTextNoPermission, lat: null, lon: null, status: 'gps_failed', failReason: 'no_permission');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return (address: kGpsFailTextDisabled, lat: null, lon: null, status: 'gps_failed', failReason: 'gps_disabled');
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );

    if (!kIsWeb) {
      try {
        final placemarks = await placemarkFromCoordinates(
  pos.latitude,
  pos.longitude,
);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [
            p.administrativeArea, p.locality,
            p.subLocality, p.thoroughfare, p.subThoroughfare,
          ].where((e) => e != null && e.isNotEmpty).toList();
          if (p.street != null && p.street!.isNotEmpty) {
            final s = p.street!;
            final sub = p.subLocality ?? '';
            final idx = sub.isNotEmpty ? s.indexOf(sub) : -1;
            if (idx >= 0) {
              return (
              address: '${p.administrativeArea ?? ''}${p.locality ?? ''}${s.substring(idx)}',
              lat: pos.latitude, lon: pos.longitude, status: 'ok', failReason: null,
            );
            }
          }
          if (parts.isNotEmpty) {
            return (
            address: parts.join(''),
            lat: pos.latitude, lon: pos.longitude, status: 'ok', failReason: null,
          );
          }
        }
      } catch (e) {
        // 握り潰しをやめ、失敗理由をログに残す（座標フォールバックの原因追跡用）
        debugPrint('[gps] 逆ジオコーディング失敗: $e');
      }
    }
    return (
      address: '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
      lat: pos.latitude, lon: pos.longitude, status: 'address_failed', failReason: null,
    );
  } catch (e) {
    return (address: kGpsFailTextError, lat: null, lon: null, status: 'gps_failed', failReason: 'gps_error');
  }
}

// ============================================================
// 共通ユーティリティ
// ============================================================

// 共通スナックバー。
// ★2026-07 是正: 従来は fontSize 20 + padding(24,20) + margin 無しの floating だったため、
//   1行のメッセージでも画面幅いっぱいの巨大な帯になり、さらに floating は
//   ソフトキーボードの上へ持ち上がる仕様のため、入力中は画面中央付近に大きく居座っていた。
//   文字と余白を実用サイズへ落とし、明示的な margin で画面下部に寄せる。
//   （キーボード表示中に中央へ来る件は、呼び出し側で unfocus してから出すのが根治。
//     日報フォームの必須通知は home_screen 側で unfocus 済み）
void showJsSnackbar(BuildContext context, String msg,
    {bool isError = false, bool isWarning = false}) {
  if (!context.mounted) return;
  Color bg = FieldTokens.statusSuccess;
  if (isError)   bg = FieldTokens.statusError;
  if (isWarning) bg = FieldTokens.statusWarning;
  // 前景色は塗り面ごとに出し分ける。success(#6FD6B4) は明るい面のため
  // 白文字だと 1.76:1 で読めず、暗色 onAccent なら 8.75:1。
  // error/warning は白のまま＝今回のスコープ(success)外のため未変更。
  // ただし白は error 3.82:1 / warning 3.56:1 で AA 未達（本件以前からの既存課題）。
  final Color fg =
      (isError || isWarning) ? FieldTokens.textBody : FieldTokens.onAccent;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(
          color: fg, fontSize: 14, fontWeight: FontWeight.w600)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),   // 画面下部へ寄せる
      duration: const Duration(seconds: 2),
    ));
}

// ★title が null の時は題を置かない（便F8b-2・後から出す日報の途中で戻る時の窓＝見本 H1 の※が本文だけを書いている）。
//   null でない時の姿は今のまま（今の呼び手は全部字を渡している）。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String? title,
  required String message,
  String confirmText = '確認',
  String cancelText  = 'キャンセル',
  bool isDanger      = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: FieldTokens.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: title == null
          ? null
          : Text(title,
              style: TextStyle(color: isDanger ? FieldTokens.statusError : FieldTokens.accent)),
      content: Text(message,
          style: const TextStyle(color: FieldTokens.textBody, height: 1.6)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelText, style: const TextStyle(color: FieldTokens.textSupport)),
        ),
        ElevatedButton(
          style: isDanger ? ElevatedButton.styleFrom(
              backgroundColor: FieldTokens.statusError, foregroundColor: FieldTokens.textBody) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return r ?? false;
}

// ============================================================
// 【画面0】GateScreen
// ============================================================
class GateScreen extends StatefulWidget {
  const GateScreen({super.key});
  @override
  State<GateScreen> createState() => _GateScreenState();
}
class _GateScreenState extends State<GateScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoNavigate());
  }
  Future<void> _autoNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    // auth_tokenがない場合はログイン画面へ
    final token = prefs.getString('auth_token') ?? '';
    if (token.isEmpty) {
      if (!mounted) return;
      final loggedOut = prefs.getBool('logged_out') ?? false;
      if (loggedOut) {
        await prefs.remove('logged_out');
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context, '/login',
          arguments: {'showPin': true},
        );
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }
    final role = prefs.getString('user_role') ?? 'worker';
    if (!mounted) return;
    if (role == 'boss') { _pushBoss(context); }
    else if (role == 'admin_exec' || role == 'admin_office') {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const ForemanHomeScreen()));
    }
    else { await _pushWorker(context); }
  }
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: FieldTokens.bgBase,
    body: Center(child: CircularProgressIndicator(color: FieldTokens.accent)));
  Future<void> _pushWorker(BuildContext context) async {
    if (!context.mounted) return;

    // 当日の作業状態を確認して復元。
    // S5b追補(B案): 勤務状態は report_done_<shift> = '<業務日>|<status>' のシフト別2キー。
    // どのシフトで見るかは shift_type（業務日スコープで永続化・home_screen の _saveShiftType）に従う。
    // 旧3キー（today_date / today_work_status / report_done_shift）は読み捨て＝
    // 旧キーしか無い端末は復元されず通常起動になるだけ（袋小路なし）。
    // →再（2026-10-14・便BJ・見本 v2 の ⑫・ボスの裁定【Q141】）: 印は '<業務日>|<status>|<書いた人>' になった。
    //   読み方（業務日が同じで、書いた人が今の人＝前の形は今の人の物）は utils/today_marks.dart の1本。
    //   勤務の種類も1本（utils/saved_shift_type.dart の savedShiftTypeForNow＝業務日が同じで、書いた人が今の人の時だけ・
    //   ほかは 'day'）で読む（元: 'shift_type' を業務日も人も見ずに読んだ・検分 a253 の N8）。
    final prefs = await SharedPreferences.getInstance();
    final shiftType  = await savedShiftTypeForNow();
    final bizDate    = businessDateForShift(shiftType, DateTime.now());
    final workStatus = reportDoneStatusOf(prefs.getString(reportDoneKeyOf(shiftType)),
            bizDate: bizDate, me: todayMarkOwnerOf(prefs)) ??
        'idle';
    // K3(Q8): 'closed'（みなしの締め）は done と同じく「その日は終わっている」状態なので、
    //   下書きの全画面復元は行わない。完了ビューは HomeScreen 側が prefs を読んで出す。
    final shouldRestore = workStatus != 'idle' &&
        workStatus != 'done' &&
        workStatus != 'closed';

    // 報告完了(done)状態は HomeScreen 側(日報タブ)が prefs を読んで完了ビューを出すため、
    // ここでは全画面pushによる復元を行わない（復元経路を一本化）。
    // 業務日が変わったキーは次回書込で上書きされ、判定側も日付一致を要求するため掃除不要。

    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          restoreWorkStatus: shouldRestore ? workStatus : null,
        ),
      ),
    );
  }
  Future<void> _pushBoss(BuildContext context) async {
    // PIN成功フラグ確認（ワンショット・インメモリ）
    if (bossPinOk) {
      bossPinOk = false;
      if (context.mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ForemanHomeScreen()));
      }
      return;
    }

    final auth = LocalAuthentication();
    bool ok = false;
    try {
      final canCheck = await auth.canCheckBiometrics;
      final supported = await auth.isDeviceSupported();
      if (canCheck && supported) {
        ok = await auth.authenticate(
          localizedReason: '職長・管理者用へアクセスするには認証が必要です',
          options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
        );
      } else {
        ok = false;
        if (context.mounted) {
          showJsSnackbar(context, '生体認証が使えないためPINで続けます', isError: false);
        }
      }
    } catch (e) {
      debugPrint('生体認証エラー: $e');
      ok = false;
    }
    if (ok) {
      if (!context.mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const ForemanHomeScreen()));
    } else if (!ok && context.mounted) {
      Navigator.pushReplacementNamed(
        context, '/login',
        arguments: {'biometricFailed': true},
      );
    }
  }
}



// ============================================================
// 残業入力ダイアログ
// ============================================================

class OvertimeDialog extends StatefulWidget {
  const OvertimeDialog({
    super.key,
    required this.workerName,
    required this.gpsAddress,
    required this.onSubmit,
  });
  final String workerName;
  final String gpsAddress;
  final Future<void> Function(String start, String end, String content) onSubmit;

  @override
  State<OvertimeDialog> createState() => _OvertimeDialogState();
}

class _OvertimeDialogState extends State<OvertimeDialog> {
  TimeOfDay _start = TimeOfDay.now();
  TimeOfDay? _end;
  final _ctrl = TextEditingController();
  bool _submitting = false;
  // 送る途中で例外が出た時の字（便BJ・見本 v1 の ②）。窓の中に出す（窓が前に在るため、SnackBar だけだと隠れる）。
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

  Future<void> _pick(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : (_end ?? TimeOfDay.now()),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) { _start = picked; } else { _end = picked; }
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_end == null) {
      showJsSnackbar(context, '残業終了時刻を入力してください', isError: true);
      return;
    }
    setState(() { _submitting = true; _error = null; });
    // 元: 例外の受けが無く、投げると回る印が戻らないまま止まった。
    // →再（2026-10-14・便BJ・見本 v1 の ②）: 受けて、回るのを止め、窓の中に字を出す（もう一度押せる）。
    try {
      await widget.onSubmit(_fmt(_start), _fmt(_end!), _ctrl.text.trim());
    } catch (e) {
      debugPrint('残業報告の送信に失敗: $e');
      if (mounted) {
        setState(() { _submitting = false; _error = kSendFailedText; });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: FieldTokens.surfaceCard,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('⏰ 残業報告', style: TextStyle(color: FieldTokens.brand, fontWeight: FontWeight.bold)),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.workerName}さんの残業', style: const TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          const SizedBox(height: 16),
          const Text('残業開始時刻', style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          const SizedBox(height: 6),
          _TimeTile(label: _fmt(_start), onTap: () => _pick(true)),
          const SizedBox(height: 12),
          const Text('残業終了時刻（予定）', style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          const SizedBox(height: 6),
          _TimeTile(label: _end != null ? _fmt(_end!) : '-- : --', onTap: () => _pick(false), isEmpty: _end == null),
          const SizedBox(height: 12),
          const Text('残業内容', style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            maxLines: 2,
            style: const TextStyle(color: FieldTokens.textBody),
            decoration: const InputDecoration(
              hintText: '例：2階配線追加工事',
              hintStyle: TextStyle(color: FieldTokens.textHint),
            ),
          ),
          // 送れなかった時の字（便BJ）。形は休憩の短縮のシートの字の行と同じ（home_screen.dart の _ShortBreakSheet）。
          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.error_outline, color: FieldTokens.statusWarning, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(_error!,
                    style: const TextStyle(color: FieldTokens.statusWarning, fontSize: 12)),
              ),
            ]),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル', style: TextStyle(color: FieldTokens.textSupport)),
      ),
      ElevatedButton(
        onPressed: _submitting ? null : _submit,
        child: _submitting
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: FieldTokens.onAccent))
            : const Text('送信'),
      ),
    ],
  );
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.label, required this.onTap, this.isEmpty = false});
  final String label;
  final VoidCallback onTap;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FieldTokens.outline),
      ),
      child: Row(children: [
        const Icon(Icons.access_time, color: FieldTokens.accent, size: 18),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(
            color: isEmpty ? FieldTokens.textSupport : FieldTokens.textBody,
            fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
        const Icon(Icons.edit, color: FieldTokens.textSupport, size: 14),
      ]),
    ),
  );
}

// ============================================================
// END OF FILE — J's Awake App v1.1.1
// ============================================================


