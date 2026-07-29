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
import 'screens/share_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    if (dart.library.html) 'stub/notifications_stub.dart';
import 'package:geocoding/geocoding.dart'
    if (dart.library.html) 'stub/geocoding_stub.dart';
    import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/js_colors.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'utils/business_date.dart';

// ============================================================
// API設定
// ============================================================

import 'config/constants.dart';
const String API_URL = kApiBaseUrl;

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
  )..apiReportId = j['apiReportId'] as String?;
}

// ============================================================
// SharedPreferences キー
// ============================================================

class _K {
  static const reports        = 'worker_reports_history';
  static const names          = 'registered_worker_names';
  static const notifHours     = 'notification_hours';
  static const pendingReports = 'pending_reports';
}

// ============================================================
// ReportStore
// ============================================================

class ReportStore {
  static final ReportStore instance = ReportStore._();
  ReportStore._();


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

  Future<bool> addReport(WorkerReportItem item) async {
    final all = await loadAll();
    all.add(item);
    await saveAll(all);
    return await _sendToAPI([item]);
  }

  Future<bool> _sendToAPI(List<WorkerReportItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    final failed = <WorkerReportItem>[];
    for (final item in items) {
      try {
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
          'gps_address':         item.gpsAddress,
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
        // BE 受け口は routes/reports.js:320-321（appendEvent の gps_lat / gps_lon）。
        // ★reports 表の列でも content_hash の対象でもない＝既存ハッシュに影響しない。
        if (item.gpsLat != null) body['gps_lat'] = item.gpsLat;
        if (item.gpsLon != null) body['gps_lon'] = item.gpsLon;
        // photos:[{photo_type,base64}] 配列で送信（site→作業 / parking→駐車・生base64＝BE互換）
        final photos = <Map<String, dynamic>>[];
        for (final p in item.workPhotoPaths) {
          try {
            photos.add({'photo_type': 'site', 'base64': base64Encode(await File(p).readAsBytes())});
          } catch (e) {
            debugPrint('作業写真エンコード失敗: $e');
          }
        }
        for (final p in item.parkingPhotoPaths) {
          try {
            photos.add({'photo_type': 'parking', 'base64': base64Encode(await File(p).readAsBytes())});
          } catch (e) {
            debugPrint('駐車写真エンコード失敗: $e');
          }
        }
        if (photos.isNotEmpty) body['photos'] = photos;
        final response = await http.post(
          Uri.parse('$API_URL/reports'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200 || response.statusCode == 201) {
          final resBody = jsonDecode(response.body);
          item.apiReportId = resBody['report_id'] as String?;
        } else {
          failed.add(item);
        }
      } catch (e) {
        debugPrint('API送信失敗: $e');
        failed.add(item);
      }
    }
    if (failed.isNotEmpty) await _savePending(failed);
    return failed.isEmpty;
  }

  Future<void> _savePending(List<WorkerReportItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await _loadPending();
    final existingIds = existing.map((e) => e.id).toSet();
    final newItems = items.where((i) => !existingIds.contains(i.id)).toList();
    final all = [...existing, ...newItems];
    await prefs.setString(_K.pendingReports, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  Future<List<WorkerReportItem>> _loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_K.pendingReports);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => WorkerReportItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  Future<void> retryPending() async {
    final pending = await _loadPending();
    if (pending.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_K.pendingReports);
    await _sendToAPI(pending);
  }

  Future<int> pendingCount() async => (await _loadPending()).length;

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
// WorkerNameStore
// ============================================================

class WorkerNameStore {
  static final WorkerNameStore instance = WorkerNameStore._();
  WorkerNameStore._();

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_K.names) ?? [];
  }

  Future<void> add(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final list  = prefs.getStringList(_K.names) ?? [];
    if (!list.contains(name)) {
      list.add(name);
      list.sort();
      await prefs.setStringList(_K.names, list);
    }
  }

  Future<void> remove(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final list  = prefs.getStringList(_K.names) ?? [];
    list.remove(name);
    await prefs.setStringList(_K.names, list);
  }

  Future<void> saveAll(List<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_K.names, names);
  }
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
Future<({String address, double? lat, double? lon, String status})> fetchGpsAddress() async {
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return (address: '位置情報の権限がありません', lat: null, lon: null, status: 'gps_failed');
    }
    if (permission == LocationPermission.denied) {
      return (address: '位置情報の権限がありません', lat: null, lon: null, status: 'gps_failed');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return (address: 'GPS が無効です', lat: null, lon: null, status: 'gps_failed');
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
              lat: pos.latitude, lon: pos.longitude, status: 'ok',
            );
            }
          }
          if (parts.isNotEmpty) {
            return (
            address: parts.join(''),
            lat: pos.latitude, lon: pos.longitude, status: 'ok',
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
      lat: pos.latitude, lon: pos.longitude, status: 'address_failed',
    );
  } catch (e) {
    return (address: 'GPS取得失敗', lat: null, lon: null, status: 'gps_failed');
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
  Color bg = JsColors.success;
  if (isError)   bg = JsColors.error;
  if (isWarning) bg = JsColors.warning;
  // 前景色は塗り面ごとに出し分ける。success(#6FD6B4) は明るい面のため
  // 白文字だと 1.76:1 で読めず、暗色 onAccent なら 8.75:1。
  // error/warning は白のまま＝今回のスコープ(success)外のため未変更。
  // ただし白は error 3.82:1 / warning 3.56:1 で AA 未達（本件以前からの既存課題）。
  final Color fg =
      (isError || isWarning) ? JsColors.textStrong : JsPalette.onAccent;
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

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '確認',
  String cancelText  = 'キャンセル',
  bool isDanger      = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: JsColors.gunmetal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title,
          style: TextStyle(color: isDanger ? JsColors.error : JsColors.gold)),
      content: Text(message,
          style: const TextStyle(color: JsColors.offWhite, height: 1.6)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelText, style: const TextStyle(color: JsColors.silver)),
        ),
        ElevatedButton(
          style: isDanger ? ElevatedButton.styleFrom(
              backgroundColor: JsColors.error, foregroundColor: JsColors.textStrong) : null,
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
    backgroundColor: JsColors.background,
    body: Center(child: CircularProgressIndicator(color: JsColors.accent)));
  Future<void> _pushWorker(BuildContext context) async {
    if (!context.mounted) return;

    // 当日の作業状態を確認して復元。
    // S5b追補(B案): 勤務状態は report_done_<shift> = '<業務日>|<status>' のシフト別2キー。
    // どのシフトで見るかは shift_type（業務日スコープで永続化・home_screen の _saveShiftType）に従う。
    // 旧3キー（today_date / today_work_status / report_done_shift）は読み捨て＝
    // 旧キーしか無い端末は復元されず通常起動になるだけ（袋小路なし）。
    final prefs = await SharedPreferences.getInstance();
    final savedShift = prefs.getString('shift_type');
    final shiftType  = (savedShift == 'day' || savedShift == 'night') ? savedShift! : 'day';
    final bizDate    = businessDateForShift(shiftType, DateTime.now());
    final raw        = prefs.getString('report_done_$shiftType') ?? '';
    final parts      = raw.split('|');
    final savedDate  = parts.length == 2 ? parts[0] : '';
    final workStatus = parts.length == 2 ? parts[1] : 'idle';
    final shouldRestore = savedDate == bizDate &&
        workStatus != 'idle' &&
        workStatus != 'done';

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
    setState(() => _submitting = true);
    await widget.onSubmit(_fmt(_start), _fmt(_end!), _ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: JsColors.gunmetal,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('⏰ 残業報告', style: TextStyle(color: JsPalette.brand, fontWeight: FontWeight.bold)),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.workerName}さんの残業', style: const TextStyle(color: JsColors.silver, fontSize: 12)),
          const SizedBox(height: 16),
          const Text('残業開始時刻', style: TextStyle(color: JsColors.silver, fontSize: 12)),
          const SizedBox(height: 6),
          _TimeTile(label: _fmt(_start), onTap: () => _pick(true)),
          const SizedBox(height: 12),
          const Text('残業終了時刻（予定）', style: TextStyle(color: JsColors.silver, fontSize: 12)),
          const SizedBox(height: 6),
          _TimeTile(label: _end != null ? _fmt(_end!) : '-- : --', onTap: () => _pick(false), isEmpty: _end == null),
          const SizedBox(height: 12),
          const Text('残業内容', style: TextStyle(color: JsColors.silver, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            maxLines: 2,
            style: const TextStyle(color: JsColors.offWhite),
            decoration: const InputDecoration(
              hintText: '例：2階配線追加工事',
              hintStyle: TextStyle(color: JsColors.hint),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル', style: TextStyle(color: JsColors.silver)),
      ),
      ElevatedButton(
        onPressed: _submitting ? null : _submit,
        child: _submitting
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: JsPalette.onAccent))
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
        color: JsColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JsColors.divider),
      ),
      child: Row(children: [
        const Icon(Icons.access_time, color: JsColors.gold, size: 18),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(
            color: isEmpty ? JsColors.silver : JsColors.offWhite,
            fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
        const Icon(Icons.edit, color: JsColors.silver, size: 14),
      ]),
    ),
  );
}

