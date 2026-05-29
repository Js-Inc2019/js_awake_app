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

const String _apiBase = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  bool _biometricFailed = false;

  @override
  void initState() {
    super.initState();
    _init();
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
      return true;
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');
    if (deviceId != null) {
      await _biometricThenLogin();
    } else {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/onboarding');
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
    try {
      final deviceId = await _getDeviceId();
      final response = await http.get(
        Uri.parse('$_apiBase/auth/verify-device?device_id=$deviceId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _saveAndNavigate(data);
        return;
      }
    } catch (e) {
      debugPrint('自動Loginエラー: $e');
    }
    // デバイス未登録・トークン無効 → device_id をクリアして初回フローへ
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_id');
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/onboarding');
  }

  Future<void> _saveAndNavigate(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', data['token'] as String? ?? '');
    await prefs.setString('user_name',  data['name']       as String? ?? '');
    await prefs.setString('user_role',  data['role']       as String? ?? 'worker');
    await prefs.setString('company_id', data['company_id'] as String? ?? '');
    await prefs.setString('work_mode',  data['work_mode']  as String? ?? 'deemed');
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
                onPressed: () {
                  Navigator.of(context).pushReplacementNamed('/onboarding');
                },
                child: const Text('機種変更（新しいデバイスで再登録）',
                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }
    // フォールバック（通常到達しない）
    return const Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      body: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
    );
  }
}
