// lib/screens/register_screen.dart - 招待コード登録フロー
import 'dart:io';
import 'package:flutter/material.dart';
 import '../core/theme/field_tokens.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/worker_service.dart';
import '../utils/device_id.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.initialInviteCode});
  final String? initialInviteCode;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _inviteCtrl  = TextEditingController();
  final _pinCtrl     = TextEditingController();
  final _pinConfCtrl = TextEditingController();

  int  _step        = 0; // 0=コード入力, 1=PIN設定
  bool _isLoading   = false;
  bool _obscurePin  = true;
  bool _obscureConf = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final code = widget.initialInviteCode;
    if (code != null && code.isNotEmpty) {
      _inviteCtrl.text = code;
      _step = 1;
    }
  }

  @override
  void dispose() {
    _inviteCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
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
    final deviceId = await getDeviceId();
    final r = await WorkerService().activate(
      inviteCode:  _inviteCtrl.text.trim().toUpperCase(),
      pin:         pin,
      deviceId:    deviceId,
      deviceName:  Platform.isAndroid ? 'Android' : 'iPhone',
    );
    if (!mounted) return;
    if (r.statusCode == 200 && r.ok) {
      final body = r.data ?? const <String, dynamic>{};
      // ★role門番: 事務・管理系の招待コードはFIELDでは有効化させない（袋小路を作らない）
      final role = body['role'] as String? ?? '';
      if (role == 'admin_office' || role == 'admin_exec') {
        setState(() {
          _isLoading = false;
          _error = 'この招待は事務・管理用です。OFFICEアプリで登録してください';
        });
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', body['token']      ?? '');
      await prefs.setString('user_id',    body['user_id']    ?? '');
      await prefs.setString('user_name',  body['name']       ?? '');
      await prefs.setString('user_role',  body['role']       ?? 'worker');
      await prefs.setString('company_id', body['company_id'] ?? '');
      await prefs.setString('device_id',  deviceId);
      await prefs.setBool('is_registered', true);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/gate');
    } else if (r.statusCode == 0) {
      // 通信不成立。errorMessage は規約1の「サーバーに接続できません: $e」を
      // そのまま出す（画面側で prefix を重ねない＝理由を1回だけ言う）。
      setState(() => _error = r.errorMessage);
    } else {
      setState(() => _error = r.errorMessage ?? '有効化に失敗しました');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String get _appBarTitle => _step == 0 ? '招待コードで登録' : 'PIN設定';

  VoidCallback? get _onBack {
    if (_step == 0) return null;
    return () => setState(() { _step = 0; _error = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        title: Text(_appBarTitle),
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        elevation: 0,
        leading: _onBack != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _onBack)
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: _step == 0 ? _buildStep0() : _buildPinStep(),
        ),
      ),
    );
  }

  Widget _buildStep0() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stepIndicator(current: 0, total: 2),
      const SizedBox(height: 28),
      const Text('招待コードを入力',
          style: TextStyle(color: FieldTokens.accentDeep, fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('管理者から受け取った招待コードを入力してください',
          style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
      const SizedBox(height: 32),
      _field(controller: _inviteCtrl, label: '招待コード', icon: Icons.vpn_key, caps: true),
      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 32),
      _primaryButton(label: '次へ', onPressed: _nextStep),
      const SizedBox(height: 16),
      Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ログイン画面に戻る',
              style: TextStyle(color: FieldTokens.textSupport)),
        ),
      ),
    ]);
  }

  Widget _buildPinStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stepIndicator(current: 1, total: 2),
      const SizedBox(height: 28),
      const Text('PINを設定',
          style: TextStyle(color: FieldTokens.accentDeep, fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('ログイン時に使用するPIN（4〜6桁）を設定してください',
          style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
      const SizedBox(height: 28),
      _field(
        controller: _pinCtrl,
        label: 'PIN（4〜6桁）',
        icon: Icons.lock,
        obscure: _obscurePin,
        numeric: true,
        maxLen: 6,
        suffix: IconButton(
          icon: Icon(_obscurePin ? Icons.visibility_off : Icons.visibility,
              color: FieldTokens.textSupport),
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
              color: FieldTokens.textSupport),
          onPressed: () => setState(() => _obscureConf = !_obscureConf),
        ),
      ),
      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 32),
      _primaryButton(
        label: '登録完了',
        onPressed: _isLoading ? null : _activateInvite,
        loading: _isLoading,
      ),
    ]);
  }

  Widget _stepIndicator({required int current, required int total}) {
    return Row(children: [
      for (var i = 0; i < total; i++) ...[
        _dot(i, current),
        if (i < total - 1) _line(current > i),
      ],
    ]);
  }

  Widget _dot(int idx, int current) {
    final active = idx == current;
    final done   = idx < current;
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (active || done) ? FieldTokens.accent : FieldTokens.surfaceRaised,
      ),
      child: Center(
        child: done
            ? const Icon(Icons.check, color: FieldTokens.onAccent, size: 16)
            : Text('${idx + 1}', style: TextStyle(
                color: active ? FieldTokens.onAccent : FieldTokens.textSupport,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ),
    );
  }

  Widget _line(bool active) => Expanded(
    child: Container(
        height: 2,
        color: active ? FieldTokens.accent : FieldTokens.outline),
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
      controller:  controller,
      obscureText: obscure,
      enabled:     !_isLoading,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      maxLength:   maxLen,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: [
        if (numeric) FilteringTextInputFormatter.digitsOnly,
        if (caps) TextInputFormatter.withFunction(
            (old, n) => n.copyWith(text: n.text.toUpperCase())),
      ],
      decoration: InputDecoration(
        labelText:  label,
        prefixIcon: Icon(icon, color: FieldTokens.textSupport),
        suffixIcon: suffix,
        filled:     true,
        fillColor:  FieldTokens.surfaceCard,
        counterStyle: const TextStyle(color: FieldTokens.textSupport),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: FieldTokens.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: FieldTokens.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: FieldTokens.accent, width: 2),
        ),
        labelStyle: const TextStyle(color: FieldTokens.textSupport),
      ),
      style: const TextStyle(color: FieldTokens.textBody),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        // 生成り抜き（画面内の主ボタン）
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: FieldTokens.textBody,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: FieldTokens.textFaint,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? FieldTokens.textFaint
                    : FieldTokens.textBody,
                width: 1.5,
              )),
        ),
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                // 面が透明になったのでスピナーも枠色（生成り）へ
                child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: FieldTokens.textFaint))
            : Text(label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _errorBox(String msg) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FieldTokens.statusError.withValues(alpha: 0.1),
        border: Border.all(color: FieldTokens.statusError),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(msg,
          style: const TextStyle(color: FieldTokens.statusError, fontSize: 13)),
    ),
  );
}