// ============================================================
// 【画面2】WorkerNameScreen
// ============================================================

class WorkerNameScreen extends StatefulWidget {
  const WorkerNameScreen({super.key});
  @override
  State<WorkerNameScreen> createState() => _WorkerNameScreenState();
}

class _WorkerNameScreenState extends State<WorkerNameScreen> {
  final _ctrl = TextEditingController();
  List<String> _names = [];

  @override
  void initState()  { super.initState(); _load(); }
  @override
  void dispose()    { _ctrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final n = await WorkerNameStore.instance.load();
    if (mounted) setState(() => _names = n);
  }

  Future<void> _add() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    await WorkerNameStore.instance.add(name);
    _ctrl.clear();
    await _load();
    if (!mounted) return;
    showJsSnackbar(context, '✅ 「$name」を追加しました');
  }

  Future<void> _delete(String name) async {
    final ok = await showConfirmDialog(context,
      title: '削除確認', message: '「$name」を削除しますか？',
      confirmText: '削除', isDanger: true);
    if (ok) { await WorkerNameStore.instance.remove(name); await _load(); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('職人名管理')),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                labelText: '名前を追加',
                prefixIcon: Icon(Icons.person_add, color: JsColors.silver),
              ),
              style: const TextStyle(color: JsColors.offWhite),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _add,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(56, 52), padding: EdgeInsets.zero,
                // 生成り抜き（画面内の主ボタン）: 面は透明・枠1.5px・文字はトークン
                backgroundColor: Colors.transparent,
                foregroundColor: JsFormTokens.outlineButtonBorder,
                side: const BorderSide(
                    color: JsFormTokens.outlineButtonBorder, width: 1.5),
                elevation: 0,
                shadowColor: Colors.transparent),
            child: const Icon(Icons.add),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _names.isEmpty
            ? const Center(child: Text('職人名が登録されていません',
                style: TextStyle(color: JsColors.silver)))
            : ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _names.length,
                itemBuilder: (_, i) => ListTile(
                  key: ValueKey(_names[i]),
                  leading: const Icon(Icons.drag_handle, color: JsColors.silver),
                  title: Text(_names[i], style: const TextStyle(color: JsColors.offWhite)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: JsColors.error),
                    onPressed: () => _delete(_names[i]),
                  ),
                ),
                onReorder: (oldIndex, newIndex) async {
                  final list = List<String>.from(_names);
                  list.insert(newIndex, list.removeAt(oldIndex));
                  setState(() => _names = list);
                  await WorkerNameStore.instance.saveAll(list);
                },
              ),
      ),
    ]),
  );
}

