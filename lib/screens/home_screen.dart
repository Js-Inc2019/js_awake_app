// lib/screens/home_screen.dart
// JsMainShell — 全画面共通 2段AppBar + 永続BottomBar + IndexedStack

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';
import '../widgets/photo_strip_field.dart';
import '../widgets/search_suggest_field.dart';

import '../main.dart'
    show
        TransportType,
        ReportStore,
        WorkerReportItem,
        SpeechManager,
        WorkerNameStore,
        fetchGpsAddress,
        showJsSnackbar,
        showConfirmDialog,
        NotificationManager,
        OvertimeDialog,
        API_URL;
import '../core/theme/js_colors.dart';
import 'revision_inbox_screen.dart';
import 'site_quick_register_screen.dart';
import 'company_link_screen.dart';
import 'monthly_history_screen.dart' show MonthlyHistoryBody, JsStatChip, JsReportTile;
import 'day_reports_screen.dart';
import 'profile_screen.dart';
import 'after_report_screen.dart';
import 'punch_screen.dart';
import '../widgets/slide_to_confirm.dart';
import '../widgets/approval_dialogs.dart';
import '../widgets/report_photos.dart';
import '../services/auth_service.dart';
import '../services/reports_service.dart';
import '../services/site_service.dart';
import '../services/company_service.dart';
import '../services/fcm_service.dart';
import '../services/routes_service.dart';
import '../services/profile_service.dart';

// ─────────────────────────────────────────────
// 季節注意喚起（6〜9月）
// ─────────────────────────────────────────────
String? _getSeasonWarning(DateTime now) {
  final m = now.month;
  if (m == 6) return '梅雨・暑熱始まり — こまめな水分補給を';
  if (m == 7) return '猛暑注意 — 熱中症指数が高い日は無理せず休憩を';
  if (m == 8) return '熱中症最警戒 — 30分に1回は水分・塩分補給を';
  if (m == 9) return '残暑注意 — まだ暑さが続きます。油断せず対策を';
  return null;
}

// OWM API キーは lib/config/constants.dart の kWeatherApiKey を使用

// ─────────────────────────────────────────────
// 天気データモデル
// ─────────────────────────────────────────────
class _WeatherData {
  final String icon;
  final String desc;
  final double tempC;
  final int precipPct;
  final int humidity;
  final double? windSpeed; // m/s
  const _WeatherData({
    required this.icon,
    required this.desc,
    required this.tempC,
    required this.precipPct,
    this.humidity = 60,
    this.windSpeed,
  });
}

class _ForecastDay {
  final String weekday;
  final String icon;
  final double maxC;
  final double minC;
  final int precipPct;
  const _ForecastDay({
    required this.weekday,
    required this.icon,
    required this.maxC,
    required this.minC,
    required this.precipPct,
  });
}

// ─────────────────────────────────────────────
// WBGT（暑さ指数）計算
// ─────────────────────────────────────────────
double _calcWBGT(double tempC, int humidity) {
  if (humidity <= 0) return tempC * 0.6;
  final rh = humidity.toDouble().clamp(1.0, 100.0);
  // Stull (2011) 湿球温度近似
  final tw = tempC * atan(0.151977 * sqrt(rh + 8.313659))
      + atan(tempC + rh)
      - atan(rh - 1.676331)
      + 0.00391838 * pow(rh, 1.5) * atan(0.023101 * rh)
      - 4.686035;
  return 0.7 * tw + 0.3 * tempC;
}

String _wbgtLevel(double wbgt) {
  if (wbgt < 21) return 'ほぼ安全';
  if (wbgt < 25) return '注意';
  if (wbgt < 28) return '警戒';
  if (wbgt < 31) return '厳重警戒';
  return '危険';
}

Color _wbgtColor(double wbgt) {
  if (wbgt < 21) return JsColors.silver;
  if (wbgt < 25) return const Color(0xFF43A047);
  if (wbgt < 28) return const Color(0xFFF9A825);
  if (wbgt < 31) return const Color(0xFFE65100);
  return JsColors.error;
}

// ─────────────────────────────────────────────
// 天気取得（OWM → wttr.in フォールバック）
// ─────────────────────────────────────────────
Future<(_WeatherData?, List<_ForecastDay>)> _fetchWeatherFull({
  double? lat,
  double? lon,
}) async {
  if (kWeatherApiKey.isNotEmpty && lat != null && lon != null) {
    return _fetchOwm(lat, lon);
  }
  return _fetchWttr();
}

Future<(_WeatherData?, List<_ForecastDay>)> _fetchOwm(double lat, double lon) async {
  try {
    final curRes = await http.get(Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather'
      '?lat=$lat&lon=$lon&appid=$kWeatherApiKey&units=metric&lang=ja',
    )).timeout(const Duration(seconds: 8));

    final fcRes = await http.get(Uri.parse(
      'https://api.openweathermap.org/data/2.5/forecast'
      '?lat=$lat&lon=$lon&appid=$kWeatherApiKey&units=metric&lang=ja&cnt=40',
    )).timeout(const Duration(seconds: 8));

    if (curRes.statusCode != 200) return (null, <_ForecastDay>[]);

    final curJ = jsonDecode(curRes.body) as Map<String, dynamic>;
    final weatherArr = curJ['weather'] as List;
    final owmId = (weatherArr.first as Map<String, dynamic>)['id'] as int? ?? 800;
    final desc = (weatherArr.first as Map<String, dynamic>)['description'] as String? ?? '';
    final temp      = ((curJ['main'] as Map)['temp'] as num).toDouble();
    final rainPop   = ((curJ['clouds'] as Map?)?['all'] as int? ?? 0).clamp(0, 100);
    final humidity  = ((curJ['main'] as Map)['humidity'] as int?) ?? 60;
    final windSpeed = ((curJ['wind'] as Map<String, dynamic>?)?['speed'] as num?)?.toDouble();

    final current = _WeatherData(
      icon:      _owmIdToIcon(owmId),
      desc:      desc,
      tempC:     temp,
      precipPct: rainPop,
      humidity:  humidity,
      windSpeed: windSpeed,
    );

    final forecast = <_ForecastDay>[];
    if (fcRes.statusCode == 200) {
      final fcJ = jsonDecode(fcRes.body) as Map<String, dynamic>;
      final items = (fcJ['list'] as List).cast<Map<String, dynamic>>();
      final Map<String, List<Map<String, dynamic>>> byDay = {};
      for (final item in items) {
        final dt = DateTime.fromMillisecondsSinceEpoch(
                (item['dt'] as int) * 1000, isUtc: true)
            .toLocal();
        final key = '${dt.year}-${dt.month}-${dt.day}';
        byDay.putIfAbsent(key, () => []).add(item);
      }
      const weekJa = ['月', '火', '水', '木', '金', '土', '日'];
      int count = 0;
      for (final entry in byDay.entries) {
        if (count >= 5) break;
        final parts = entry.key.split('-');
        final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final dayItems = entry.value;
        final maxC = dayItems
            .map((e) => ((e['main'] as Map)['temp_max'] as num).toDouble())
            .reduce((a, b) => a > b ? a : b);
        final minC = dayItems
            .map((e) => ((e['main'] as Map)['temp_min'] as num).toDouble())
            .reduce((a, b) => a < b ? a : b);
        final maxPop = dayItems
            .map((e) => ((e['pop'] as num?)?.toDouble() ?? 0.0))
            .reduce((a, b) => a > b ? a : b);
        final repId =
            ((dayItems[dayItems.length ~/ 2]['weather'] as List).first as Map)['id'] as int? ?? 800;
        forecast.add(_ForecastDay(
          weekday: weekJa[dt.weekday - 1],
          icon: _owmIdToIcon(repId),
          maxC: maxC,
          minC: minC,
          precipPct: (maxPop * 100).round(),
        ));
        count++;
      }
    }
    return (current, forecast);
  } catch (_) {
    return _fetchWttr();
  }
}

