// ============================================================
// J's Awake App v1.1.1 — main.dart 完全版
// 株式会社J's 電気工事業 日報アプリ
// v1.1.1変更点：プレビュー画面に写真表示追加
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/site_select_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/share_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
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

// ============================================================
// API設定
// ============================================================

const String API_URL = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

// ============================================================
// エントリーポイント
// ============================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
  if (!kIsWeb) {
    await NotificationManager.instance.initialize();
  }
  runApp(const JsAwakeApp());
}

// ============================================================
// ブランドカラー
// ============================================================

class JsColors {
  static const black    = Color(0xFF111111);
  static const gunmetal = Color(0xFF2A2A2A);
  static const gold     = Color(0xFFD4AF37);
  static const silver   = Color(0xFF9E9E9E);
  static const offWhite = Color(0xFFF5F5F0);
  static const surface  = Color(0xFF1E1E1E);
  static const divider  = Color(0xFF3A3A3A);
  static const success  = Color(0xFF2E7D5E);
  static const error    = Color(0xFFB71C1C);
  static const warning  = Color(0xFFE65100);
}

// ============================================================
// アプリルート
// ============================================================

class JsAwakeApp extends StatelessWidget {
  const JsAwakeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "J's Inc. 日報報告APP",
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const LoginScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/gate': (_) => const GateScreen(),
        '/register': (_) => const RegisterScreen(),
      },
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: JsColors.black,
      colorScheme: const ColorScheme.dark(
        primary:      JsColors.gold,
        secondary:    JsColors.silver,
        surface:      JsColors.gunmetal,
        background:   JsColors.black,
        error:        JsColors.error,
        onPrimary:    Colors.black,
        onSecondary:  JsColors.offWhite,
        onSurface:    JsColors.offWhite,
        onBackground: JsColors.offWhite,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: JsColors.black,
        foregroundColor: JsColors.gold,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: JsColors.gold,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: JsColors.gold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: JsColors.gold,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: JsColors.gold,
          side: const BorderSide(color: JsColors.gold),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: JsColors.gunmetal,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: JsColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: JsColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: JsColors.gold, width: 2),
        ),
        labelStyle: const TextStyle(color: JsColors.silver),
        hintStyle: const TextStyle(color: Color(0xFF666666)),
      ),
      cardTheme: CardThemeData(
        color: JsColors.gunmetal,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: JsColors.divider),
        ),
      ),
      dividerTheme: const DividerThemeData(color: JsColors.divider, thickness: 1),
    );
  }
}

// ============================================================
// Enum: 交通手段
// ============================================================