// ============================================================
// 【画面3】SummaryScreen
// ============================================================

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});
  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  List<WorkerReportItem> _all   = [];
  List<WorkerReportItem> _today = [];
  bool _loading = true;
  bool _showAll = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all   = await ReportStore.instance.loadAll();
    final today = await ReportStore.instance.loadToday();
    if (mounted) setState(() { _all = all; _today = today; _loading = false; });
  }

  List<WorkerReportItem> get _shown => _showAll ? _all : _today;

  Future<void> _toggleActive(WorkerReportItem item) async {
    setState(() => item.isActive = !item.isActive);
    await ReportStore.instance.saveAll(_all);
  }

  Future<void> _deleteItem(WorkerReportItem item) async {
    setState(() { _all.remove(item); _today.remove(item); });
    await ReportStore.instance.saveAll(_all);
  }

  Future<void> _shareItem(WorkerReportItem item) async {
    if (!mounted) return;
    final reportId = item.apiReportId ?? item.id;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ShareScreen(
      reportId: reportId,
      workerName: item.name,
      reportDate: item.timestamp.toIso8601String().substring(0, 10),
    )));
  }
  Future<void> _clearAll() async {
    final ok = await showConfirmDialog(context,
      title: '⚠️ 全件削除',
      message: '全ての報告データを削除します。\nこの操作は取り消せません。',
      confirmText: '削除する', isDanger: true);
    if (ok) {
      await ReportStore.instance.clearAll();
      setState(() { _all.clear(); _today.clear(); });
    }
  }

  String _buildReportText() {
    final active = _shown.where((r) => r.isActive).toList();
    if (active.isEmpty) return '報告データがありません';

    final now = DateTime.now();
    final dateStr =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    final Map<String, List<WorkerReportItem>> grouped = {};
    for (final r in active) {
      final key = r.gpsAddress.isEmpty ? '現場住所 未取得' : r.gpsAddress;
      grouped.putIfAbsent(key, () => []).add(r);
    }

    final buf = StringBuffer();
    buf.writeln("【J's 日報報告】");
    buf.writeln('報告日付：$dateStr');
    buf.writeln();

    for (final entry in grouped.entries) {
      buf.writeln('■ 現場住所：${entry.key}');
      buf.writeln();
      final workers = entry.value
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (final w in workers) {
        buf.writeln('【${w.timeLabel}】${w.name}：${w.transport.label}');
        if (w.parkingFee != null && w.parkingFee!.isNotEmpty) {
          buf.writeln('　駐車料金：${w.parkingFee}円${w.parkingPhotoPath != null ? ' 📷' : ''}');
        }
        if (w.workContent.isNotEmpty) {
          buf.writeln('　作業内容：${w.workContent}${w.workPhotoPath != null ? ' 📷' : ''}');
        }
      }
      buf.writeln();
    }
    buf.write('以上、本日も安全作業で終了しました。');
    return buf.toString();
  }

  // 写真ウィジェットリスト生成
  List<Widget> _buildPhotoWidgets() {
    final active = _shown.where((r) => r.isActive).toList();
    final widgets = <Widget>[];
    for (final r in active) {
      if (r.parkingPhotoPath != null && File(r.parkingPhotoPath!).existsSync()) {
        widgets.add(_PhotoPreview(
          label: '${r.name} — 駐車料金領収書',
          path: r.parkingPhotoPath!,
        ));
      }
      if (r.workPhotoPath != null && File(r.workPhotoPath!).existsSync()) {
        widgets.add(_PhotoPreview(
          label: '${r.name} — 作業写真',
          path: r.workPhotoPath!,
        ));
      }
    }
    return widgets;
  }

  Future<void> _shareReport() async {
    final active = _shown.where((r) => r.isActive).toList();
    final photoPaths = <String>[];
    for (final r in active) {
      if (r.parkingPhotoPath != null && File(r.parkingPhotoPath!).existsSync()) {
        photoPaths.add(r.parkingPhotoPath!);
      }
      if (r.workPhotoPath != null && File(r.workPhotoPath!).existsSync()) {
        photoPaths.add(r.workPhotoPath!);
      }
    }

    final text = _buildReportText();

    if (photoPaths.isNotEmpty) {
      final attachPhotos = await showConfirmDialog(context,
        title:       '📷 写真を添付しますか？',
        message:     '${photoPaths.length}枚の写真があります。\n日報と一緒に共有しますか？',
        confirmText: '写真も添付する',
        cancelText:  'テキストのみ',
      );
      if (attachPhotos) {
        final xFiles = photoPaths.map((p) => XFile(p)).toList();
        await Share.shareXFiles(xFiles, text: text, subject: "J's 日報報告");
        return;
      }
    }
    await Share.share(text, subject: "J's 日報報告");
  }

  void _previewReport() {
    final photoWidgets = _buildPhotoWidgets();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: JsColors.gunmetal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ヘッダー
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('📋 日報プレビュー',
                        style: TextStyle(
                            color: JsColors.gold,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: JsColors.silver),
                  ),
                ],
              ),
            ),
            const Divider(),
            // コンテンツ
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // テキスト
                    SelectableText(_buildReportText(),
                        style: const TextStyle(
                            color: JsColors.offWhite,
                            height: 1.7,
                            fontFamily: 'monospace',
                            fontSize: 13)),
                    // 写真
                    if (photoWidgets.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text('📷 添付写真',
                          style: TextStyle(
                              color: JsColors.gold,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...photoWidgets,
                    ],
                  ],
                ),
              ),
            ),
            // ボタン
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () { Navigator.pop(ctx); _shareReport(); },
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('共有する'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active   = _shown.where((r) => r.isActive).toList();
    final totalFee = active
        .where((r) => r.parkingFee != null && r.parkingFee!.isNotEmpty)
        .fold<int>(0, (s, r) => s + (int.tryParse(r.parkingFee!) ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('集計・日報'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? '今日のみ' : '全件表示',
                style: const TextStyle(color: JsColors.gold)),
          ),
          IconButton(icon: const Icon(Icons.preview), tooltip: 'プレビュー', onPressed: _previewReport),
          IconButton(icon: const Icon(Icons.delete_sweep), tooltip: '全件削除', onPressed: _clearAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
          : Column(children: [
              _SummaryCard(count: active.length, totalFee: totalFee, dateMode: _showAll ? '全件' : '本日'),
              const Divider(height: 1),
              Expanded(
                child: _shown.isEmpty
                    ? Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inbox, size: 64, color: JsColors.divider),
                          const SizedBox(height: 16),
                          Text(_showAll ? '報告データがありません' : '本日の報告がありません',
                              style: const TextStyle(color: JsColors.silver)),
                        ],
                      ))
                    : RefreshIndicator(
                        color: JsColors.gold,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _shown.length,
                          itemBuilder: (_, i) => _ReportCard(
                            item:     _shown[i],
                            onToggle: () => _toggleActive(_shown[i]),
                            onDelete: () => _deleteItem(_shown[i]),
                            onShare:  () => _shareItem(_shown[i]),
                          ),
                        ),
                      ),
              ),
            ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _previewReport,
                icon:  const Icon(Icons.preview),
                label: const Text('プレビュー'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _shareReport,
                // 生成り抜き（画面内の主ボタン）
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: JsFormTokens.outlineButtonBorder,
                  side: const BorderSide(
                      color: JsFormTokens.outlineButtonBorder, width: 1.5),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                icon:  const Icon(Icons.share),
                label: const Text('共有する'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ============================================================
// 写真プレビューウィジェット
// ============================================================

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.label, required this.path});
  final String label;
  final String path;

  void _showFullScreen(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: JsColors.background,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: JsColors.textStrong, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: JsColors.silver, fontSize: 11)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showFullScreen(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 2),
        const Text('タップで拡大',
            style: TextStyle(color: JsColors.silver, fontSize: 10)),
      ],
    ),
  );
}

