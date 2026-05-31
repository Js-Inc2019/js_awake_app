// lib/screens/welcome_screen.dart - AIウェルカム画面
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, API_URL;

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
  bool _loading = true;

  Map<String, dynamic>? _weather;
  String _claudeMessage = '';
  String _gpsAddress    = '';

  // shortcuts
  bool _hasPendingReport   = false;
  bool _notCheckedIn       = false;
  bool _hasUnreadRevision  = false;
  bool _hasPendingApproval = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('auth_token') ?? ''}',
      'Content-Type': 'application/json',
    };
  }

  Future<void> _init() async {
    await Future.wait([
      _loadWeatherAndMessage(),
      _loadShortcutStatus(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadWeatherAndMessage() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) { return; }
      if (!await Geolocator.isLocationServiceEnabled()) { return; }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );
      _gpsAddress = '${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}';

      final headers = await _headers;
      final wRes = await http.get(
        Uri.parse('$API_URL/weather?lat=${pos.latitude}&lon=${pos.longitude}'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (wRes.statusCode == 200) {
        _weather = jsonDecode(wRes.body) as Map<String, dynamic>;
        await _loadClaudeMessage(headers);
      }
    } catch (e) {
      debugPrint('weather load error: $e');
    }
  }

  Future<void> _loadClaudeMessage(Map<String, String> headers) async {
    if (_weather == null) return;
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final cachedDate = prefs.getString('welcome_msg_date') ?? '';
    final cachedMsg  = prefs.getString('welcome_msg_text') ?? '';

    if (cachedDate == today && cachedMsg.isNotEmpty) {
      _claudeMessage = cachedMsg;
      return;
    }

    try {
      final r = await http.post(
        Uri.parse('$API_URL/weather/welcome-message'),
        headers: headers,
        body: jsonEncode({
          'temp':        _weather!['temp'],
          'humidity':    _weather!['humidity'],
          'description': _weather!['description'],
          'wbgt':        _weather!['wbgt'],
          'wbgt_level':  _weather!['wbgt_level'],
          'user_name':   widget.userName,
        }),
      ).timeout(const Duration(seconds: 15));

      if (r.statusCode == 200) {
        final msg = (jsonDecode(r.body)['message'] as String?) ?? '';
        if (msg.isNotEmpty) {
          _claudeMessage = msg;
          await prefs.setString('welcome_msg_date', today);
          await prefs.setString('welcome_msg_text', msg);
        }
      }
    } catch (e) {
      debugPrint('claude message error: $e');
    }
  }

  Future<void> _loadShortcutStatus() async {
    try {
      final headers = await _headers;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // 日報未送信チェック
      final rptRes = await http.get(
        Uri.parse('$API_URL/workers/attendance/today?self=true'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (rptRes.statusCode == 200) {
        final body = jsonDecode(rptRes.body) as Map<String, dynamic>;
        _hasPendingReport = body['report_sent'] != true;
        _notCheckedIn     = body['checked_in'] != true;
      }

      // 是正依頼未読チェック
      final revRes = await http.get(
        Uri.parse('$API_URL/revisions/mine'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (revRes.statusCode == 200) {
        final body = jsonDecode(revRes.body) as Map<String, dynamic>;
        final revisions = (body['revisions'] as List? ?? []);
        _hasUnreadRevision = revisions.any((r) =>
            r['status'] == 'pending' || r['status'] == 'resubmitted');
      }

      // 未承認チェック（事務のみ）
      if (widget.userRole == 'admin' || widget.userRole == 'office') {
        final pendRes = await http.get(
          Uri.parse('$API_URL/reports?approved=false&date=$today'),
          headers: headers,
        ).timeout(const Duration(seconds: 8));
        if (pendRes.statusCode == 200) {
          final body = jsonDecode(pendRes.body) as Map<String, dynamic>;
          final count = (body['reports'] as List? ?? []).length;
          _hasPendingApproval = count > 0;
        }
      }
    } catch (e) {
      debugPrint('shortcut status error: $e');
    }
  }

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
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGreeting(),
                    const SizedBox(height: 20),
                    if (_weather != null) _buildWeatherCard(),
                    if (_claudeMessage.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildClaudeMessage(),
                    ],
                    const SizedBox(height: 24),
                    _buildShortcuts(),
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

  Widget _buildGreeting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_greeting,
            style: const TextStyle(
                color: JsColors.silver, fontSize: 14)),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(children: [
            TextSpan(
              text: '${widget.userName}さん',
              style: const TextStyle(
                  color: JsColors.gold,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
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
  }

  Widget _buildWeatherCard() {
    final temp = _weather!['temp'];
    final hum  = _weather!['humidity'];
    final desc = _weather!['description'] as String? ?? '';
    final wbgt      = _weather!['wbgt'];
    final wbgtLevel = _weather!['wbgt_level'] as String?;
    final wbgtEmoji = _weather!['wbgt_emoji'] as String?;
    final wbgtColor = _weather!['wbgt_color'] as String?;

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
      child: Column(
        children: [
          Row(children: const [
            Icon(Icons.wb_sunny_outlined, color: JsColors.gold, size: 20),
            SizedBox(width: 8),
            Text('現在の天気',
                style: TextStyle(
                    color: JsColors.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$wbgtEmoji ', style: const TextStyle(fontSize: 18)),
                Text('熱中症危険度: ',
                    style: const TextStyle(color: JsColors.silver, fontSize: 13)),
                Text('$wbgtLevel  (WBGT $wbgt℃)',
                    style: TextStyle(
                        color: wColor ?? JsColors.warning,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClaudeMessage() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JsColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JsColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, color: JsColors.gold, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_claudeMessage,
                style: const TextStyle(
                    color: JsColors.offWhite, fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcuts() {
    final shortcuts = <_Shortcut>[];

    if (_notCheckedIn) {
      shortcuts.add(_Shortcut(
        label: '出勤する',
        icon: Icons.login,
        color: JsColors.success,
        onTap: widget.onContinue,
      ));
    }
    if (_hasPendingReport && !_notCheckedIn) {
      shortcuts.add(_Shortcut(
        label: '日報を送る',
        icon: Icons.send,
        color: JsColors.gold,
        onTap: widget.onContinue,
      ));
    }
    if (_hasUnreadRevision) {
      shortcuts.add(_Shortcut(
        label: '是正依頼確認',
        icon: Icons.warning_amber,
        color: JsColors.warning,
        onTap: widget.onContinue,
      ));
    }
    if (_hasPendingApproval) {
      shortcuts.add(_Shortcut(
        label: '未承認確認',
        icon: Icons.pending_actions,
        color: JsColors.error,
        onTap: widget.onContinue,
      ));
    }

    if (shortcuts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ショートカット',
            style: TextStyle(
                color: JsColors.silver,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
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
                Text(s.label,
                    style: TextStyle(
                        color: s.color,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
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
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label, style: const TextStyle(color: JsColors.silver, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(
              color: JsColors.offWhite,
              fontWeight: FontWeight.bold,
              fontSize: 14)),
    ]);
  }
}

class _Shortcut {
  const _Shortcut({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}