Future<(_WeatherData?, List<_ForecastDay>)> _fetchWttr() async {
  try {
    final res = await http
        .get(Uri.parse('https://wttr.in/?format=j1'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return (null, <_ForecastDay>[]);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final cur = (j['current_condition'] as List).first as Map<String, dynamic>;
    final tempC = double.tryParse(cur['temp_C'] as String? ?? '0') ?? 0;
    final rawDesc =
        ((cur['weatherDesc'] as List?)?.first as Map<String, dynamic>?)?['value'] as String? ??
            '';
    final precip   = int.tryParse(cur['precipMM'] as String? ?? '0') ?? 0;
    final humidity = int.tryParse(cur['humidity'] as String? ?? '60') ?? 60;
    final windKmh  = double.tryParse(cur['windspeedKmph'] as String? ?? '');
    final windMs   = windKmh != null
        ? double.parse((windKmh / 3.6).toStringAsFixed(1)) : null;
    final (icon, desc) = _mapDescStr(rawDesc);

    final current = _WeatherData(
      icon:      icon,
      desc:      desc,
      tempC:     tempC,
      precipPct: precip.clamp(0, 100),
      humidity:  humidity,
      windSpeed: windMs,
    );

    const weekJa = ['月', '火', '水', '木', '金', '土', '日'];
    final forecast = <_ForecastDay>[];
    final weatherDays = (j['weather'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final day in weatherDays.take(5)) {
      final dateStr = day['date'] as String? ?? '';
      DateTime? dt;
      try { dt = DateTime.parse(dateStr); } catch (_) {}
      final maxC = double.tryParse(day['maxtempC'] as String? ?? '0') ?? 0;
      final minC = double.tryParse(day['mintempC'] as String? ?? '0') ?? 0;
      final hourly = (day['hourly'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final maxPrecip = hourly
          .map((h) => int.tryParse(h['chanceofrain'] as String? ?? '0') ?? 0)
          .fold(0, (a, b) => a > b ? a : b);
      final rawD =
          ((day['weatherDesc'] as List?)?.first as Map<String, dynamic>?)?['value'] as String? ?? '';
      final (fIcon, _) = _mapDescStr(rawD);
      forecast.add(_ForecastDay(
        weekday: dt != null ? weekJa[dt.weekday - 1] : '-',
        icon: fIcon,
        maxC: maxC,
        minC: minC,
        precipPct: maxPrecip,
      ));
    }
    return (current, forecast);
  } catch (_) {
    return (null, <_ForecastDay>[]);
  }
}

String _owmIdToIcon(int id) {
  if (id >= 200 && id < 300) return '⛈️';
  if (id >= 300 && id < 400) return '🌦️';
  if (id >= 500 && id < 510) return '🌧️';
  if (id == 511) return '🌨️';
  if (id >= 510 && id < 600) return '🌧️';
  if (id >= 600 && id < 700) return '❄️';
  if (id >= 700 && id < 800) return '🌫️';
  if (id == 800) return '☀️';
  if (id == 801) return '🌤️';
  if (id == 802) return '⛅';
  if (id >= 803) return '☁️';
  return '🌤️';
}

(String, String) _mapDescStr(String raw) {
  final r = raw.toLowerCase();
  if (r.contains('sunny') || r.contains('clear')) return ('☀️', '晴れ');
  if (r.contains('partly cloudy') || r.contains('partly')) return ('⛅', '薄曇り');
  if (r.contains('overcast') || r.contains('cloudy')) return ('☁️', '曇り');
  if (r.contains('thunder') || r.contains('storm')) return ('⛈️', '雷雨');
  if (r.contains('heavy rain') || r.contains('torrential')) return ('🌧️', '大雨');
  if (r.contains('rain') || r.contains('drizzle')) return ('🌦️', '雨');
  if (r.contains('snow') || r.contains('blizzard')) return ('❄️', '雪');
  if (r.contains('fog') || r.contains('mist')) return ('🌫️', '霧');
  return ('🌤️', raw.isNotEmpty ? raw : '取得中');
}

// ─────────────────────────────────────────────
// リトライヘルパー
// ─────────────────────────────────────────────
Future<T> _withRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  Duration firstTimeout = const Duration(seconds: 60),
}) async {
  Object? lastErr;
  for (var i = 0; i < maxAttempts; i++) {
    try {
      return await fn().timeout(firstTimeout + Duration(seconds: i * 20));
    } catch (e) {
      lastErr = e;
      if (i < maxAttempts - 1) await Future.delayed(Duration(seconds: 1 << i));
    }
  }
  throw lastErr!;
}

// ─────────────────────────────────────────────
// JsMainShell — 全画面共通シェル
// ─────────────────────────────────────────────
class JsMainShell extends StatefulWidget {
  const JsMainShell({super.key, this.isForeman = false, this.restoreWorkStatus});
  final bool isForeman;
  final String? restoreWorkStatus;

  @override
  State<JsMainShell> createState() => _JsMainShellState();
}

class _JsMainShellState extends State<JsMainShell> with WidgetsBindingObserver {
  // ─── タブ ───
  int _tabIndex = 0;

  // ─── ユーザー情報 ───
  bool _initialLoading = true;
  String _companyName = "";
  String _userName = '';
  int _revisionCount = 0;
  int _pendingApprovalCount = 0;
  int _linkCount     = 0;

  // ─── GPS ───
  String _gpsAddress = '';
  bool _gpsLoading = false;
  double? _lat;
  double? _lon;

  // ─── 作業現場選択（null=対象なし） ───
  String? _selectedSiteId;
  String? _selectedSiteName;

  // ─── 天気 ───
  _WeatherData? _weather;
  List<_ForecastDay> _forecast = [];
  bool _weatherLoading = false;

  // ─── 季節 ───
  String? _seasonWarning;
  DateTime? _healthCheckDate;

  // ─── 起点 ───
  String _originType = 'home';
  String _companyAddress = '';

  // ─── 移動手段 ───
  Set<TransportType> _transports = {};
  TransportType get _transport => _transports.isEmpty ? TransportType.none : _transports.first;
  String _carType = 'own';
  final _carpoolCtrl       = TextEditingController();
  final _transportMemoCtrl = TextEditingController();
  Map<String, dynamic> _routeComparisons = {};
  bool _loadingRoutes = false;

  // ─── 作業内容 ───
  final _workCtrl    = TextEditingController();
  final _otherCtrl   = TextEditingController();
  final _parkingCtrl = TextEditingController();
  List<String> _workPhotoPaths = [];
  List<String> _parkingPhotoPaths = [];
  bool _isListening = false;
  final _speechMgr = SpeechManager();

  // ─── 残業 ───
  bool _overtimeExpanded = false;
  int _overtimeHours = 0;
  int _overtimeMinutes = 0;

  // ─── 送信 ───
  bool _submitting = false;
  // 完了ビューが日報タブ(index1)を占有中か。true の間フォームへ到達不能＝二重報告防止の要
  bool _todayReportDone = false;
  // 完了ビューに渡す送信成否。送信直後経路は実成否、復元経路は暫定true
  // （S4-②: 送信成否がtoday_work_statusに永続化されていないため復元時の実態は不明。今回は未修正）
  bool _lastSentOk = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSeasonAndDaily();
    _loadCacheAndStart();
    _restoreTabIndex();
    _loadOriginPrefs();
    _initTodayReportDone();
    _workCtrl.addListener(_onWorkContentChanged);
    if (widget.restoreWorkStatus != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _restoreDraft(widget.restoreWorkStatus!));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await FcmService.ready;
      final d = FcmService.pendingTapData;
      if (d != null) {
        FcmService.pendingTapData = null;
        FcmService().handleNotificationTap(d);
      }
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _speechMgr.ensureReady();
        ReportStore.instance.retryPending();
      }
    });
  }

  void _onWorkContentChanged() {
    if (_workCtrl.text.isNotEmpty) {
      _saveWorkStatus('working');
      _saveDraft();
    }
  }

  Future<void> _saveWorkStatus(String status) async {
    final now = DateTime.now();
    final todayDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('today_date', todayDate);
    await prefs.setString('today_work_status', status);
  }

  // 起動時: 当日ぶんが送信済み(done)なら完了ビューを日報タブに出す（復元経路を一本化）
  Future<void> _initTodayReportDone() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final savedDate = prefs.getString('today_date') ?? '';
    final status    = prefs.getString('today_work_status') ?? '';
    if (mounted && savedDate == todayDate && status == 'done') {
      setState(() => _todayReportDone = true);
    }
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('today_transport', _transports.map((t) => t.name).join(','));
    await prefs.setString('today_work_content', _workCtrl.text);
    await prefs.setString('today_parking_fee', _parkingCtrl.text);
    await prefs.setInt('today_overtime_hours', _overtimeHours);
    await prefs.setInt('today_overtime_minutes', _overtimeMinutes);
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('today_transport');
    await prefs.remove('today_work_content');
    await prefs.remove('today_parking_fee');
    await prefs.remove('today_overtime_hours');
    await prefs.remove('today_overtime_minutes');
  }

  Future<void> _restoreDraft(String workStatus) async {
    final prefs = await SharedPreferences.getInstance();
    final transportName = prefs.getString('today_transport') ?? '';
    final workContent   = prefs.getString('today_work_content') ?? '';
    final parkingFee    = prefs.getString('today_parking_fee') ?? '';
    final overtimeH     = prefs.getInt('today_overtime_hours') ?? 0;
    final overtimeM     = prefs.getInt('today_overtime_minutes') ?? 0;
    final restored = transportName.isEmpty
        ? <TransportType>{}
        : transportName.split(',').map((n) => TransportType.values.firstWhere(
              (t) => t.name == n, orElse: () => TransportType.none))
            .where((t) => t != TransportType.none)
            .toSet();
    if (!mounted) return;
    setState(() {
      _transports = restored;
      _workCtrl.text = workContent;
      _parkingCtrl.text = parkingFee;
      _overtimeHours = overtimeH;
      _overtimeMinutes = overtimeM;
      if (workStatus == 'overtime' && (overtimeH > 0 || overtimeM > 0)) {
        _overtimeExpanded = true;
      }
    });
  }

  // 最後のタブを復元（モード別キー）
  Future<void> _restoreTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final key   = widget.isForeman ? 'last_tab_index_v2_foreman' : 'last_tab_index_v2_worker';
    final saved = prefs.getInt(key) ?? 0;
    if (mounted) setState(() => _tabIndex = saved);
  }

  // タブ切り替え＋保存
  void _setTab(int index) {
    setState(() => _tabIndex = index);
    // 承認・是正タブ(index3)進入時のみバッジ2値を再取得（全index一律はAPI連打になるため回避）
    if (index == 3) {
      _loadPendingApprovalCount();
      _loadRevisionCount();
    }
    SharedPreferences.getInstance().then((p) {
      final key = widget.isForeman ? 'last_tab_index_v2_foreman' : 'last_tab_index_v2_worker';
      p.setInt(key, index);
    });
  }

  @override
  void dispose() {
    _workCtrl.removeListener(_onWorkContentChanged);
    _workCtrl.dispose();
    _otherCtrl.dispose();
    _parkingCtrl.dispose();
    _carpoolCtrl.dispose();
    _transportMemoCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _fetchGps();
  }

  // ─── キャッシュ即時表示 → バックグラウンド最新取得 ───
  Future<void> _loadCacheAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedLat  = prefs.getDouble('gps_lat');
    final cachedLon  = prefs.getDouble('gps_lon');
    final cachedAddr = prefs.getString('gps_address') ?? '';
    final revCount   = prefs.getInt('cache_revision_count') ?? 0;
    final hcIso      = prefs.getString('health_check_date_iso');
    final wIcon      = prefs.getString('cache_weather_icon');
    final wTempC     = prefs.getDouble('cache_weather_temp');
    final wDesc      = prefs.getString('cache_weather_desc') ?? '';
    final wPrecip    = prefs.getInt('cache_weather_precip') ?? 0;
    final wHumidity  = prefs.getInt('cache_weather_humidity') ?? 60;
    final wWindSpeed = prefs.getDouble('cache_weather_wind');

    if (mounted) {
      setState(() {
        _userName        = prefs.getString('user_name') ?? '';
        _companyName     = prefs.getString('company_name') ?? "";
        _healthCheckDate = hcIso != null ? DateTime.tryParse(hcIso) : null;
        _revisionCount   = revCount;
        if (cachedAddr.isNotEmpty) _gpsAddress = cachedAddr;
        if (wIcon != null && wTempC != null) {
          _weather = _WeatherData(
            icon: wIcon, desc: wDesc, tempC: wTempC,
            precipPct: wPrecip, humidity: wHumidity,
            windSpeed: wWindSpeed);
        }
        _initialLoading = false;
      });
    }

    if (cachedLat != null && cachedLon != null) {
      _lat = cachedLat;
      _lon = cachedLon;
      _loadWeather();
    }

    await Future.wait([
      _fetchGps(prefs: prefs),
      _loadRevisionCount(prefs: prefs),
      _loadPendingApprovalCount(),
      _loadLinkCount(),
      _fetchCompanyAddress(),
    ]);
    // 位置 → 通知許可 → token取得・POST の順を保証（権限衝突完全解消）
    await FcmService().requestNotificationPermission();
    await FcmService().registerToken();
  }

  Future<void> _fetchGps({SharedPreferences? prefs}) async {
    if (mounted) setState(() => _gpsLoading = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
        _lat = pos.latitude;
        _lon = pos.longitude;
        prefs?.setDouble('gps_lat', _lat!);
        prefs?.setDouble('gps_lon', _lon!);
      }
    } catch (e) {
      debugPrint('GPS取得エラー: $e');
    }
    final (:address, lat: _, lon: _) = await fetchGpsAddress();
    if (address.isNotEmpty) prefs?.setString('gps_address', address);
    if (mounted) {
      setState(() { _gpsAddress = address; _gpsLoading = false; });
      _loadWeather();
      _calculateRoutes();
    }
  }

  Future<void> _loadWeather() async {
    if (mounted) setState(() => _weatherLoading = true);
    final (data, forecast) = await _fetchWeatherFull(lat: _lat, lon: _lon);
    if (!mounted) return;
    setState(() {
      _weather  = data;
      _forecast = forecast;
      _weatherLoading = false;
    });
    if (data != null) {
      SharedPreferences.getInstance().then((p) {
        p.setString('cache_weather_icon',     data.icon);
        p.setDouble('cache_weather_temp',     data.tempC);
        p.setString('cache_weather_desc',     data.desc);
        p.setInt('cache_weather_precip',      data.precipPct);
        p.setInt('cache_weather_humidity',    data.humidity);
        if (data.windSpeed != null) p.setDouble('cache_weather_wind', data.windSpeed!);
      });
    }
  }

  void _initSeasonAndDaily() {
    _seasonWarning = _getSeasonWarning(DateTime.now());
  }

  String? _buildHealthBannerMsg() {
    final hc = _healthCheckDate;
    if (hc == null) return null;
    final next = DateTime(hc.year + 1, hc.month, hc.day);
    final days = next.difference(DateTime.now()).inDays;
    if (days <= 14) return '🔴 健康診断期限まで$days日 — 今すぐ予約を！';
    if (days <= 30) return '🟡 健康診断まで$days日 — 早めに予約を';
    return null;
  }

  Future<void> _loadOriginPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _originType     = prefs.getString('default_origin') ?? 'home';
        _companyAddress = prefs.getString('company_address') ?? '';
      });
    }
  }

  Future<void> _fetchCompanyAddress() async {
    try {
      final companyId = await AuthService().getCompanyId();
      if (companyId == null || companyId.isEmpty) return;
      final result = await CompanyService().getCompanyById(companyId);
      if (result['success'] == true) {
        final company = result['company'] as Map<String, dynamic>?;
        final address = company?['address'] as String? ?? '';
        if (address.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('company_address', address);
          if (mounted) setState(() => _companyAddress = address);
        }
      }
    } catch (e) {
      debugPrint('会社住所取得エラー: $e');
    }
  }

  Future<void> _loadRevisionCount({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final token = p.getString('auth_token') ?? '';
      final res = await _withRetry(
        () => http.get(
          Uri.parse('$API_URL/reports?revision_requested=true'),
          headers: {'Authorization': 'Bearer $token'},
        ),
        firstTimeout: const Duration(seconds: 60),
      );
      if (res.statusCode == 200 && mounted) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final count = (j['reports'] as List?)?.length ?? 0;
        p.setInt('cache_revision_count', count);
        setState(() => _revisionCount = count);
      }
    } catch (e) {
      debugPrint('是正件数取得エラー: $e');
    }
  }

  // 承認待ち件数（送信済み・未承認・差戻し中でない）をシェルへ取得
  Future<void> _loadPendingApprovalCount() async {
    try {
      final result = await ReportsService().getReports(limit: 50);
      if (result['success'] == true && mounted) {
        final raw = List<Map<String, dynamic>>.from(result['reports'] ?? []);
        final count = raw
            .where((r) =>
                r['is_sent'] == true &&
                r['approved'] != true &&
                r['revision_requested'] != true)
            .length;
        setState(() => _pendingApprovalCount = count);
      }
    } catch (e) {
      debugPrint('承認待ち件数取得エラー: $e');
    }
  }

  Future<void> _loadLinkCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http.get(
        Uri.parse('$API_URL/company-links/my'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 && mounted) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final links = (j['links'] as List? ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();
        final count = links.where((l) => (l['status'] as String?) == 'pending').length;
        setState(() => _linkCount = count);
      }
    } catch (e) {
      debugPrint('協力申請件数取得エラー: $e');
    }
  }

  Future<void> _calculateRoutes() async {
    if (_gpsAddress.isEmpty) return;
    final String originAddr;
    if (_originType == 'office' && _companyAddress.isNotEmpty) {
      originAddr = _companyAddress;
    } else {
      originAddr = await ProfileService().getHomeAddress() ?? '兵庫県神戸市長田区';
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    if (mounted) setState(() => _loadingRoutes = true);
    Map<String, dynamic> routes = {};
    for (int attempt = 0; attempt < 3 && routes.isEmpty; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(seconds: attempt * 2));
      routes = await RoutesService().compareRoutesV2(
        origin: originAddr,
        destination: (_lat != null && _lon != null)
            ? '${_lat!.toStringAsFixed(6)},${_lon!.toStringAsFixed(6)}'
            : _gpsAddress,
        authToken: token,
      );
    }
    if (mounted) {
      setState(() {
        _routeComparisons = routes;
        _loadingRoutes = false;
      });
    }
  }

  Future<void> _startVoice() async {
    final ready = await _speechMgr.ensureReady();
    if (!ready) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: const Text('マイク/音声認識の権限がありません。設定から許可してください',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          backgroundColor: JsColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '設定を開く',
            textColor: Colors.white,
            onPressed: () => launchUrl(Uri.parse('app-settings:')),
          ),
        ));
      return;
    }
    setState(() => _isListening = true);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VoiceInputDialog(
        manager: _speechMgr,
        onConfirm: (text) {
          Navigator.pop(ctx);
          setState(() {
            _workCtrl.text =
                _workCtrl.text.isEmpty ? text : '${_workCtrl.text}。$text';
          });
        },
        onCancel: () { _speechMgr.cancel(); Navigator.pop(ctx); },
      ),
    );
    setState(() => _isListening = false);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_userName.isEmpty) {
      showJsSnackbar(context, '氏名が取得できていません', isError: true);
      return;
    }
    if (_transports.isEmpty) {
      showJsSnackbar(context, '移動手段を選択してください', isError: true);
      return;
    }
    setState(() => _submitting = true);
    if ((_transports.contains(TransportType.car) || _transports.contains(TransportType.other)) && _parkingPhotoPaths.isEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('写真が添付されていません'),
          content: const Text('駐車場の看板または領収書の写真が添付されていません。このまま送信しますか？\n\n※戻ると、駐車場写真の帯にある「＋撮影」から撮影できます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('戻って撮影する'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('このまま送信'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        if (mounted) setState(() => _submitting = false);
        return; // 「戻って撮影する」→送信中断。駐車場写真は帯の「＋撮影」から追加してもらう
      }
    }
    final name = _userName;
    final gpsAddr = _gpsAddress;
    try {
      final overtimeNote = (_overtimeHours > 0 || _overtimeMinutes > 0)
          ? ' 【残業$_overtimeHours時間$_overtimeMinutes分】'
          : '';
      final carpoolPrefix = (_transports.contains(TransportType.car) && _carType == 'carpool')
          ? '[相乗り:${_carpoolCtrl.text.trim().isEmpty ? "未記入" : _carpoolCtrl.text.trim()}] '
          : '';
      final parkingPrefix = (_transports.contains(TransportType.car) && _carType == 'own' && _parkingCtrl.text.trim().isNotEmpty)
          ? '[駐車料金:${_parkingCtrl.text.trim()}円] '
          : '';
      final otherPrefix = (_transports.contains(TransportType.other) && _otherCtrl.text.trim().isNotEmpty)
          ? '[その他:${_otherCtrl.text.trim()}] '
          : '';
      await WorkerNameStore.instance.add(name);
      final sent = await ReportStore.instance.addReport(WorkerReportItem(
        name: name,
        transport: _transport,
        transportTypes: _transports.map((t) => t.name).toList(),
        workContent: carpoolPrefix + parkingPrefix + otherPrefix + _workCtrl.text.trim() + overtimeNote,
        workPhotoPaths: _workPhotoPaths,
        parkingPhotoPaths: _parkingPhotoPaths,
        gpsAddress: gpsAddr,
        originType: _originType,
        siteId: _selectedSiteId,   // 「対象なし」= null（BE側 NULL）
      ));
      await ReportStore.instance.retryPending();
      _saveWorkStatus('done');
      _clearDraft();
      NotificationManager.instance.cancelOvertimeReminder();
      if (!mounted) return;
      showJsSnackbar(
        context,
        sent ? '✅ 報告を送信しました' : '📋 報告を保存しました（再送待ち）',
        isWarning: !sent,
      );
      _carpoolCtrl.clear();
      _transportMemoCtrl.clear();
      setState(() {
        _transports = {};
        _carType = 'own';
        _workCtrl.clear();
        _otherCtrl.clear();
        _parkingCtrl.clear();
        _workPhotoPaths = [];
        _parkingPhotoPaths = [];
        _overtimeExpanded = false;
        _overtimeHours = 0;
        _overtimeMinutes = 0;
        _selectedSiteId = null;      // 送信後は現場選択を「対象なし」に戻す
        _selectedSiteName = null;
        // 全画面push(AfterReportScreen)は廃止。完了ビューを日報タブ(index1)に出す。
        // ＝日報フォームへ到達不能にして二重報告を防止する不変条件。
        _lastSentOk = sent;   // 送信直後経路は実際の送信成否を渡す
        _todayReportDone = true;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // 作業現場の選択ボトムシート（getSites をサルベージ・「対象なし」を最上段固定）
  Future<void> _showSitePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JsColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SitePickerSheet(
        selectedSiteId: _selectedSiteId,
        onSelected: (id, name) {
          setState(() {
            _selectedSiteId = id;
            _selectedSiteName = name;
          });
        },
      ),
    );
  }

  // ─── J's Tool 起動 ───
  Future<void> _launchToolApp() async {
    final prefs     = await SharedPreferences.getInstance();
    final token     = prefs.getString('auth_token')  ?? '';
    if (token.isEmpty) {
      if (mounted) showJsSnackbar(context, 'ログイン情報がありません', isError: true);
      return;
    }
    final userName  = prefs.getString('user_name')   ?? '';
    final companyId = prefs.getString('company_id')  ?? '';
    final role      = prefs.getString('user_role')   ?? ''; // 二重キー統一: 'user_role' に一本化
    final userId    = prefs.getString('user_id')     ?? '';

    final uri = Uri(
      scheme: 'jstool',
      host:   'auth',
      queryParameters: {
        'token':      token,
        'user_name':  userName,
        'company_id': companyId,
        'role':       role,
        'user_id':    userId,
      },
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        showJsSnackbar(context, "J's Toolがインストールされていません", isWarning: true);
      }
    }
  }

  // ─── 日付ラベル ───
  String get _dateLabel {
    final n = DateTime.now();
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final w = weekdays[n.weekday - 1];
    return '${n.year}/${n.month.toString().padLeft(2, '0')}/${n.day.toString().padLeft(2, '0')}（$w）';
  }

  // ─── ページタイトル ───
  String get _pageTitle {
    switch (_tabIndex) {
      case 0: return '日報';
      case 1: return '日報';
      case 2: return '月間履歴';
      case 3: return widget.isForeman ? '承認・是正' : '是正依頼';
      case 4: return '管理・集計';
      default: return '打刻';
    }
  }

  // ─────────────────────── BUILD ───────────────────────
  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return Scaffold(
        backgroundColor: JsColors.black,
        appBar: _buildAppBar(),
        body: const SafeArea(child: _HomeSkeletonBody()),
      );
    }

    // IndexedStack の children リスト
    final tabChildren = <Widget>[
      PunchScreen(
        onNavigateToReport: () => _setTab(1),
        weatherPanel: _PunchWeatherPanel(
          weather:       _weather,
          forecast:      _forecast,
          loading:       _weatherLoading,
          seasonWarning: _seasonWarning,
        ),
      ),
      _buildHomeTabContent(),
      const MonthlyHistoryBody(),
      if (widget.isForeman) ...[
        const _ReviewTab(),               // index3: 承認・是正
        const _ForemanManagementBody(),   // index4: 管理・集計
      ],
    ];

    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex.clamp(0, tabChildren.length - 1),
          children: tabChildren,
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ─── 2段 AppBar ───
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: JsColors.black,
      elevation: 0,
      titleSpacing: 12,
      title: Row(
        children: [
          Text(
            _pageTitle,
            style: const TextStyle(
                color: JsColors.gold, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            _dateLabel,
            style: const TextStyle(color: JsColors.silver, fontSize: 11),
          ),
          const Spacer(),
        ],
      ),
      actions: [
        // 🧮 TOOL（ARC FLASH）ボタン
        IconButton(
          icon: const Icon(Icons.calculate, color: Color(0xFF00E5CC)),
          tooltip: 'TOOL',
          onPressed: _launchToolApp,
        ),
        // 🤝 協力申請ボタン
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.handshake_outlined,
                color: _linkCount > 0 ? JsColors.gold : JsColors.silver,
              ),
              tooltip: '協力申請',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CompanyLinkScreen()),
              ).then((_) => _loadLinkCount()),
            ),
            if (_linkCount > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: JsColors.gold, shape: BoxShape.circle),
                  child: Text('$_linkCount',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        // ⚙️ 設定ボタン
        IconButton(
          icon: const Icon(Icons.settings, color: JsColors.silver),
          tooltip: '設定',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ).then((_) => _loadCacheAndStart()),
        ),
      ],
      // 2段目: 上段=会社名（薄・小）、下段=アイコン+氏名（メイン）
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: Container(
          width: double.infinity,
          color: JsColors.gunmetal,
          padding: const EdgeInsets.fromLTRB(14, 5, 14, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _companyName,
                style: const TextStyle(
                    color: Color(0xFF637080),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  const Icon(Icons.business, color: JsColors.gold, size: 13),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _userName.isEmpty ? '---' : _userName,
                      style: const TextStyle(
                          color: JsColors.offWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── BottomBar ───
  Widget _buildBottomBar() {
    final divider = Container(width: 1, height: 36, color: JsColors.divider);
    return BottomAppBar(
      color: JsColors.gunmetal,
      height: 60,
      padding: EdgeInsets.zero,
      child: Row(children: [
        _BottomTabItem(
          icon: Icons.edit_note,
          label: '日報',
          active: _tabIndex == 0,
          onTap: () => _setTab(0),
        ),
        divider,
        if (widget.isForeman) ...[
          _BottomTabItem(
            icon: Icons.fact_check,
            label: '承認・是正',
            active: _tabIndex == 3,
            onTap: () => _setTab(3),
            badge: _pendingApprovalCount,
            badgeColor: JsColors.success,
            badge2: _revisionCount,
            badge2Color: JsColors.warning,
          ),
          divider,
        ],
        _BottomTabItem(
          icon: Icons.calendar_month,
          label: '月間履歴',
          active: _tabIndex == 2,
          onTap: () => _setTab(2),
        ),
        divider,
        if (widget.isForeman)
          _BottomTabItem(
            icon: Icons.bar_chart,
            label: '管理・集計',
            active: _tabIndex == 4,
            onTap: () => _setTab(4),
          )
        else
          _BottomTabItem(
            icon: Icons.warning_amber_rounded,
            label: '是正依頼',
            active: false,
            badge: _revisionCount,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RevisionInboxScreen()),
            ).then((_) => _loadRevisionCount()),
          ),
      ]),
    );
  }

  // ─── ホームタブ本体 ───
  Widget _buildHomeTabContent() {
    // 完了ビューが占有中は日報フォームを出さない＝到達不能（二重報告防止の要）
    if (_todayReportDone) {
      return AfterReportBody(
        workerName: _userName,
        sent: _lastSentOk,
        // 「今すぐ再送」：既存の再送手段(retryPending)のみ使用。addReport再呼び出しはしない（二重報告防止）
        onRetry: () async {
          await ReportStore.instance.retryPending();
          final remaining = await ReportStore.instance.pendingCount();
          if (mounted) {
            showJsSnackbar(
              context,
              remaining == 0
                  ? '✅ 再送しました'
                  : '📋 まだ未送信です（$remaining件・自動再送を継続します）',
              isWarning: remaining != 0,
            );
          }
        },
        // 現場移動：Navigator.popは廃止。クリア+GPS再取得に加え、完了ビュー解除＋
        // prefsのtoday_work_statusを'working'へ更新してフォームへ復帰する。
        onMoveToNextSite: () async {
          _otherCtrl.clear();
          _parkingCtrl.clear();
          _carpoolCtrl.clear();
          _transportMemoCtrl.clear();
          await _saveWorkStatus('working');
          if (!mounted) return;
          setState(() {
            _todayReportDone = false;
            _gpsAddress = '';
            _transports = {};
            _carType = 'own';
            _routeComparisons = {};
            _workPhotoPaths = [];
            _parkingPhotoPaths = [];
            // 現場移動：現場選択は「対象なし」にリセット
            _selectedSiteId = null;
            _selectedSiteName = null;
          });
          _fetchGps();
        },
        // 夜勤継続：Navigator.popは廃止しスナックバーのみ（挙動は現状維持・設計は別途）
        onNightShift: () {
          if (mounted) showJsSnackbar(context, '🌙 夜勤モードで継続します');
        },
        onOvertime: () async {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => OvertimeDialog(
              workerName: _userName,
              gpsAddress: _gpsAddress,
              onSubmit: (start, end, overtime) async {
                final sentOt = await ReportStore.instance.addReport(WorkerReportItem(
                  name: _userName,
                  transport: TransportType.other,
                  workContent: '【残業】$start〜$end $overtime',
                  gpsAddress: _gpsAddress,
                ));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  showJsSnackbar(
                  context,
                  sentOt ? '✅ 残業報告を送信しました' : '📋 残業報告を保存しました（再送待ち）',
                  isWarning: !sentOt,
                );
                }
              },
            ),
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // コンテンツエリア
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),

                // ① GPS バー（1列、更新ボタン付き）
                _GpsBar(
                  address: _gpsAddress,
                  loading: _gpsLoading,
                  onRefresh: _fetchGps,
                ),
                const SizedBox(height: 8),

                // ①' 作業現場選択（GPS住所の直下・選択必須バッジ付き・金枠強調）
                _SiteSelectField(
                  siteName: _selectedSiteName,
                  onTap: _showSitePicker,
                ),
                const SizedBox(height: 8),

                // 起点選択（自宅/会社）
                _OriginSelector(
                  selected: _originType,
                  onChanged: (type) async {
                    setState(() => _originType = type);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('default_origin', type);
                    await _calculateRoutes();
                  },
                ),
                const SizedBox(height: 4),

                // 健康診断警告
                if (_buildHealthBannerMsg() != null) ...[
                  const SizedBox(height: 4),
                  _HealthCheckBanner(message: _buildHealthBannerMsg()!),
                ],
                const SizedBox(height: 4),

                // ④ 移動手段 4択（1タップ排他・ダブルタップで複数追加）→ 車種別/相乗り → ルート情報
                _TransportRow(
                  selectedSet: _transports,
                  onTap: (t) {
                    final newSet = Set<TransportType>.from(_transports);
                    if (!newSet.contains(t)) {
                      newSet.clear();
                      newSet.add(t);
                    } else if (newSet.length > 1) {
                      newSet.remove(t);
                    }
                    if (!newSet.contains(TransportType.car)) {
                      _parkingCtrl.clear();
                      _parkingPhotoPaths = [];
                    }
                    setState(() => _transports = newSet);
                    _saveWorkStatus('moving');
                    _saveDraft();
                  },
                  onDoubleTap: (t) async {
                    final newSet = Set<TransportType>.from(_transports);
                    if (!newSet.contains(t)) {
                      newSet.add(t);
                      if (newSet.length >= 2) {
                        if (!context.mounted) return;
                        final ok = await showConfirmDialog(context,
                          title: '⚠️ 複数の移動手段',
                          message: '移動手段が2つ以上選択されています。\nよろしいですか？',
                          confirmText: 'OK', cancelText: 'キャンセル',
                        );
                        if (!ok) return;
                      }
                      if (!newSet.contains(TransportType.car)) {
                        _parkingCtrl.clear();
                        if (mounted) setState(() => _parkingPhotoPaths = []);
                      }
                      if (mounted) setState(() => _transports = newSet);
                      _saveWorkStatus('moving');
                      _saveDraft();
                    }
                  },
                ),
                // 車選択時: 社用車/相乗り 2択 → 各入力欄
                if (_transports.contains(TransportType.car)) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _carType = 'own'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _carType == 'own' ? JsColors.gold : JsColors.gunmetal,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _carType == 'own' ? JsColors.gold : JsColors.divider),
                          ),
                          child: Center(child: Text('社用車・自家用車',
                            style: TextStyle(
                              color: _carType == 'own' ? Colors.black : JsColors.offWhite,
                              fontSize: 12,
                              fontWeight: _carType == 'own' ? FontWeight.bold : FontWeight.normal,
                            ))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _carType = 'carpool';
                          _parkingCtrl.clear();
                          _parkingPhotoPaths = [];
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _carType == 'carpool' ? JsColors.gold : JsColors.gunmetal,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _carType == 'carpool' ? JsColors.gold : JsColors.divider),
                          ),
                          child: Center(child: Text('相乗り',
                            style: TextStyle(
                              color: _carType == 'carpool' ? Colors.black : JsColors.offWhite,
                              fontSize: 12,
                              fontWeight: _carType == 'carpool' ? FontWeight.bold : FontWeight.normal,
                            ))),
                        ),
                      ),
                    ),
                  ]),
                  if (_carType == 'carpool') ...[
                    const SizedBox(height: 4),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: JsColors.gunmetal,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: JsColors.gold.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.people, color: JsColors.silver, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _carpoolCtrl,
                            decoration: const InputDecoration(
                              hintText: '誰の相乗りか（任意）',
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: JsColors.silver, fontSize: 12),
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: const TextStyle(color: JsColors.offWhite, fontSize: 13),
                          ),
                        ),
                      ]),
                    ),
                  ],
                  if (_carType == 'own') ...[
                    const SizedBox(height: 4),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: JsColors.gunmetal,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: JsColors.gold.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_parking, color: JsColors.silver, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _parkingCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '駐車料金（円）',
                                border: InputBorder.none,
                                hintStyle: TextStyle(color: JsColors.silver, fontSize: 12),
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: const TextStyle(color: JsColors.offWhite, fontSize: 13),
                              onChanged: (_) => _saveDraft(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 駐車場写真（複数・横スクロール帯）
                    PhotoStripField(
                      label: '駐車場写真（看板・領収書）',
                      paths: _parkingPhotoPaths,
                      onChanged: (v) => setState(() => _parkingPhotoPaths = v),
                    ),
                  ],
                ],
                // その他選択時: 駐車料金・写真欄
                if (_transports.contains(TransportType.other)) ...[
                  const SizedBox(height: 4),
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: JsColors.gunmetal,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: JsColors.gold.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_parking, color: JsColors.silver, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _parkingCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '駐車料金（円）',
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: JsColors.silver, fontSize: 12),
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: const TextStyle(color: JsColors.offWhite, fontSize: 13),
                            onChanged: (_) => _saveDraft(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 駐車場写真（複数・横スクロール帯）
                  PhotoStripField(
                    label: '駐車場写真（看板・領収書）',
                    paths: _parkingPhotoPaths,
                    onChanged: (v) => setState(() => _parkingPhotoPaths = v),
                  ),
                ],
                // 補足テキスト（その他 or 複数選択時）
                if (_transports.contains(TransportType.other) || _transports.length >= 2) ...[
                  const SizedBox(height: 4),
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: JsColors.gunmetal,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: JsColors.gold.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.edit_note, color: JsColors.silver, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _transportMemoCtrl,
                          decoration: const InputDecoration(
                            hintText: '移動手段の補足（任意）例：バイクで駅まで → 電車 → 徒歩',
                            border: InputBorder.none,
                            hintStyle: TextStyle(color: JsColors.silver, fontSize: 12),
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: const TextStyle(color: JsColors.offWhite, fontSize: 13),
                        ),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 4),
                _RouteInfoBar(
                  transport: _transport,
                  comparisons: _routeComparisons,
                  loading: _loadingRoutes,
                ),
                const SizedBox(height: 4),

                // ⑤ 作業内容テキスト（音声入力）
                _WorkContentSection(
                  controller: _workCtrl,
                  showMediaButtons: true,
                  isListening: _isListening,
                  onMicTap: _startVoice,
                ),
                const SizedBox(height: 8),
                // 作業写真（複数・横スクロール帯）
                PhotoStripField(
                  label: '作業写真',
                  paths: _workPhotoPaths,
                  onChanged: (v) => setState(() => _workPhotoPaths = v),
                ),
                const SizedBox(height: 4),

                // ⑥ 残業（タップで時計入力）
                _OvertimeSection(
                  hours: _overtimeHours,
                  minutes: _overtimeMinutes,
                  expanded: _overtimeExpanded,
                  onToggle: () =>
                      setState(() => _overtimeExpanded = !_overtimeExpanded),
                  onChanged: (h, m) {
                    setState(() { _overtimeHours = h; _overtimeMinutes = m; });
                    if (h > 0 || m > 0) {
                      _saveWorkStatus('overtime');
                      _saveDraft();
                    }
                  },
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),

        // 送信ボタン（画面最下部に固定・スクロール外）
        Container(
          color: JsColors.black,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: SlideToConfirm(
            label:     'スライドで送信',
            icon:      Icons.send,
            filled:    true,
            busy:      _submitting,
            onConfirm: _submit,
          ),
        ),
      ],
    );
  }

}