// ============================================================
// 集計カード
// ============================================================

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count, required this.totalFee, required this.dateMode});
  final int count;
  final int totalFee;
  final String dateMode;

  String _fmt(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(14),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(
      color: JsColors.gunmetal,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: JsColors.divider),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _StatItem(label: '$dateMode の報告数', value: '$count 件'),
        Container(width: 1, height: 36, color: JsColors.divider),
        _StatItem(label: '駐車料金合計', value: '¥ ${_fmt(totalFee)}'),
      ],
    ),
  );
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(color: JsColors.silver, fontSize: 11)),
    const SizedBox(height: 6),
    Text(value, style: const TextStyle(
        color: JsColors.gold, fontSize: 22, fontWeight: FontWeight.bold)),
  ]);
}

// ============================================================
// 報告カード
// ============================================================

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.item, required this.onToggle, required this.onDelete, required this.onShare});
  final WorkerReportItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  void _showPhoto(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: JsColors.background,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: JsColors.textStrong, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: item.isActive ? 1.0 : 0.38,
    duration: const Duration(milliseconds: 200),
    child: Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Switch(value: item.isActive, onChanged: (_) => onToggle()),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(item.name, style: const TextStyle(
                      color: JsColors.offWhite, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 8),
                  _Badge(label: item.transport.label),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time, size: 12, color: JsColors.silver),
                  const SizedBox(width: 3),
                  Text(item.timeLabel,
                      style: const TextStyle(color: JsColors.silver, fontSize: 12)),
                  if (item.parkingFee != null && item.parkingFee!.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.local_parking, size: 12, color: JsColors.gold),
                    const SizedBox(width: 3),
                    Text('¥${item.parkingFee}', style: const TextStyle(
                        color: JsColors.gold, fontSize: 12, fontWeight: FontWeight.bold)),
                    if (item.parkingPhotoPath != null) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _showPhoto(context, item.parkingPhotoPath!),
                        child: const Icon(Icons.camera_alt, size: 16, color: JsColors.success),
                      ),
                    ],
                  ],
                ]),
                if (item.workContent.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.construction, size: 12, color: JsColors.silver),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(item.workContent,
                              style: const TextStyle(color: JsColors.offWhite, fontSize: 12),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        if (item.workPhotoPath != null) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _showPhoto(context, item.workPhotoPath!),
                            child: const Icon(Icons.photo, size: 16, color: JsColors.success),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (item.gpsAddress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('📍 ${item.gpsAddress}',
                        style: const TextStyle(color: JsColors.silver, fontSize: 10),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share, color: JsColors.gold, size: 20),
            onPressed: onShare,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: JsColors.error, size: 20),
            onPressed: onDelete,
          ),
        ]),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: JsColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: JsColors.divider),
    ),
    child: Text(label, style: const TextStyle(color: JsColors.silver, fontSize: 11)),
  );
}

// ============================================================
// END OF FILE — J's Awake App v1.1.1
// ============================================================


