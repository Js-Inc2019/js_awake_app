// ============================================================
// lib/screens/login_screen.dart - デバイス認証＋生体認証
// ============================================================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

const String _apiBase    = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';
const String _healthUrl  = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/health';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading    = true;
  bool _isRegistered = false; // 登録済みフラグ（prefs: is_registered）
  String? _errorMessage;
  final _companyCodeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _selectedRole = 'worker';
  bool _biometricFailed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _companyCodeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');
    if (deviceId != null) return deviceId;
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await info.androidInfo;
      deviceId = androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await info.iosInfo;
      deviceId = iosInfo.identifierForVendor ?? 'ios-unknown';
    } else {
      deviceId = 'unknown-device';
    }
    await prefs.setString('device_id', deviceId);
    return deviceId;
  }

  Future<bool> _doBiometric() async {
    try {
      final auth = LocalAuthentication();
      final canCheck = await auth.canCheckBiometrics;
      if (!canCheck) return true;
      final result = await auth.authenticate(
        localizedReason: '本人確認を行ってください',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      return result;
    } catch (e) {
      debugPrint('生体認証エラー: $e');
      return true; // エラー時はスキップして続行
    }
  }

  Future<void> _init() async {
    // ① Heroku コールドスタート対策 — 先に /health を叩いてdynoを起こす（60秒許容）
    http.get(Uri.parse(_healthUrl)).timeout(const Duration(seconds: 60)).ignore();

    final prefs = await SharedPreferences.getInstance();

    // auth_token あり → POST /api/v1/auth/verify-token でサーバー検証
    final cachedToken = prefs.getString('auth_token') ?? '';
    if (cachedToken.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('$_apiBase/auth/verify-token'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $cachedToken',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          // 有効なトークン → /gate へ
          if (mounted) Navigator.of(context).pushReplacementNamed('/gate');
          return;
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          // トークン無効・期限切れ → 削除してログイン画面を表示
          await prefs.remove('auth_token');
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        // 5xx などサーバーエラー → オフライン扱いで通過
        if (mounted) Navigator.of(context).pushReplacementNamed('/gate');
        return;
      } catch (e) {
        // ネットワークエラー → キャッシュで /gate（オフライン対応維持）
        debugPrint('トークン検証エラー（オフライン）: $e');
        if (mounted) Navigator.of(context).pushReplacementNamed('/gate');
        return;
      }
    }

    // auth_token なし → デバイス登録チェック → 生体認証
    final hasDevice  = prefs.getString('device_id') != null;
    final registered = prefs.getBool('is_registered') ?? false;
    if (mounted) setState(() => _isRegistered = registered);
    if (hasDevice) {
      await _biometricThenLogin();
    } else {
      // 未登録ユーザー: 自動リダイレクトせずログイン画面を表示し「新規登録」ボタンを案内
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _biometricThenLogin() async {
    setState(() { _isLoading = true; _biometricFailed = false; _errorMessage = null; });
    final ok = await _doBiometric();
    if (!ok) {
      setState(() { _isLoading = false; _biometricFailed = true; _errorMessage = '認識に失敗しました。Retryしてください。'; });
      return;
    }
    await _autoLogin();
  }

  Future<void> _autoLogin() async {
    bool serverResponded = false;
    try {
      final deviceId = await _getDeviceId();
      final response = await http.get(
        Uri.parse('$_apiBase/auth/verify-device?device_id=$deviceId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      serverResponded = true;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveAndNavigate(data);
        return;
      }
      // サーバーが応答して非200を返した場合（トークン期限切れ・デバイス無効など）
      // → キャッシュを信頼せず登録フォームを表示
    } catch (e) {
      debugPrint('自動Loginエラー: $e');
      // ネットワーク到達不可（タイムアウト・例外）
    }
    if (!serverResponded) {
      // オフライン時のみキャッシュ済みトークンでゲートへ
      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString('auth_token') ?? '';
      if (cachedToken.isNotEmpty && mounted) {
        Navigator.of(context).pushReplacementNamed('/gate');
        return;
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _register() async {
    final companyCode = _companyCodeCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    if (companyCode.isEmpty || name.isEmpty) {
      setState(() => _errorMessage = '会社コードと氏名を入力してください');
      return;
    }
    final ok = await _doBiometric();
    if (!ok) {
      setState(() => _errorMessage = '認識に失敗しました');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final deviceId = await _getDeviceId();
      final response = await http.post(
        Uri.parse('$_apiBase/auth/register-device'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'company_code': companyCode, 'name': name, 'device_id': deviceId, 'role': _selectedRole}),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _saveAndNavigate(data);
      } else {
        setState(() { _isLoading = false; _errorMessage = data['error'] ?? '登録に失敗しました'; });
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'ネットワークエラー: $e'; });
    }
  }

  Future<void> _saveAndNavigate(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', data['token'] as String? ?? '');
    await prefs.setString('user_name', data['name'] as String? ?? '');
    await prefs.setString('user_role', data['role'] as String? ?? 'worker');
    await prefs.setString('company_id', data['company_id'] as String? ?? '');
    await prefs.setString('work_mode', data['work_mode'] as String? ?? 'deemed');
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/gate');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A1A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
      );
    }
    if (_biometricFailed) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint, color: Color(0xFFD4AF37), size: 80),
              const SizedBox(height: 24),
              const Text('Login', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorMessage ?? '', style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _biometricThenLogin,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('device_id');
                  nav.pushNamed('/register');
                },
                child: const Text('機種変更（新しいデバイスで再登録）',
                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('株式会社J\'s', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('勤務管理システム', style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 48),
              TextField(
                controller: _companyCodeCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: '会社コード',
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFD4AF37)), borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: '氏名',
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFD4AF37)), borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              const Align(alignment: Alignment.centerLeft, child: Text('役割', style: TextStyle(color: Colors.white54, fontSize: 12))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRole = 'worker'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _selectedRole == 'worker' ? const Color(0xFFD4AF37) : Colors.transparent,
                          border: Border.all(color: _selectedRole == 'worker' ? const Color(0xFFD4AF37) : Colors.white24),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text('職人', style: TextStyle(color: _selectedRole == 'worker' ? Colors.black : Colors.white70, fontWeight: FontWeight.bold))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRole = 'boss'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _selectedRole == 'boss' ? const Color(0xFFD4AF37) : Colors.transparent,
                          border: Border.all(color: _selectedRole == 'boss' ? const Color(0xFFD4AF37) : Colors.white24),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text('職長', style: TextStyle(color: _selectedRole == 'boss' ? Colors.black : Colors.white70, fontWeight: FontWeight.bold))),
                      ),
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _register,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Sign Up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                ),
              ),
              // 未登録ユーザー向け「新規登録はこちら」ボタン
              if (!_isRegistered) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pushNamed('/register')
                        .then((_) async {
                      // 登録完了後にフラグを再読み込みしてボタンを隠す
                      final prefs = await SharedPreferences.getInstance();
                      if (mounted) {
                        setState(() {
                          _isRegistered = prefs.getBool('is_registered') ?? false;
                        });
                      }
                    }),
                    icon: const Icon(Icons.person_add_alt_1,
                        color: Color(0xFFD4AF37)),
                    label: const Text(
                      '新規登録はこちら',
                      style: TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD4AF37)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/register'),
                  child: const Text(
                    '機種変更はこちら（管理者から招待コードを受け取った方）',
                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
