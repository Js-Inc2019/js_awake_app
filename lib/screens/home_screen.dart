// lib/screens/home_screen.dart
// ホーム画面 — スクロールなし1画面レイアウト

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        API_URL;
import 'revision_inbox_screen.dart';
import 'monthly_history_screen.dart';
import 'profile_screen.dart';

// ─────────────────────────────────────────────
// 今日の一言リスト（日付ベースローテーション）
// ─────────────────────────────────────────────
const _dailyMessages = [
  '今日も安全第一で！現場での一歩一歩が信頼をつくる。',
  '丁寧な仕事が、お客様の笑顔につながる。',
  '確認・確認・確認。それがプロの証。',
  'チームワークこそが最高の工具。',
  '今日の作業が未来の自分の誇りになる。',
  'ヒヤリハットをゼロに。気づいたら必ず報告を。',
  '技術は磨くもの。今日も一つ学んで帰ろう。',
  '整理・整頓・清潔・清掃・躾。5Sを忘れずに。',
  '報告・連絡・相談。現場のコミュニケーションが命を守る。',
  '一仕事一仕事を誠実に。それが株式会社J\'sのDNA。',
  '安全帽を正しく着用。頭を守るのは自分自身。',
  '焦りは事故の元。落ち着いて、確実に。',
  '今日の天気はどうであれ、仕事の品質は曇りなし。',
  '工具の点検は作業前に。備えあれば憂いなし。',
  '電気工事のプロとして、今日も誇りを持って。',
  '困ったときは一人で抱え込まない。仲間に声をかけよう。',
  'KY活動で危険を先読み。ゼロ災害を目指して。',
  '現場を綺麗に保つことが次の作業の効率を上げる。',
  '今日の頑張りが、現場の評判を高める。',
  '作業終了後の確認が、帰路の安心につながる。',
  '挨拶から始まるコミュニケーション。今日も元気よく。',
  '失敗を恐れず、しかし安全は妥協せず。',
  '一灯の電気が、誰かの家庭を照らしている。',
  '今日も無事故で。それが最高の成果。',
  'プロの誇りを胸に、今日の現場も全力で。',
  '配線一本一本に、職人の魂を込める。',
  '仲間の安全を守ることが、自分の安全にもつながる。',
  '今日も良い仕事をして、気持ちよく帰ろう。',
  '難しい作業ほど、チームの力が輝く。',
  '電気のプロが現場を支える。今日も頼りにされる仕事を。',
];

// ─────────────────────────────────────────────
// 季節注意喚起メッセージ（6〜9月）
// ─────────────────────────────────────────────
String? _getSeasonWarning(DateTime now) {
  final m = now.month;
  if (m == 6) return '☀️ 梅雨・暑熱始まり — こまめな水分補給を忘れずに';
  if (m == 7) return '🌡️ 猛暑注意 — 熱中症指数が高い日は無理せず休憩を';
  if (m == 8) return '🔥 熱中症最警戒 — 30分に1回は水分・塩分補給を';
  if (m == 9) return '🌤️ 残暑注意 — まだ暑さが続きます。油断せず対策を';
  return null;
}

// ─────────────────────────────────────────────
// OpenWeatherMap API キー
// ─────────────────────────────────────────────
// TODO: OWM_API_KEY を実際のキーに置き換える
const String _owmApiKey = '***REMOVED***';