enum TransportType {
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
    this.parkingFee,
    this.parkingPhotoPath,
    this.workContent = '',
    this.workPhotoPath,
    this.gpsAddress = '',
    DateTime? timestamp,
    this.isActive = true,
    String? id,
    this.apiReportId,
  }) : timestamp = timestamp ?? DateTime.now(),
       id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final String name;
  final TransportType transport;
  final String? parkingFee;
  final String? parkingPhotoPath;
  final String workContent;
  final String? workPhotoPath;
  final String gpsAddress;
  final DateTime timestamp;
  bool isActive;
  String? apiReportId;

  String get timeLabel {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Map<String, dynamic> toJson() => {
    'id':               id,
    'name':             name,
    'transport':        transport.name,
    'parkingFee':       parkingFee,
    'parkingPhotoPath': parkingPhotoPath,
    'workContent':      workContent,
    'workPhotoPath':    workPhotoPath,
    'gpsAddress':       gpsAddress,
    'timestamp':        timestamp.toIso8601String(),
    'isActive':         isActive,
    'apiReportId':      apiReportId,
  };

  static WorkerReportItem fromJson(Map<String, dynamic> j) => WorkerReportItem(
    id:               j['id'] as String?,
    name:             j['name'] as String? ?? '',
    transport:        TransportType.values.firstWhere(
      (t) => t.name == j['transport'], orElse: () => TransportType.train),
    parkingFee:       j['parkingFee']       as String?,
    parkingPhotoPath: j['parkingPhotoPath'] as String?,
    workContent:      j['workContent']      as String? ?? '',
    workPhotoPath:    j['workPhotoPath']    as String?,
    gpsAddress:       j['gpsAddress']       as String? ?? '',
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
  static const reports    = 'worker_reports_history';
  static const names      = 'registered_worker_names';
  static const notifHours = 'notification_hours';
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

  Future<void> addReport(WorkerReportItem item) async {
    final all = await loadAll();
    all.add(item);
    await saveAll(all);
    await _sendToAPI([item]);
  }

Future<void> _sendToAPI(List<WorkerReportItem> items) async {
    try {
      for (final item in items) {
        final response = await http.post(
          Uri.parse('$API_URL/reports'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${(await SharedPreferences.getInstance()).getString('auth_token') ?? ""}',
          },
          body: jsonEncode({
            'worker_name': item.name,
            'worker_company': '',
            'report_date': item.timestamp.toIso8601String().substring(0, 10),
            'clock_in_time': item.timeLabel + ':00',
            'transport_type': item.transport.name,
            'parking_fee': item.parkingFee != null ? double.tryParse(item.parkingFee!) : null,
            'gps_address': item.gpsAddress,
            'work_content': item.workContent,
          }),
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200 && response.statusCode != 201) {
          debugPrint('API エラー: ${response.statusCode} - ${response.body}');
        } else {
          final resBody = jsonDecode(response.body);
          item.apiReportId = resBody['report_id'] as String?;
          debugPrint('API 送信成功: ${item.name} id=${item.apiReportId}');
        }
      }
    } catch (e) {
      debugPrint('API 送信失敗: $e');
    }
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
      const InitializationSettings(android: androidInit, iOS: iosInit));
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
    } catch (e) {
      debugPrint('通知スケジュール失敗: $e');
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

  Future<bool> initialize() async {
    _initialized = await _speech.initialize(
      onError: (e) => debugPrint('音声エラー: ${e.errorMsg}'),
    );
    return _initialized;
  }

  bool get isAvailable => _initialized && _speech.isAvailable;
  bool get isListening => _speech.isListening;

  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    if (!_initialized) return;
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) =>
          onResult(r.recognizedWords, r.finalResult),
      localeId:  'ja_JP',
      listenFor: const Duration(seconds: 60),
      pauseFor:  const Duration(seconds: 15),
    );
  }

  Future<void> stop()   async => _speech.stop();
  Future<void> cancel() async => _speech.cancel();

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

Future<String> fetchGpsAddress() async {
  try {
    var status = await Permission.location.status;
    if (!status.isGranted) status = await Permission.location.request();
    if (!status.isGranted) return '位置情報の権限がありません';
    if (!await Geolocator.isLocationServiceEnabled()) return 'GPS が無効です';

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
          if (parts.isNotEmpty) return parts.join('');
        }
      } catch (_) {}
    }
    return '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
  } catch (e) {
    return 'GPS取得失敗';
  }
}

// ============================================================
// 共通ユーティリティ
// ============================================================

void showJsSnackbar(BuildContext context, String msg,
    {bool isError = false, bool isWarning = false}) {
  if (!context.mounted) return;
  Color bg = JsColors.success;
  if (isError)   bg = JsColors.error;
  if (isWarning) bg = JsColors.warning;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              backgroundColor: JsColors.error, foregroundColor: Colors.white) : null,
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

class GateScreen extends StatelessWidget {
  const GateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const Text('日報報告',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: JsColors.gold,
                    letterSpacing: 4,
                  )),
              const SizedBox(height: 8),
              const Text("J's Inc.",
                  style: TextStyle(color: JsColors.silver, fontSize: 14)),
              const Spacer(flex: 2),
              ElevatedButton.icon(
                onPressed: () => _pushWorker(context),
                icon:  const Icon(Icons.engineering),
                label: const Text('職 人 用'),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _pushBoss(context),
                icon:  const Icon(Icons.supervisor_account),
                label: const Text('職長・管理者用'),
              ),
              const Spacer(),
              const Text("職人 × AI × J's ＝ 覚醒",
                  style: TextStyle(color: JsColors.silver, fontSize: 11)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _pushWorker(BuildContext context) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const SharedWorkerForm(
        screenTitle: '職人用 — 日報報告', isBossMode: false)));

  Future<void> _pushBoss(BuildContext context) async {
    final auth = LocalAuthentication();
    bool ok = false;
    try {
      final supported = await auth.isDeviceSupported();
      if (supported) {
        ok = await auth.authenticate(
          localizedReason: '職長・管理者用へアクセスするには認証が必要です',
          options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
        );
      } else { ok = true; }
    } catch (_) { ok = true; }
    if (ok && context.mounted) {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => const SharedWorkerForm(
            screenTitle: '職長・管理者用 — 日報管理', isBossMode: true)));
    }
  }
}

