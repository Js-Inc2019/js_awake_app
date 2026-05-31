// lib/screens/register_screen.dart - 職人登録フロー（5ステップ）
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors;

const String _apiUrl = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ─── ステップ管理 ────────────────────────────────────────
  // 0: 選択, 1: 個人情報, 2: 緊急連絡先, 3: PIN設定, 4: 完了
  int _step = 0;
  bool _isLoading = false;
  String? _error;

  // ─── STEP1: 個人情報 ─────────────────────────────────────
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _postalCtrl  = TextEditingController();
  final _addressCtrl = TextEditingController();
  String? _bloodType;
  DateTime? _birthDate;
  bool _postalLoading = false;
  static const _bloodTypes = ['A', 'B', 'O', 'AB'];

  // ─── STEP2: 緊急連絡先 ───────────────────────────────────
  final _emgNameCtrl    = TextEditingController();
  final _emgRelCtrl     = TextEditingController();
  final _emgPhoneCtrl   = TextEditingController();
  final _emgAddressCtrl = TextEditingController();

  // ─── STEP3: PIN ──────────────────────────────────────────
  final _pinCtrl  = TextEditingController();
  final _pinConfCtrl = TextEditingController();
  bool _obscurePin  = true;
  bool _obscureConf = true;

  // ─── STEP4: 完了 ─────────────────────────────────────────
  String _registeredPin = '';

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _companyCtrl, _postalCtrl, _addressCtrl,
                     _emgNameCtrl, _emgRelCtrl, _emgPhoneCtrl, _emgAddressCtrl,
                     _pinCtrl, _pinConfCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── デバイスID取得 ──────────────────────────────────────

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

  // ─── 郵便番号→住所（zipcloud） ────────────────────────────

  Future<void> _lookupPostalCode() async {
    final code = _postalCtrl.text.trim().replaceAll('-', '');
    if (code.length != 7 || int.tryParse(code) == null) {
      setState(() => _error = '郵便番号は7桁の数字で入力してください');
      return;
    }
    setState(() { _postalLoading = true; _error = null; });
    try {
      final res = await http.get(
        Uri.parse('https://zipcloud.ibsnet.co.jp/api/search?zipcode=$code'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final r = results[0];
          if (mounted) {
            setState(() => _addressCtrl.text =
                '${r['address1'] ?? ''}${r['address2'] ?? ''}${r['address3'] ?? ''}');
          }
        } else {
          if (mounted) setState(() => _error = '該当する住所が見つかりません');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = '住所の取得に失敗しました');
    } finally {
      if (mounted) setState(() => _postalLoading = false);
    }
  }

  // ─── ステップバリデーション ──────────────────────────────

  bool _validateStep1() {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = '名前を入力してください');
      return false;
    }
    if (_companyCtrl.text.trim().isEmpty) {
      setState(() => _error = '会社名を入力してください');
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  bool _validateStep3() {
    final pin = _pinCtrl.text;
    if (pin.length != 6 || int.tryParse(pin) == null) {
      setState(() => _error = 'PINは6桁の数字で入力してください');
      return false;
    }
    if (pin != _pinConfCtrl.text) {
      setState(() => _error = 'PINが一致しません');
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  // ─── 登録実行 ────────────────────────────────────────────

  Future<void> _register() async {
    if (!_validateStep3()) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final deviceId = await _deviceId();
      final pin = _pinCtrl.text;
      final res = await http.post(
        Uri.parse('$_apiUrl/workers/self-register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name':              _nameCtrl.text.trim(),
          'phone':             _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          'company_name':      _companyCtrl.text.trim(),
          'pin':               pin,
          'device_id':         deviceId,
          'device_name':       Platform.isAndroid ? 'Android' : 'iPhone',
          'blood_type':        _bloodType,
          'birth_date':        _birthDate?.toIso8601String().substring(0, 10),
          'postal_code':       _postalCtrl.text.trim().isEmpty ? null : _postalCtrl.text.trim(),
          'address':           _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          'emergency_name':    _emgNameCtrl.text.trim().isEmpty ? null : _emgNameCtrl.text.trim(),
          'emergency_relation':_emgRelCtrl.text.trim().isEmpty ? null : _emgRelCtrl.text.trim(),
          'emergency_phone':   _emgPhoneCtrl.text.trim().isEmpty ? null : _emgPhoneCtrl.text.trim(),
          'emergency_address': _emgAddressCtrl.text.trim().isEmpty ? null : _emgAddressCtrl.text.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', body['token'] as String? ?? '');
        await prefs.setString('user_id',    body['user_id'] as String? ?? '');
        await prefs.setString('user_name',  body['name']    as String? ?? '');
        await prefs.setString('user_role',  body['role']    as String? ?? 'worker');
        await prefs.setString('company_id', body['company_id'] as String? ?? '');
        setState(() { _registeredPin = pin; _step = 4; });
      } else {
        setState(() => _error = body['error'] as String? ?? '登録に失敗しました');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '通信エラー: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── ナビゲーション ──────────────────────────────────────

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() { _step = _step - 1; _error = null; });
    }
  }

  // ─── Build ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(
        title: Text(_stepTitle()),
        leading: _step > 0 && _step < 4
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _back,
              )
            : null,
        automaticallyImplyLeading: _step > 0 && _step < 4,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: _buildStep(),
        ),
      ),
    );
  }

  String _stepTitle() {
    switch (_step) {
      case 0: return '登録方法を選択';
      case 1: return '個人情報の入力';
      case 2: return '緊急連絡先';
      case 3: return 'PIN設定';
      case 4: return '登録完了';
      default: return '';
    }
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _buildStep0();
      case 1: return _buildStep1();
      case 2: return _buildStep2();
      case 3: return _buildStep3();
      case 4: return _buildStep4();
      default: return const SizedBox.shrink();
    }
  }

  // ─── STEP 0: 選択 ────────────────────────────────────────

  Widget _buildStep0() => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      const SizedBox(height: 24),
      const Text("J's Inc.", style: TextStyle(
          color: JsColors.gold, fontSize: 36,
          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      const SizedBox(height: 8),
      const Text('勤務管理システム', style: TextStyle(color: JsColors.silver, fontSize: 16)),
      const SizedBox(height: 8),
      Container(width: 48, height: 2, color: JsColors.gold),
      const SizedBox(height: 48),

      // 招待コードで登録
      _OptionCard(
        icon: Icons.vpn_key_rounded,
        title: '招待コードで登録',
        subtitle: '管理者から招待コードを受け取った方\n（機種変更・初回登録）',
        isPrimary: true,
        onTap: () => Navigator.of(context).pushNamed('/invite-activate'),
      ),
      const SizedBox(height: 16),

      // 新規登録
      _OptionCard(
        icon: Icons.person_add_alt_1_rounded,
        title: '新規登録',
        subtitle: '名前・情報・PINを設定して\nすぐに使い始める',
        isPrimary: false,
        onTap: () => setState(() { _step = 1; _error = null; }),
      ),
      const SizedBox(height: 40),
      const Text('ご不明な点は管理者にお問い合わせください',
          style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
    ],
  );

  // ─── STEP 1: 個人情報 ────────────────────────────────────

  Widget _buildStep1() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _StepIndicator(current: 1, total: 4),
      const SizedBox(height: 24),
      _field(_nameCtrl,    '名前（必須）',    Icons.person),
      const SizedBox(height: 14),
      _field(_phoneCtrl,   '電話番号',        Icons.phone,
          keyboard: TextInputType.phone),
      const SizedBox(height: 14),
      _field(_companyCtrl, '会社名（必須）',  Icons.business),
      const SizedBox(height: 20),

      // 郵便番号
      const Text('住所', style: TextStyle(color: JsColors.silver, fontSize: 13)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _postalCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(7)],
            decoration: const InputDecoration(
              labelText: '郵便番号（7桁）',
              hintText: '1234567',
              prefixIcon: Icon(Icons.local_post_office, color: JsColors.silver),
            ),
            style: const TextStyle(color: JsColors.offWhite),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _postalLoading ? null : _lookupPostalCode,
          style: ElevatedButton.styleFrom(minimumSize: const Size(64, 52)),
          child: _postalLoading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('検索'),
        ),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _addressCtrl,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: '住所',
          prefixIcon: Icon(Icons.home_work_outlined, color: JsColors.silver),
        ),
        style: const TextStyle(color: JsColors.offWhite),
      ),
      const SizedBox(height: 20),

      // 血液型
      const Text('血液型', style: TextStyle(color: JsColors.silver, fontSize: 13)),
      const SizedBox(height: 8),
      Row(children: _bloodTypes.map((t) {
        final sel = _bloodType == t;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _bloodType = sel ? null : t),
            child: Container(
              width: 60,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel ? JsColors.gold : JsColors.gunmetal,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? JsColors.gold : JsColors.divider),
              ),
              child: Center(child: Text(t, style: TextStyle(
                color: sel ? Colors.black : JsColors.offWhite,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              ))),
            ),
          ),
        );
      }).toList()),
      const SizedBox(height: 20),

      // 生年月日
      const Text('生年月日', style: TextStyle(color: JsColors.silver, fontSize: 13)),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: _birthDate ?? DateTime(1990),
            firstDate: DateTime(1920),
            lastDate: DateTime.now(),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: JsColors.gold, surface: JsColors.gunmetal,
                  onSurface: JsColors.offWhite),
              ),
              child: child!,
            ),
          );
          if (d != null && mounted) setState(() => _birthDate = d);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: JsColors.gunmetal,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: JsColors.divider),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today, color: JsColors.silver, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _birthDate != null
                    ? '${_birthDate!.year}年${_birthDate!.month.toString().padLeft(2,'0')}月${_birthDate!.day.toString().padLeft(2,'0')}日'
                    : '生年月日を選択（任意）',
                style: TextStyle(
                    color: _birthDate != null ? JsColors.offWhite : const Color(0xFF666666),
                    fontSize: 14),
              ),
            ),
            if (_birthDate != null)
              GestureDetector(
                onTap: () => setState(() => _birthDate = null),
                child: const Icon(Icons.close, color: JsColors.silver, size: 18),
              ),
          ]),
        ),
      ),

      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 28),
      _nextButton('次へ（緊急連絡先）', () {
        if (_validateStep1()) setState(() => _step = 2);
      }),
    ],
  );

  // ─── STEP 2: 緊急連絡先 ─────────────────────────────────

  Widget _buildStep2() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _StepIndicator(current: 2, total: 4),
      const SizedBox(height: 8),
      const Text('緊急連絡先は任意です。後からプロフィール画面で入力できます。',
          style: TextStyle(color: JsColors.silver, fontSize: 12, height: 1.5)),
      const SizedBox(height: 20),
      _field(_emgNameCtrl,    '緊急連絡先 氏名',      Icons.person),
      const SizedBox(height: 14),
      _field(_emgRelCtrl,     '続柄（例：妻・父）',   Icons.family_restroom),
      const SizedBox(height: 14),
      _field(_emgPhoneCtrl,   '緊急連絡先 電話番号',  Icons.phone,
          keyboard: TextInputType.phone),
      const SizedBox(height: 14),
      TextField(
        controller: _emgAddressCtrl,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: '緊急連絡先 住所',
          prefixIcon: Icon(Icons.location_on, color: JsColors.silver),
        ),
        style: const TextStyle(color: JsColors.offWhite),
      ),
      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 28),
      _nextButton('次へ（PIN設定）', () => setState(() { _step = 3; _error = null; })),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => setState(() { _step = 3; _error = null; }),
          child: const Text('スキップ', style: TextStyle(color: JsColors.silver)),
        ),
      ),
    ],
  );

  // ─── STEP 3: PIN設定 ─────────────────────────────────────

  Widget _buildStep3() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _StepIndicator(current: 3, total: 4),
      const SizedBox(height: 8),
      const Text('ログイン時に使用する6桁のPINを設定してください。\nPINは安全な場所に控えてください。',
          style: TextStyle(color: JsColors.silver, fontSize: 12, height: 1.5)),
      const SizedBox(height: 24),
      _pinField(controller: _pinCtrl, label: '6桁PIN',
          obscure: _obscurePin,
          onToggle: () => setState(() => _obscurePin = !_obscurePin)),
      const SizedBox(height: 16),
      _pinField(controller: _pinConfCtrl, label: 'PIN確認',
          obscure: _obscureConf,
          onToggle: () => setState(() => _obscureConf = !_obscureConf)),
      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 28),
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _register,
          child: _isLoading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
              : const Text('登録する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    ],
  );

  // ─── STEP 4: 完了 ────────────────────────────────────────

  Widget _buildStep4() => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      const SizedBox(height: 32),
      const Icon(Icons.check_circle, color: JsColors.gold, size: 72),
      const SizedBox(height: 20),
      const Text('登録完了！', style: TextStyle(
          color: JsColors.gold, fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('ようこそ、${_nameCtrl.text.trim()}さん',
          style: const TextStyle(color: JsColors.offWhite, fontSize: 16)),
      const SizedBox(height: 32),

      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: JsColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JsColors.error),
        ),
        child: Column(children: [
          const Text('あなたのPIN番号', style: TextStyle(color: JsColors.silver, fontSize: 13)),
          const SizedBox(height: 8),
          Text(_registeredPin, style: const TextStyle(
              color: JsColors.gold, fontSize: 40, fontWeight: FontWeight.bold,
              letterSpacing: 12)),
          const SizedBox(height: 12),
          const Text('このPINは再表示されません。\n必ず安全な場所に控えてください。',
              style: TextStyle(color: JsColors.error, fontSize: 13,
                  fontWeight: FontWeight.bold, height: 1.5),
              textAlign: TextAlign.center),
        ]),
      ),

      const SizedBox(height: 32),
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pushNamedAndRemoveUntil('/gate', (_) => false),
          child: const Text('アプリをはじめる',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    ],
  );

  // ─── 共通ウィジェット ─────────────────────────────────────

  Widget _nextButton(String label, VoidCallback onTap) => SizedBox(
    width: double.infinity, height: 52,
    child: ElevatedButton(
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboard}) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboard,
        enabled: !_isLoading,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: JsColors.silver),
        ),
        style: const TextStyle(color: JsColors.offWhite),
      );

  Widget _pinField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6)],
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: JsColors.offWhite, fontSize: 24, letterSpacing: 10),
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                color: JsColors.silver),
            onPressed: onToggle,
          ),
        ),
      );

  Widget _errorBox(String msg) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JsColors.error.withValues(alpha: 0.1),
        border: Border.all(color: JsColors.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(msg, style: const TextStyle(color: JsColors.error, fontSize: 13)),
    ),
  );
}

