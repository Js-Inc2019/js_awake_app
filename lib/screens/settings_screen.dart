// lib/screens/settings_screen.dart - 職人設定画面
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, showJsSnackbar, NotificationManager;
import '../services/auth_service.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _userName = '';
  String _userRole = '';
  bool _biometricEnabled = true;
  bool _biometricAvailable = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final auth = LocalAuthentication();
    final canCheck = await auth.canCheckBiometrics;
    final supported = await auth.isDeviceSupported();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? '';
        _userRole = _roleLabel(prefs.getString('user_role') ?? 'worker');
        _biometricEnabled = prefs.getBool('biometric_enabled') ?? true;
        _biometricAvailable = canCheck && supported;
        _loading = false;
      });
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'boss':       return '職長';
      case 'admin_office': return '事務';
      case 'admin_exec': return '管理者';
      default:           return '職人';
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', value);
    if (mounted) setState(() => _biometricEnabled = value);
    if (mounted) {
      showJsSnackbar(context, value ? '生体認証を有効にしました' : '生体認証を無効にしました');
    }
  }

  void _openNotifSettings() {
    final nm = NotificationManager.instance;
    final current = Set<int>.from(nm.hours);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: JsColors.gunmetal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('通知時刻の設定', style: TextStyle(color: JsColors.gold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView.builder(
              itemCount: 24,
              itemBuilder: (_, i) => CheckboxListTile(
                dense: true,
                title: Text('${i.toString().padLeft(2, '0')}:00',
                    style: const TextStyle(color: JsColors.offWhite)),
                value: current.contains(i),
                activeColor: JsColors.gold,
                checkColor: Colors.black,
                onChanged: (v) => setSt(() {
                  if (v == true) current.add(i); else current.remove(i);
                }),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル', style: TextStyle(color: JsColors.silver)),
            ),
            ElevatedButton(
              onPressed: () async {
                await nm.setHours(current.toList());
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) showJsSnackbar(context, '通知時刻を更新しました');
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _openChangePinDialog() {
    final oldCtrl  = TextEditingController();
    final newCtrl  = TextEditingController();
    final confCtrl = TextEditingController();
    bool obscOld = true, obscNew = true, obscConf = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: JsColors.gunmetal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('PIN変更', style: TextStyle(color: JsColors.gold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PinField(
                ctrl: oldCtrl,
                label: '現在のPIN',
                obscure: obscOld,
                onToggle: () => setSt(() => obscOld = !obscOld),
              ),
              const SizedBox(height: 12),
              _PinField(
                ctrl: newCtrl,
                label: '新しいPIN（6桁）',
                obscure: obscNew,
                onToggle: () => setSt(() => obscNew = !obscNew),
              ),
              const SizedBox(height: 12),
              _PinField(
                ctrl: confCtrl,
                label: '新しいPIN（確認）',
                obscure: obscConf,
                onToggle: () => setSt(() => obscConf = !obscConf),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル', style: TextStyle(color: JsColors.silver)),
            ),
            ElevatedButton(
              onPressed: () async {
                final oldPin  = oldCtrl.text.trim();
                final newPin  = newCtrl.text.trim();
                final confPin = confCtrl.text.trim();
                if (oldPin.isEmpty || newPin.isEmpty) {
                  showJsSnackbar(context, 'PINを入力してください', isError: true);
                  return;
                }
                if (newPin.length != 6 || int.tryParse(newPin) == null) {
                  showJsSnackbar(context, '新しいPINは6桁の数字で入力してください', isError: true);
                  return;
                }
                if (newPin != confPin) {
                  showJsSnackbar(context, '新しいPINが一致しません', isError: true);
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx);
                final ok = await AuthService().changePin(
                  oldPin: oldPin, newPin: newPin,
                );
                if (mounted) {
                  if (ok) {
                    showJsSnackbar(context, 'PINを変更しました');
                  } else {
                    showJsSnackbar(context,
                        AuthService().lastError ?? 'PIN変更に失敗しました',
                        isError: true);
                  }
                }
              },
              child: const Text('変更する'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JsColors.gunmetal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ログアウト', style: TextStyle(color: JsColors.error)),
        content: const Text('ログアウトすると次回起動時に再認証が必要になります。',
            style: TextStyle(color: JsColors.offWhite, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル', style: TextStyle(color: JsColors.silver)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: JsColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await AuthService().logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_id');
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(title: const Text('設定')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                // ── ユーザー情報 ───────────────────────────────
                _UserCard(name: _userName, role: _userRole),
                const SizedBox(height: 8),

                // ── アカウント ─────────────────────────────────
                _SectionHeader('アカウント'),
                _SettingsTile(
                  icon: Icons.person_outline,
                  title: 'プロフィール・自宅住所',
                  subtitle: '自宅住所・情報変更申請',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen())),
                ),
                _SettingsTile(
                  icon: Icons.lock_outline,
                  title: 'PIN変更',
                  subtitle: '現在のPINから新しいPINに変更',
                  onTap: _openChangePinDialog,
                ),

                // ── セキュリティ ───────────────────────────────
                _SectionHeader('セキュリティ'),
                if (_biometricAvailable)
                  _SettingsSwitchTile(
                    icon: Icons.fingerprint,
                    title: '生体認証',
                    subtitle: 'FaceID / TouchIDでのログイン',
                    value: _biometricEnabled,
                    onChanged: _toggleBiometric,
                  ),

                // ── 通知 ───────────────────────────────────────
                _SectionHeader('通知'),
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: '日報リマインダー',
                  subtitle: '通知時刻を設定する',
                  trailing: Text(
                    NotificationManager.instance.hours.isEmpty
                        ? 'OFF'
                        : NotificationManager.instance.hours
                            .map((h) => '${h.toString().padLeft(2, '0')}:00')
                            .join(', '),
                    style: const TextStyle(color: JsColors.silver, fontSize: 12),
                  ),
                  onTap: _openNotifSettings,
                ),

                // ── ログアウト ─────────────────────────────────
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, color: JsColors.error),
                    label: const Text('ログアウト',
                        style: TextStyle(color: JsColors.error)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: JsColors.error),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                const Center(
                  child: Text("J's Awake App v1.1.1",
                      style: TextStyle(color: JsColors.silver, fontSize: 11)),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

// ─── ユーザー情報カード ──────────────────────────────────────

class _UserCard extends StatelessWidget {
  const _UserCard({required this.name, required this.role});
  final String name, role;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: JsColors.gunmetal,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JsColors.divider),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: JsColors.gold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: JsColors.gold),
            ),
            child: const Icon(Icons.person, color: JsColors.gold, size: 28),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? '―' : name,
                style: const TextStyle(
                    color: JsColors.offWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(role,
                style: const TextStyle(color: JsColors.silver, fontSize: 12)),
          ]),
        ]),
      );
}

// ─── セクションヘッダー ──────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: const TextStyle(
                color: JsColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8)),
      );
}