// ============================================================
// 【画面1】SharedWorkerForm
// ============================================================

class SharedWorkerForm extends StatefulWidget {
  const SharedWorkerForm({
    super.key,
    required this.screenTitle,
    required this.isBossMode,
  });
  final String screenTitle;
  final bool   isBossMode;

  @override
  State<SharedWorkerForm> createState() => _SharedWorkerFormState();
}

class _SharedWorkerFormState extends State<SharedWorkerForm> {
  final _nameCtrl        = TextEditingController();
  final _feeCtrl         = TextEditingController();
  final _workContentCtrl = TextEditingController();
  final _speechMgr       = SpeechManager();
  final _imagePicker     = ImagePicker();

  TransportType _transport    = TransportType.train;
  String?       _photoPath;
  String?       _workPhotoPath;
  String        _gpsAddress   = '';
  bool          _gpsLoading   = false;
  bool          _isListening  = false;
  bool          _submitting   = false;
  bool          _voiceMode    = false;
  Map<String, dynamic>? _selectedSite;

  List<String> _nameSuggestions = [];
  bool         _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _speechMgr.initialize();
    _fetchGps();
    _loadNames();
    _nameCtrl.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _feeCtrl.dispose();
    _workContentCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchGps() async {
    setState(() => _gpsLoading = true);
    final addr = await fetchGpsAddress();
    if (mounted) setState(() { _gpsAddress = addr; _gpsLoading = false; });
  }

  Future<void> _loadNames() async {
    final n = await WorkerNameStore.instance.load();
    if (mounted) setState(() => _nameSuggestions = n);
  }

  void _onNameChanged() {
    setState(() => _showSuggestions =
        _nameCtrl.text.isNotEmpty && _nameSuggestions.isNotEmpty);
  }

  List<String> get _filtered {
    final q = _nameCtrl.text;
    if (q.isEmpty) return _nameSuggestions;
    return _nameSuggestions.where((n) => n.contains(q)).toList();
  }

