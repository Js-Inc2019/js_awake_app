// lib/screens/welcome_screen.dart - AIウェルカム画面（高速化版）
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors;
import '../services/api_cache.dart';
import '../services/http_client.dart';

class WelcomeScreen extends StatefulWidget {
  final String userName;
  final String userRole;
  final VoidCallback onContinue;

  const WelcomeScreen({
    super.key,
    required this.userName,
    required this.userRole,
    required this.onContinue,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // コンテンツの準備状態（個別に管理→部分表示で即座に表示）
  bool _shortcutsLoaded = false;
  bool _weatherLoaded   = false;

  Map<String, dynamic>? _weather;
  String _claudeMessage = '';
  String _gpsAddress    = '';

  bool _hasPendingReport   = false;
  bool _notCheckedIn       = false;
  bool _hasUnreadRevision  = false;
  bool _hasPendingApproval = false;

  @override
  void initState() {
    super.initState();
    // 並列で全データ取得開始（互いに待たない）
    _loadShortcutStatus();
    _loadWeatherAndMessage();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // ─── ショートカット状態 ───────────────────────────────────
  // 3 API を完全並列化 + 30秒キャッシュ

  Future<void> _loadShortcutStatus() async {
    try {
      final token  = await _getToken() ?? '';
      final today  = DateTime.now().toIso8601String().substring(0, 10);
      final client = AppHttpClient.instance;

      // キャッシュチェック
      final cachedAtt = ApiCache.instance.get<Map<String, dynamic>>('attendance:$today');
      final cachedRev = ApiCache.instance.get<List<dynamic>>('revisions:mine');

      // キャッシュがある部分は即座に反映
      if (cachedAtt != null) {
        _hasPendingReport = cachedAtt['report_sent'] != true;
        _notCheckedIn     = cachedAtt['checked_in']  != true;
      }
      if (cachedRev != null) {
        _hasUnreadRevision = cachedRev.any((r) =>
            r['status'] == 'pending' || r['status'] == 'resubmitted');
      }
      if (cachedAtt != null || cachedRev != null) {
        if (mounted) setState(() => _shortcutsLoaded = true);
      }

      // 未キャッシュ分だけ並列取得
      final futures = <Future>[];
      if (cachedAtt == null) {
        futures.add(client.authGet(
          '/workers/attendance/today?self=true',
          token: token,
          timeout: const Duration(seconds: 8),
        ));
      }
      if (cachedRev == null) {
        futures.add(client.authGet(
          '/revisions/mine',
          token: token,
          timeout: const Duration(seconds: 8),
        ));
      }
      if (futures.isEmpty) return;

      final results = await Future.wait(futures, eagerError: false);
      int idx = 0;

      if (cachedAtt == null && idx < results.length) {
        final res = results[idx++] as dynamic;
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          ApiCache.instance.set('attendance:$today', body, const Duration(seconds: 30));
          _hasPendingReport = body['report_sent'] != true;
          _notCheckedIn     = body['checked_in']  != true;
        }
      }
      if (cachedRev == null && idx < results.length) {
        final res = results[idx] as dynamic;
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final revs = (body['revisions'] as List? ?? []);
          ApiCache.instance.set('revisions:mine', revs, const Duration(seconds: 30));
          _hasUnreadRevision = revs.any((r) =>
              r['status'] == 'pending' || r['status'] == 'resubmitted');
        }
      }

      if (mounted) setState(() => _shortcutsLoaded = true);
    } catch (e) {
      debugPrint('shortcut status error: $e');
      if (mounted) setState(() => _shortcutsLoaded = true);
    }
  }

  // ─── 天気 + Claude メッセージ ────────────────────────────
  // 天気は1時間キャッシュ、Claude は1日キャッシュ

  Future<void> _loadWeatherAndMessage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // Claude メッセージはキャッシュから即座に表示
      final cachedMsg  = prefs.getString('welcome_msg_text') ?? '';
      final cachedDate = prefs.getString('welcome_msg_date') ?? '';
      if (cachedDate == today && cachedMsg.isNotEmpty) {
        if (mounted) setState(() => _claudeMessage = cachedMsg);
      }

      // 天気キャッシュ確認
      final cachedWeather = ApiCache.instance.get<Map<String, dynamic>>('weather');
      if (cachedWeather != null) {
        if (mounted) setState(() {
          _weather = cachedWeather;
          _weatherLoaded = true;
        });
        // キャッシュがあっても Claude message が未ロードなら取得
        if (cachedDate != today || cachedMsg.isEmpty) {
          _loadClaudeMessage(prefs, token, cachedWeather, today);
        }
        return;
      }

      // GPS + 天気 取得
      String? lat, lon;
      try {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever &&
            await Geolocator.isLocationServiceEnabled()) {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 8),
          );
          lat = pos.latitude.toString();
          lon = pos.longitude.toString();
          if (mounted) setState(() {
            _gpsAddress = '${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}';
          });
        }
      } catch (_) {}

      if (lat == null) { if (mounted) setState(() => _weatherLoaded = true); return; }

      final wRes = await AppHttpClient.instance.authGet(
        '/weather?lat=$lat&lon=$lon',
        token: token,
        timeout: const Duration(seconds: 8),
      );
      if (wRes.statusCode == 200) {
        final weather = jsonDecode(wRes.body) as Map<String, dynamic>;
        ApiCache.instance.set('weather', weather, const Duration(hours: 1));
        if (mounted) setState(() { _weather = weather; _weatherLoaded = true; });
        _loadClaudeMessage(prefs, token, weather, today);
      } else {
        if (mounted) setState(() => _weatherLoaded = true);
      }
    } catch (e) {
      debugPrint('weather load error: $e');
      if (mounted) setState(() => _weatherLoaded = true);
    }
  }

  Future<void> _loadClaudeMessage(
    SharedPreferences prefs, String token,
    Map<String, dynamic> weather, String today,
  ) async {
    final cached = prefs.getString('welcome_msg_text') ?? '';
    final cachedDate = prefs.getString('welcome_msg_date') ?? '';
    if (cachedDate == today && cached.isNotEmpty) return;
    try {
      final r = await AppHttpClient.instance.authPost(
        '/weather/welcome-message',
        token: token,
        body: jsonEncode({
          'temp':        weather['temp'],
          'humidity':    weather['humidity'],
          'description': weather['description'],
          'wbgt':        weather['wbgt'],
          'wbgt_level':  weather['wbgt_level'],
          'user_name':   widget.userName,
        }),
        timeout: const Duration(seconds: 12),
      );
      if (r.statusCode == 200) {
        final msg = (jsonDecode(r.body)['message'] as String?) ?? '';
        if (msg.isNotEmpty) {
          await prefs.setString('welcome_msg_date', today);
          await prefs.setString('welcome_msg_text', msg);
          if (mounted) setState(() => _claudeMessage = msg);
        }
      }
    } catch (e) { debugPrint('claude message error: $e'); }
  }

  // ─── Build ───────────────────────────────────────────────

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 10) return 'おはようございます';
    if (h < 17) return 'こんにちは';
    return 'お疲れ様です';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("J's Awake"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreeting(),
              const SizedBox(height: 20),

              // 天気カード（ロード済みなら表示、ローディング中はスケルトン）
              if (_weather != null) _buildWeatherCard()
              else if (!_weatherLoaded) _buildWeatherSkeleton(),

              if (_claudeMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildClaudeMessage(),
              ],
              const SizedBox(height: 24),

              // ショートカット（ロード済みなら表示、ローディング中はスケルトン）
              if (_shortcutsLoaded) _buildShortcuts()
              else _buildShortcutSkeleton(),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: widget.onContinue,
                  child: const Text('はじめる'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_greeting, style: const TextStyle(color: JsColors.silver, fontSize: 14)),
      const SizedBox(height: 4),
      RichText(
        text: TextSpan(children: [
          TextSpan(
            text: '${widget.userName}さん',
            style: const TextStyle(
                color: JsColors.gold, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const TextSpan(
            text: '　ご用件は何でしょう？',
            style: TextStyle(color: JsColors.offWhite, fontSize: 16),
          ),
        ]),
      ),
      if (_gpsAddress.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.location_on, size: 13, color: JsColors.silver),
          const SizedBox(width: 4),
          Text(_gpsAddress,
              style: const TextStyle(color: JsColors.silver, fontSize: 12)),
        ]),
      ],
    ],
  );

  Widget _buildWeatherCard() {
    final temp       = _weather!['temp'];
    final hum        = _weather!['humidity'];
    final desc       = _weather!['description'] as String? ?? '';
    final wbgt       = _weather!['wbgt'];
    final wbgtLevel  = _weather!['wbgt_level']  as String?;
    final wbgtEmoji  = _weather!['wbgt_emoji']  as String?;
    final wbgtColor  = _weather!['wbgt_color']  as String?;

    Color? wColor;
    if (wbgtColor != null) {
      final hex = wbgtColor.replaceFirst('#', 'FF');
      wColor = Color(int.parse(hex, radix: 16));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.divider),
      ),
      child: Column(children: [
        const Row(children: [
          Icon(Icons.wb_sunny_outlined, color: JsColors.gold, size: 20),
          SizedBox(width: 8),
          Text('現在の天気', style: TextStyle(
              color: JsColors.gold, fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _WeatherStat(label: '気温', value: '${temp?.toStringAsFixed(1) ?? '--'}°C'),
            _WeatherStat(label: '湿度', value: '${hum ?? '--'}%'),
            _WeatherStat(label: '天気', value: desc),
          ],
        ),
        if (wbgt != null && wbgtLevel != null) ...[
          const Divider(color: JsColors.divider, height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$wbgtEmoji ', style: const TextStyle(fontSize: 18)),
            const Text('熱中症危険度: ',
                style: TextStyle(color: JsColors.silver, fontSize: 13)),
            Text('$wbgtLevel  (WBGT $wbgt℃)',
                style: TextStyle(
                    color: wColor ?? JsColors.warning,
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
        ],
      ]),
    );
  }

  Widget _buildWeatherSkeleton() => Container(
    height: 80,
    decoration: BoxDecoration(
      color: JsColors.gunmetal,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: JsColors.divider),
    ),
    child: const Center(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: JsColors.gold)),
        SizedBox(width: 10),
        Text('天気を取得中...', style: TextStyle(color: JsColors.silver, fontSize: 13)),
      ]),
    ),
  );

  Widget _buildClaudeMessage() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: JsColors.gold.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: JsColors.gold.withValues(alpha: 0.4)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.auto_awesome, color: JsColors.gold, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Text(_claudeMessage,
            style: const TextStyle(color: JsColors.offWhite, fontSize: 13, height: 1.5)),
      ),
    ]),
  );

  Widget _buildShortcutSkeleton() => Container(
    height: 48,
    decoration: BoxDecoration(
      color: JsColors.gunmetal.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Center(
      child: SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: JsColors.silver)),
    ),
  );

  Widget _buildShortcuts() {
    final shortcuts = <_Shortcut>[];
    if (_notCheckedIn) shortcuts.add(_Shortcut('出勤する', Icons.login, JsColors.success, widget.onContinue));
    if (_hasPendingReport && !_notCheckedIn) shortcuts.add(_Shortcut('日報を送る', Icons.send, JsColors.gold, widget.onContinue));
    if (_hasUnreadRevision) shortcuts.add(_Shortcut('是正依頼確認', Icons.warning_amber, JsColors.warning, widget.onContinue));
    if (_hasPendingApproval) shortcuts.add(_Shortcut('未承認確認', Icons.pending_actions, JsColors.error, widget.onContinue));
    if (shortcuts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ショートカット',
            style: TextStyle(color: JsColors.silver, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: shortcuts.map((s) => GestureDetector(
            onTap: s.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: s.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: s.color.withValues(alpha: 0.6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(s.icon, color: s.color, size: 16),
                const SizedBox(width: 6),
                Text(s.label, style: TextStyle(
                    color: s.color, fontSize: 13, fontWeight: FontWeight.bold)),
              ]),
            ),
          )).toList(),
        ),
      ],
    );
  }
}

class _WeatherStat extends StatelessWidget {
  const _WeatherStat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(color: JsColors.silver, fontSize: 11)),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(
        color: JsColors.offWhite, fontWeight: FontWeight.bold, fontSize: 14)),
  ]);
}

class _Shortcut {
  const _Shortcut(this.label, this.icon, this.color, this.onTap);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}