// ─── 設定タイル ─────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        tileColor: JsColors.gunmetal,
        leading: Icon(icon, color: JsColors.gold, size: 22),
        title: Text(title,
            style: const TextStyle(color: JsColors.offWhite, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: const TextStyle(color: JsColors.silver, fontSize: 11))
            : null,
        trailing: trailing ??
            const Icon(Icons.chevron_right, color: JsColors.silver, size: 20),
        onTap: onTap,
      );
}

// ─── Switch付き設定タイル ────────────────────────────────────

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        tileColor: JsColors.gunmetal,
        secondary: Icon(icon, color: JsColors.gold, size: 22),
        title: Text(title,
            style: const TextStyle(color: JsColors.offWhite, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: const TextStyle(color: JsColors.silver, fontSize: 11))
            : null,
        value: value,
        onChanged: onChanged,
        activeColor: JsColors.gold,
        activeTrackColor: JsColors.gold.withValues(alpha: 0.3),
      );
}

// ─── PINフィールド ───────────────────────────────────────────

class _PinField extends StatelessWidget {
  const _PinField({
    required this.ctrl,
    required this.label,
    required this.obscure,
    required this.onToggle,
  });
  final TextEditingController ctrl;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        style: const TextStyle(
            color: JsColors.offWhite, fontSize: 20, letterSpacing: 8),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: JsColors.silver, fontSize: 13),
          filled: true,
          fillColor: JsColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: JsColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: JsColors.gold, width: 2),
          ),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                color: JsColors.silver, size: 20),
            onPressed: onToggle,
          ),
        ),
      );
}