// ─────────────────────────────────────────────
// 天気データモデル
// ─────────────────────────────────────────────
class _WeatherData {
  final String icon;
  final String desc;
  final double tempC;
  final int precipPct; // 降水確率 %
  const _WeatherData({
    required this.icon,
    required this.desc,
    required this.tempC,
    required this.precipPct,
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
// 天気取得（OWM → wttr.in フォールバック）
// ─────────────────────────────────────────────
Future<(_WeatherData?, List<_ForecastDay>)> _fetchWeatherFull({
  double? lat,
  double? lon,
}) async {
  if (_owmApiKey != 'YOUR_OPENWEATHERMAP_API_KEY' && lat != null && lon != null) {
    return _fetchOwm(lat, lon);
  }
  return _fetchWttr();
}

Future<(_WeatherData?, List<_ForecastDay>)> _fetchOwm(double lat, double lon) async {
  try {
    // 現在天気
    final curRes = await http.get(Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather'
      '?lat=$lat&lon=$lon&appid=$_owmApiKey&units=metric&lang=ja',
    )).timeout(const Duration(seconds: 8));

    // 5日/3時間予報
    final fcRes = await http.get(Uri.parse(
      'https://api.openweathermap.org/data/2.5/forecast'
      '?lat=$lat&lon=$lon&appid=$_owmApiKey&units=metric&lang=ja&cnt=40',
    )).timeout(const Duration(seconds: 8));

    if (curRes.statusCode != 200) return (null, <_ForecastDay>[]);

    final curJ = jsonDecode(curRes.body) as Map<String, dynamic>;
    final weatherArr = curJ['weather'] as List;
    final owmId = (weatherArr.first as Map<String, dynamic>)['id'] as int? ?? 800;
    final desc = (weatherArr.first as Map<String, dynamic>)['description'] as String? ?? '';
    final temp = ((curJ['main'] as Map)['temp'] as num).toDouble();
    final rainPop = ((curJ['clouds'] as Map?)?['all'] as int? ?? 0).clamp(0, 100);

    final current = _WeatherData(
      icon: _owmIdToIcon(owmId),
      desc: desc,
      tempC: temp,
      precipPct: rainPop,
    );

    // 予報集計
    final forecast = <_ForecastDay>[];
    if (fcRes.statusCode == 200) {
      final fcJ = jsonDecode(fcRes.body) as Map<String, dynamic>;
      final items = (fcJ['list'] as List).cast<Map<String, dynamic>>();
      final Map<String, List<Map<String, dynamic>>> byDay = {};
      for (final item in items) {
        final dt = DateTime.fromMillisecondsSinceEpoch((item['dt'] as int) * 1000, isUtc: true)
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
        final maxC = dayItems.map((e) => ((e['main'] as Map)['temp_max'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
        final minC = dayItems.map((e) => ((e['main'] as Map)['temp_min'] as num).toDouble()).reduce((a, b) => a < b ? a : b);
        final maxPop = dayItems.map((e) => ((e['pop'] as num?)?.toDouble() ?? 0.0)).reduce((a, b) => a > b ? a : b);
        final repId = ((dayItems[dayItems.length ~/ 2]['weather'] as List).first as Map)['id'] as int? ?? 800;
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
        ((cur['weatherDesc'] as List?)?.first as Map<String, dynamic>?)?['value'] as String? ?? '';
    final precip = int.tryParse(cur['precipMM'] as String? ?? '0') ?? 0;
    final (icon, desc) = _mapDescStr(rawDesc);

    final current = _WeatherData(icon: icon, desc: desc, tempC: tempC, precipPct: precip.clamp(0, 100));

    // wttr.in 3日予報
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
      final maxPrecip = hourly.map((h) => int.tryParse(h['chanceofrain'] as String? ?? '0') ?? 0).fold(0, (a, b) => a > b ? a : b);
      final rawD = ((day['weatherDesc'] as List?)?.first as Map<String, dynamic>?)?['value'] as String? ?? '';
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
// HomeScreen
// ─────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // ユーザー情報
  String _companyName = '株式会社J\'s';
  String _userName = '';

  // GPS
  String _gpsAddress = '';
  bool _gpsLoading = false;
  double? _lat;
  double? _lon;

  // 天気
  _WeatherData? _weather;
  List<_ForecastDay> _forecast = [];
  bool _weatherLoading = false;

  // 季節・一言
  String? _seasonWarning;
  String _dailyMessage = '';

  // 移動手段
  TransportType _transport = TransportType.car;

  // 作業内容
  final _workCtrl = TextEditingController();
  String? _workPhotoPath;
  bool _workExpanded = false;
  bool _isListening = false;
  final _speechMgr = SpeechManager();
  final _imagePicker = ImagePicker();

  // 残業
  bool _overtimeExpanded = false;
  int _overtimeHours = 0;
  int _overtimeMinutes = 0;

  // 送信
  bool _submitting = false;
  int _revisionCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speechMgr.initialize();
    _loadUserData();
    _fetchGps(); // GPS取得完了後に天気も自動更新
    _initSeasonAndDaily();
    _loadRevisionCount();
    _refreshPendingCount();
  }

  @override
  void dispose() {
    _workCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _fetchGps();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? '';
        _companyName = prefs.getString('company_name') ?? '株式会社J\'s';
      });
    }
  }

  Future<void> _fetchGps() async {
    setState(() => _gpsLoading = true);
    // GPS座標も取得する
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
      }
    } catch (_) {}
    final addr = await fetchGpsAddress();
    if (mounted) {
      setState(() { _gpsAddress = addr; _gpsLoading = false; });
      _loadWeather(); // GPS取得後に天気を更新
    }
  }

  Future<void> _loadWeather() async {
    setState(() => _weatherLoading = true);
    final (data, forecast) = await _fetchWeatherFull(lat: _lat, lon: _lon);
    if (mounted) {
      setState(() {
        _weather = data;
        _forecast = forecast;
        _weatherLoading = false;
      });
    }
  }

  void _initSeasonAndDaily() {
    final now = DateTime.now();
    _seasonWarning = _getSeasonWarning(now);
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    _dailyMessage = _dailyMessages[dayOfYear % _dailyMessages.length];
  }

  Future<void> _loadRevisionCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http.get(
        Uri.parse('$API_URL/revisions/unread-count'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() => _revisionCount = (j['count'] as int?) ?? 0);
      }
    } catch (_) {}
  }