// ─────────────────────────────────────────────
// HomeScreen / ForemanHomeScreen — 後方互換ラッパー
// ─────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.restoreWorkStatus});
  final String? restoreWorkStatus;
  @override
  Widget build(BuildContext context) =>
      JsMainShell(isForeman: false, restoreWorkStatus: restoreWorkStatus);
}

class ForemanHomeScreen extends StatelessWidget {
  const ForemanHomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const JsMainShell(isForeman: true);
}

// ─────────────────────────────────────────────
// BottomTabItem
// ─────────────────────────────────────────────
class _BottomTabItem extends StatelessWidget {
  const _BottomTabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
    this.badge2 = 0,
    this.badgeColor = JsColors.error,
    this.badge2Color = JsColors.error,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;
  final int badge2;
  final Color badgeColor;
  final Color badge2Color;

  // 数値バッジ（丸）1個を生成
  Widget _badgeDot(int n, Color c) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        child: Text('$n',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon,
                  color: active ? JsColors.gold : JsColors.silver, size: 22),
              // 1つ目の丸（右上）
              if (badge > 0)
                Positioned(
                  top: -4, right: -6,
                  child: _badgeDot(badge, badgeColor),
                ),
              // 2つ目の丸（1つ目の左隣＝右上領域に横並び）
              if (badge2 > 0)
                Positioned(
                  top: -4, right: badge > 0 ? 12 : -6,
                  child: _badgeDot(badge2, badge2Color),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: active ? JsColors.gold : JsColors.silver,
                  fontSize: 11,
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// ①' 作業現場 選択欄（GPS住所の直下・金枠強調・選択必須バッジ）
// ─────────────────────────────────────────────
class _SiteSelectField extends StatelessWidget {
  const _SiteSelectField({required this.siteName, required this.onTap});
  final String? siteName;      // null = 対象なし
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isNone = siteName == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: JsColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JsColors.gold, width: 1.5), // 金枠強調
        ),
        child: Row(
          children: [
            const Icon(Icons.place, color: JsColors.gold, size: 20),
            const SizedBox(width: 8),
            const Text('作業現場',
                style: TextStyle(
                    color: JsColors.textMid,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isNone ? '対象なし' : siteName!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isNone ? JsColors.textWeak : JsColors.textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 「選択必須」小バッジ
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x2EA89868), // gold 約18%
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: JsColors.gold, width: 1),
              ),
              child: const Text('選択必須',
                  style: TextStyle(
                      color: JsColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, color: JsColors.gold, size: 20),
          ],
        ),
      ),
    );
  }
}

