// lib/screens/register_screen.dart - 招待コード検証フロー
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
  final _inviteCtrl = TextEditingController();
  final _pinCtrl    = TextEditingController();
  final _pinConfCtrl = TextEditingController();

  int  _step         = 0; // 0=招待コード入力, 1=PIN設定
  bool _isLoading    = false;
  bool _obscurePin   = true;
  bool _obscureConf  = true;
  String? _error;

  @override
  void dispose() {
    _inviteCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfCtrl.dispose();
    super.dispose();
  }

  Future<String> _deviceId() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      return (await info.androidInfo).id;
    } else if (Platform.isIOS) {
      return (await info.iosInfo).identifierForVendor ?? 'ios-unknown';
    }
    return 'unknown-device';
  }

  void _nextStep() {
    final code = _inviteCtrl.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _error = '招待コードを入力してください');
      return;
    }
    setState(() { _error = null; _step = 1; });
  }

  Future<void> _activate() async {
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
        Uri.parse('$_apiUrl/workers/activate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'invite_code': _inviteCtrl.text.trim().toUpperCase(),
          'pin':         pin,
          'device_id':   deviceId,
          'device_name': Platform.isAndroid ? 'Android' : 'iPhone',
        }),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      final body = jsonDecode(res.body);

      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token',  body['token']);
        await prefs.setString('user_id',     body['user_id'] ?? '');
        await prefs.setString('user_name',   body['name']    ?? '');
        await prefs.setString('user_role',   body['role']    ?? 'worker');
        await prefs.setString('company_id',  body['company_id'] ?? '');
        await prefs.setString('device_id',   deviceId);
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/gate');
      } else {
        setState(() => _error = body['error'] ?? '有効化に失敗しました');
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
        title: Text(_step == 0 ? '招待コード入力' : 'PIN設定'),
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

  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIndicator(current: 0),
        const SizedBox(height: 28),
        const Text('招待コードを入力',
            style: TextStyle(color: Color(0xFFD4AF37), fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('管理者から受け取った招待コードを入力してください',
            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
        const SizedBox(height: 32),
        _field(
          controller: _inviteCtrl,
          label: '招待コード',
          icon: Icons.vpn_key,
          caps: true,
        ),
        if (_error != null) _errorBox(_error!),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _nextStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('次へ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ログイン画面に戻る',
                style: TextStyle(color: Color(0xFF9E9E9E))),
          ),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIndicator(current: 1),
        const SizedBox(height: 28),
        const Text('PINを設定',
            style: TextStyle(color: Color(0xFFD4AF37), fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('ログイン時に使用するPIN（4〜6桁）を設定してください',
            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
        const SizedBox(height: 32),
        _field(
          controller: _pinCtrl,
          label: 'PIN（4〜6桁）',
          icon: Icons.lock,
          obscure: _obscurePin,
          numeric: true,
          maxLen: 6,
          suffix: IconButton(
            icon: Icon(_obscurePin ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFF9E9E9E)),
            onPressed: () => setState(() => _obscurePin = !_obscurePin),
          ),
        ),
        const SizedBox(height: 20),
        _field(
          controller: _pinConfCtrl,
          label: 'PIN確認',
          icon: Icons.lock_outline,
          obscure: _obscureConf,
          numeric: true,
          maxLen: 6,
          suffix: IconButton(
            icon: Icon(_obscureConf ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFF9E9E9E)),
            onPressed: () => setState(() => _obscureConf = !_obscureConf),
          ),
        ),
        if (_error != null) _errorBox(_error!),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _activate,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              disabledBackgroundColor: const Color(0xFF9E9E9E),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                : const Text('アカウントを有効化', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _stepIndicator({required int current}) {
    return Row(
      children: [
        _dot(0, current),
        _line(current >= 1),
        _dot(1, current),
      ],
    );
  }

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
            : Text('${idx + 1}',
                style: TextStyle(
                  color: active ? Colors.black : const Color(0xFF9E9E9E),
                  fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _line(bool active) {
    return Expanded(
      child: Container(
        height: 2,
        color: active ? const Color(0xFFD4AF37) : const Color(0xFF3A3A3A),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    bool numeric = false,
    bool caps    = false,
    int? maxLen,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: !_isLoading,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      maxLength: maxLen,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: [
        if (numeric) FilteringTextInputFormatter.digitsOnly,
        if (caps) TextInputFormatter.withFunction(
            (old, n) => n.copyWith(text: n.text.toUpperCase())),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF9E9E9E)),
        suffixIcon: suffix,
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

  Widget _errorBox(String msg) {
    return Padding(
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
}