  Future<void> _refreshPendingCount() async {
    await ReportStore.instance.retryPending();
  }

  Future<void> _startVoice() async {
    setState(() => _isListening = true);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VoiceInputDialog(
        manager: _speechMgr,
        onConfirm: (text) {
          Navigator.pop(ctx);
          setState(() {
            _workCtrl.text = _workCtrl.text.isEmpty ? text : '${_workCtrl.text}。$text';
            _workExpanded = true;
          });
        },
        onCancel: () { _speechMgr.cancel(); Navigator.pop(ctx); },
      ),
    );
    setState(() => _isListening = false);
  }

  Future<void> _takeWorkPhoto() async {
    final f = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (f != null && mounted) {
      setState(() { _workPhotoPath = f.path; _workExpanded = true; });
      showJsSnackbar(context, '✅ 作業写真を撮影しました');
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_userName.isEmpty) {
      showJsSnackbar(context, '氏名が取得できていません', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final overtimeNote = (_overtimeHours > 0 || _overtimeMinutes > 0)
          ? ' 【残業$_overtimeHours時間$_overtimeMinutes分】'
          : '';
      await WorkerNameStore.instance.add(_userName);
      await ReportStore.instance.addReport(WorkerReportItem(
        name: _userName,
        transport: _transport,
        workContent: _workCtrl.text.trim() + overtimeNote,
        workPhotoPath: _workPhotoPath,
        gpsAddress: _gpsAddress,
      ));
      await _refreshPendingCount();
      NotificationManager.instance.cancelOvertimeReminder();
      if (!mounted) return;
      showJsSnackbar(context, '✅ 報告を送信しました');
      setState(() {
        _transport = TransportType.car;
        _workCtrl.clear();
        _workPhotoPath = null;
        _workExpanded = false;
        _overtimeExpanded = false;
        _overtimeHours = 0;
        _overtimeMinutes = 0;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ─── AppBar日付フォーマット ───
  String get _dateLabel {
    final n = DateTime.now();
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final w = weekdays[n.weekday - 1];
    return '${n.month}/${n.day}（$w）';
  }

  // ─────────────────────── BUILD ───────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              const SizedBox(height: 8),
              // ① 会社名 / 氏名
              _CompanyNameRow(company: _companyName, name: _userName),
              const SizedBox(height: 8),
              // ② 天気 / GPS
              _WeatherGpsRow(
                weather: _weather,
                forecast: _forecast,
                weatherLoading: _weatherLoading,
                gpsAddress: _gpsAddress,
                gpsLoading: _gpsLoading,
                onRefreshGps: _fetchGps,
              ),
              // ③ 季節注意（6〜9月のみ）
              if (_seasonWarning != null) ...[
                const SizedBox(height: 6),
                _SeasonBanner(message: _seasonWarning!),
              ],
              const SizedBox(height: 6),
              // ④ 今日の一言
              _DailyMessageRow(message: _dailyMessage),
              const SizedBox(height: 8),
              // ⑤ 移動手段4択
              _TransportRow(
                selected: _transport,
                onChanged: (t) => setState(() => _transport = t),
              ),
              const SizedBox(height: 8),
              // ⑥ 作業内容 + 残業 — Expanded
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 作業内容 flex:2
                    Flexible(
                      flex: 2,
                      child: _WorkContentCard(
                        controller: _workCtrl,
                        photoPath: _workPhotoPath,
                        expanded: _workExpanded,
                        isListening: _isListening,
                        onToggle: () => setState(() => _workExpanded = !_workExpanded),
                        onVoice: _startVoice,
                        onCamera: _takeWorkPhoto,
                        onClearPhoto: () => setState(() => _workPhotoPath = null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 残業 flex:1
                    Flexible(
                      flex: 1,
                      child: _OvertimeCard(
                        hours: _overtimeHours,
                        minutes: _overtimeMinutes,
                        expanded: _overtimeExpanded,
                        onToggle: () => setState(() => _overtimeExpanded = !_overtimeExpanded),
                        onChanged: (h, m) => setState(() {
                          _overtimeHours = h;
                          _overtimeMinutes = m;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ⑦ 報告ボタン
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                      : const Text('報告を送信する',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ─── AppBar ───
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: JsColors.black,
      title: Row(
        children: [
          const Text('日報報告',
              style: TextStyle(
                  color: JsColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Text(_dateLabel,
              style: const TextStyle(color: JsColors.silver, fontSize: 13)),
        ],
      ),
      actions: [
        // 是正依頼アイコン（未読あれば赤）
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.warning_amber,
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
        IconButton(
          icon: const Icon(Icons.settings, color: JsColors.silver),
          tooltip: '設定',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ).then((_) => _loadUserData()),
        ),
      ],
    );
  }

  // ─── BottomAppBar ───
  Widget _buildBottomBar() {
    return BottomAppBar(
      color: JsColors.gunmetal,
      height: 60,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          // 月間報告
          Expanded(
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MonthlyHistoryScreen()),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_month, color: JsColors.gold, size: 22),
                  SizedBox(height: 2),
                  Text('月間報告',
                      style: TextStyle(color: JsColors.gold, fontSize: 11)),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 36, color: JsColors.divider),
          // TOOL
          Expanded(
            child: InkWell(
              onTap: () => showJsSnackbar(context, 'TOOLは近日公開予定です'),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.build, color: JsColors.silver, size: 22),
                  SizedBox(height: 2),
                  Text('TOOL',
                      style: TextStyle(color: JsColors.silver, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ① 会社名 / 氏名
// ─────────────────────────────────────────────
class _CompanyNameRow extends StatelessWidget {
  const _CompanyNameRow({required this.company, required this.name});
  final String company;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _InfoChip(icon: Icons.business, label: '会社', value: company)),
        const SizedBox(width: 8),
        Expanded(child: _InfoChip(icon: Icons.person, label: '氏名', value: name.isEmpty ? '読込中...' : name)),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: JsColors.gunmetal,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: JsColors.divider),
    ),
    child: Row(
      children: [
        Icon(icon, color: JsColors.silver, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(color: JsColors.silver, fontSize: 10)),
              Text(value,
                  style: const TextStyle(
                      color: JsColors.offWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────
// ② 天気 / GPS
// ─────────────────────────────────────────────
class _WeatherGpsRow extends StatelessWidget {
  const _WeatherGpsRow({
    required this.weather,
    required this.forecast,
    required this.weatherLoading,
    required this.gpsAddress,
    required this.gpsLoading,
    required this.onRefreshGps,
  });
  final _WeatherData? weather;
  final List<_ForecastDay> forecast;
  final bool weatherLoading;
  final String gpsAddress;
  final bool gpsLoading;
  final VoidCallback onRefreshGps;

  void _showForecast(BuildContext context) {
    if (forecast.isEmpty) {
      showJsSnackbar(context, '週間予報データがありません');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: JsColors.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ForecastSheet(forecast: forecast),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          // 天気ボックス（タップで週間予報）
          GestureDetector(
            onTap: () => _showForecast(context),
            child: Container(
              width: 130,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: JsColors.gunmetal,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: JsColors.divider),
              ),
              child: weatherLoading
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
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // 天気アイコン＋名称
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(weather!.icon,
                                    style: const TextStyle(fontSize: 16)),
                                Text(weather!.desc,
                                    style: const TextStyle(
                                        color: JsColors.silver, fontSize: 9),
                                    maxLines: 1),
                              ],
                            ),
                            // 気温
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('🌡️',
                                    style: TextStyle(fontSize: 11)),
                                Text('${weather!.tempC.round()}°',
                                    style: const TextStyle(
                                        color: JsColors.offWhite,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            // 降水確率
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('☂️',
                                    style: TextStyle(fontSize: 11)),
                                Text('${weather!.precipPct}%',
                                    style: TextStyle(
                                        color: weather!.precipPct >= 50
                                            ? const Color(0xFF64B5F6)
                                            : JsColors.silver,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
            ),
          ),
          const SizedBox(width: 8),
          // GPS
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: JsColors.gunmetal,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: JsColors.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: JsColors.gold, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: gpsLoading
                        ? const Text('GPS取得中...',
                            style: TextStyle(
                                color: JsColors.silver, fontSize: 12))
                        : Text(
                            gpsAddress.isEmpty ? '現場住所 未取得' : gpsAddress,
                            style: const TextStyle(
                                color: JsColors.offWhite, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  IconButton(
                    onPressed: onRefreshGps,
                    icon: const Icon(Icons.refresh,
                        color: JsColors.silver, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
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
            const Icon(Icons.wb_sunny_outlined, color: JsColors.gold, size: 18),
            const SizedBox(width: 8),
            const Text('週間天気予報',
                style: TextStyle(
                    color: JsColors.gold,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: JsColors.silver, size: 20),
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
      child: Row(
        children: [
          // 曜日
          SizedBox(
            width: 28,
            child: Text(day.weekday,
                style: const TextStyle(
                    color: JsColors.silver,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          // 天気アイコン
          Text(day.icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          // 最高/最低気温
          Expanded(
            child: Row(
              children: [
                Text('${day.maxC.round()}°',
                    style: const TextStyle(
                        color: Color(0xFFEF9A9A),
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const Text(' / ',
                    style:
                        TextStyle(color: JsColors.silver, fontSize: 13)),
                Text('${day.minC.round()}°',
                    style: const TextStyle(
                        color: Color(0xFF90CAF9),
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // 降水確率
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ③ 季節注意喚起バナー
// ─────────────────────────────────────────────
class _SeasonBanner extends StatelessWidget {
  const _SeasonBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFE65100).withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.5)),
    ),
    child: Text(
      message,
      style: const TextStyle(
          color: Color(0xFFFFCC80), fontSize: 12, fontWeight: FontWeight.w500),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

// ─────────────────────────────────────────────
// ④ 今日の一言
// ─────────────────────────────────────────────
class _DailyMessageRow extends StatelessWidget {
  const _DailyMessageRow({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: JsColors.gold.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: JsColors.gold.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome, color: JsColors.gold, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(message,
              style: const TextStyle(color: JsColors.offWhite, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────
// ⑤ 移動手段4択
// ─────────────────────────────────────────────
class _TransportRow extends StatelessWidget {
  const _TransportRow({required this.selected, required this.onChanged});
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
                margin: EdgeInsets.only(right: t != _options.last ? 6 : 0),
                decoration: BoxDecoration(
                  color: sel ? JsColors.gold : JsColors.gunmetal,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? JsColors.gold : JsColors.divider),
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
                            fontWeight:
                                sel ? FontWeight.bold : FontWeight.normal)),
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
// ⑥-L 作業内容カード
// ─────────────────────────────────────────────
class _WorkContentCard extends StatelessWidget {
  const _WorkContentCard({
    required this.controller,
    required this.photoPath,
    required this.expanded,
    required this.isListening,
    required this.onToggle,
    required this.onVoice,
    required this.onCamera,
    required this.onClearPhoto,
  });
  final TextEditingController controller;
  final String? photoPath;
  final bool expanded;
  final bool isListening;
  final VoidCallback onToggle;
  final VoidCallback onVoice;
  final VoidCallback onCamera;
  final VoidCallback onClearPhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: expanded ? JsColors.gold.withValues(alpha: 0.5) : JsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー（タップで展開）
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.construction, color: JsColors.gold, size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('作業内容',
                        style: TextStyle(
                            color: JsColors.offWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ),
                  Icon(
                    expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: JsColors.silver, size: 18),
                ],
              ),
            ),
          ),
          // サマリー表示（折り畳み時）
          if (!expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                controller.text.isEmpty ? '未入力（タップして展開）' : controller.text,
                style: TextStyle(
                    color: controller.text.isEmpty
                        ? JsColors.silver
                        : JsColors.offWhite,
                    fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          // 展開コンテンツ
          if (expanded) ...[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  children: [
                    const Divider(height: 1, color: JsColors.divider),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        maxLines: null,
                        expands: true,
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
                    // 写真プレビュー
                    if (photoPath != null) ...[
                      const SizedBox(height: 6),
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(File(photoPath!),
                                height: 70,
                                width: double.infinity,
                                fit: BoxFit.cover),
                          ),
                          GestureDetector(
                            onTap: onClearPhoto,
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // ボタン行
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _SmallBtn(
                          icon: isListening ? Icons.mic : Icons.mic_none,
                          active: isListening,
                          onTap: onVoice,
                        ),
                        const SizedBox(width: 8),
                        _SmallBtn(
                          icon: photoPath != null
                              ? Icons.check_circle
                              : Icons.camera_alt,
                          active: photoPath != null,
                          onTap: onCamera,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ⑥-R 残業カード
// ─────────────────────────────────────────────
class _OvertimeCard extends StatelessWidget {
  const _OvertimeCard({
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
    return Container(
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (hours > 0 || minutes > 0)
              ? JsColors.warning.withValues(alpha: 0.6)
              : expanded
                  ? JsColors.gold.withValues(alpha: 0.5)
                  : JsColors.divider,
        ),
      ),
      child: Column(
        children: [
          // ヘッダー
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: JsColors.gold, size: 16),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text('残業',
                        style: TextStyle(
                            color: JsColors.offWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ),
                  Icon(
                    expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: JsColors.silver, size: 18),
                ],
              ),
            ),
          ),
          // 折り畳み表示
          if (!expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                _label,
                style: TextStyle(
                    color: (hours > 0 || minutes > 0)
                        ? JsColors.warning
                        : JsColors.silver,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
          // 展開: ドラムロールピッカー
          if (expanded) ...[
            const Divider(height: 1, color: JsColors.divider),
            Expanded(
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
    _mCtrl = FixedExtentScrollController(initialItem: widget.minutes ~/ 5);
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 時間ホイール (0〜12)
        Expanded(
          child: Column(
            children: [
              const SizedBox(height: 4),
              const Text('時間',
                  style: TextStyle(color: JsColors.silver, fontSize: 10)),
              Expanded(
                child: CupertinoPicker(
                  scrollController: _hCtrl,
                  itemExtent: 36,
                  backgroundColor: Colors.transparent,
                  selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                    background: JsColors.gold.withValues(alpha: 0.12),
                  ),
                  onSelectedItemChanged: (i) =>
                      widget.onChanged(i, widget.minutes),
                  children: List.generate(
                    13,
                    (i) => Center(
                      child: Text('$i',
                          style: const TextStyle(
                              color: JsColors.offWhite, fontSize: 20)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 区切り
        const Text(':',
            style: TextStyle(
                color: JsColors.silver,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        // 分ホイール (0, 5, 10, ...55)
        Expanded(
          child: Column(
            children: [
              const SizedBox(height: 4),
              const Text('分',
                  style: TextStyle(color: JsColors.silver, fontSize: 10)),
              Expanded(
                child: CupertinoPicker(
                  scrollController: _mCtrl,
                  itemExtent: 36,
                  backgroundColor: Colors.transparent,
                  selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                    background: JsColors.gold.withValues(alpha: 0.12),
                  ),
                  onSelectedItemChanged: (i) =>
                      widget.onChanged(widget.hours, i * 5),
                  children: List.generate(
                    12,
                    (i) => Center(
                      child: Text((i * 5).toString().padLeft(2, '0'),
                          style: const TextStyle(
                              color: JsColors.offWhite, fontSize: 20)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 小ボタン（音声・カメラ）
// ─────────────────────────────────────────────
class _SmallBtn extends StatelessWidget {
  const _SmallBtn({required this.icon, required this.active, required this.onTap});
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: active
            ? JsColors.gold.withValues(alpha: 0.2)
            : JsColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: active ? JsColors.gold : JsColors.divider),
      ),
      child: Icon(icon,
          size: 18, color: active ? JsColors.gold : JsColors.silver),
    ),
  );
}

// ─────────────────────────────────────────────
// 音声入力ダイアログ
// ─────────────────────────────────────────────
class _VoiceInputDialog extends StatefulWidget {
  const _VoiceInputDialog(
      {required this.manager, required this.onConfirm, required this.onCancel});
  final SpeechManager manager;
  final void Function(String) onConfirm;
  final VoidCallback onCancel;

  @override
  State<_VoiceInputDialog> createState() => _VoiceInputDialogState();
}

class _VoiceInputDialogState extends State<_VoiceInputDialog>
    with SingleTickerProviderStateMixin {
  String _text = '';
  bool _listening = false;
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
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _listening = true; _text = ''; });
    await widget.manager.startListening(
      onResult: (t, _) { if (mounted) setState(() => _text = t); },
    );
    if (mounted) setState(() => _listening = false);
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
                  ? JsColors.gold.withValues(alpha: 0.15 + _pulse.value * 0.15)
                  : JsColors.surface,
            ),
            child: Icon(_listening ? Icons.mic : Icons.mic_off,
                color: _listening ? JsColors.gold : JsColors.silver, size: 32),
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
            _text.isEmpty ? '例：1階電気配線工事 コンセント10箇所設置' : _text,
            style: TextStyle(
                color: _text.isEmpty ? JsColors.silver : JsColors.offWhite,
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
            onPressed: () async {
              await widget.manager.stop();
              setState(() => _listening = false);
            },
            child:
                const Text('停止', style: TextStyle(color: JsColors.gold))),
      if (!_listening && _text.isNotEmpty)
        ElevatedButton(
            onPressed: () => widget.onConfirm(_text),
            child: const Text('確定')),
    ],
  );
}