// 作業現場 選択ボトムシート（getSites サルベージ・「対象なし」最上段固定）
class _SitePickerSheet extends StatefulWidget {
  const _SitePickerSheet(
      {required this.selectedSiteId, required this.onSelected});
  final String? selectedSiteId;
  final void Function(String? id, String? name) onSelected;
  @override
  State<_SitePickerSheet> createState() => _SitePickerSheetState();
}

class _SitePickerSheetState extends State<_SitePickerSheet> {
  final SiteService _siteService = SiteService();
  List<dynamic> _sites = [];
  bool _loading = true;
  String? _error;

  // 現場名の部分一致フィルタ（ローカルのみ・APIは叩かない）。「対象なし」は常に先頭固定＝未選択の道を塞がない。
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // 検索候補（登録現場名・重複除去・非空）。取得済み _sites から生成（新規API無し）。
  List<String> get _candidates {
    final seen = <String>{};
    final out = <String>[];
    for (final s in _sites) {
      final n = ((s as Map)['site_name'] as String? ?? '').trim();
      if (n.isNotEmpty && seen.add(n)) out.add(n);
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _siteService.getSites();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _sites = result['sites'] as List<dynamic>;
      } else {
        _error = result['message'] as String? ?? '現場一覧を取得できませんでした';
      }
    });
  }

  void _choose(String? id, String? name) {
    widget.onSelected(id, name);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('作業現場を選択',
                style: TextStyle(
                    color: JsColors.gold,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Divider(color: JsColors.border, height: 1),
            // 上段=スクロール（「対象なし」＋現場リスト）。高さ不足時はここが逃げる。
            Flexible(child: _buildBody()),
            // 下段=固定: 検索欄（最下段）＋候補チップ（直上）。キーボード追従（viewInsets）。
            // 既存の絞り込みは _buildBody の .where が担当（onChanged で _query 更新）。
            Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchSuggestField(
                  controller: _searchCtrl,
                  candidates: _candidates,
                  hintText: '現場名で検索',
                  onChanged: (v) => setState(() => _query = v),
                  onSelected: (v) => setState(() => _query = v),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: JsColors.gold)),
      );
    }
    // 「対象なし」は最上段固定（エラー時でも必ず選べる）
    final noneTile = _tile(
      id: null,
      title: '対象なし',
      subtitle: '該当現場がない・現場未登録',
      selected: widget.selectedSiteId == null,
    );
    if (_error != null) {
      return ListView(
        shrinkWrap: true,
        children: [
          noneTile,
          const Divider(color: JsColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(_error!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: JsColors.error, fontSize: 13)),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, color: JsColors.gold),
                  label: const Text('再試行',
                      style: TextStyle(color: JsColors.gold)),
                ),
              ],
            ),
          ),
        ],
      );
    }
    // 現場名の部分一致でローカルフィルタ（登録現場の並びは getSites の順を維持）。
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _sites
        : _sites.where((s) =>
            ((s as Map)['site_name'] as String? ?? '').toLowerCase().contains(q)).toList();
    // 検索0件でも「対象なし」は必ず残す（未選択の道を塞がない＝袋小路禁止）。
    if (shown.isEmpty && q.isNotEmpty) {
      return ListView(
        shrinkWrap: true,
        children: [
          noneTile,
          const Divider(color: JsColors.border, height: 1),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('該当する現場がありません',
                textAlign: TextAlign.center,
                style: TextStyle(color: JsColors.textMid, fontSize: 13)),
          ),
        ],
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: shown.length + 1,
      separatorBuilder: (_, __) =>
          const Divider(color: JsColors.border, height: 1),
      itemBuilder: (context, i) {
        if (i == 0) return noneTile;
        final site = shown[i - 1] as Map<String, dynamic>;
        final id = site['site_id'] as String?;
        final name = site['site_name'] as String? ?? '(名称未設定)';
        final addr = site['address'] as String?;
        return _tile(
          id: id,
          title: name,
          subtitle: (addr != null && addr.isNotEmpty) ? addr : null,
          selected: widget.selectedSiteId == id,
        );
      },
    );
  }

  Widget _tile({
    required String? id,
    required String title,
    String? subtitle,
    required bool selected,
  }) {
    return ListTile(
      title: Text(title,
          style: TextStyle(
            color: id == null ? JsColors.textWeak : JsColors.textWhite,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          )),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: const TextStyle(color: JsColors.textMid, fontSize: 12))
          : null,
      trailing:
          selected ? const Icon(Icons.check, color: JsColors.gold) : null,
      onTap: () => _choose(id, id == null ? null : title),
    );
  }
}

