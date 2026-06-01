// lib/screens/register_screen.dart - 招待コード登録 + 新規登録フロー
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
  // 招待コードフロー
  final _inviteCtrl = TextEditingController();
  // 新規登録フロー
  final _directNameCtrl    = TextEditingController();
  final _directPhoneCtrl   = TextEditingController();
  final _directCompanyCtrl = TextEditingController();
  // PIN（共通）
  final _pinCtrl    = TextEditingController();
  final _pinConfCtrl = TextEditingController();

  String? _mode;       // null=選択画面, 'invite'=招待コード, 'direct'=新規登録
  int  _step         = 0; // invite: 0=コード入力, 1=PIN
  int  _directStep   = 0; // direct: 0=情報入力, 1=PIN
  bool _isLoading    = false;
  bool _obscurePin   = true;
  bool _obscureConf  = true;
  String? _error;

  @override
  void dispose() {
    _inviteCtrl.dispose();
    _directNameCtrl.dispose();
    _directPhoneCtrl.dispose();
    _directCompanyCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfCtrl.dispose();
    super.dispose();
  }

  Future<String> _deviceId() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) return (await info.androidInfo).id;
    if (Platform.isIOS) return (await info.iosInfo).identifierForVendor ?? 'ios-unknown';
    return 'unknown-device';
  }

  void _nextInviteStep() {
    final code = _inviteCtrl.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _error = '招待コードを入力してください');
      return;
    }
    _pinCtrl.clear();
    _pinConfCtrl.clear();
    setState(() { _error = null; _step = 1; });
  }

  Future<void> _activateInvite() async {
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
        await prefs.setString('auth_token', body['token']);
        await prefs.setString('user_id',    body['user_id']    ?? '');
        await prefs.setString('user_name',  body['name']       ?? '');
        await prefs.setString('user_role',  body['role']       ?? 'worker');
        await prefs.setString('company_id', body['company_id'] ?? '');
        await prefs.setString('device_id',  deviceId);
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

  void _nextDirectStep() {
    if (_directNameCtrl.text.trim().isEmpty) {
      setState(() => _error = '氏名を入力してください');
      return;
    }
    if (_directPhoneCtrl.text.trim().isEmpty) {
      setState(() => _error = '電話番号を入力してください');
      return;
    }
    if (_directCompanyCtrl.text.trim().isEmpty) {
      setState(() => _error = '会社名を入力してください');
      return;
    }
    _pinCtrl.clear();
    _pinConfCtrl.clear();
    setState(() { _error = null; _directStep = 1; });
  }

  Future<void> _activateDirect() async {
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
          'name':         _directNameCtrl.text.trim(),
          'phone':        _directPhoneCtrl.text.trim(),
          'company_name': _directCompanyCtrl.text.trim(),
          'pin':          pin,
          'device_id':    deviceId,
          'device_name':  Platform.isAndroid ? 'Android' : 'iPhone',
        }),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', body['token']      ?? '');
        await prefs.setString('user_id',    body['user_id']    ?? '');
        await prefs.setString('user_name',  body['name']       ?? _directNameCtrl.text.trim());
        await prefs.setString('user_role',  body['role']       ?? 'worker');
        await prefs.setString('company_id', body['company_id'] ?? '');
        await prefs.setString('device_id',  deviceId);
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

  String get _appBarTitle {
    if (_mode == null) return 'アカウント登録';
    if (_mode == 'invite') return _step == 0 ? '招待コード入力' : 'PIN設定';
    return _directStep == 0 ? '基本情報入力' : 'PIN設定';
  }

  VoidCallback? get _onBack {
    if (_mode == null) return null;
    return () {
      if (_mode == 'invite' && _step == 1) {
        setState(() { _step = 0; _error = null; });
      } else if (_mode == 'direct' && _directStep == 1) {
        setState(() { _directStep = 0; _error = null; });
      } else {
        setState(() { _mode = null; _step = 0; _directStep = 0; _error = null; });
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: Text(_appBarTitle),
        backgroundColor: const Color(0xFF111111),
        foregroundColor: const Color(0xFFD4AF37),
        elevation: 0,
        leading: _onBack != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _onBack)
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == null) return _buildChoice();
    if (_mode == 'invite') {
      return _step == 0 ? _buildInviteStep0() : _buildPinStep(onActivate: _activateInvite);
    }
    return _directStep == 0 ? _buildDirectStep0() : _buildPinStep(onActivate: _activateDirect);
  }

  // ── 登録方法選択画面 ──────────────────────────────────────────
  Widget _buildChoice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('登録方法を選択',
            style: TextStyle(color: Color(0xFFD4AF37), fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('アカウントの登録方法を選択してください',
            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
        const SizedBox(height: 40),
        _choiceCard(
          icon: Icons.vpn_key,
          title: '招待コードで登録',
          description: '管理者から招待コードを受け取った方',
          onTap: () => setState(() { _mode = 'invite'; _error = null; }),
        ),
        const SizedBox(height: 16),
        _choiceCard(
          icon: Icons.person_add,
          title: '新規登録（招待コードなし）',
          description: '招待コードをお持ちでない方・自己登録の方',
          onTap: () => setState(() { _mode = 'direct'; _error = null; }),
        ),
        const SizedBox(height: 28),
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

  Widget _choiceCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          border: Border.all(color: const Color(0xFF3A3A3A)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFD4AF37), size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                color: Color(0xFFF5F5F0), fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
          ])),
          const Icon(Icons.arrow_forward_ios, color: Color(0xFF9E9E9E), size: 16),
        ]),
      ),
    );
  }

  // ── 招待コード入力 ────────────────────────────────────────────
  Widget _buildInviteStep0() {
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
        _field(controller: _inviteCtrl, label: '招待コード', icon: Icons.vpn_key, caps: true),
        if (_error != null) _errorBox(_error!),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _nextInviteStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('次へ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // ── 新規登録 情報入力 ─────────────────────────────────────────
  Widget _buildDirectStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIndicator(current: 0),
        const SizedBox(height: 28),
        const Text('基本情報を入力',
            style: TextStyle(color: Color(0xFFD4AF37), fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('お名前・電話番号・会社名を入力してください',
            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
        const SizedBox(height: 32),
        _field(controller: _directNameCtrl, label: '氏名', icon: Icons.person),
        const SizedBox(height: 20),
        _field(
          controller: _directPhoneCtrl,
          label: '電話番号',
          icon: Icons.phone,
          numeric: true,
          maxLen: 11,
        ),
        const SizedBox(height: 20),
        _field(controller: _directCompanyCtrl, label: '会社名', icon: Icons.business),
        if (_error != null) _errorBox(_error!),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _nextDirectStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('次へ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // ── PIN設定（招待コード・新規登録共通） ──────────────────────────
  Widget _buildPinStep({required VoidCallback onActivate}) {
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
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : onActivate,
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
                : const Text('登録完了', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // ── 共通ウィジェット ──────────────────────────────────────────
  Widget _stepIndicator({required int current}) => Row(children: [
    _dot(0, current),
    _line(current >= 1),
    _dot(1, current),
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
