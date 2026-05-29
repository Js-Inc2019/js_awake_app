// lib/screens/register_screen.dart - 職人自己登録（名前・電話・会社名→PIN→即ログイン）
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String _apiUrl = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _pinCtrl     = TextEditingController();
  final _pinConfCtrl = TextEditingController();

  int  _step       = 0; // 0=基本情報, 1=PIN設定
  bool _isLoading  = false;
  bool _obscurePin = true;
  bool _obscureConf = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_nameCtrl,_phoneCtrl,_companyCtrl,_pinCtrl,_pinConfCtrl]) c.dispose();
    super.dispose();
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('device_id');
    if (id != null) return id;
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      id = (await info.androidInfo).id;
    } else if (Platform.isIOS) {
      id = (await info.iosInfo).identifierForVendor ?? 'ios-unknown';
    } else {
      id = 'unknown-device';
    }
    await prefs.setString('device_id', id);
    return id;
  }

  void _nextStep() {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = '名前を入力してください');
      return;
    }
    if (_companyCtrl.text.trim().isEmpty) {
      setState(() => _error = '会社名を入力してください');
      return;
    }
    setState(() { _error = null; _step = 1; });
  }

  Future<void> _register() async {
    final pin  = _pinCtrl.text;
    final conf = _pinConfCtrl.text;
    if (pin.length < 4 || pin.length > 6) {
      setState(() => _error = 'PINは4〜6桁で入力してください');
      return;
    }
    if (pin != conf) {
      setState(() => _error = 'PINが一致しません');
      return;
    }
    setState(() { _isLoading = true; _error = null; });

    try {
      final deviceId = await _deviceId();
      final res = await http.post(
        Uri.parse('$_apiUrl/workers/self-register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name':         _nameCtrl.text.trim(),
          'phone':        _phoneCtrl.text.trim(),
          'company_name': _companyCtrl.text.trim(),
          'pin':          pin,
          'device_id':    deviceId,
          'device_name':  Platform.isAndroid ? 'Android' : 'iPhone',
        }),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      final body = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', body['token']);
        await prefs.setString('user_id',    body['user_id'] ?? '');
        await prefs.setString('user_name',  body['name']    ?? '');
        await prefs.setString('user_role',  body['role']    ?? 'worker');
        await prefs.setString('company_id', body['company_id'] ?? '');
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/gate');
      } else {
        setState(() => _error = body['error'] ?? '登録に失敗しました');
      }
    } catch (e) {
      setState(() => _error = '通信エラー: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: Text(_step == 0 ? '新規登録' : 'PIN設定'),
        backgroundColor: const Color(0xFF111111),
        foregroundColor: const Color(0xFFD4AF37),
        elevation: 0,
        leading: _step == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() { _step = 0; _error = null; }),
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: _step == 0 ? _buildStep0() : _buildStep1(),
        ),
      ),
    );
  }

  Widget _buildStep0() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stepIndicator(0),
      const SizedBox(height: 28),
      const Text('基本情報を入力',
          style: TextStyle(color: Color(0xFFD4AF37), fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('名前・電話番号・会社名を入力してください',
          style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
      const SizedBox(height: 32),
      _field(controller: _nameCtrl,    label: '名前（必須）',    icon: Icons.person),
      const SizedBox(height: 16),
      _field(controller: _phoneCtrl,   label: '電話番号',        icon: Icons.phone,
          keyboard: TextInputType.phone),
      const SizedBox(height: 16),
      _field(controller: _companyCtrl, label: '会社名（必須）',  icon: Icons.business),
      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 32),
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('次へ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
      const SizedBox(height: 16),
      Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ログイン画面に戻る', style: TextStyle(color: Color(0xFF9E9E9E))),
        ),
      ),
    ],
  );

  Widget _buildStep1() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stepIndicator(1),
      const SizedBox(height: 28),
      const Text('PINを設定',
          style: TextStyle(color: Color(0xFFD4AF37), fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('ログイン時に使用する4〜6桁のPINを設定してください',
          style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
      const SizedBox(height: 32),
      _field(
        controller: _pinCtrl, label: 'PIN（4〜6桁）', icon: Icons.lock,
        obscure: _obscurePin, numeric: true, maxLen: 6,
        suffix: IconButton(
          icon: Icon(_obscurePin ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF9E9E9E)),
          onPressed: () => setState(() => _obscurePin = !_obscurePin),
        ),
      ),
      const SizedBox(height: 20),
      _field(
        controller: _pinConfCtrl, label: 'PIN確認', icon: Icons.lock_outline,
        obscure: _obscureConf, numeric: true, maxLen: 6,
        suffix: IconButton(
          icon: Icon(_obscureConf ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF9E9E9E)),
          onPressed: () => setState(() => _obscureConf = !_obscureConf),
        ),
      ),
      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 32),
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _register,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            disabledBackgroundColor: const Color(0xFF9E9E9E),
          ),
          child: _isLoading
              ? const SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
              : const Text('登録してすぐ使う', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    ],
  );

  Widget _stepIndicator(int current) => Row(children: [
    _dot(0, current), _line(current >= 1), _dot(1, current),
  ]);

  Widget _dot(int idx, int current) {
    final active = idx == current;
    final done   = idx < current;
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (active || done) ? const Color(0xFFD4AF37) : const Color(0xFF3A3A3A),
      ),
      child: Center(
        child: done
            ? const Icon(Icons.check, color: Colors.black, size: 16)
            : Text('${idx + 1}', style: TextStyle(
                color: active ? Colors.black : const Color(0xFF9E9E9E),
                fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _line(bool active) => Expanded(
    child: Container(height: 2, color: active ? const Color(0xFFD4AF37) : const Color(0xFF3A3A3A)),
  );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    bool numeric = false,
    int? maxLen,
    Widget? suffix,
    TextInputType? keyboard,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    enabled: !_isLoading,
    keyboardType: numeric ? TextInputType.number : (keyboard ?? TextInputType.text),
    maxLength: maxLen,
    inputFormatters: [if (numeric) FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF9E9E9E)),
      suffixIcon: suffix,
      filled: true, fillColor: const Color(0xFF2A2A2A),
      counterStyle: const TextStyle(color: Color(0xFF9E9E9E)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2)),
      labelStyle: const TextStyle(color: Color(0xFF9E9E9E)),
    ),
    style: const TextStyle(color: Color(0xFFF5F5F0)),
  );

  Widget _errorBox(String msg) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFB71C1C).withValues(alpha: 0.1),
        border: Border.all(color: const Color(0xFFB71C1C)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(msg, style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 13)),
    ),
  );
}