// ─── ステップインジケーター ──────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});
  final int current, total;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(children: List.generate(total * 2 - 1, (i) {
          if (i.isOdd) {
            return Expanded(
              child: Container(
                  height: 2,
                  color: i ~/ 2 < current - 1 ? JsColors.gold : JsColors.divider),
            );
          }
          final idx = i ~/ 2 + 1;
          final done = idx < current;
          final active = idx == current;
          return Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (done || active) ? JsColors.gold : JsColors.gunmetal,
              border: Border.all(
                  color: (done || active) ? JsColors.gold : JsColors.divider),
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check, color: Colors.black, size: 16)
                  : Text('$idx', style: TextStyle(
                      color: active ? Colors.black : JsColors.silver,
                      fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          );
        })),
      );
}

// ─── 選択カード ─────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isPrimary,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isPrimary
                ? JsColors.gold.withValues(alpha: 0.12)
                : JsColors.gunmetal,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isPrimary ? JsColors.gold : JsColors.divider, width: 1.5),
          ),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPrimary
                    ? JsColors.gold.withValues(alpha: 0.2)
                    : JsColors.surface,
              ),
              child: Icon(icon,
                  color: isPrimary ? JsColors.gold : JsColors.silver, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(
                    color: isPrimary ? JsColors.gold : JsColors.offWhite,
                    fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(
                    color: JsColors.silver, fontSize: 12, height: 1.5)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: JsColors.silver),
          ]),
        ),
      );
}