// 提出時刻を JST「MM/DD HH:mm」へ整形（端末TZ=Asia/Tokyo前提・punch_screen.dart:17 と同型の手動整形）
String? _fmtSubmittedJst(String? iso) {
  if (iso == null) return null;
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return null;
  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mi = dt.minute.toString().padLeft(2, '0');
  return '$mm/$dd $hh:$mi';
}

// 職長承認ゲート：site_id が null の日報を承認する前に現場を選ばせる
class _SiteLinkGateDialog extends StatefulWidget {
  const _SiteLinkGateDialog({required this.report});
  final Map<String, dynamic> report;
  @override
  State<_SiteLinkGateDialog> createState() => _SiteLinkGateDialogState();
}

class _SiteLinkGateDialogState extends State<_SiteLinkGateDialog> {
  final SiteService _siteService = SiteService();
  List<dynamic> _sites = [];
  bool _loading = true;
  String? _error;
  String? _selectedId; // null = 現場未登録（事務へ回す）＝デフォルト

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _siteService.getSites();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _sites = result['sites'] as List<dynamic>;
      } else {
        _error = result['message'] as String? ?? '現場一覧を取得できませんでした';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final worker = r['worker_name'] as String? ?? '(氏名不明)';
    final submitted = _fmtSubmittedJst(r['created_at'] as String?);  // 生ISO禁止・JST整形
    final gps = r['gps_address'] as String?;
    return AlertDialog(
      backgroundColor: JsColors.surface,
      title: const Text('現場の紐づけ',
          style: TextStyle(color: JsColors.gold, fontSize: 17)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 参考情報
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: JsColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('提出者', worker),
                  if (submitted != null) _infoRow('提出時刻', submitted),
                  if (gps != null && gps.isNotEmpty) _infoRow('GPS住所', gps),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(child: _buildList()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // キャンセル → null
          child: const Text('キャンセル',
              style: TextStyle(color: JsColors.textMid)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {'site_id': _selectedId}),
          style: ElevatedButton.styleFrom(
            backgroundColor: JsColors.success,
            foregroundColor: Colors.white,
          ),
          child: const Text('選択して承認'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style:
                    const TextStyle(color: JsColors.textMid, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: JsColors.textStrong, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ＋新規現場を登録 → 仮登録フォームへ。site_id が返ったら既存の現場選択フローに合流:
  // ゲートを {'site_id': ...} 付きで pop → 承認ハンドラが PATCH /reports/:id/site → 承認 を実行。
  Future<void> _openQuickRegister() async {
    final siteId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SiteQuickRegisterScreen(
          // a案: 対象日報の gps_address を渡し、画面は即開く（geocode を待たない）。
          // 住所欄の初期値になり、かつ画面側で gps_address→geocode→matchSites の重複チェックに使う。
          initialAddress: widget.report['gps_address'] as String?,
          // reports に lat/lng 列は無い（prod_schema）ため数値座標は渡さない（画面が gps_address を
          // geocode して座標化する）。職長の現在GPSは使わない（誤マッチ回避・確定設計）。
          lat: null,
          lng: null,
        ),
      ),
    );
    if (!mounted || siteId == null || siteId.isEmpty) return;
    Navigator.pop(context, {'site_id': siteId});
  }

  Widget _buildList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: JsColors.gold)),
      );
    }
    // 最上段固定は上から順に:
    //   ① ＋新規現場を登録（緑・仮登録の正のアクション＝OFFICE S3 ダイアログの並びに合わせ最上段）
    //   ② 現場未登録（事務へ回す）（オレンジ・既存の退避選択肢）
    // ①は選択(radio)ではなくアクションのため RadioListTile ではなくタップ行にする。
    final children = <Widget>[
      InkWell(
        onTap: _openQuickRegister,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: const Row(children: [
            Icon(Icons.add_location_alt, color: JsColors.success, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text('＋新規現場を登録',
                  style: TextStyle(
                      color: JsColors.success, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            Icon(Icons.chevron_right, color: JsColors.success, size: 20),
          ]),
        ),
      ),
      const Divider(color: JsColors.divider, height: 1),
      RadioListTile<String?>(
        value: null,
        groupValue: _selectedId,
        onChanged: (v) => setState(() => _selectedId = v),
        activeColor: JsColors.warning,
        title: const Text('現場未登録（事務へ回す）',
            style: TextStyle(
                color: JsColors.warning,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
        subtitle: const Text('承認は完了・紐づけは事務の未紐づけ一覧に残る',
            style: TextStyle(color: JsColors.textMid, fontSize: 11)),
        contentPadding: EdgeInsets.zero,
      ),
    ];
    if (_error != null) {
      children.add(Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: JsColors.error, fontSize: 12)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon:
                  const Icon(Icons.refresh, color: JsColors.gold, size: 18),
              label:
                  const Text('再試行', style: TextStyle(color: JsColors.gold)),
            ),
          ],
        ),
      ));
    } else {
      for (final s in _sites) {
        final site = s as Map<String, dynamic>;
        final id = site['site_id'] as String?;
        final name = site['site_name'] as String? ?? '(名称未設定)';
        children.add(RadioListTile<String?>(
          value: id,
          groupValue: _selectedId,
          onChanged: (v) => setState(() => _selectedId = v),
          activeColor: JsColors.gold,
          title: Text(name,
              style:
                  const TextStyle(color: JsColors.textWhite, fontSize: 14)),
          contentPadding: EdgeInsets.zero,
        ));
      }
    }
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