  Future<void> _startVoiceReport() async {
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      showJsSnackbar(context, 'マイクの権限が必要です', isError: true);
      return;
    }
    setState(() { _isListening = true; _voiceMode = false; });
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VoiceDialog(
        manager:   _speechMgr,
        title:     '🎤 音声報告モード',
        hint:      '例：「太郎は電車で来ました」\n「花子は車で来ました 駐車料金1000円」',
        onConfirm: (text) { Navigator.pop(ctx); _applyVoiceReport(text); },
        onCancel:  () { _speechMgr.cancel(); Navigator.pop(ctx); },
      ),
    );
    setState(() => _isListening = false);
  }

  void _applyVoiceReport(String text) {
    final r = _speechMgr.extractInfo(text);
    setState(() {
      if (r.name != null)      _nameCtrl.text = r.name!;
      if (r.transport != null) _transport     = r.transport!;
      if (r.parkingFee != null) {
        _feeCtrl.text = r.parkingFee!;
      } else {
        _feeCtrl.clear();
        _photoPath = null;
      }
    });
    if (r.warning != null) showJsSnackbar(context, '⚠️ ${r.warning}', isWarning: true);
  }

  Future<void> _startVoiceWork() async {
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      showJsSnackbar(context, 'マイクの権限が必要です', isError: true);
      return;
    }
    setState(() { _isListening = true; _voiceMode = true; });
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VoiceDialog(
        manager:   _speechMgr,
        title:     '🎤 作業内容 音声入力',
        hint:      '例：「1階電気配線工事 コンセント10箇所設置」',
        onConfirm: (text) {
          Navigator.pop(ctx);
          setState(() {
            if (_workContentCtrl.text.isEmpty) {
              _workContentCtrl.text = text;
            } else {
              _workContentCtrl.text += '。$text';
            }
          });
        },
        onCancel: () { _speechMgr.cancel(); Navigator.pop(ctx); },
      ),
    );
    setState(() => _isListening = false);
  }

  Future<void> _takeParkingPhoto() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      showJsSnackbar(context, 'カメラの権限が必要です', isError: true);
      return;
    }
    final f = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (f != null && mounted) {
      setState(() => _photoPath = f.path);
      showJsSnackbar(context, '✅ 領収書の写真を撮影しました');
    }
  }

  Future<void> _takeWorkPhoto() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      showJsSnackbar(context, 'カメラの権限が必要です', isError: true);
      return;
    }
    final f = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (f != null && mounted) {
      setState(() => _workPhotoPath = f.path);
      showJsSnackbar(context, '✅ 作業写真を撮影しました');
    }
  }

  Future<bool> _validate() async {
    if (_nameCtrl.text.trim().isEmpty) {
      showJsSnackbar(context, '名前を入力してください', isError: true);
      return false;
    }
    if (_transport == TransportType.car) {
      final fee      = _feeCtrl.text.trim();
      final hasPhoto = _photoPath != null;
      if (fee.isEmpty && !hasPhoto) {
        showJsSnackbar(context, '車の場合は駐車料金または領収書写真が必要です', isError: true);
        return false;
      }
      if (fee.isNotEmpty && !hasPhoto) {
        final ok = await showConfirmDialog(context,
          title: '⚠️ 写真なしで送信しますか？',
          message: '駐車料金 $fee 円のみで送信します。\n推奨：領収書の写真も撮影してください。',
          confirmText: 'このまま送信', cancelText: '写真を撮る');
        if (!ok) return false;
      }
    }
    return true;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final valid = await _validate();
    if (!valid) return;

    setState(() => _submitting = true);
    final name = _nameCtrl.text.trim();
    await WorkerNameStore.instance.add(name);
    await ReportStore.instance.addReport(WorkerReportItem(
      name:             name,
      transport:        _transport,
      parkingFee:       _transport == TransportType.car ? _feeCtrl.text.trim() : null,
      parkingPhotoPath: _photoPath,
      workContent:      _workContentCtrl.text.trim(),
      workPhotoPath:    _workPhotoPath,
      gpsAddress:       _gpsAddress,
    ));
    if (mounted) {
      setState(() {
        _submitting    = false;
        _transport     = TransportType.train;
        _photoPath     = null;
        _workPhotoPath = null;
      });
      _nameCtrl.clear();
      _feeCtrl.clear();
      _workContentCtrl.clear();
      await _loadNames();
      showJsSnackbar(context, '✅ ${name}の報告を送信しました');
    }
  }

  void _openNotifSettings() {
    if (kIsWeb) {
      showJsSnackbar(context, '通知設定はAndroid/iOSのみ対応しています', isWarning: true);
      return;
    }
    final nm      = NotificationManager.instance;
    final current = Set<int>.from(nm.hours);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: JsColors.gunmetal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('🔔 通知時刻の設定', style: TextStyle(color: JsColors.gold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView.builder(
              itemCount: 24,
              itemBuilder: (_, i) => CheckboxListTile(
                dense: true,
                title: Text('${i.toString().padLeft(2, '0')}:00',
                    style: const TextStyle(color: JsColors.offWhite)),
                value: current.contains(i),
                activeColor: JsColors.gold,
                checkColor: Colors.black,
                onChanged: (v) => setSt(() {
                  if (v == true) current.add(i); else current.remove(i);
                }),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル', style: TextStyle(color: JsColors.silver)),
            ),
            ElevatedButton(
              onPressed: () async {
                await nm.setHours(current.toList());
                if (ctx.mounted) Navigator.pop(ctx);
                showJsSnackbar(context, '✅ 通知時刻を更新しました');
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.screenTitle),
        actions: widget.isBossMode ? [
          IconButton(
            icon: const Icon(Icons.inbox),
            tooltip: '受信トレイ',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => InboxScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.location_on),
            tooltip: '現場選択',
            onPressed: () async {
              final site = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SiteSelectScreen()));
              if (site != null) setState(() => _selectedSite = site);
            },
          ),
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: '職人名管理',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const WorkerNameScreen()))
                .then((_) => _loadNames()),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_active),
            tooltip: '通知設定',
            onPressed: _openNotifSettings,
          ),
        ] : null,
      ),
      floatingActionButton: widget.isBossMode
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SummaryScreen())),
              backgroundColor: JsColors.gold,
              foregroundColor: Colors.black,
              icon:  const Icon(Icons.assessment),
              label: const Text('集計モードへ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GpsCard(address: _gpsAddress, isLoading: _gpsLoading, onRefresh: _fetchGps),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isListening ? null : _startVoiceReport,
                  icon: Icon(_isListening && !_voiceMode ? Icons.mic : Icons.mic_none),
                  label: Text(_isListening && !_voiceMode ? '聞いています...' : '🎤  音声報告モード'),
                ),
              ),

              const _DividerLabel(label: 'または手動入力'),

              _NameField(
                controller: _nameCtrl,
                suggestions: _filtered,
                showSuggestions: _showSuggestions && _filtered.isNotEmpty,
                onSelect: (n) => setState(() {
                  _nameCtrl.text = n;
                  _showSuggestions = false;
                }),
              ),
              const SizedBox(height: 16),

              const _Label(text: '本日の交通手段 *'),
              const SizedBox(height: 8),
              _TransportSelector(
                selected: _transport,
                onChanged: (t) => setState(() {
                  _transport = t;
                  if (t != TransportType.car) { _feeCtrl.clear(); _photoPath = null; }
                }),
              ),
              const SizedBox(height: 16),

              if (_transport == TransportType.car) ...[
                _ParkingSection(
                  controller: _feeCtrl,
                  photoPath:  _photoPath,
                  onTakePhoto:  _takeParkingPhoto,
                  onClearPhoto: () => setState(() => _photoPath = null),
                ),
                const SizedBox(height: 16),
              ],

              // 作業内容セクション
              const _Label(text: '作業内容'),
              const SizedBox(height: 8),
              TextField(
                controller: _workContentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '作業内容を入力',
                  hintText: '例：1階電気配線工事 コンセント10箇所設置',
                  prefixIcon: Icon(Icons.construction, color: JsColors.silver),
                  alignLabelWithHint: true,
                ),
                style: const TextStyle(color: JsColors.offWhite),
              ),
              const SizedBox(height: 8),

              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isListening ? null : _startVoiceWork,
                    icon: Icon(
                        _isListening && _voiceMode ? Icons.mic : Icons.mic_none,
                        size: 18),
                    label: Text(
                      _isListening && _voiceMode ? '聞いています...' : '🎤 音声で作業内容入力',
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  ),
                ),
                const SizedBox(width: 8),
                _CameraBtn(hasPhoto: _workPhotoPath != null, onTap: _takeWorkPhoto),
              ]),

              if (_workPhotoPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(_workPhotoPath!),
                            height: 120, width: double.infinity, fit: BoxFit.cover),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _workPhotoPath = null),
                        child: Container(
                          margin: const EdgeInsets.all(6),
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                      : const Text('報告を送信する'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// サブウィジェット
// ============================================================

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: JsColors.silver, fontSize: 13));
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label, style: const TextStyle(color: JsColors.silver, fontSize: 12)),
      ),
      const Expanded(child: Divider()),
    ]),
  );
}

