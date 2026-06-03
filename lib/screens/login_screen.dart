// ============================================================
// lib/screens/login_screen.dart - デバイス認証＋生体認証
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'consent_screen.dart';

const String _apiBase    = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';
const String _healthUrl  = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/health';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading    = true;
  bool _isRegistered = false;
  String? _errorMessage;
  final _companyCodeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _selectedRole = 'worker';
  bool _biometricFailed = false;

  // PIN設定ステップ（Sign Up後）
  int _step = 0; // 0=登録フォーム, 1=PIN設定
  Map<String, dynamic>? _pendingData;
  final _pinCtrl     = TextEditingController();
  final _pinConfCtrl = TextEditingController();
  bool _obscurePin  = true;
  bool _obscureConf = true;

  // PINログインフォールバック（生体認証NotAvailable時）
  bool _showPinLogin = false;
  final _loginPinCtrl = TextEditingController();
  bool _obscureLoginPin = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _companyCodeCtrl.dispose();
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfCtrl.dispose();
    _loginPinCtrl.dispose();
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
      final canCheck  = await auth.canCheckBiometrics;
      final supported = await auth.isDeviceSupported();
      if (!canCheck || !supported) {
        if (mounted) setState(() { _showPinLogin = true; _isLoading = false; });
        return false;
      }
      final result = await auth.authenticate(
        localizedReason: '本人確認を行ってください',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      return result;
    } catch (e) {
      if (mounted) setState(() { _showPinLogin = true; _isLoading = false; });
      return false;
    }
  }

  Future<void> _init() async {
    // ① Heroku コールドスタート対策 — 先に /health を叩いてdynoを起こす（60秒許容）
    http.get(Uri.parse(_healthUrl)).timeout(const Duration(seconds: 60)).ignore();

    final prefs = await SharedPreferences.getInstance();

    // ② 初回起動: 同意未完了なら ConsentScreen を表示して完了後に続行
    final consentAgreed = prefs.getBool('consent_agreed') ?? false;
    if (!consentAgreed && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConsentScreen(
          onAgreed: () {
            prefs.setBool('consent_agreed', true);
            prefs.setString('consent_version', '1.0');
            prefs.setString(
                'consent_agreed_at', DateTime.now().toIso8601String());
          },
        ),
      ));
      if (!mounted) return;
    }

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
        if (mounted) Navigator.of(context).pushReplacementNamed('/gate');
        return;
      }
    }

    // auth_token なし → デバイス登録チェック → 生体認証
    final hasDevice  = prefs.getString('device_id') != null;
    final registered = prefs.getBool('is_registered') ?? false;
    if (mounted) setState(() => _isRegistered = registered);
    if (hasDevice) {
      // ログアウト直後はPINログインへ直行（生体認証スキップ）
      final loggedOut = prefs.getBool('logged_out') ?? false;
      if (loggedOut) {
        await prefs.remove('logged_out');
        if (mounted) setState(() { _showPinLogin = true; _isLoading = false; });
        return;
      }
      await _biometricThenLogin();
    } else {
      // 未登録ユーザー: 自動リダイレクトせずログイン画面を表示し「新規登録」ボタンを案内
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _biometricThenLogin() async {
    setState(() { _isLoading = true; _biometricFailed = false; _showPinLogin = false; _errorMessage = null; });
    final ok = await _doBiometric();
    if (!ok) {
      // NotAvailable の場合は _doBiometric() 内で _showPinLogin = true が設定済み
      if (!_showPinLogin) {
        setState(() { _isLoading = false; _biometricFailed = true; _errorMessage = '認識に失敗しました。Retryしてください。'; });
      }
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
    } catch (_) {
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
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final deviceId = await _getDeviceId();
      // Herokuコールドスタート対策：最大3回リトライ（60秒タイムアウト）
      http.Response? response;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          response = await http.post(
            Uri.parse('$_apiBase/auth/register-device'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'company_code': companyCode, 'name': name, 'device_id': deviceId, 'role': _selectedRole}),
          ).timeout(const Duration(seconds: 60));
          break;
        } catch (_) {
          if (attempt == 2) rethrow;
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
        }
      }
      final data = jsonDecode(response!.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        // PIN設定ステップへ（仮PIN 000000のまま進まないよう）
        _pinCtrl.clear();
        _pinConfCtrl.clear();
        setState(() { _isLoading = false; _pendingData = data; _step = 1; _errorMessage = null; });
      } else {
        setState(() { _isLoading = false; _errorMessage = data['error'] ?? '登録に失敗しました'; });
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'ネットワークエラー: $e'; });
    }
  }

  Future<void> _setupPin() async {
    final pin  = _pinCtrl.text;
    final conf = _pinConfCtrl.text;
    if (pin.length < 4 || pin.length > 6) {
      setState(() => _errorMessage = 'PINは4〜6桁で入力してください');
      return;
    }
    if (pin != conf) {
      setState(() => _errorMessage = 'PINが一致しません');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final token = _pendingData!['token'] as String;
      final response = await http.post(
        Uri.parse('$_apiBase/auth/setup-pin'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'new_pin': pin}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF181810),
            title: const Row(children: [
              Icon(Icons.warning_amber, color: Color(0xFFA89868)),
              SizedBox(width: 8),
              Flexible(child: Text('PINコードを必ず記録してください',
                style: TextStyle(color: Colors.white, fontSize: 15))),
            ]),
            content: const Text(
              'PINコードを忘れた場合、\nログインできなくなります。\n\nメモ帳などに必ず控えてから\n次へ進んでください。',
              style: TextStyle(color: Color(0xFF484830), height: 1.7)),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _saveAndNavigate(_pendingData!);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA89868),
                  foregroundColor: const Color(0xFF181810)),
                child: const Text('記録しました。次へ進む',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      } else {
        final data = jsonDecode(response.body);
        setState(() { _isLoading = false; _errorMessage = data['error'] ?? 'PIN設定に失敗しました'; });
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'ネットワークエラー: $e'; });
    }
  }

  Future<void> _doLoginWithPin() async {
    final pin = _loginPinCtrl.text.trim();
    if (pin.length < 4) {
      setState(() => _errorMessage = 'PINを入力してください（4〜6桁）');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final deviceId = await _getDeviceId();
      final response = await http.post(
        Uri.parse('$_apiBase/auth/verify-pin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pin': pin,
          'device_id': deviceId,
          'device_name': Platform.isAndroid ? 'Android' : 'iPhone',
          'device_type': 'smartphone',
        }),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        await _saveAndNavigate(data);
      } else {
        setState(() { _isLoading = false; _errorMessage = data['error'] ?? 'PINが違います'; });
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'ネットワークエラー: $e'; });
    }
  }

  Future<void> _saveAndNavigate(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token',  data['token']      as String? ?? '');
    await prefs.setString('user_name',   data['name']       as String? ?? '');
    await prefs.setString('user_role',   data['role']       as String? ?? 'worker');
    await prefs.setString('company_id',  data['company_id'] as String? ?? '');
    await prefs.setString('work_mode',   data['work_mode']  as String? ?? 'deemed');
    await prefs.setString('user_id',     data['user_id']    as String? ?? '');
    await prefs.setString('consent_agreed_at',
        data['consent_agreed_at'] ?? DateTime.now().toIso8601String());
    await prefs.setString('consent_version', '1.0');
    String deviceId = prefs.getString('device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = await _getDeviceId();
      await prefs.setString('device_id', deviceId);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/gate');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF080806),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFA89868))),
      );
    }
    if (_step == 1) {
      return _buildPinSetupScreen();
    }
    if (_showPinLogin) {
      return _buildPinLoginScreen();
    }
    if (_biometricFailed) {
      return Scaffold(
        backgroundColor: const Color(0xFF080806),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint, color: Color(0xFFA89868), size: 80),
              const SizedBox(height: 24),
              const Text('Login', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorMessage ?? '', style: const TextStyle(color: Color(0xFF686040)), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _biometricThenLogin,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA89868), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
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
                    style: TextStyle(color: Color(0xFF484830), fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF080806),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('株式会社J\'s', style: TextStyle(color: Color(0xFFA89868), fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('勤務管理システム', style: TextStyle(color: Color(0xFFEDE8DC), fontSize: 16)),
              const SizedBox(height: 48),
              TextField(
                controller: _companyCodeCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: '会社コード',
                  labelStyle: const TextStyle(color: Color(0xFF686040)),
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF242418)), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFA89868)), borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: '氏名',
                  labelStyle: const TextStyle(color: Color(0xFF686040)),
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF242418)), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFA89868)), borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              const Align(alignment: Alignment.centerLeft, child: Text('役割', style: TextStyle(color: Color(0xFF686040), fontSize: 12))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRole = 'worker'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _selectedRole == 'worker' ? const Color(0xFFA89868) : Colors.transparent,
                          border: Border.all(color: _selectedRole == 'worker' ? const Color(0xFFA89868) : const Color(0xFF242418)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text('職人', style: TextStyle(color: _selectedRole == 'worker' ? Colors.black : const Color(0xFFEDE8DC), fontWeight: FontWeight.bold))),
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
                          color: _selectedRole == 'boss' ? const Color(0xFFA89868) : Colors.transparent,
                          border: Border.all(color: _selectedRole == 'boss' ? const Color(0xFFA89868) : const Color(0xFF242418)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text('職長', style: TextStyle(color: _selectedRole == 'boss' ? Colors.black : const Color(0xFFEDE8DC), fontWeight: FontWeight.bold))),
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA89868), foregroundColor: Colors.black),
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
                        color: Color(0xFFA89868)),
                    label: const Text(
                      '招待コードをお持ちの方はこちら',
                      style: TextStyle(
                          color: Color(0xFFA89868),
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFA89868)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinLoginScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF080806),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, color: Color(0xFFA89868), size: 64),
              const SizedBox(height: 24),
              const Text('PINでログイン',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('登録済みのPINを入力してください',
                  style: TextStyle(color: Color(0xFF686040), fontSize: 13)),
              const SizedBox(height: 40),
              TextField(
                controller: _loginPinCtrl,
                obscureText: _obscureLoginPin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '● ● ● ●',
                  hintStyle: const TextStyle(color: Color(0xFF242418), letterSpacing: 8),
                  filled: true,
                  fillColor: const Color(0xFF181810),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFA89868), width: 2)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureLoginPin ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF484830)),
                    onPressed: () => setState(() => _obscureLoginPin = !_obscureLoginPin),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _doLoginWithPin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA89868),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('ログイン', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinSetupScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF080806),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('株式会社J\'s', style: TextStyle(color: Color(0xFFA89868), fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('勤務管理システム', style: TextStyle(color: Color(0xFFEDE8DC), fontSize: 16)),
              const SizedBox(height: 40),
              const Text('PINを設定', style: TextStyle(color: Color(0xFFA89868), fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('ログイン時に使用するPIN（4〜6桁）を設定してください',
                  style: TextStyle(color: Color(0xFF484830), fontSize: 13)),
              const SizedBox(height: 28),
              TextField(
                controller: _pinCtrl,
                obscureText: _obscurePin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'PIN（4〜6桁）',
                  labelStyle: const TextStyle(color: Color(0xFF686040)),
                  prefixIcon: const Icon(Icons.lock, color: Color(0xFF686040)),
                  counterText: '',
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF242418)), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFA89868)), borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePin ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF686040)),
                    onPressed: () => setState(() => _obscurePin = !_obscurePin),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _pinConfCtrl,
                obscureText: _obscureConf,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'PIN確認',
                  labelStyle: const TextStyle(color: Color(0xFF686040)),
                  prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF686040)),
                  counterText: '',
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF242418)), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFA89868)), borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConf ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF686040)),
                    onPressed: () => setState(() => _obscureConf = !_obscureConf),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _setupPin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA89868),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('PINを設定してはじめる', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
