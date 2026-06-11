// ============================================================
// lib/screens/login_screen.dart - 新設計ログイン画面
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'consent_screen.dart';
import 'pending_approval_screen.dart';
import '../config/constants.dart';
import '../services/fcm_service.dart';

const String _apiBase = kApiBaseUrl;

// ─── DAWNBREAKパレット（ログイン画面専用）─────────────────
const _bgColor     = Color(0xFF0A0E14);
const _goldColor   = Color(0xFFC9A84C);
const _navyColor   = Color(0xFF0D1B2A);
const _silverColor = Color(0xFF8A9BA8);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading    = true;
  String? _errorMessage;
  final _nameCtrl           = TextEditingController();
  final _companyCodeCtrl    = TextEditingController();
  final _partnerCompanyCtrl = TextEditingController();
  final _ownCompanyCtrl     = TextEditingController();

  bool _biometricFailed = false;

  // PIN設定ステップ（Sign Up後 — 旧フロー互換）
  final int _step = 0;
  Map<String, dynamic>? _pendingData;
  final _pinCtrl     = TextEditingController();
  final _pinConfCtrl = TextEditingController();
  bool _obscurePin  = true;
  bool _obscureConf = true;

  // PINログインフォールバック
  bool _showPinLogin = false;
  bool _isUpdateRecovery = false;
  final _loginPinCtrl = TextEditingController();
  bool _biometricErrorShown = false;
  bool _obscureLoginPin = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_biometricErrorShown) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['biometricFailed'] == true) {
        _biometricErrorShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text(
                '生体認証に失敗しました。PINコードでログインしてください。',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 20),
              duration: const Duration(seconds: 3),
            ));
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCodeCtrl.dispose();
    _partnerCompanyCtrl.dispose();
    _ownCompanyCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfCtrl.dispose();
    _loginPinCtrl.dispose();
    super.dispose();
  }

  Future<File> _getRegFlagFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/.js_reg');
  }

  Future<bool> _readPersistentRegistered() async {
    try {
      final f = await _getRegFlagFile();
      return f.existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> _writePersistentRegistered() async {
    try {
      final f = await _getRegFlagFile();
      await f.create(recursive: true);
    } catch (_) {}
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

  Future<void> _warmUpServer() async {
    for (int i = 0; i < 3; i++) {
      try {
        final res = await http.get(Uri.parse(kHealthUrl))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) return;
      } catch (_) {}
      if (i < 2) await Future.delayed(const Duration(seconds: 2));
    }
    debugPrint('サーバーウォームアップ失敗（処理続行）');
  }

  Future<void> _init() async {
    await _warmUpServer();

    final prefs = await SharedPreferences.getInstance();

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
          try {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final serverConsentAt = data['consent_agreed_at'];
            if (serverConsentAt != null) {
              await prefs.setString('consent_agreed_at', serverConsentAt.toString());
            }
            final serverConsentVersion = data['consent_version'];
            if (serverConsentVersion != null) {
              await prefs.setString('consent_version', serverConsentVersion.toString());
            }
            // 承認待ちステータス確認
            final status = data['status'] as String?;
            if (status == 'pending') {
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const PendingApprovalScreen()),
                );
              }
              return;
            }
          } catch (_) {}
          if (mounted) Navigator.of(context).pushReplacementNamed('/gate');
          return;
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          await prefs.remove('auth_token');
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        if (mounted) Navigator.of(context).pushReplacementNamed('/gate');
        return;
      } catch (e) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/gate');
        return;
      }
    }

    final hasDevice  = prefs.getString('device_id') != null;
    final registered = prefs.getBool('is_registered') ?? false;
    // _isRegistered は内部チェック用（UI未使用）
    if (hasDevice) {
      final loggedOut = prefs.getBool('logged_out') ?? false;
      if (loggedOut) {
        if (mounted) setState(() { _showPinLogin = true; _isLoading = false; });
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) await prefs.remove('logged_out');
        });
        return;
      }
      await _biometricThenLogin();
    } else if (registered) {
      if (!mounted) return;
      setState(() { _isUpdateRecovery = true; _showPinLogin = true; _isLoading = false; });
    } else {
      final persistentReg = await _readPersistentRegistered();
      if (!mounted) return;
      if (persistentReg) {
        await prefs.setBool('is_registered', true);
        setState(() { _isUpdateRecovery = true; _showPinLogin = true; _isLoading = false; });
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _biometricThenLogin() async {
    setState(() { _isLoading = true; _biometricFailed = false; _showPinLogin = false; _errorMessage = null; });
    final ok = await _doBiometric();
    if (!ok) {
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
    } catch (_) {}
    if (!serverResponded) {
      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString('auth_token') ?? '';
      if (cachedToken.isNotEmpty && mounted) {
        Navigator.of(context).pushReplacementNamed('/gate');
        return;
      }
    }
    if (mounted) setState(() => _isLoading = false);
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

  // ─── 自己登録（仮登録申請）────────────────────────────────
  Future<void> _selfRegister() async {
    final ownCompany     = _ownCompanyCtrl.text.trim();
    final name           = _nameCtrl.text.trim();
    final partnerCompany = _partnerCompanyCtrl.text.trim();
    final companyCode    = _companyCodeCtrl.text.trim().toUpperCase();

    if (ownCompany.isEmpty) {
      setState(() => _errorMessage = '自社の会社名を入力してください');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = '氏名を入力してください');
      return;
    }
    setState(() => _errorMessage = null);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _navyColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '仮登録として申請します',
          style: TextStyle(color: _goldColor, fontSize: 16),
        ),
        content: const Text(
          '職長・事務スタッフに通知されます\n承認後にフル機能が使えます\nよろしいですか？',
          style: TextStyle(color: Colors.white, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: _silverColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _goldColor,
              foregroundColor: Colors.black,
            ),
            child: const Text('確認'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final deviceId   = await _getDeviceId();
      final deviceName = Platform.isAndroid ? 'Android' : 'iPhone';
      final res = await http.post(
        Uri.parse('$_apiBase/workers/self-register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name':                 name,
          'own_company_name':     ownCompany,
          'partner_company_name': partnerCompany.isNotEmpty ? partnerCompany : null,
          'company_code':         companyCode.isNotEmpty ? companyCode : null,
          'device_id':            deviceId,
          'device_name':          deviceName,
        }),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 || res.statusCode == 201) {
        final token = body['token'] as String?;
        if (token != null && token.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
          await prefs.setString('user_name',  name);
          await prefs.setString('user_role',  'worker');
          await prefs.setString('device_id',  deviceId);
          await prefs.setBool('is_registered', true);
          await _writePersistentRegistered();
        }
        if (!mounted) return;
        // already_registered: true でも PendingApprovalScreen へ（ゲートUIはフェーズ2）
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PendingApprovalScreen()),
        );
      } else {
        final errMsg = body['error'] as String? ?? '登録に失敗しました';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errMsg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('通信エラー: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAndNavigate(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token',  data['token']      as String? ?? '');
    await prefs.setString('user_name',   data['name']       as String? ?? '');
    await prefs.setString('user_role',   data['role']       as String? ?? 'worker');
    await prefs.setString('company_id',  data['company_id'] as String? ?? '');
    await prefs.setString('company_name', data['company_name'] as String? ?? '');
    await prefs.setString('work_mode',   data['work_mode']  as String? ?? 'deemed');
    await prefs.setString('user_id',     data['user_id']    as String? ?? '');
    await prefs.setString('consent_agreed_at',
        data['consent_agreed_at'] ?? DateTime.now().toIso8601String());
    await prefs.setString('consent_version', '1.0');
    await prefs.setBool('is_registered', true);
    String deviceId = prefs.getString('device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = await _getDeviceId();
      await prefs.setString('device_id', deviceId);
    }
    await _writePersistentRegistered();
    FcmService().registerToken(); // fire-and-forget（権限要求はホーム画面で順番化）
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/gate');
  }

  // ─── build ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _goldColor)),
      );
    }
    if (_step == 1) return _buildPinSetupScreen();
    if (_showPinLogin) return _buildPinLoginScreen();
    if (_biometricFailed) {
      return Scaffold(
        backgroundColor: const Color(0xFF080806),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint, color: Color(0xFFA89868), size: 80),
              const SizedBox(height: 24),
              const Text('Login',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorMessage ?? '',
                  style: const TextStyle(color: Color(0xFF686040)),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _biometricThenLogin,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA89868),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
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

    // ─── 新設計ランディングページ ─────────────────────────────
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── ヘッダー ─────────────────────────────────
              const Text(
                '株式会社J\'s',
                style: TextStyle(
                  color: _goldColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                '勤務管理システム',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // ── ログイン ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _biometricThenLogin,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _goldColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: _silverColor),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('生体認証',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _showPinLogin = true;
                        _errorMessage = null;
                      }),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _goldColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: _silverColor),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('PIN入力',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // ── 新規登録 セクション ──────────────────────
              const Row(children: [
                Expanded(child: Divider(color: _silverColor)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text('新規登録',
                      style: TextStyle(color: _silverColor, fontSize: 13)),
                ),
                Expanded(child: Divider(color: _silverColor)),
              ]),
              const SizedBox(height: 24),

              // 会社コード（任意）
              _regField(
                controller: _companyCodeCtrl,
                label: '会社コード（わかる方のみ）',
              ),
              const SizedBox(height: 14),

              // 協力先の業者名（任意）
              _regField(
                controller: _partnerCompanyCtrl,
                label: '協力先の業者名（自社で働く方は未記入でOK）',
                showMic: true,
              ),
              const SizedBox(height: 14),

              // 自社の会社名（必須）
              _regField(
                controller: _ownCompanyCtrl,
                label: '自社の会社名',
                showMic: true,
              ),
              const SizedBox(height: 14),

              // 氏名（必須）
              _regField(
                controller: _nameCtrl,
                label: '氏名',
                showMic: true,
              ),
              const SizedBox(height: 24),

              // サインアップボタン
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _selfRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _goldColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('サインアップ',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.red),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_errorMessage!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── ランディングページ ボタンウィジェット ──────────────────
  Widget _loginButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: _goldColor),
        label: Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: _navyColor,
          side: const BorderSide(color: _silverColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _regField({
    required TextEditingController controller,
    required String label,
    bool showMic = false,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _silverColor, fontSize: 13),
        prefixIcon: const Icon(Icons.edit_note, color: _silverColor),
        suffixIcon: showMic
            ? const Icon(Icons.mic_none, color: _silverColor)
            : null,
        filled: true,
        fillColor: _navyColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _silverColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _silverColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _goldColor, width: 2),
        ),
      ),
    );
  }

  // ─── PIN ログイン画面 ─────────────────────────────────────
  Widget _buildPinLoginScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF080806),
      appBar: _isUpdateRecovery
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF080806),
              foregroundColor: const Color(0xFFA89868),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _showPinLogin = false;
                  _errorMessage = null;
                  _loginPinCtrl.clear();
                }),
              ),
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, color: Color(0xFFA89868), size: 64),
              const SizedBox(height: 24),
              const Text('PINでログイン',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_isUpdateRecovery) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1810),
                    border:
                        Border.all(color: const Color(0xFFA89868), width: 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'アプリのアップデートのため、\nPINコードでの再認証が必要です',
                    style: TextStyle(
                        color: Color(0xFFA89868), fontSize: 13, height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                const Text('登録済みのPINを入力してください',
                    style: TextStyle(
                        color: Color(0xFF686040), fontSize: 13)),
                const SizedBox(height: 40),
              ],
              TextField(
                controller: _loginPinCtrl,
                obscureText: _obscureLoginPin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(
                    color: Colors.white, fontSize: 24, letterSpacing: 8),
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '● ● ● ●',
                  hintStyle: const TextStyle(
                      color: Color(0xFF242418), letterSpacing: 8),
                  filled: true,
                  fillColor: const Color(0xFF181810),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFFA89868), width: 2)),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureLoginPin
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: const Color(0xFF484830)),
                    onPressed: () =>
                        setState(() => _obscureLoginPin = !_obscureLoginPin),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('ログイン',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── PIN 設定画面（旧フロー互換）────────────────────────────
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
              const Text('株式会社J\'s',
                  style: TextStyle(
                      color: Color(0xFFA89868),
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('勤務管理システム',
                  style: TextStyle(color: Color(0xFFEDE8DC), fontSize: 16)),
              const SizedBox(height: 40),
              const Text('PINを設定',
                  style: TextStyle(
                      color: Color(0xFFA89868),
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
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
                  prefixIcon:
                      const Icon(Icons.lock, color: Color(0xFF686040)),
                  counterText: '',
                  enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF242418)),
                      borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFA89868)),
                      borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscurePin
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: const Color(0xFF686040)),
                    onPressed: () =>
                        setState(() => _obscurePin = !_obscurePin),
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
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: Color(0xFF686040)),
                  counterText: '',
                  enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF242418)),
                      borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFA89868)),
                      borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureConf
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: const Color(0xFF686040)),
                    onPressed: () =>
                        setState(() => _obscureConf = !_obscureConf),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!,
                    style: const TextStyle(color: Colors.redAccent)),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('PINを設定してはじめる',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