class _GpsCard extends StatelessWidget {
  const _GpsCard({required this.address, required this.isLoading, required this.onRefresh});
  final String address;
  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: JsColors.gunmetal,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: JsColors.divider),
    ),
    child: Row(children: [
      const Icon(Icons.location_on, color: JsColors.gold, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: isLoading
            ? const Text('GPS 取得中...', style: TextStyle(color: JsColors.silver))
            : Text(address.isEmpty ? '現場住所 未取得' : address,
                style: const TextStyle(color: JsColors.offWhite, fontSize: 13), maxLines: 2),
      ),
      IconButton(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh, color: JsColors.silver, size: 20),
        padding: EdgeInsets.zero, constraints: const BoxConstraints(),
      ),
    ]),
  );
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller, required this.suggestions,
    required this.showSuggestions, required this.onSelect,
  });
  final TextEditingController controller;
  final List<String> suggestions;
  final bool showSuggestions;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: '名前 *',
          prefixIcon: Icon(Icons.person, color: JsColors.silver),
        ),
        style: const TextStyle(color: JsColors.offWhite),
        textInputAction: TextInputAction.next,
      ),
      if (showSuggestions)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: JsColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: JsColors.divider),
          ),
          child: Column(
            children: suggestions.take(5).map((n) => ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline, color: JsColors.silver, size: 18),
              title: Text(n, style: const TextStyle(color: JsColors.offWhite)),
              onTap: () => onSelect(n),
            )).toList(),
          ),
        ),
    ],
  );
}

class _TransportSelector extends StatelessWidget {
  const _TransportSelector({required this.selected, required this.onChanged});
  final TransportType selected;
  final void Function(TransportType) onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8, runSpacing: 8,
    children: TransportType.values.map((t) {
      final active = t == selected;
      return GestureDetector(
        onTap: () => onChanged(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: active ? JsColors.gold : JsColors.gunmetal,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: active ? JsColors.gold : JsColors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(t.icon, size: 16, color: active ? Colors.black : JsColors.silver),
              const SizedBox(width: 5),
              Text(t.label, style: TextStyle(
                color: active ? Colors.black : JsColors.offWhite,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              )),
            ],
          ),
        ),
      );
    }).toList(),
  );
}

