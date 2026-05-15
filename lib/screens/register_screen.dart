// ============================================================
// lib/screens/register_screen.dart - 登録画面
// 新規ユーザー登録
// ============================================================

import 'package:flutter/material.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _obscurePin = true;
  bool _obscurePinConfirm = true;
  bool _agreeToTerms = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ============================================================
  // バリデーション
  // ============================================================

  bool _validateForm() {
    // 名前チェック
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = '名前を入力してください');
      return false;
    }

    // PIN チェック
    if (_pinController.text.isEmpty) {
      setState(() => _errorMessage = 'PINを入力してください');
      return false;
    }

    if (_pinController.text.length < 4 || _pinController.text.length > 6) {
      setState(() => _errorMessage = 'PINは4〜6桁である必要があります');
      return false;
    }

    // PIN 確認チェック
    if (_pinConfirmController.text.isEmpty) {
      setState(() => _errorMessage = 'PIN確認を入力してください');
      return false;
    }

    if (_pinController.text != _pinConfirmController.text) {
      setState(() => _errorMessage = 'PINが一致しません');
      return false;
    }

    // 利用規約チェック
    if (!_agreeToTerms) {
      setState(() => _errorMessage = '利用規約に同意してください');
      return false;
    }

    return true;
  }

  // ============================================================
  // 登録処理
  // ============================================================

  Future<void> _register() async {
    setState(() => _errorMessage = null);

    if (!_validateForm()) return;

    setState(() => _isLoading = true);

    try {
      // TODO: バックエンド API にユーザー登録リクエストを送信
      // 現在はシミュレーション
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        // 登録成功 → ログイン画面に戻る
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登録が完了しました。PINでログインしてください。'),
            backgroundColor: Color(0xFF2E7D5E),
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'エラーが発生しました: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('新規登録'),
        backgroundColor: const Color(0xFF111111),
        foregroundColor: const Color(0xFFD4AF37),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ============================================================
              // タイトル
              // ============================================================

              const Text(
                '職人情報の登録',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD4AF37),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '職場での認識用に必要な情報を登録してください',
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 32),

              // ============================================================
              // エラーメッセージ
              // ============================================================

              if (_errorMessage != null)
                Container(
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
              if (_errorMessage != null) const SizedBox(height: 20),

              // ============================================================
              // 名前フィールド
              // ============================================================

              const Text(
                '名前 *',
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  labelText: '例：田中太郎',
                  prefixIcon: const Icon(Icons.person),
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
                ),
                style: const TextStyle(color: Color(0xFFF5F5F0)),
              ),
              const SizedBox(height: 20),

              // ============================================================
              // 電話番号フィールド（オプション）
              // ============================================================

              const Text(
                '電話番号（オプション）',
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                enabled: !_isLoading,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: '例：09012345678',
                  prefixIcon: const Icon(Icons.phone),
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
                ),
                style: const TextStyle(color: Color(0xFFF5F5F0)),
              ),
              const SizedBox(height: 20),

              // ============================================================
              // メールフィールド（オプション）
              // ============================================================

              const Text(
                'メール（オプション）',
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                enabled: !_isLoading,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: '例：tanaka@example.com',
                  prefixIcon: const Icon(Icons.email),
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
                ),
                style: const TextStyle(color: Color(0xFFF5F5F0)),
              ),
              const SizedBox(height: 20),

              // ============================================================
              // PIN フィールド
              // ============================================================

              const Text(
                '職場PIN（4〜6桁） *',
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pinController,
                obscureText: _obscurePin,
                enabled: !_isLoading,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'PIN',
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
                ),
                style: const TextStyle(color: Color(0xFFF5F5F0)),
              ),
              const SizedBox(height: 20),

              // ============================================================
              // PIN 確認フィールド
              // ============================================================

              const Text(
                'PIN確認 *',
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pinConfirmController,
                obscureText: _obscurePinConfirm,
                enabled: !_isLoading,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'PIN確認',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePinConfirm ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() => _obscurePinConfirm = !_obscurePinConfirm);
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
                ),
                style: const TextStyle(color: Color(0xFFF5F5F0)),
              ),
              const SizedBox(height: 20),

              // ============================================================
              // 利用規約チェック
              // ============================================================

              Row(
                children: [
                  Checkbox(
                    value: _agreeToTerms,
                    onChanged: _isLoading ? null : (value) {
                      setState(() => _agreeToTerms = value ?? false);
                    },
                    activeColor: const Color(0xFFD4AF37),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isLoading
                          ? null
                          : () {
                              setState(() => _agreeToTerms = !_agreeToTerms);
                            },
                      child: const Text(
                        '利用規約に同意します *',
                        style: TextStyle(
                          color: Color(0xFFF5F5F0),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ============================================================
              // 登録ボタン
              // ============================================================

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
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
                          '登録して始める',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // ============================================================
              // ログインリンク
              // ============================================================

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'すでにアカウントをお持ちですか？',
                    style: TextStyle(color: Color(0xFF9E9E9E)),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.of(context).pop();
                          },
                    child: const Text(
                      'ログイン',
                      style: TextStyle(
                        color: Color(0xFFD4AF37),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}