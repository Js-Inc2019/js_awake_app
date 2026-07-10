// lib/screens/recovery_screen.dart
// 機種変更・再インストール後の端末再接続（会社コード＋worker_id＋PIN）
// POST /auth/recover-by-code で既存 person へ device_id を再紐付けする。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../utils/device_id.dart';

// login_screen.dart と同一配色（当ファイル内 private 定数）
const _bgColor     = Color(0xFF0A0E14);
const _goldColor   = Color(0xFFC9A84C);
const _navyColor   = Color(0xFF0D1B2A);
const _silverColor = Color(0xFF8A9BA8);

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _companyCodeCtrl = TextEditingController();
  final _workerIdCtrl    = TextEditingController();
  final _pinCtrl         = TextEditingController();

  bool _obscurePin  = true;
  bool _isLoading   = false;
  String? _errorMessage;

  @override
  void dispose() {
    _companyCodeCtrl.dispose();
    _workerIdCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  // ─── 復旧実行 ─────────────────────────────────────────────
  Future<void> _recover() async {
    final companyCode = _companyCodeCtrl.text.trim().toUpperCase();
    final workerId    = _workerIdCtrl.text.trim().toUpperCase();
    final pin         = _pinCtrl.text.trim();

    if (companyCode.isEmpty) {
      setState(() => _errorMessage = '会社コードを入力してください');
      return;
    }
    if (workerId.isEmpty) {
      setState(() => _errorMessage = '作業員IDを入力してください');
      return;
    }
    if (pin.length < 4) {
      setState(() => _errorMessage = 'PINを入力してください（4〜6桁）');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final deviceId = await getDeviceId();
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/auth/recover-by-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'company_code': companyCode,
          'worker_id':    workerId,
          'pin':          pin,
          'device_id':    deviceId,
        }),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        await _saveAndNavigate(data, deviceId);
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = _mapError(response.statusCode, data['code'] as String?);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '通信エラーが発生しました';
        });
      }
    }
  }

  String _mapError(int status, String? code) {
    if (code == 'COMPANY_NOT_FOUND') return '会社コードが見つかりません';
    if (code == 'MEMBER_NOT_FOUND')  return '作業員IDが見つかりません';
    if (code == 'DEVICE_IN_USE')     return 'この端末は別のユーザーに登録されています。会社の管理者にご相談ください';
    if (code == 'NO_ACTIVE_MEMBERSHIP') return '有効な所属が見つかりません。会社の管理者にご相談ください';
    if (code == 'PIN_LOCKED')        return '試行回数を超過しました。30分後に再試行してください';
    if (status == 401)               return 'PINが違います';
    return '通信エラーが発生しました';
  }

  // login_screen.dart:523-545 _saveAndNavigate と同一キーで保存
  Future<void> _saveAndNavigate(Map<String, dynamic> data, String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token',   data['token']        as String? ?? '');
    await prefs.setString('user_name',    data['name']         as String? ?? '');
    await prefs.setString('user_role',    data['role']         as String? ?? 'worker');
    await prefs.setString('company_id',   data['company_id']   as String? ?? '');
    await prefs.setString('company_name', data['company_name'] as String? ?? '');
    await prefs.setString('work_mode',    data['work_mode']    as String? ?? 'deemed');
    await prefs.setString('user_id',      data['user_id']      as String? ?? '');
    await prefs.setString('consent_agreed_at',
        data['consent_agreed_at'] ?? DateTime.now().toIso8601String());
    await prefs.setString('consent_version', '1.0');
    await prefs.setBool('is_registered', true);
    // recover-by-code は単一membership時に worker_id を返す（BE auth.js:908）→ prefs へ保存
    final wid = data['worker_id'] as String?;
    if (wid != null && wid.isNotEmpty) {
      await prefs.setString('worker_id', wid);
    }
    String did = prefs.getString('device_id') ?? '';
    if (did.isEmpty) {
      did = deviceId;
      await prefs.setString('device_id', did);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/gate');
  }

  // ─── UI 部品 ─────────────────────────────────────────────
  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool caps = false,
  }) {
    return TextField(
      controller: controller,
      enabled: !_isLoading,
      textCapitalization:
          caps ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: [
        if (caps)
          TextInputFormatter.withFunction(
              (old, n) => n.copyWith(text: n.text.toUpperCase())),
      ],
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _silverColor, fontSize: 13),
        prefixIcon: Icon(icon, color: _silverColor),
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

  // login_screen.dart:940-973 の PIN 入力スタイル流用
  Widget _pinField() {
    return TextField(
      controller: _pinCtrl,
      enabled: !_isLoading,
      obscureText: _obscurePin,
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
            borderSide: const BorderSide(color: _goldColor, width: 2)),
        suffixIcon: IconButton(
          icon: Icon(
              _obscurePin ? Icons.visibility_off : Icons.visibility,
              color: const Color(0xFF484830)),
          onPressed: () => setState(() => _obscurePin = !_obscurePin),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _goldColor,
        elevation: 0,
        title: const Text('端末の復旧',
            style: TextStyle(color: _goldColor, fontSize: 18)),
        // 戻る＝常にランディングへ戻れる（push 元へ pop）
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.phonelink_setup,
                  color: _goldColor, size: 56),
              const SizedBox(height: 16),
              const Text(
                '機種変更・再インストール後の復旧',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '会社コード・作業員ID・PIN を入力すると、\nこの端末を既存の登録に再接続します',
                style: TextStyle(color: _silverColor, fontSize: 13, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _textField(
                controller: _companyCodeCtrl,
                label: '会社コード',
                icon: Icons.business,
                caps: true,
              ),
              const SizedBox(height: 16),
              _textField(
                controller: _workerIdCtrl,
                label: '作業員ID',
                icon: Icons.badge_outlined,
                caps: true,
              ),
              const SizedBox(height: 16),
              _pinField(),
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
                          color: Colors.redAccent, fontSize: 13),
                      textAlign: TextAlign.center),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _recover,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _goldColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('この端末で復旧',
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
}