class _ParkingSection extends StatelessWidget {
  const _ParkingSection({
    required this.controller, required this.photoPath,
    required this.onTakePhoto, required this.onClearPhoto,
  });
  final TextEditingController controller;
  final String? photoPath;
  final VoidCallback onTakePhoto;
  final VoidCallback onClearPhoto;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Label(text: '駐車料金'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '金額（円）',
              prefixIcon: Icon(Icons.local_parking, color: JsColors.silver),
              suffixText: '円',
            ),
            style: const TextStyle(color: JsColors.offWhite),
          ),
        ),
        const SizedBox(width: 10),
        _CameraBtn(hasPhoto: photoPath != null, onTap: onTakePhoto),
      ]),
      if (photoPath != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(photoPath!),
                    height: 100, width: double.infinity, fit: BoxFit.cover),
              ),
              GestureDetector(
                onTap: onClearPhoto,
                child: Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ),
      if (photoPath == null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: const [
            Icon(Icons.info_outline, color: JsColors.silver, size: 14),
            SizedBox(width: 4),
            Text('領収書の写真も撮影することを推奨します',
                style: TextStyle(color: JsColors.silver, fontSize: 11)),
          ]),
        ),
    ],
  );
}

class _CameraBtn extends StatelessWidget {
  const _CameraBtn({required this.hasPhoto, required this.onTap});
  final bool hasPhoto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: hasPhoto ? JsColors.success : JsColors.gunmetal,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hasPhoto ? JsColors.success : JsColors.divider),
      ),
      child: Icon(
        hasPhoto ? Icons.check_circle : Icons.camera_alt,
        color: hasPhoto ? Colors.white : JsColors.silver,
      ),
    ),
  );
}

// ============================================================
// 音声入力ダイアログ
// ============================================================

class _VoiceDialog extends StatefulWidget {
  const _VoiceDialog({
    required this.manager, required this.title, required this.hint,
    required this.onConfirm, required this.onCancel,
  });
  final SpeechManager manager;
  final String title;
  final String hint;
  final void Function(String) onConfirm;
  final VoidCallback onCancel;

  @override
  State<_VoiceDialog> createState() => _VoiceDialogState();
}

class _VoiceDialogState extends State<_VoiceDialog>
    with SingleTickerProviderStateMixin {
  String _text      = '';
  bool   _listening = false;
  late   AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _start();
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  Future<void> _start() async {
    setState(() { _listening = true; _text = ''; });
    await widget.manager.startListening(
      onResult: (text, isFinal) { if (mounted) setState(() => _text = text); },
    );
    if (mounted) setState(() => _listening = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: JsColors.gunmetal,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(widget.title, style: const TextStyle(color: JsColors.gold)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _listening
                  ? JsColors.gold.withOpacity(0.15 + _pulse.value * 0.15)
                  : JsColors.gunmetal,
            ),
            child: Icon(
              _listening ? Icons.mic : Icons.mic_off,
              color: _listening ? JsColors.gold : JsColors.silver, size: 36,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(_listening ? '聞いています...' : '認識完了',
            style: TextStyle(
                color: _listening ? JsColors.gold : JsColors.silver, fontSize: 12)),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: JsColors.surface, borderRadius: BorderRadius.circular(10)),
          constraints: const BoxConstraints(minHeight: 60),
          child: Text(
            _text.isEmpty ? widget.hint : _text,
            style: TextStyle(
              color: _text.isEmpty ? JsColors.silver : JsColors.offWhite,
              height: 1.5, fontSize: _text.isEmpty ? 12 : 15,
            ),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: widget.onCancel,
        child: const Text('キャンセル', style: TextStyle(color: JsColors.silver)),
      ),
      if (_listening)
        TextButton(
          onPressed: () async {
            await widget.manager.stop();
            setState(() => _listening = false);
          },
          child: const Text('停止', style: TextStyle(color: JsColors.gold)),
        ),
      if (!_listening && _text.isNotEmpty)
        ElevatedButton(
          onPressed: () => widget.onConfirm(_text),
          child: const Text('確定'),
        ),
    ],
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
                minimumSize: const Size(56, 52), padding: EdgeInsets.zero),
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
                  if (newIndex > oldIndex) newIndex--;
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
        backgroundColor: Colors.black,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
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
        backgroundColor: Colors.black,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
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