// ─────────────────────────────────────────────
// ① GPS バー
// ─────────────────────────────────────────────
class _GpsBar extends StatelessWidget {
  const _GpsBar({
    required this.address,
    required this.loading,
    required this.onRefresh,
  });
  final String address;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JsColors.divider),
      ),
      child: Row(
        children: [
          const Text('📍', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(
            child: loading
                ? const Text('GPS取得中...',
                    style: TextStyle(color: JsColors.silver, fontSize: 12))
                : Text(
                    address.isEmpty ? '現場住所 未取得' : address,
                    style: const TextStyle(
                        color: JsColors.offWhite, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          GestureDetector(
            onTap: onRefresh,
            child: Container(
              padding: const EdgeInsets.all(6),
              child: const Icon(Icons.refresh,
                  color: JsColors.silver, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 打刻タブ 天気パネル（JsMainShell → PunchScreen へ渡す Widget）
// ─────────────────────────────────────────────
class _PunchWeatherPanel extends StatefulWidget {
  const _PunchWeatherPanel({
    required this.weather,
    required this.forecast,
    required this.loading,
    required this.seasonWarning,
  });
  final _WeatherData? weather;
  final List<_ForecastDay> forecast;
  final bool loading;
  final String? seasonWarning;

  @override
  State<_PunchWeatherPanel> createState() => _PunchWeatherPanelState();
}

class _PunchWeatherPanelState extends State<_PunchWeatherPanel> {
  bool _showForecast = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C0C0A),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PunchWeatherRow(
            weather:      widget.weather,
            loading:      widget.loading,
            expanded:     _showForecast,
            onToggle:     () => setState(() => _showForecast = !_showForecast),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve:    Curves.easeInOut,
            child: _showForecast && widget.forecast.isNotEmpty
                ? _PunchForecastStrip(forecast: widget.forecast)
                : const SizedBox.shrink(),
          ),
          if (widget.weather != null) ...[
            const SizedBox(height: 4),
            _PunchWbgtRow(
              weather:       widget.weather!,
              seasonWarning: widget.seasonWarning,
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _PunchWeatherRow extends StatelessWidget {
  const _PunchWeatherRow({
    required this.weather,
    required this.loading,
    required this.expanded,
    required this.onToggle,
  });
  final _WeatherData? weather;
  final bool loading;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: JsColors.gunmetal,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JsColors.divider),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: JsColors.gold)))
            : weather == null
                ? const Center(
                    child: Text('天気データ取得中...',
                        style: TextStyle(color: JsColors.silver, fontSize: 12)))
                : Row(
                    children: [
                      _PunchWeatherItem(
                          label: '気温',
                          value: '${weather!.tempC.round()}°C'),
                      _PunchVd(),
                      _PunchWeatherItem(
                          label: '降水',
                          value: '${weather!.precipPct}%',
                          valueColor: weather!.precipPct >= 50
                              ? const Color(0xFF64B5F6)
                              : null),
                      _PunchVd(),
                      _PunchWeatherItem(
                          label: '風速',
                          value: weather!.windSpeed != null
                              ? '${weather!.windSpeed!.toStringAsFixed(1)}m/s'
                              : '--'),
                      _PunchVd(),
                      _PunchWeatherItem(
                          label: '天気',
                          value: weather!.icon,
                          isEmoji: true),
                      const SizedBox(width: 4),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: JsColors.silver,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
      ),
    );
  }
}

class _PunchWeatherItem extends StatelessWidget {
  const _PunchWeatherItem({
    required this.label,
    required this.value,
    this.valueColor,
    this.isEmoji = false,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final bool isEmoji;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: JsColors.silver, fontSize: 9)),
          const SizedBox(height: 2),
          isEmoji
              ? Text(value, style: const TextStyle(fontSize: 18))
              : Text(value,
                  style: TextStyle(
                      color: valueColor ?? JsColors.offWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PunchVd extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 28,
        color: JsColors.divider,
      );
}

class _PunchForecastStrip extends StatelessWidget {
  const _PunchForecastStrip({required this.forecast});
  final List<_ForecastDay> forecast;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JsColors.divider),
      ),
      child: Row(
        children: forecast.map((day) {
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(day.weekday,
                    style: const TextStyle(
                        color: JsColors.silver,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(day.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 2),
                Text('${day.maxC.round()}°',
                    style: const TextStyle(
                        color: Color(0xFFEF9A9A),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
                Text('${day.minC.round()}°',
                    style: const TextStyle(
                        color: Color(0xFF90CAF9), fontSize: 11)),
                if (day.precipPct > 0)
                  Text('${day.precipPct}%',
                      style: TextStyle(
                          color: day.precipPct >= 50
                              ? const Color(0xFF64B5F6)
                              : JsColors.silver,
                          fontSize: 9)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PunchWbgtRow extends StatelessWidget {
  const _PunchWbgtRow({
    required this.weather,
    required this.seasonWarning,
  });
  final _WeatherData weather;
  final String? seasonWarning;

  @override
  Widget build(BuildContext context) {
    final wbgt  = _calcWBGT(weather.tempC, weather.humidity);
    final level = _wbgtLevel(wbgt);
    final color = _wbgtColor(wbgt);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('⚠️ WBGT ${wbgt.round()}',
                style: const TextStyle(color: JsColors.offWhite, fontSize: 11)),
            const SizedBox(width: 6),
            Text(level,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
        if (seasonWarning != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(seasonWarning!,
                style: const TextStyle(
                    color: Color(0xFFFFCC80), fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
// スケルトンローディング
// ─────────────────────────────────────────────
class _HomeSkeletonBody extends StatefulWidget {
  const _HomeSkeletonBody();
  @override
  State<_HomeSkeletonBody> createState() => _HomeSkeletonBodyState();
}

class _HomeSkeletonBodyState extends State<_HomeSkeletonBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.25, end: 0.55)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Widget _box({double h = 16, double? w, double radius = 8}) =>
      AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _box(h: 44, w: double.infinity, radius: 10),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _box(h: 90, radius: 10)),
          const SizedBox(width: 8),
          Expanded(child: _box(h: 90, radius: 10)),
        ]),
        const SizedBox(height: 8),
        _box(h: 34, w: double.infinity, radius: 8),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < 4; i++) ...[
            Expanded(child: _box(h: 56, radius: 8)),
            if (i < 3) const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: _box(h: double.infinity, w: double.infinity, radius: 10),
        ),
        const SizedBox(height: 8),
        _box(h: 52, w: double.infinity, radius: 10),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// 健康診断警告バナー
// ─────────────────────────────────────────────
class _HealthCheckBanner extends StatelessWidget {
  const _HealthCheckBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final isDanger = message.startsWith('🔴');
    final base =
        isDanger ? const Color(0xFFB71C1C) : const Color(0xFFE65100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: base.withValues(alpha: 0.6)),
      ),
      child: Text(
        message,
        style: TextStyle(
            color: isDanger
                ? const Color(0xFFEF9A9A)
                : const Color(0xFFFFCC80),
            fontSize: 12,
            fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ③.5 起点選択（自宅 / 会社）
// ─────────────────────────────────────────────
class _OriginSelector extends StatelessWidget {
  const _OriginSelector({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('今日の起点:',
            style: TextStyle(color: JsColors.silver, fontSize: 13)),
        const SizedBox(width: 10),
        ...['home', 'office'].map((type) {
          final label = type == 'home' ? '自宅' : '会社';
          final sel = selected == type;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: sel
                      ? JsColors.gold.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: sel ? JsColors.gold : JsColors.divider),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: sel ? JsColors.gold : JsColors.silver,
                    fontSize: 13,
                    fontWeight:
                        sel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ④ 移動手段 4択横並び
// ─────────────────────────────────────────────
class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.selectedSet,
    required this.onTap,
    required this.onDoubleTap,
  });
  final Set<TransportType> selectedSet;
  final Function(TransportType) onTap;
  final Function(TransportType) onDoubleTap;

  static const _options = [
    TransportType.car,
    TransportType.train,
    TransportType.bus,
    TransportType.other,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: _options.map((t) {
          final sel = selectedSet.contains(t);
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(t),
              onDoubleTap: () => onDoubleTap(t),
              child: Container(
                margin: EdgeInsets.only(right: t != _options.last ? 6 : 0),
                decoration: BoxDecoration(
                  color: sel ? JsColors.gold : JsColors.gunmetal,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? JsColors.gold : JsColors.divider),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(t.icon, size: 18, color: sel ? Colors.black : JsColors.silver),
                    const SizedBox(height: 3),
                    Text(t.label,
                        style: TextStyle(
                            color: sel ? Colors.black : JsColors.offWhite,
                            fontSize: 11,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ⑤ 作業内容セクション（マイク / カメラ / テキスト）
// ─────────────────────────────────────────────
class _WorkContentSection extends StatelessWidget {
  const _WorkContentSection({
    required this.controller,
    this.showMediaButtons = false,
    this.isListening = false,
    this.onMicTap,
  });
  final TextEditingController controller;
  final bool showMediaButtons;
  final bool isListening;
  final VoidCallback? onMicTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(children: [
                  Icon(Icons.construction,
                      color: JsColors.gold, size: 15),
                  SizedBox(width: 6),
                  Text('作業内容',
                      style: TextStyle(
                          color: JsColors.offWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ]),
                if (showMediaButtons)
                  _SmallMediaButton(
                    icon: isListening ? Icons.mic : Icons.mic_none,
                    active: isListening,
                    onTap: onMicTap,
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: JsColors.divider),

          // テキスト入力欄
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: TextField(
                controller: controller,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: '例：1階電気配線工事 コンセント10箇所設置',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(
                    color: JsColors.offWhite, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// メディアボタン（マイク / カメラ）
// ─────────────────────────────────────────────
class _SmallMediaButton extends StatelessWidget {
  const _SmallMediaButton({
    required this.icon,
    required this.active,
    this.onTap,
  });
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32,
      height: 28,
      decoration: BoxDecoration(
        color: active
            ? JsColors.gold.withValues(alpha: 0.18)
            : JsColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: active ? JsColors.gold : JsColors.divider),
      ),
      child: Icon(icon,
          size: 15,
          color: active ? JsColors.gold : JsColors.silver),
    ),
  );
}

// ─────────────────────────────────────────────
// ⑥ 残業セクション（タップで時計入力）
// ─────────────────────────────────────────────
class _OvertimeSection extends StatelessWidget {
  const _OvertimeSection({
    required this.hours,
    required this.minutes,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
  });
  final int hours;
  final int minutes;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(int hours, int minutes) onChanged;

  String get _label {
    if (hours == 0 && minutes == 0) return 'なし';
    if (hours == 0) return '$minutes分';
    if (minutes == 0) return '$hours時間';
    return '$hours時間$minutes分';
  }

  @override
  Widget build(BuildContext context) {
    final hasOvertime = hours > 0 || minutes > 0;
    return Container(
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasOvertime
              ? JsColors.warning.withValues(alpha: 0.6)
              : JsColors.divider,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Row(children: [
                const Icon(Icons.access_time,
                    color: JsColors.gold, size: 16),
                const SizedBox(width: 6),
                const Text('残業',
                    style: TextStyle(
                        color: JsColors.offWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text(_label,
                    style: TextStyle(
                        color:
                            hasOvertime ? JsColors.warning : JsColors.silver,
                        fontSize: 13,
                        fontWeight: hasOvertime
                            ? FontWeight.bold
                            : FontWeight.normal)),
                const Spacer(),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: JsColors.silver,
                  size: 18,
                ),
              ]),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: JsColors.divider),
            SizedBox(
              height: 120,
              child: _OvertimePicker(
                hours: hours,
                minutes: minutes,
                onChanged: onChanged,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 残業ドラムロールピッカー
// ─────────────────────────────────────────────
class _OvertimePicker extends StatefulWidget {
  const _OvertimePicker({
    required this.hours,
    required this.minutes,
    required this.onChanged,
  });
  final int hours;
  final int minutes;
  final void Function(int, int) onChanged;

  @override
  State<_OvertimePicker> createState() => _OvertimePickerState();
}

class _OvertimePickerState extends State<_OvertimePicker> {
  late FixedExtentScrollController _hCtrl;
  late FixedExtentScrollController _mCtrl;

  @override
  void initState() {
    super.initState();
    _hCtrl = FixedExtentScrollController(initialItem: widget.hours);
    _mCtrl =
        FixedExtentScrollController(initialItem: widget.minutes ~/ 5);
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Column(children: [
          const SizedBox(height: 4),
          const Text('時間',
              style: TextStyle(color: JsColors.silver, fontSize: 10)),
          Expanded(
            child: CupertinoPicker(
              scrollController: _hCtrl,
              itemExtent: 36,
              backgroundColor: Colors.transparent,
              selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                  background: JsColors.gold.withValues(alpha: 0.12)),
              onSelectedItemChanged: (i) =>
                  widget.onChanged(i, widget.minutes),
              children: List.generate(
                13,
                (i) => Center(
                    child: Text('$i',
                        style: const TextStyle(
                            color: JsColors.offWhite, fontSize: 20))),
              ),
            ),
          ),
        ]),
      ),
      const Text(':',
          style: TextStyle(
              color: JsColors.silver,
              fontSize: 20,
              fontWeight: FontWeight.bold)),
      Expanded(
        child: Column(children: [
          const SizedBox(height: 4),
          const Text('分',
              style: TextStyle(color: JsColors.silver, fontSize: 10)),
          Expanded(
            child: CupertinoPicker(
              scrollController: _mCtrl,
              itemExtent: 36,
              backgroundColor: Colors.transparent,
              selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                  background: JsColors.gold.withValues(alpha: 0.12)),
              onSelectedItemChanged: (i) =>
                  widget.onChanged(widget.hours, i * 5),
              children: List.generate(
                12,
                (i) => Center(
                    child: Text((i * 5).toString().padLeft(2, '0'),
                        style: const TextStyle(
                            color: JsColors.offWhite, fontSize: 20))),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
// 音声入力ダイアログ
// ─────────────────────────────────────────────
class _VoiceInputDialog extends StatefulWidget {
  const _VoiceInputDialog(
      {required this.manager,
      required this.onConfirm,
      required this.onCancel});
  final SpeechManager manager;
  final void Function(String) onConfirm;
  final VoidCallback onCancel;

  @override
  State<_VoiceInputDialog> createState() => _VoiceInputDialogState();
}

class _VoiceInputDialogState extends State<_VoiceInputDialog>
    with SingleTickerProviderStateMixin {
  String _text          = '';
  bool   _listening     = false;
  bool   _manualStop    = false;
  String _committed     = '';
  int    _emptyRestarts = 0;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _start();
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  void _onResult(String text, bool isFinal) {
    if (!mounted) return;
    if (text.trim().isNotEmpty) _emptyRestarts = 0;
    setState(() => _text = '$_committed$text'.trim());
    if (isFinal && text.trim().isNotEmpty) _committed = '$_committed$text ';
  }

  void _onSessionDone() {
    if (!mounted || !_listening || _manualStop) return;
    if (++_emptyRestarts > 6) { setState(() => _listening = false); return; }
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted && _listening && !_manualStop) {
        widget.manager.startListening(
          onResult: _onResult,
          onSessionDone: _onSessionDone,
          onPermanentError: _onPermanentError,
        );
      }
    });
  }

  void _onPermanentError(String errorMsg) async {
    if (!mounted) return;
    setState(() => _listening = false);
    final ok = await widget.manager.hasPermission;
    if (!ok && mounted) {
      showJsSnackbar(context, 'マイクの権限がありません。設定から許可してください', isError: true);
    }
  }

  void _start() {
    _listening     = true;
    _manualStop    = false;
    _emptyRestarts = 0;
    _committed     = _text.isEmpty ? '' : '${_text.trim()} ';
    setState(() {});
    widget.manager.startListening(
      onResult: _onResult,
      onSessionDone: _onSessionDone,
      onPermanentError: _onPermanentError,
    );
  }

  void _stop() {
    _manualStop = true;
    _listening  = false;
    widget.manager.stop();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: JsColors.gunmetal,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('🎤 作業内容 音声入力',
        style: TextStyle(color: JsColors.gold)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _listening
                  ? JsColors.gold.withValues(
                      alpha: 0.15 + _pulse.value * 0.15)
                  : JsColors.surface,
            ),
            child: Icon(
                _listening ? Icons.mic : Icons.mic_off,
                color:
                    _listening ? JsColors.gold : JsColors.silver,
                size: 32),
          ),
        ),
        const SizedBox(height: 6),
        Text(_listening ? '聞いています...' : '認識完了',
            style: TextStyle(
                color: _listening ? JsColors.gold : JsColors.silver,
                fontSize: 12)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: JsColors.surface,
              borderRadius: BorderRadius.circular(8)),
          constraints: const BoxConstraints(minHeight: 56),
          child: Text(
            _text.isEmpty
                ? '例：1階電気配線工事 コンセント10箇所設置'
                : _text,
            style: TextStyle(
                color: _text.isEmpty
                    ? JsColors.silver
                    : JsColors.offWhite,
                fontSize: _text.isEmpty ? 12 : 14,
                height: 1.5),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
          onPressed: widget.onCancel,
          child: const Text('キャンセル',
              style: TextStyle(color: JsColors.silver))),
      if (_listening)
        TextButton(
            onPressed: _stop,
            child: const Text('停止',
                style: TextStyle(color: JsColors.gold))),
      if (!_listening && _text.isNotEmpty)
        ElevatedButton(
            onPressed: () => widget.onConfirm(_text),
            child: const Text('確定')),
    ],
  );
}

// ─────────────────────────────────────────────
// ルート情報バー
// ─────────────────────────────────────────────
class _RouteInfoBar extends StatelessWidget {
  const _RouteInfoBar({
    required this.transport,
    required this.comparisons,
    required this.loading,
  });
  final TransportType transport;
  final Map<String, dynamic> comparisons;
  final bool loading;

  Widget _placeholder() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: JsColors.gunmetal,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JsColors.divider),
        ),
        child: const Row(children: [
          Icon(Icons.route, color: JsColors.silver, size: 14),
          SizedBox(width: 6),
          Text('距離: -- km　金額: ¥--',
              style: TextStyle(color: JsColors.silver, fontSize: 12)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: JsColors.gunmetal,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JsColors.divider),
        ),
        child: const Row(children: [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: JsColors.gold)),
          SizedBox(width: 8),
          Text('ルート計算中...',
              style: TextStyle(color: JsColors.silver, fontSize: 12)),
        ]),
      );
    }

    String? timeStr, costStr, distStr;

    if (comparisons.isNotEmpty) {
      if (transport == TransportType.car || transport == TransportType.other) {
        final c = comparisons['car'] as CarRoute?;
        if (c != null) {
          timeStr = '${c.time}分';
          distStr = c.distanceText;
          if (c.gasCost > 0) costStr = '⛽¥${c.gasCost}';
        }
      } else if (transport == TransportType.train ||
          transport == TransportType.bus) {
        final t = comparisons['transit'] as TransitRoute?;
        if (t != null) {
          timeStr = '${t.time}分';
          costStr = '💴¥${t.fareIc}';
          if (t.depStation.isNotEmpty && t.arrStation.isNotEmpty) {
            distStr = '${t.depStation}→${t.arrStation}';
          }
        }
      } else if (transport == TransportType.bike) {
        final b = comparisons['bicycling'] as SimpleRoute?;
        if (b != null) { timeStr = b.duration; distStr = b.distance; }
      } else {
        final w = comparisons['walking'] as SimpleRoute?;
        if (w != null) { timeStr = w.duration; distStr = w.distance; }
      }
    }

    if (timeStr == null) return _placeholder();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JsColors.gold.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.route, color: JsColors.gold, size: 14),
        const SizedBox(width: 6),
        if (distStr != null) ...[
          Flexible(
            child: Text(distStr,
                style: const TextStyle(
                    color: JsColors.offWhite, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
          ),
          const SizedBox(width: 8),
        ],
        const Icon(Icons.access_time, color: JsColors.silver, size: 13),
        const SizedBox(width: 3),
        Text(timeStr,
            style: const TextStyle(
                color: JsColors.offWhite,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        if (costStr != null) ...[
          const SizedBox(width: 10),
          Text(costStr,
              style: const TextStyle(
                  color: JsColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// 職長管理・集計タブ本体（3入口）
// ─────────────────────────────────────────────
class _ForemanManagementBody extends StatelessWidget {
  const _ForemanManagementBody();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: JsColors.gunmetal,
            child: const TabBar(
              tabs: [
                Tab(text: '📅 カレンダー'),
                Tab(text: '👥 社員'),
                Tab(text: '🏢 協力'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _CalendarTab(),
                _StaffTab(),
                _CooperationTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 承認・是正タブ（S2）: [承認待ち / 差戻し] の2サブタブ
// ─────────────────────────────────────────────
class _ReviewTab extends StatefulWidget {
  const _ReviewTab();
  @override
  State<_ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<_ReviewTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  // 両サブタブの State へアクセスして再読込するためのキー（同一ライブラリ内解決）。
  final GlobalKey<_PendingApprovalTabState> _pendingKey =
      GlobalKey<_PendingApprovalTabState>();
  final GlobalKey<RevisionInboxBodyState> _revisionKey =
      GlobalKey<RevisionInboxBodyState>();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_onTabSettled);
  }

  // (i) サブタブがアクティブになるたび、そのリストを再読込（stale 表示の防止）。
  void _onTabSettled() {
    if (_tab.indexIsChanging) return;
    if (_tab.index == 0) {
      _pendingKey.currentState?.reload();
    } else {
      _revisionKey.currentState?.reload();
    }
  }

  // (ii) 承認/修正依頼の操作成功後、両リストを再読込（相互の残存を解消）。
  void _reloadBoth() {
    _pendingKey.currentState?.reload();
    _revisionKey.currentState?.reload();
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabSettled);
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: JsColors.gunmetal,
          child: TabBar(
            controller: _tab,
            tabs: const [
              Tab(text: '承認待ち'),
              Tab(text: '差戻し'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _PendingApprovalTab(key: _pendingKey, onActionSuccess: _reloadBoth),
              RevisionInboxBody(key: _revisionKey, isForeman: true),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ④ 承認待ちタブ（P4-2 STEP3a: 一覧表示のみ。承認/差戻し・写真は後続STEP）
// ─────────────────────────────────────────────
class _PendingApprovalTab extends StatefulWidget {
  const _PendingApprovalTab({super.key, this.onActionSuccess});
  // 承認/修正依頼の成功後に呼ぶ（親 _ReviewTab が両リスト再読込に配線）。
  final VoidCallback? onActionSuccess;
  @override
  State<_PendingApprovalTab> createState() => _PendingApprovalTabState();
}

class _PendingApprovalTabState extends State<_PendingApprovalTab> {
  List<Map<String, dynamic>> _pending = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  // 親（_ReviewTab）からの再読込用に公開。
  void reload() => _loadPending();

  Future<void> _loadPending() async {
    setState(() => _loading = true);
    final result = await ReportsService().getReports(limit: 50);
    if (!mounted) return;
    if (result['success'] == true) {
      final raw = List<Map<String, dynamic>>.from(result['reports'] ?? []);
      // 承認待ち＝送信済み かつ 未承認 かつ 差戻し中でない
      final pending = raw
          .where((r) =>
              r['is_sent'] == true &&
              r['approved'] != true &&
              r['revision_requested'] != true)
          .map((r) => {...r, 'status': 'pending'})
          .toList();
      setState(() {
        _pending = pending;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: JsColors.gold));
    }
    if (_pending.isEmpty) {
      return const Center(
        child: Text('承認待ちの日報はありません',
            style: TextStyle(color: JsColors.silver, fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pending.length,
      itemBuilder: (context, i) => _pendingCard(context, _pending[i]),
    );
  }

  // 読み取り専用の日報詳細ボトムシートを開く（根因a対策：承認待ちカードの詳細導線）。
  void _openDetail(BuildContext context, Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      backgroundColor: JsColors.gunmetal,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ReportDetailSheet(report: r),
    );
  }

  // カード1件: 共有部品 JsReportTile(非改変) に写真とアクション行を合成。
  Widget _pendingCard(BuildContext context, Map<String, dynamic> r) {
    final reportId = r['report_id']?.toString() ?? '';
    bool sending = false;
    // カード本体タップで詳細シートを開く。承認/修正依頼ボタンは自前でタップを消費するため干渉しない。
    // JsReportTile は自前 onTap（不完全な旧詳細）を持つため AbsorbPointer で無効化し、導線を一本化する。
    return GestureDetector(
      onTap: () => _openDetail(context, r),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AbsorbPointer(child: JsReportTile(report: r, myCompanyId: '')),
          const SizedBox(height: 8),
          ReportPhotos(reportId: reportId, report: r),
          const SizedBox(height: 8),
          StatefulBuilder(
            builder: (context, setSending) => Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: sending
                        ? null
                        : () async {
                            String selectedOrigin =
                                r['origin_type'] as String? ?? 'home';
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (_) => OriginConfirmDialog(
                                initialOrigin: selectedOrigin,
                                onChanged: (v) => selectedOrigin = v,
                              ),
                            );
                            if (confirmed != true || !context.mounted) return;

                            // 現場紐づけゲート：site_id が null の日報は承認前に現場選択を促す。
                            // site_id が既にある日報は従来どおりダイアログなしで承認する。
                            final existingSiteId = r['site_id'] as String?;
                            if (existingSiteId == null) {
                              final gate =
                                  await showDialog<Map<String, dynamic>>(
                                context: context,
                                builder: (_) => _SiteLinkGateDialog(report: r),
                              );
                              // キャンセル（null）→ 何もしない
                              if (gate == null || !context.mounted) return;
                              final chosenSiteId =
                                  gate['site_id'] as String?;
                              if (chosenSiteId != null) {
                                // 現場を選択 → PATCH site を先に実行。非200は無言禁止＝承認中断。
                                setSending(() => sending = true);
                                final linkRes = await ReportsService()
                                    .linkReportToSite(reportId, chosenSiteId);
                                if (linkRes['success'] != true) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '現場の紐づけに失敗しました：${linkRes['error']}'),
                                        backgroundColor: JsColors.error,
                                      ),
                                    );
                                    setSending(() => sending = false);
                                  }
                                  return; // 承認は中断
                                }
                              }
                              // chosenSiteId == null（事務へ回す）→ 紐づけせず承認へ進む
                            }

                            setSending(() => sending = true);
                            final result = await ReportsService()
                                .approveReport(reportId,
                                    originType: selectedOrigin);
                            final ok = result['success'] == true;
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? '承認しました'
                                      : '承認に失敗しました：${result['error']}'),
                                  backgroundColor:
                                      ok ? JsColors.success : JsColors.error,
                                ),
                              );
                              if (ok) (widget.onActionSuccess ?? _loadPending)();
                            }
                            if (context.mounted) {
                              setSending(() => sending = false);
                            }
                          },
                    icon: const Icon(Icons.check),
                    label: const Text('承認'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: JsColors.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: sending
                        ? null
                        : () async {
                            final result =
                                await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (_) => RevisionReasonDialog(
                                transportTypes: r['transport_types_json']
                                    as List<dynamic>?,
                              ),
                            );
                            if (result == null || !context.mounted) return;
                            final reasons = result['reasons'] as List<String>;
                            if (reasons.isEmpty) return;
                            final comment = result['comment'] as String?;
                            setSending(() => sending = true);
                            final res = await ReportsService().requestRevision(
                                reportId, reasons,
                                reason: comment ?? '');
                            final ok = res['success'] == true;
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? '修正依頼を送りました'
                                      : '修正依頼に失敗しました：${res['error']}'),
                                  backgroundColor:
                                      ok ? JsColors.warning : JsColors.error,
                                ),
                              );
                              if (ok) (widget.onActionSuccess ?? _loadPending)();
                            }
                            if (context.mounted) {
                              setSending(() => sending = false);
                            }
                          },
                    icon: const Icon(Icons.edit_note),
                    label: const Text('修正依頼'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: JsColors.warning,
                      foregroundColor: const Color(0xFF3D1E00),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ② 社員一覧タブ
// ─────────────────────────────────────────────
class _StaffTab extends StatefulWidget {
  const _StaffTab();
  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  List<Map<String, dynamic>> _staff = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http
          .get(
            Uri.parse('$API_URL/workers?membership_type=employee'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final companies =
            List<Map<String, dynamic>>.from(data['companies'] ?? []);
        final own = companies.firstWhere(
          (c) => c['is_own'] == true,
          orElse: () => <String, dynamic>{},
        );
        setState(() {
          _staff = List<Map<String, dynamic>>.from(own['workers'] ?? []);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: JsColors.gold));
    }
    if (_staff.isEmpty) {
      return const Center(
        child: Text('社員がいません',
            style: TextStyle(color: JsColors.silver, fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _staff.length,
      itemBuilder: (context, i) => _StaffCard(worker: _staff[i]),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.worker});
  final Map<String, dynamic> worker;

  @override
  Widget build(BuildContext context) {
    final name = worker['name'] as String? ?? '不明';
    final role = worker['role'] as String? ?? '';
    final roleLabel = role == 'boss' ? '職長' : '職人';
    final expYears = (worker['experience_years'] as num?)?.toInt() ?? 0;
    final personId = worker['user_id'] as String? ?? '';

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: JsColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => _StaffMonthlySheet(personId: personId, name: name),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: JsColors.gunmetal,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.person_outline, color: JsColors.silver, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: JsColors.gold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(roleLabel,
                  style:
                      const TextStyle(color: JsColors.gold, fontSize: 10)),
            ),
            const SizedBox(width: 8),
            Text('$expYears年',
                style:
                    const TextStyle(color: JsColors.silver, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _StaffMonthlySheet extends StatefulWidget {
  const _StaffMonthlySheet({required this.personId, required this.name});
  final String personId;
  final String name;

  @override
  State<_StaffMonthlySheet> createState() => _StaffMonthlySheetState();
}

class _StaffMonthlySheetState extends State<_StaffMonthlySheet> {
  DateTime _selectedMonth = DateTime.now();
  Map<String, dynamic>? _summary;
  bool _loading = false;

  String get _monthStr =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadMonthly();
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _loadMonthly();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year &&
        _selectedMonth.month == now.month) {
      return;
    }
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _loadMonthly();
  }

  Future<void> _loadMonthly() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http
          .get(
            Uri.parse(
                '$API_URL/attendance/monthly-summary?person_id=${widget.personId}&month=$_monthStr'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _summary = jsonDecode(res.body) as Map<String, dynamic>;
          _loading = false;
        });
      } else {
        setState(() {
          _summary = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _summary = null;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;
    final note = _summary?['note'] as String? ??
        '参考値です。労働時間・賃金の最終確定は貴社の責任で行ってください';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: JsColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Container(
            color: JsColors.gunmetal,
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: JsColors.gold),
                  onPressed: _prevMonth,
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_selectedMonth.year}年${_selectedMonth.month}月',
                      style: const TextStyle(
                          color: JsColors.gold,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.chevron_right,
                    color: isCurrentMonth
                        ? JsColors.divider
                        : JsColors.gold,
                  ),
                  onPressed: isCurrentMonth ? null : _nextMonth,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: JsColors.gold))
                : _summary == null
                    ? const Center(
                        child: Text('データなし',
                            style: TextStyle(
                                color: JsColors.silver, fontSize: 13)))
                    : ListView(
                        controller: controller,
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        children: [
                          Row(
                            children: [
                              JsStatChip(
                                '出勤日数',
                                (_summary!['days_worked'] as num?)
                                        ?.toInt() ??
                                    0,
                                JsColors.silver,
                              ),
                              const SizedBox(width: 4),
                              _StaffStatChip(
                                '実働',
                                () {
                                  final mins =
                                      (_summary!['total_net_minutes']
                                                  as num?)
                                              ?.toDouble() ??
                                          0;
                                  return '${(mins / 60).toStringAsFixed(1)}h';
                                }(),
                                JsColors.gold,
                              ),
                              const SizedBox(width: 4),
                              JsStatChip(
                                '残業',
                                ((_summary!['overtime']
                                            as Map<String, dynamic>?)?[
                                        'total_min'] as num?)
                                    ?.toInt() ??
                                    0,
                                JsColors.warning,
                              ),
                              const SizedBox(width: 4),
                              JsStatChip(
                                '休日出勤',
                                (_summary!['holiday_work_days'] as num?)
                                        ?.toInt() ??
                                    0,
                                JsColors.error,
                              ),
                            ],
                          ),
                        ],
                      ),
          ),
          // note は summary の有無にかかわらず常時表示（法務の盾3層目）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              note,
              style:
                  const TextStyle(color: JsColors.silver, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// JsStatChip の String値版（実働時間 h表記用）
class _StaffStatChip extends StatelessWidget {
  const _StaffStatChip(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────
// ③ 協力業者タブ
// ─────────────────────────────────────────────
class _CooperationTab extends StatefulWidget {
  const _CooperationTab();

  @override
  State<_CooperationTab> createState() => _CooperationTabState();
}

class _CooperationTabState extends State<_CooperationTab> {
  DateTime _selectedMonth = DateTime.now();
  List<Map<String, dynamic>> _companies = [];
  bool _loading = false;

  String get _monthStr =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadByCompany();
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _loadByCompany();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year &&
        _selectedMonth.month == now.month) {
      return;
    }
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _loadByCompany();
  }

  Future<void> _loadByCompany() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http
          .get(
            Uri.parse('$API_URL/reports/by-company?month=$_monthStr'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) { return; }
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _companies =
              List<Map<String, dynamic>>.from(data['companies'] ?? []);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) { setState(() => _loading = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;

    return Column(
      children: [
        Container(
          color: JsColors.gunmetal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: JsColors.gold),
                onPressed: _prevMonth,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_selectedMonth.year}年${_selectedMonth.month}月',
                    style: const TextStyle(
                        color: JsColors.gold,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: isCurrentMonth ? JsColors.divider : JsColors.gold,
                ),
                onPressed: isCurrentMonth ? null : _nextMonth,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: JsColors.gold))
              : _companies.isEmpty
                  ? const Center(
                      child: Text(
                        'この月の協力業者実績はありません',
                        style:
                            TextStyle(color: JsColors.silver, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _companies.length,
                      itemBuilder: (context, i) =>
                          _CoopCard(company: _companies[i]),
                    ),
        ),
      ],
    );
  }
}

class _CoopCard extends StatelessWidget {
  const _CoopCard({required this.company});
  final Map<String, dynamic> company;

  @override
  Widget build(BuildContext context) {
    final id = company['coop_company_id'] as String? ?? '';
    final isPerson = id.startsWith('person:');
    final name = company['company_name'] as String? ?? '不明';
    final reportCount =
        (company['report_count'] as num?)?.toInt() ?? 0;
    final workerCount =
        (company['worker_count'] as num?)?.toInt() ?? 0;
    final siteCount =
        (company['site_count'] as num?)?.toInt() ?? 0;
    final parkingFee =
        (company['parking_fee_total'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPerson
                    ? Icons.person_outline
                    : Icons.business_outlined,
                color: const Color(0xFF4FC3F7),
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isPerson)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4FC3F7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '個人',
                    style: TextStyle(
                        color: Color(0xFF4FC3F7), fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              JsStatChip('延べ人工', reportCount, JsColors.silver),
              const SizedBox(width: 4),
              JsStatChip('職人', workerCount,
                  const Color(0xFF4FC3F7)),
              const SizedBox(width: 4),
              JsStatChip('現場', siteCount, JsColors.gold),
              const SizedBox(width: 4),
              JsStatChip('¥駐車料金', parkingFee, JsColors.silver),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ① カレンダータブ
// ─────────────────────────────────────────────
class _CalendarTab extends StatefulWidget {
  const _CalendarTab();

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
  DateTime _selectedMonth = DateTime.now();
  List<Map<String, dynamic>> _monthReports = [];
  Set<String> _submittedDates = {};
  bool _monthLoading = false;
  String _myCompanyId = '';

  String get _monthStr =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _initCompanyId();
    _loadMonth();
  }

  Future<void> _initCompanyId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _myCompanyId = prefs.getString('company_id') ?? '');
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _loadMonth();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year &&
        _selectedMonth.month == now.month) {
      return;
    }
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() {
      _monthLoading = true;
      _monthReports = [];
      _submittedDates = {};
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http
          .get(
            Uri.parse('$API_URL/reports?date=$_monthStr&limit=300'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final raw = List<Map<String, dynamic>>.from(data['reports'] ?? []);
        final enriched = raw.map((r) {
          final approved = r['approved'] == true;
          final revision = r['revision_requested'] == true;
          return <String, dynamic>{
            ...r,
            'status': approved ? 'approved' : revision ? 'rejected' : 'pending',
          };
        }).toList();
        final dates = enriched
            .map((r) => r['report_date'] as String? ?? '')
            .where((d) => d.isNotEmpty)
            .toSet();
        setState(() {
          _monthReports = enriched;
          _submittedDates = dates;
          _monthLoading = false;
        });
      } else {
        setState(() => _monthLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _monthLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;

    return Column(
      children: [
        // ① 月ナビ
        Container(
          color: JsColors.gunmetal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: JsColors.gold),
                onPressed: _prevMonth,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_selectedMonth.year}年${_selectedMonth.month}月',
                    style: const TextStyle(
                        color: JsColors.offWhite,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth ? JsColors.silver : JsColors.gold),
                onPressed: isCurrentMonth ? null : _nextMonth,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.refresh,
                    color: JsColors.silver, size: 18),
                onPressed: _loadMonth,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        // ③ カレンダーグリッド
        _monthLoading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: CircularProgressIndicator(color: JsColors.gold)))
            : _buildCalendarGrid(),
        // ④ 日別詳細
        const Divider(height: 1, color: JsColors.divider),
        Expanded(
          child: _buildHint(),
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final now      = DateTime.now();
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay  =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final startOffset = firstDay.weekday - 1; // 月曜始まり
    final rowCount = ((startOffset + lastDay.day) / 7).ceil();

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Table(
        children: [
          // 曜日ヘッダー
          TableRow(
            children: weekdays.asMap().entries.map((e) {
              final color = e.key == 5
                  ? const Color(0xFF90CAF9)
                  : e.key == 6
                      ? const Color(0xFFEF9A9A)
                      : JsColors.silver;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Center(
                  child: Text(e.value,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              );
            }).toList(),
          ),
          // 日付行
          for (int row = 0; row < rowCount; row++)
            TableRow(
              children: List.generate(7, (col) {
                final cellIndex = row * 7 + col;
                final dayNum = cellIndex - startOffset + 1;
                if (dayNum < 1 || dayNum > lastDay.day) {
                  return const SizedBox(height: 48);
                }
                final date = DateTime(
                    _selectedMonth.year, _selectedMonth.month, dayNum);
                final ds =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                final isToday = date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;
                final dayReps = _monthReports
                    .where((r) => r['report_date'] == ds)
                    .toList();
                return _DayCell(
                  day: dayNum,
                  hasReport: _submittedDates.contains(ds),
                  isSelected: false,
                  isToday: isToday,
                  isSaturday: col == 5,
                  isSunday: col == 6,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DayReportsScreen(
                        date: date,
                        reports: dayReps,
                        myCompanyId: _myCompanyId,
                      ),
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildHint() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.touch_app_outlined, color: JsColors.silver, size: 32),
        SizedBox(height: 8),
        Text('日付をタップして日報を確認',
            style: TextStyle(color: JsColors.silver, fontSize: 13)),
      ],
    ),
  );

}

// ─────────────────────────────────────────────
// カレンダーのセル
// ─────────────────────────────────────────────
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.hasReport,
    required this.isSelected,
    required this.isToday,
    this.isSaturday = false,
    this.isSunday = false,
    required this.onTap,
  });
  final int day;
  final bool hasReport;
  final bool isSelected;
  final bool isToday;
  final bool isSaturday;
  final bool isSunday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color textColor = isSunday
        ? const Color(0xFFEF9A9A)
        : isSaturday
            ? const Color(0xFF90CAF9)
            : JsColors.offWhite;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: isSelected
              ? JsColors.gold.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: JsColors.gold, width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: (isToday || isSelected)
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            if (hasReport)
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                  color: JsColors.gold,
                  shape: BoxShape.circle,
                ),
              )
            else
              const SizedBox(height: 7),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ForemanManagementScreen — 後方互換用フルスクリーン
// ─────────────────────────────────────────────
class ForemanManagementScreen extends StatelessWidget {
  const ForemanManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(
        backgroundColor: JsColors.black,
        iconTheme: const IconThemeData(color: JsColors.gold),
        title: const Text('管理・集計',
            style: TextStyle(
                color: JsColors.gold,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
      body: const _ForemanManagementBody(),
    );
  }
}
