// ============================================================
// lib/screens/register_screen.dart - ユーザー登録画面
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String _API_URL = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController       = TextEditingController();
  final _pinController        = TextEditingController();
  final _pinConfirmController = TextEditingController();
  final _phoneController      = TextEditingController();

  String _selectedRole = 'worker';
  bool   _obscurePin        = true;
  bool   _obscurePinConfirm = true;
  bool   _isLoading         = false;
  String? _errorMessage;

  static const _roles = [
    {'value': 'worker',       'label': '職人'},
    {'value': 'boss',         'label': '職長'},
    {'value': 'admin_office', 'label': '事務'},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool _validateForm() {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = '名前を入力してください');
      return false;
    }
    if (_pinController.text.isEmpty) {
      setState(() => _errorMessage = 'PINを入力してください');
      return false;
    }
    if (_pinController.text.length < 4 || _pinController.text.length > 6) {
      setState(() => _errorMessage = 'PINは4〜6桁である必要があります');
      return false;
    }
    if (_pinController.text != _pinConfirmController.text) {
      setState(() => _errorMessage = 'PINが一致しません');
      return false;
    }
    return true;
  }

  Future<void> _register() async {
    setState(() => _errorMessage = null);
    if (!_validateForm()) return;
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$_API_URL/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name':        _nameController.text.trim(),
          'pin':         _pinController.text,
          'phone_number': _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          'device_name': 'Android',
          'device_type': 'smartphone',
          'os_type':     'android',
          'role':        _selectedRole,
        }),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 201) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${_nameController.text.trim()}を登録しました'),
            backgroundColor: const Color(0xFF2E7D5E),
          ),
        );
      } else {
        final body = jsonDecode(response.body);
        setState(() => _errorMessage = body['error'] ?? '登録に失敗しました');
      }
    } catch (e) {
      setState(() => _errorMessage = '通信エラー: $e');
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
              const Text('新しいメンバーを登録',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD4AF37),
                  )),
              const SizedBox(height: 8),
              const Text('職人・職長・事務スタッフを追加します',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
              const SizedBox(height: 32),

              // エラーメッセージ
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C).withOpacity(0.1),
                    border: Border.all(color: const Color(0xFFB71C1C)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_errorMessage!,
                      style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 13)),
                ),
                const SizedBox(height: 20),
              ],

              // 役割選択
              const Text('役割 *',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: _roles.map((role) {
                  final selected = _selectedRole == role['value'];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRole = role['value']!),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFD4AF37)
                              : const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFFD4AF37)
                                : const Color(0xFF3A3A3A),
                          ),
                        ),
                        child: Text(
                          role['label']!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selected ? Colors.black : const Color(0xFFF5F5F0),
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // 名前
              const Text('名前 *',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _nameController,
                label: '例：田中 太郎',
                icon: Icons.person,
              ),
              const SizedBox(height: 20),

              // 電話番号
              const Text('電話番号（オプション）',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _phoneController,
                label: '例：09012345678',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),

              // PIN
              const Text('PIN（4〜6桁） *',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _pinController,
                label: 'PIN',
                icon: Icons.lock,
                obscureText: _obscurePin,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                suffixIcon: IconButton(
                  icon: Icon(_obscurePin
                      ? Icons.visibility_off
                      : Icons.visibility,
                      color: const Color(0xFF9E9E9E)),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
              ),
              const SizedBox(height: 20),

              // PIN確認
              const Text('PIN確認 *',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _pinConfirmController,
                label: 'PINを再入力',
                icon: Icons.lock_outline,
                obscureText: _obscurePinConfirm,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                suffixIcon: IconButton(
                  icon: Icon(_obscurePinConfirm
                      ? Icons.visibility_off
                      : Icons.visibility,
                      color: const Color(0xFF9E9E9E)),
                  onPressed: () =>
                      setState(() => _obscurePinConfirm = !_obscurePinConfirm),
                ),
              ),
              const SizedBox(height: 32),

              // 登録ボタン
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    disabledBackgroundColor: const Color(0xFF9E9E9E),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.black))
                      : const Text('登録する',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('すでにアカウントをお持ちですか？',
                      style: TextStyle(color: Color(0xFF9E9E9E))),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('ログイン',
                        style: TextStyle(
                            color: Color(0xFFD4AF37),
                            fontWeight: FontWeight.bold)),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    int? maxLength,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: !_isLoading,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF9E9E9E)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        counterStyle: const TextStyle(color: Color(0xFF9E9E9E)),
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
          borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF9E9E9E)),
      ),
      style: const TextStyle(color: Color(0xFFF5F5F0)),
    );
  }
}