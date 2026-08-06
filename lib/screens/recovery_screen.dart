// lib/screens/recovery_screen.dart
// 機種変更・再インストール後の端末再接続（会社コード＋worker_id＋PIN）
// POST /auth/recover-by-code で既存 person へ device_id を再紐付けする。
import 'package:flutter/material.dart';
 import '../core/theme/field_tokens.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../utils/device_id.dart';
import 'consent_screen.dart';

// 現行の利用規約バージョン（BE の CURRENT_CONSENT_VERSION と同値・当ファイル内 private 定数）。
const String _kCurrentConsentVersion = '1.0';

// 配色は lib/core/theme/field_tokens.dart のトークンへ統一（画面ローカル定数は撤去）

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
        // 【旧時代ユーザー救済・角ケース】recover-by-code 成功でも、サーバの consent_agreed_at が
        // null/空（DB未記録）だと同意が永久未記録になり得る。保存/遷移の前に ConsentScreen を出して
        // 同意を取得する。onAgreed で consent_agreed=true 等を prefs 保存 → 直後の _saveAndNavigate 内の
        // 既存救済刻印（localAgreed=true + サーバ null 検知）が POST /auth/consent で正式刻印する（重複実装しない）。
        // ※ サーバ値が非null（既に刻印済み）の時は表示しない＝毎回同意の復活を防ぐ。
        final serverConsentAt = data['consent_agreed_at'] as String?;
        if (serverConsentAt == null || serverConsentAt.isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          bool agreedNow = false;
          if (!mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ConsentScreen(
              onAgreed: () {
                agreedNow = true;
                prefs.setBool('consent_agreed', true);
                prefs.setString('consent_version', _kCurrentConsentVersion);
                prefs.setString(
                    'consent_agreed_at', DateTime.now().toIso8601String());
              },
            ),
          ));
          if (!mounted) return;
          if (!agreedNow) {
            // 同意せず戻った → 進めない。復旧画面に留まる（袋小路ではない・再試行/戻る可能）。
            setState(() => _isLoading = false);
            return;
          }
        }
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
    // 同意証跡はサーバ真実に一本化: サーバ値が非null/非空の時だけ保存（毎回 now() 上書きを廃止）。
    final serverConsentAt  = data['consent_agreed_at'] as String?;
    final serverConsentVer = data['consent_version']   as String?;
    if (serverConsentAt != null && serverConsentAt.isNotEmpty) {
      await prefs.setString('consent_agreed_at', serverConsentAt);
    }
    if (serverConsentVer != null && serverConsentVer.isNotEmpty) {
      await prefs.setString('consent_version', serverConsentVer);
    }
    // 規約バージョン不一致（サーバ値が非null かつ現行と不一致）の時だけ次回起動で再同意させる。
    // それ以外の理由で consent_agreed を false に戻さない（毎回同意の復活防止）。
    if (serverConsentVer != null && serverConsentVer.isNotEmpty
        && serverConsentVer != _kCurrentConsentVersion) {
      await prefs.setBool('consent_agreed', false);
    }
    await prefs.setBool('is_registered', true);
    // 既存ユーザー救済刻印: サーバが consent_agreed_at=null を返し、かつローカルで同意済みなら、
    // 受領した本token で POST /auth/consent を1回呼びサーバに正式刻印する（fail-open・8秒）。
    // ※ recover-by-code は「既存ユーザーの端末復旧」経路のため救済対象に合致する。
    final localAgreed = prefs.getBool('consent_agreed') ?? false;
    final consentToken = data['token'] as String? ?? '';
    if ((serverConsentAt == null || serverConsentAt.isEmpty)
        && localAgreed && consentToken.isNotEmpty) {
      try {
        final cRes = await http.post(
          Uri.parse('$kApiBaseUrl/auth/consent'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $consentToken',
          },
          body: jsonEncode({'consent_version': _kCurrentConsentVersion}),
        ).timeout(const Duration(seconds: 8));
        if (cRes.statusCode == 200) {
          final cd = jsonDecode(cRes.body) as Map<String, dynamic>;
          final cAt  = cd['consent_agreed_at'] as String?;
          final cVer = cd['consent_version']   as String?;
          if (cAt  != null && cAt.isNotEmpty)  await prefs.setString('consent_agreed_at', cAt);
          if (cVer != null && cVer.isNotEmpty) await prefs.setString('consent_version', cVer);
        }
      } catch (_) { /* fail-open: 失敗は無視（次回ログインで再試行） */ }
    }
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
      style: const TextStyle(color: FieldTokens.textBody),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: FieldTokens.textSupport, fontSize: 13),
        prefixIcon: Icon(icon, color: FieldTokens.textSupport),
        filled: true,
        fillColor: FieldTokens.surfaceRaised,
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
          color: FieldTokens.textBody, fontSize: 24, letterSpacing: 8),
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        counterText: '',
        hintText: '● ● ● ●',
        hintStyle: const TextStyle(
            color: FieldTokens.textHint, letterSpacing: 8),
        filled: true,
        fillColor: FieldTokens.surfaceRaised,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: FieldTokens.accent, width: 2)),
        suffixIcon: IconButton(
          icon: Icon(
              _obscurePin ? Icons.visibility_off : Icons.visibility,
              color: FieldTokens.textSupport),
          onPressed: () => setState(() => _obscurePin = !_obscurePin),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        elevation: 0,
        title: const Text('端末の復旧',
            style: TextStyle(color: FieldTokens.accent, fontSize: 18)),
        // 戻る＝常にランディングへ戻れる（push 元へ pop）
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.phonelink_setup,
                  color: FieldTokens.accent, size: 56),
              const SizedBox(height: 16),
              const Text(
                '機種変更・再インストール後の復旧',
                style: TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '会社コード・作業員ID・PIN を入力すると、\nこの端末を既存の登録に再接続します',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 13, height: 1.6),
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
                  // 生成り抜き（画面内の主ボタン）
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: FieldTokens.textBody,
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor:
                        FieldTokens.textFaint,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ).copyWith(
                    side: WidgetStateProperty.resolveWith((states) =>
                        BorderSide(
                          color: states.contains(WidgetState.disabled)
                              ? FieldTokens.textFaint
                              : FieldTokens.textBody,
                          width: 1.5,
                        )),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          // 面が透明になったのでスピナーも枠色（生成り）へ
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: FieldTokens.textFaint))
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
