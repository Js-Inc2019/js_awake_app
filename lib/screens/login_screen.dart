// ============================================================
// lib/screens/login_screen.dart - ログイン画面
// PIN入力と生体認証対応
// ============================================================

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pinController = TextEditingController();
  bool _obscurePin = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // _tryBiometricAuth(); // 生体認証は手動のみ
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  // ============================================================
  // 生体認証を試行
  // ============================================================

  Future<void> _tryBiometricAuth() async {
    try {
      final auth = LocalAuthentication();
      final canCheckBiometrics = await auth.canCheckBiometrics;

      if (!canCheckBiometrics) return;

      final isAuthenticated = await auth.authenticate(
        localizedReason: '生体認証でログインしてください',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (isAuthenticated && mounted) {
        _navigateToGate();
      }
    } catch (e) {
      debugPrint('生体認証エラー: $e');
    }
  }

// ============================================================
  // PIN認証
  // ============================================================

  Future<void> _verifyPin() async {
    final pin = _pinController.text.trim();

    // バリデーション
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'PINを入力してください');
      return;
    }

    if (pin.length < 4) {
      setState(() => _errorMessage = 'PINは4桁以上である必要があります');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await AuthService().loginWithPin(pin);
      
      if (result['success'] && mounted) {
        _navigateToGate();
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'ログインに失敗しました';
          _pinController.clear();
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'エラーが発生しました: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // GateScreen へナビゲート
  // ============================================================

  void _navigateToGate() {
    Navigator.of(context).pushReplacementNamed('/gate');
  }

  // ============================================================
  // 登録画面へナビゲート
  // ============================================================

  void _navigateToRegister() {
    Navigator.of(context).pushNamed('/register');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ============================================================
                // ロゴ
                // ============================================================

                const SizedBox(height: 40),
                const Text(
                  '日報報告',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD4AF37),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "J's Inc.",
                  style: TextStyle(
                    color: Color(0xFF9E9E9E),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 60),

                // ============================================================
                // PIN入力フィールド
                // ============================================================

                TextField(
                  controller: _pinController,
                  obscureText: _obscurePin,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    labelText: '職場PIN',
                    hintText: '4〜6桁のPINを入力',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePin ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _obscurePin = !_obscurePin);
                      },
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFD4AF37),
                        width: 2,
                      ),
                    ),
                    labelStyle: const TextStyle(color: Color(0xFF9E9E9E)),
                    hintStyle: const TextStyle(color: Color(0xFF666666)),
                  ),
                  style: const TextStyle(color: Color(0xFFF5F5F0)),
                  onSubmitted: (_) => _verifyPin(),
                ),

                // ============================================================
                // エラーメッセージ
                // ============================================================

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB71C1C).withOpacity(0.1),
                        border: Border.all(color: const Color(0xFFB71C1C)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFB71C1C),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 28),

                // ============================================================
                // ログインボタン
                // ============================================================

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyPin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      disabledBackgroundColor: const Color(0xFF9E9E9E),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'ログイン',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // ============================================================
                // 新規登録リンク
                // ============================================================

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '初めてですか？',
                      style: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _isLoading ? null : _navigateToRegister,
                      child: const Text(
                        '新規登録',
                        style: TextStyle(
                          color: Color(0xFFD4AF37),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // ============================================================
                // 生体認証ボタン（オプション）
                // ============================================================

                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _tryBiometricAuth,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('生体認証で開く'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD4AF37),
                    side: const BorderSide(color: Color(0xFFD4AF37)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // ============================================================
                // フッターテキスト
                // ============================================================

                const Text(
                  '職人 × AI × J\'s ＝ 覚醒',
                  style: TextStyle(
                    color: Color(0xFF9E9E9E),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      backgroundColor: const Color(0xFF111111),
    );
  }
}