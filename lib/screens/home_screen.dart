// lib/screens/home_screen.dart
// JsMainShell — 全画面共通 2段AppBar + 永続BottomBar + IndexedStack

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';

import '../main.dart'
    show
        JsColors,
        TransportType,
        ReportStore,
        WorkerReportItem,
        SpeechManager,
        WorkerNameStore,
        fetchGpsAddress,
        showJsSnackbar,
        NotificationManager,
        OvertimeDialog,
        API_URL;
import 'revision_inbox_screen.dart';
import 'company_link_screen.dart';
import 'monthly_history_screen.dart' show MonthlyHistoryBody;
import 'profile_screen.dart';
import 'after_report_screen.dart';
import '../services/fcm_service.dart';
import '../services/routes_service.dart';
import '../services/profile_service.dart';

// ─────────────────────────────────────────────
// 今日の一言リスト（日付ベースローテーション）
// ─────────────────────────────────────────────
const _dailyMessages = [
  '今日も現場で輝こう。太陽には負けるけど。',
  '段取りは大事。弁当を忘れても段取りは忘れるな。',
  'ヘルメットは頭を守る。悩みは守れない。',
  '職人の朝は早い。でも鳥よりは遅い。',
  '安全帯を締めよう。気持ちも引き締めて。',
  '今日のミスは明日の笑い話になる予定。',
  '道具を大切に。特に昼飯後の道具は優しく。',
  '確認は何度でも。でもトイレの確認は一回でいい。',
  '体が資本。だから今日も飯をしっかり食え。',
  '雨の日は雨の仕事がある。傘を持ってきても使えないけど。',
  '職人の技は積み重ね。腰痛も積み重なる。',
  '仲間に声をかけよう。弁当の話でもいい。',
  '今日も全員で家に帰ろう。夕飯が待ってる。',
  '整理整頓は安全の基本。机の上は知らない。',
  '失敗しても大丈夫。同じ失敗じゃなければ。',
  '職人の仕事は街に残る。それってすごいこと。',
  '暑い日は無理せず休もう。涼しくなってから頑張る。',
  'ヒヤリハットは報告しよう。小さなことでいい。',
  '今日も誰かの暮らしを支えている。それが職人。',
  '寝不足は判断力を落とす。早く寝ろ昨日の自分。',
  '道具の手入れは自分の手入れと同じ大切さ。',
  '現場を去る時は来た時より少しだけ綺麗に。',
  '今日の丁寧が、10年後の信頼になる。',
  '朝礼は眠くても大事。特に安全の話は。',
  '職人に休日は必要。体も心もリセットしよう。',
  '危ないと思ったら止まれ。勇気ある一歩。',
  '技術は盗むもの。でも道具は盗むな。',
  'お疲れ様でした。また明日も頼むよ。',
  '今日も無事に終わった。それが一番の成果。',
  '仕事の後のご飯は格別。今日も頑張った証拠。',
];

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
  const _WeatherData({
    required this.icon,
    required this.desc,
    required this.tempC,
    required this.precipPct,
    this.humidity = 60,
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
    final temp = ((curJ['main'] as Map)['temp'] as num).toDouble();
    final rainPop = ((curJ['clouds'] as Map?)?['all'] as int? ?? 0).clamp(0, 100);
    final humidity = ((curJ['main'] as Map)['humidity'] as int?) ?? 60;

    final current = _WeatherData(
      icon: _owmIdToIcon(owmId),
      desc: desc,
      tempC: temp,
      precipPct: rainPop,
      humidity: humidity,
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
    final precip = int.tryParse(cur['precipMM'] as String? ?? '0') ?? 0;
    final humidity = int.tryParse(cur['humidity'] as String? ?? '60') ?? 60;
    final (icon, desc) = _mapDescStr(rawDesc);

    final current = _WeatherData(
      icon: icon,
      desc: desc,
      tempC: tempC,
      precipPct: precip.clamp(0, 100),
      humidity: humidity,
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
  int _linkCount     = 0;

  // ─── GPS ───
  String _gpsAddress = '';
  bool _gpsLoading = false;
  double? _lat;
  double? _lon;

  // ─── 天気 ───
  _WeatherData? _weather;
  List<_ForecastDay> _forecast = [];
  bool _weatherLoading = false;

  // ─── 季節・一言 ───
  String? _seasonWarning;
  String _dailyMessage = '';
  DateTime? _healthCheckDate;

  // ─── 移動手段 ───
  TransportType _transport = TransportType.none;
  Map<String, dynamic> _routeComparisons = {};
  bool _loadingRoutes = false;

  // ─── 作業内容 ───
  final _workCtrl    = TextEditingController();
  final _otherCtrl   = TextEditingController();
  final _parkingCtrl = TextEditingController();
  String? _workPhotoPath;
  String? _parkingPhotoPath;
  bool _isListening = false;
  final _speechMgr = SpeechManager();
  final _imagePicker = ImagePicker();

  // ─── 残業 ───
  bool _overtimeExpanded = false;
  int _overtimeHours = 0;
  int _overtimeMinutes = 0;

  // ─── 送信 ───
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSeasonAndDaily();
    _loadCacheAndStart();
    _restoreTabIndex();
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

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('today_transport', _transport.name);
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
    final transport = TransportType.values.firstWhere(
      (t) => t.name == transportName,
      orElse: () => TransportType.none,
    );
    if (!mounted) return;
    setState(() {
      _transport = transport;
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
    final key   = widget.isForeman ? 'last_tab_index_foreman' : 'last_tab_index_worker';
    final saved = prefs.getInt(key) ?? 0;
    if (mounted) setState(() => _tabIndex = saved);
  }

  // タブ切り替え＋保存
  void _setTab(int index) {
    setState(() => _tabIndex = index);
    SharedPreferences.getInstance().then((p) {
      final key = widget.isForeman ? 'last_tab_index_foreman' : 'last_tab_index_worker';
      p.setInt(key, index);
    });
  }

  @override
  void dispose() {
    _workCtrl.removeListener(_onWorkContentChanged);
    _workCtrl.dispose();
    _otherCtrl.dispose();
    _parkingCtrl.dispose();
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
            precipPct: wPrecip, humidity: wHumidity);
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
      _loadLinkCount(),
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
    final addr = await fetchGpsAddress();
    if (addr.isNotEmpty) prefs?.setString('gps_address', addr);
    if (mounted) {
      setState(() { _gpsAddress = addr; _gpsLoading = false; });
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
      });
    }
  }

  void _initSeasonAndDaily() {
    final now = DateTime.now();
    _seasonWarning = _getSeasonWarning(now);
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    _dailyMessage = _dailyMessages[dayOfYear % _dailyMessages.length];
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

  Future<void> _loadRevisionCount({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final token = p.getString('auth_token') ?? '';
      final res = await _withRetry(
        () => http.get(
          Uri.parse('$API_URL/revisions/unread-count'),
          headers: {'Authorization': 'Bearer $token'},
        ),
        firstTimeout: const Duration(seconds: 60),
      );
      if (res.statusCode == 200 && mounted) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final count = (j['count'] as int?) ?? 0;
        p.setInt('cache_revision_count', count);
        setState(() => _revisionCount = count);
      }
    } catch (e) {
      debugPrint('是正件数取得エラー: $e');
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
    final homeAddr =
        await ProfileService().getHomeAddress() ?? '兵庫県神戸市長田区';
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    if (mounted) setState(() => _loadingRoutes = true);
    Map<String, dynamic> routes = {};
    for (int attempt = 0; attempt < 3 && routes.isEmpty; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(seconds: attempt * 2));
      routes = await RoutesService().compareRoutesV2(
        origin: homeAddr,
        destination: _gpsAddress,
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

  Future<void> _takeWorkPhoto() async {
    final f = await _imagePicker.pickImage(
        source: ImageSource.camera, imageQuality: 80);
    if (f != null && mounted) {
      setState(() => _workPhotoPath = f.path);
      showJsSnackbar(context, '✅ 作業写真を撮影しました');
    }
  }

  Future<void> _takeParkingPhoto() async {
    final f = await _imagePicker.pickImage(
        source: ImageSource.camera, imageQuality: 80);
    if (f != null && mounted) {
      setState(() => _parkingPhotoPath = f.path);
      showJsSnackbar(context, '✅ 駐車場の写真を撮影しました');
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_userName.isEmpty) {
      showJsSnackbar(context, '氏名が取得できていません', isError: true);
      return;
    }
    if (_transport == TransportType.none) {
      showJsSnackbar(context, '移動手段を選択してください', isError: true);
      return;
    }
    setState(() => _submitting = true);
    if ((_transport == TransportType.car || _transport == TransportType.other) && _parkingPhotoPath == null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('写真が添付されていません'),
          content: const Text('駐車場の看板または領収書の写真が添付されていません。このまま送信しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('写真を撮る'),
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
        await _takeParkingPhoto();
        return;
      }
    }
    final name = _userName;
    final gpsAddr = _gpsAddress;
    try {
      final overtimeNote = (_overtimeHours > 0 || _overtimeMinutes > 0)
          ? ' 【残業$_overtimeHours時間$_overtimeMinutes分】'
          : '';
      await WorkerNameStore.instance.add(name);
      await ReportStore.instance.addReport(WorkerReportItem(
        name: name,
        transport: _transport,
        workContent: (_transport == TransportType.car && _parkingCtrl.text.trim().isNotEmpty
            ? '[駐車料金:${_parkingCtrl.text.trim()}円] '
            : '') +
            (_transport == TransportType.other && _otherCtrl.text.trim().isNotEmpty
            ? '[その他:${_otherCtrl.text.trim()}] '
            : '') + _workCtrl.text.trim() + overtimeNote,
        workPhotoPath: _workPhotoPath,
        parkingPhotoPath: _parkingPhotoPath,
        gpsAddress: gpsAddr,
      ));
      await ReportStore.instance.retryPending();
      _saveWorkStatus('done');
      _clearDraft();
      NotificationManager.instance.cancelOvertimeReminder();
      if (!mounted) return;
      showJsSnackbar(context, '✅ 報告を送信しました');
      setState(() {
        _transport = TransportType.none;
        _workCtrl.clear();
        _otherCtrl.clear();
        _parkingCtrl.clear();
        _workPhotoPath = null;
        _parkingPhotoPath = null;
        _overtimeExpanded = false;
        _overtimeHours = 0;
        _overtimeMinutes = 0;
      });
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => AfterReportScreen(
          workerName: name,
          onMoveToNextSite: () {
            Navigator.pop(context);
            _otherCtrl.clear();
            _parkingCtrl.clear();
            setState(() {
              _gpsAddress = '';
              _transport = TransportType.none;
              _routeComparisons = {};
              _workPhotoPath = null;
              _parkingPhotoPath = null;
            });
            _fetchGps();
          },
          onNightShift: () {
            Navigator.pop(context);
            if (mounted) showJsSnackbar(context, '🌙 夜勤モードで継続します');
          },
          onOvertime: () async {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => OvertimeDialog(
                workerName: name,
                gpsAddress: gpsAddr,
                onSubmit: (start, end, overtime) async {
                  await ReportStore.instance.addReport(WorkerReportItem(
                    name: name,
                    transport: TransportType.other,
                    workContent: '【残業】$start〜$end $overtime',
                    gpsAddress: gpsAddr,
                  ));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) showJsSnackbar(context, '✅ 残業報告を送信しました');
                },
              ),
            );
          },
        ),
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
    final role      = prefs.getString('user_role')   ?? prefs.getString('role') ?? '';
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
      _buildHomeTabContent(),
      const MonthlyHistoryBody(),
      if (widget.isForeman) const _ForemanManagementBody(),
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
          const Text(
            '日報報告',
            style: TextStyle(
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
        // ⚠️ 是正依頼ボタン（foreman/boss のみ）
        if (widget.isForeman)
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.warning_amber_rounded,
                    color: _revisionCount > 0 ? JsColors.error : JsColors.silver),
                tooltip: '是正依頼',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RevisionInboxScreen()),
                ).then((_) => _loadRevisionCount()),
              ),
              if (_revisionCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: JsColors.error, shape: BoxShape.circle),
                    child: Text('$_revisionCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
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
          icon: Icons.home_outlined,
          label: '日報',
          active: _tabIndex == 0,
          onTap: () => _setTab(0),
        ),
        divider,
        _BottomTabItem(
          icon: Icons.calendar_month,
          label: '月間履歴',
          active: _tabIndex == 1,
          onTap: () => _setTab(1),
        ),
        divider,
        if (widget.isForeman)
          _BottomTabItem(
            icon: Icons.bar_chart,
            label: '管理・集計',
            active: _tabIndex == 2,
            onTap: () => _setTab(2),
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
        divider,
        _BottomTabItem(
          icon: Icons.build,
          label: 'TOOL',
          active: false,
          onTap: _launchToolApp,
        ),
      ]),
    );
  }

  // ─── ホームタブ本体 ───
  Widget _buildHomeTabContent() {
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
                const SizedBox(height: 4),

                // ② 天気（左）+ 熱中症指数（右）
                _WeatherHeatRow(
                  weather: _weather,
                  loading: _weatherLoading,
                  seasonWarning: _seasonWarning,
                  onForecastTap: () => _showForecastSheet(context),
                ),

                // 健康診断警告
                if (_buildHealthBannerMsg() != null) ...[
                  const SizedBox(height: 4),
                  _HealthCheckBanner(message: _buildHealthBannerMsg()!),
                ],
                const SizedBox(height: 4),

                // ③ AIの一言メッセージ
                _DailyMessageRow(message: _dailyMessage),
                const SizedBox(height: 4),

                // ④ 移動手段 4択 → 金額 → ルート情報
                _TransportRow(
                  selected: _transport,
                  onChanged: (t) {
                    setState(() => _transport = t);
                    _saveWorkStatus('moving');
                    _saveDraft();
                  },
                ),
                if (_transport == TransportType.car) ...[
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
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _takeParkingPhoto,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: JsColors.gunmetal,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _parkingPhotoPath != null
                              ? JsColors.gold
                              : JsColors.gold.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _parkingPhotoPath != null ? Icons.check_circle : Icons.camera_alt,
                            color: _parkingPhotoPath != null ? JsColors.gold : JsColors.silver,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _parkingPhotoPath != null ? '📷 看板/領収書（撮影済）' : '📷 看板/領収書（任意）',
                              style: TextStyle(
                                color: _parkingPhotoPath != null ? JsColors.gold : JsColors.silver,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (_parkingPhotoPath != null)
                            GestureDetector(
                              onTap: () => setState(() => _parkingPhotoPath = null),
                              child: const Icon(Icons.close, color: JsColors.silver, size: 16),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_transport == TransportType.other) ...[
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
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _takeParkingPhoto,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: JsColors.gunmetal,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _parkingPhotoPath != null
                              ? JsColors.gold
                              : JsColors.gold.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _parkingPhotoPath != null ? Icons.check_circle : Icons.camera_alt,
                            color: _parkingPhotoPath != null ? JsColors.gold : JsColors.silver,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _parkingPhotoPath != null ? '📷 看板/領収書（撮影済）' : '📷 看板/領収書（任意）',
                              style: TextStyle(
                                color: _parkingPhotoPath != null ? JsColors.gold : JsColors.silver,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (_parkingPhotoPath != null)
                            GestureDetector(
                              onTap: () => setState(() => _parkingPhotoPath = null),
                              child: const Icon(Icons.close, color: JsColors.silver, size: 16),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                _RouteInfoBar(
                  transport: _transport,
                  comparisons: _routeComparisons,
                  loading: _loadingRoutes,
                ),
                const SizedBox(height: 4),

                // ⑤ 作業内容テキスト
                _WorkContentSection(
                  controller: _workCtrl,
                  photoPath: _workPhotoPath,
                  onClearPhoto: () => setState(() => _workPhotoPath = null),
                  showMediaButtons: true,
                  isListening: _isListening,
                  onMicTap: _startVoice,
                  onCameraTap: _takeWorkPhoto,
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
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.black))
                  : const Text('報告を送信する',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  void _showForecastSheet(BuildContext context) {
    if (_forecast.isEmpty) {
      showJsSnackbar(context, '週間予報データがありません');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: JsColors.gunmetal,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ForecastSheet(forecast: _forecast),
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
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;

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
              if (badge > 0)
                Positioned(
                  top: -4, right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: JsColors.error, shape: BoxShape.circle),
                    child: Text('$badge',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
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
// ② 天気（左）+ 熱中症指数（右）2列
// ─────────────────────────────────────────────
class _WeatherHeatRow extends StatelessWidget {
  const _WeatherHeatRow({
    required this.weather,
    required this.loading,
    required this.seasonWarning,
    required this.onForecastTap,
  });
  final _WeatherData? weather;
  final bool loading;
  final String? seasonWarning;
  final VoidCallback onForecastTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Row(
        children: [
          // 左: 天気（タップで週間予報）
          Expanded(
            flex: 54,
            child: GestureDetector(
              onTap: onForecastTap,
              child: Container(
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
                            child: Text('--',
                                style: TextStyle(
                                    color: JsColors.silver, fontSize: 12)))
                        : _WeatherContent(weather: weather!),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 右: 熱中症指数 + 危険度 + 季節注意
          Expanded(
            flex: 46,
            child: Container(
              decoration: BoxDecoration(
                color: JsColors.gunmetal,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: JsColors.divider),
              ),
              child: weather == null
                  ? const Center(
                      child: Text('--',
                          style: TextStyle(
                              color: JsColors.silver, fontSize: 12)))
                  : _HeatIndexContent(
                      weather: weather!, seasonWarning: seasonWarning),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({required this.weather});
  final _WeatherData weather;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(weather.icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weather.desc,
                  style: const TextStyle(
                      color: JsColors.silver, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${weather.tempC.round()}°C',
                  style: const TextStyle(
                      color: JsColors.offWhite,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                Row(children: [
                  const Text('💧', style: TextStyle(fontSize: 10)),
                  const SizedBox(width: 2),
                  Text('${weather.humidity}%',
                      style: const TextStyle(
                          color: JsColors.silver, fontSize: 11)),
                  const SizedBox(width: 6),
                  const Text('☂', style: TextStyle(fontSize: 10)),
                  const SizedBox(width: 2),
                  Text('${weather.precipPct}%',
                      style: TextStyle(
                          color: weather.precipPct >= 50
                              ? const Color(0xFF64B5F6)
                              : JsColors.silver,
                          fontSize: 11)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatIndexContent extends StatelessWidget {
  const _HeatIndexContent({
    required this.weather,
    required this.seasonWarning,
  });
  final _WeatherData weather;
  final String? seasonWarning;

  @override
  Widget build(BuildContext context) {
    final wbgt = _calcWBGT(weather.tempC, weather.humidity);
    final level = _wbgtLevel(wbgt);
    final color = _wbgtColor(wbgt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('⚠️', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            Text(
              '熱中症指数 ${wbgt.round()}',
              style: const TextStyle(
                  color: JsColors.offWhite,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 5),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.7)),
            ),
            child: Text(level,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          if (seasonWarning != null) ...[
            const SizedBox(height: 5),
            Text(
              seasonWarning!,
              style: const TextStyle(
                  color: Color(0xFFFFCC80), fontSize: 9, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 週間予報 BottomSheet
// ─────────────────────────────────────────────
class _ForecastSheet extends StatelessWidget {
  const _ForecastSheet({required this.forecast});
  final List<_ForecastDay> forecast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.wb_sunny_outlined,
                color: JsColors.gold, size: 18),
            const SizedBox(width: 8),
            const Text('週間天気予報',
                style: TextStyle(
                    color: JsColors.gold,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close,
                  color: JsColors.silver, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(color: JsColors.divider, height: 1),
          const SizedBox(height: 12),
          ...forecast.map((day) => _ForecastRow(day: day)),
        ],
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.day});
  final _ForecastDay day;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Text(day.weekday,
              style: const TextStyle(
                  color: JsColors.silver,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ),
        Text(day.icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Row(children: [
            Text('${day.maxC.round()}°',
                style: const TextStyle(
                    color: Color(0xFFEF9A9A),
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const Text(' / ',
                style: TextStyle(color: JsColors.silver, fontSize: 13)),
            Text('${day.minC.round()}°',
                style: const TextStyle(
                    color: Color(0xFF90CAF9),
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
        Row(children: [
          const Text('☂️', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 3),
          Text('${day.precipPct}%',
              style: TextStyle(
                  color: day.precipPct >= 50
                      ? const Color(0xFF64B5F6)
                      : JsColors.silver,
                  fontSize: 13,
                  fontWeight: day.precipPct >= 50
                      ? FontWeight.bold
                      : FontWeight.normal)),
        ]),
      ]),
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
// ③ AIの一言メッセージ
// ─────────────────────────────────────────────
class _DailyMessageRow extends StatelessWidget {
  const _DailyMessageRow({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: JsColors.gold.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: JsColors.gold.withValues(alpha: 0.25)),
    ),
    child: Row(children: [
      const Icon(Icons.auto_awesome, color: JsColors.gold, size: 14),
      const SizedBox(width: 6),
      Expanded(
        child: Text(message,
            style: const TextStyle(color: JsColors.offWhite, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────
// ④ 移動手段 4択横並び
// ─────────────────────────────────────────────
class _TransportRow extends StatelessWidget {
  const _TransportRow(
      {required this.selected, required this.onChanged});
  final TransportType selected;
  final ValueChanged<TransportType> onChanged;

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
          final sel = t == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(t),
              child: Container(
                margin: EdgeInsets.only(
                    right: t != _options.last ? 6 : 0),
                decoration: BoxDecoration(
                  color: sel ? JsColors.gold : JsColors.gunmetal,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: sel ? JsColors.gold : JsColors.divider),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(t.icon,
                        size: 18,
                        color: sel ? Colors.black : JsColors.silver),
                    const SizedBox(height: 3),
                    Text(t.label,
                        style: TextStyle(
                            color: sel ? Colors.black : JsColors.offWhite,
                            fontSize: 11,
                            fontWeight: sel
                                ? FontWeight.bold
                                : FontWeight.normal)),
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
    required this.photoPath,
    required this.onClearPhoto,
    this.showMediaButtons = false,
    this.isListening = false,
    this.onMicTap,
    this.onCameraTap,
  });
  final TextEditingController controller;
  final String? photoPath;
  final VoidCallback onClearPhoto;
  final bool showMediaButtons;
  final bool isListening;
  final VoidCallback? onMicTap;
  final VoidCallback? onCameraTap;

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
                  Row(children: [
                    _SmallMediaButton(
                      icon: isListening ? Icons.mic : Icons.mic_none,
                      active: isListening,
                      onTap: onMicTap,
                    ),
                    const SizedBox(width: 8),
                    _SmallMediaButton(
                      icon: photoPath != null ? Icons.check_circle : Icons.camera_alt,
                      active: photoPath != null,
                      onTap: onCameraTap,
                    ),
                  ]),
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

          // 写真プレビュー
          if (photoPath != null) ...[
            Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  child: Image.file(
                    File(photoPath!),
                    height: 72,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                GestureDetector(
                  onTap: onClearPhoto,
                  child: Container(
                    margin: const EdgeInsets.all(5),
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 13),
                  ),
                ),
              ],
            ),
          ] else
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

class _MediaButton extends StatelessWidget {
  const _MediaButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 40,
      decoration: BoxDecoration(
        color: active
            ? JsColors.gold.withValues(alpha: 0.18)
            : JsColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: active ? JsColors.gold : JsColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 16,
              color: active ? JsColors.gold : JsColors.silver),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: active ? JsColors.gold : JsColors.silver,
                  fontSize: 12,
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
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
// 職長管理・集計タブ本体（プレースホルダー）
// ─────────────────────────────────────────────
class _ForemanManagementBody extends StatelessWidget {
  const _ForemanManagementBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, color: JsColors.silver, size: 64),
          SizedBox(height: 16),
          Text('管理・集計画面は準備中',
              style: TextStyle(
                  color: JsColors.silver,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: 8),
          Text('部下の日報確認・承認・是正依頼',
              style: TextStyle(color: JsColors.divider, fontSize: 13)),
        ],
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
