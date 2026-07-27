// ============================================================
// lib/screens/profile_screen.dart
// 設定・プロフィール表示 + 編集
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show API_URL, showJsSnackbar;
import '../core/theme/js_colors.dart';
import '../services/profile_service.dart';
import '../config/constants.dart';
import 'consent_view_screen.dart';
import 'privacy_policy_screen.dart';
import 'notification_settings_screen.dart';

// ─── 経験年数 → バッジ色 ───────────────────────────────────
Color experienceColor(int? years) {
  final y = years ?? 0;
  if (y >= 20) return const Color(0xFFCE93D8); // 紫: マスター
  if (y >= 10) return const Color(0xFF4FC3F7); // 青: ベテラン
  if (y >= 3)  return JsColors.gold;           // 金: 中堅
  return const Color(0xFF9E9E9E);              // グレー: 新人
}

String experienceTier(int? years) {
  final y = years ?? 0;
  if (y >= 20) return 'マスター';
  if (y >= 10) return 'ベテラン';
  if (y >= 3)  return '中堅';
  if (y > 0)   return '新人';
  return '';
}

// ─── プロフィールデータモデル ───────────────────────────────
class _ProfileData {
  final String name;
  final String role;
  final String companyName;
  final String homeAddress;
  final String phone;
  final String bloodType;      // 例: "A+", "AB-", ""
  final int? experienceYears;
  final DateTime? healthCheckDate;
  final String? profileImageUrl;
  final String? workerId;
  final String? postalCode;
  final String? emergencyName;
  final String? emergencyRelation;
  final String? emergencyPhone;
  final String? emergencyAddress;

  const _ProfileData({
    required this.name,
    required this.role,
    required this.companyName,
    required this.homeAddress,
    required this.phone,
    required this.bloodType,
    this.experienceYears,
    this.healthCheckDate,
    this.profileImageUrl,
    this.workerId,
    this.postalCode,
    this.emergencyName,
    this.emergencyRelation,
    this.emergencyPhone,
    this.emergencyAddress,
  });

  String get roleLabel {
    switch (role) {
      case 'worker':       return '職人';
      case 'boss':         return '職長';
      case 'admin_office': return '事務';
      case 'admin_exec':   return '管理者';
      default:             return role;
    }
  }

  // 経験年数でworkerのバッジ色が変わる
  Color get badgeColor {
    if (role == 'boss') return const Color(0xFF4FC3F7);
    return experienceColor(experienceYears);
  }
}

// プロフィール写真を data URI(base64) と http(s) URL の両対応で描画
// （BE v433 は data:image/jpeg;base64,... を返す。将来 http URL へ戻る可能性も残す）
Widget _profileAvatarImage(String url, {double iconSize = 48}) {
  final fallback = Icon(Icons.person, color: JsColors.silver, size: iconSize);
  if (url.startsWith('data:image')) {
    try {
      final bytes = Uri.parse(url).data?.contentAsBytes();
      if (bytes == null || bytes.isEmpty) return fallback;
      return Image.memory(bytes, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback);
    } catch (_) {
      return fallback;
    }
  }
  if (url.startsWith('http')) {
    return Image.network(url, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback);
  }
  return fallback;
}

// ─────────────────────────────────────────────
// ProfileScreen — 表示画面
// ─────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  _ProfileData? _profile;
  bool _loading = true;
  String _token = '';
  String _consentDate = '';
  String _consentVersion = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadConsentInfo();
  }

  Future<void> _loadConsentInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('consent_agreed_at') ?? '';
    if (raw.isNotEmpty) {
      final dt = DateTime.parse(raw).toLocal();
      if (mounted) {
        setState(() {
          _consentDate =
              '${dt.year}年${dt.month}月${dt.day}日 '
              '${dt.hour.toString().padLeft(2, '0')}:'
              '${dt.minute.toString().padLeft(2, '0')}';
          _consentVersion = prefs.getString('consent_version') ?? '1.0';
        });
      }
    }
  }

  Future<_ProfileData> _localProfile(SharedPreferences prefs) {
    final hcIso = prefs.getString('health_check_date_iso');
    return Future.value(_ProfileData(
      name:            prefs.getString('user_name')    ?? '',
      role:            prefs.getString('user_role')    ?? 'worker',
      companyName:     prefs.getString('company_name') ?? '',
      homeAddress:     prefs.getString('home_address') ?? '',
      phone:           prefs.getString('profile_phone') ?? '',
      bloodType:       prefs.getString('profile_blood_type') ?? '',
      experienceYears: prefs.getInt('experience_years'),
      healthCheckDate: hcIso != null ? DateTime.tryParse(hcIso) : null,
      workerId:        prefs.getString('worker_id'),
    ));
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final token  = prefs.getString('auth_token') ?? '';
    _token = token;

    final local = await _localProfile(prefs);
    if (mounted) setState(() { _profile = local; _loading = false; });

    try {
      final res = await http.get(
        Uri.parse('$API_URL/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type':  'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        final homeAddr   = data['home_address']   as String? ?? '';
        final phone      = data['phone']           as String? ?? '';
        final bloodType  = data['blood_type']      as String? ?? '';
        final expYears   = data['experience_years'] is int
            ? data['experience_years'] as int
            : (data['experience_years'] != null
                ? int.tryParse(data['experience_years'].toString())
                : null);
        final hcStr      = data['health_check_date'] as String?;
        final hcDate     = hcStr != null ? DateTime.tryParse(hcStr) : null;

        // v433 追加項目
        final serverWorkerId   = data['worker_id']          as String?;
        final postalCode       = data['postal_code']        as String?;
        final emergencyName    = data['emergency_name']     as String?;
        final emergencyRel     = data['emergency_relation'] as String?;
        final emergencyPhone   = data['emergency_phone']    as String?;
        final emergencyAddress = data['emergency_address']  as String?;

        // SharedPreferences にキャッシュ
        if (homeAddr.isNotEmpty)  await prefs.setString('home_address', homeAddr);
        if (phone.isNotEmpty)     await prefs.setString('profile_phone', phone);
        if (bloodType.isNotEmpty) await prefs.setString('profile_blood_type', bloodType);
        if (expYears != null)     await prefs.setInt('experience_years', expYears);
        if (hcDate != null)       await prefs.setString('health_check_date_iso', hcStr!);
        // worker_id はサーバ真実を優先して prefs を上書き（空/nullなら既存値を保持）
        if (serverWorkerId != null && serverWorkerId.isNotEmpty) {
          await prefs.setString('worker_id', serverWorkerId);
        }
        // 顔（role）もサーバ真実を prefs('user_role') へ書き戻す（/gate 用キャッシュを最新化・欠落経路の是正）
        final serverRole = data['role'] as String?;
        if (serverRole != null && serverRole.isNotEmpty) {
          await prefs.setString('user_role', serverRole);
          await prefs.remove('role'); // 旧キー残骸掃除
        }

        setState(() {
          _profile = _ProfileData(
            name:            data['name']             as String? ?? local.name,
            role:            data['role']             as String? ?? local.role,
            companyName:     data['company_name']     as String? ?? local.companyName,
            homeAddress:     homeAddr.isEmpty ? local.homeAddress : homeAddr,
            phone:           phone,
            bloodType:       bloodType,
            experienceYears: expYears ?? local.experienceYears,
            healthCheckDate: hcDate,
            profileImageUrl: data['profile_image_url'] as String?,
            workerId:        (serverWorkerId != null && serverWorkerId.isNotEmpty)
                ? serverWorkerId
                : local.workerId,
            postalCode:        postalCode,
            emergencyName:     emergencyName,
            emergencyRelation: emergencyRel,
            emergencyPhone:    emergencyPhone,
            emergencyAddress:  emergencyAddress,
          );
        });
      }
    } catch (e) {
      debugPrint('プロフィール取得エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(
        title: const Text('設定・プロフィール'),
        actions: [
          if (p != null)
            IconButton(
              icon: const Icon(Icons.edit, color: JsColors.gold),
              tooltip: '編集',
              onPressed: () => _openEdit(p),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
          : p == null
              ? const Center(
                  child: Text('プロフィールを読み込めませんでした',
                      style: TextStyle(color: JsColors.silver)))
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildHeader(p),
                        const SizedBox(height: 24),
                        _buildInfoCard(p),
                        const SizedBox(height: 16),
                        _buildEmergencyCard(p),
                        const SizedBox(height: 16),
                        _ToolKeyCard(token: _token),
                        // 通知設定・プライバシーポリシー・利用規約/同意状況はログアウト直上ブロックへ
                        const SizedBox(height: 16),
                        _buildNotificationSettingsTile(),
                        const SizedBox(height: 12),
                        _buildPrivacyTile(),
                        const SizedBox(height: 12),
                        _buildConsentCard(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 32, 0, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _confirmLogout,
                              icon: const Icon(Icons.logout,
                                  color: Colors.redAccent),
                              label: const Text('ログアウト',
                                  style:
                                      TextStyle(color: Colors.redAccent)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Colors.redAccent),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JsColors.gunmetal,
        title: const Text('ログアウト',
            style: TextStyle(color: JsColors.offWhite)),
        content: const Text('ログアウトしますか？',
            style: TextStyle(color: JsColors.silver)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: JsColors.silver)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ログアウト',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    // 単一の顔の掟: 明示ログアウトで端末アンカーを白紙化させる（BEは device_id 受領時に実行・冪等・常時200）。
    // 通信失敗でもローカルログアウトは絶対にブロックしない（袋小路禁止）。
    final deviceId = prefs.getString('device_id') ?? '';
    if (deviceId.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('$API_URL/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'device_id': deviceId}),
        ).timeout(const Duration(seconds: 5));
      } catch (_) { /* 通信失敗でもローカルログアウトは継続 */ }
    }
    await prefs.setBool('logged_out', true);
    await prefs.remove('auth_token');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_role');
    await prefs.remove('role');
    await prefs.remove('company_id');
    await prefs.remove('work_mode');
    // 勤務設定(みなし)・打刻状態：別ユーザーが同一端末でログインした際の残置を防ぐ
    await prefs.remove('deemed_start');
    await prefs.remove('deemed_end');
    await prefs.remove('break_minutes');
    await prefs.remove('work_checked_in');
    await prefs.remove('work_check_in_time');
    // 勤務区分（業務日スコープ）：別ユーザーへの引き継ぎ防止
    await prefs.remove('shift_type');
    await prefs.remove('shift_business_date');
    // 勤務状態（S5b追補: シフト別2キー）。旧3キーも残置端末のために掃除する。
    await prefs.remove('report_done_day');
    await prefs.remove('report_done_night');
    await prefs.remove('today_date');          // 旧キー（読み捨て済み・残骸掃除）
    await prefs.remove('today_work_status');   // 旧キー（同上）
    await prefs.remove('report_done_shift');   // 旧キー（同上）
    await prefs.remove('today_transport');
    await prefs.remove('today_work_content');
    await prefs.remove('today_parking_fee');
    await prefs.remove('today_overtime_hours');
    await prefs.remove('today_overtime_minutes');
    // 現場の引き継ぎ（裁定A・home_screen.dart _kLastSiteId/_kLastSiteName）：
    // 別ユーザーが前任者の現場をデフォルトで背負わないよう掃除する
    await prefs.remove('last_site_id');
    await prefs.remove('last_site_name');
    // 移動手段のデフォルト復元（home_screen.dart _kLastTransports/_kLastCarType）：同上
    await prefs.remove('last_transports');
    await prefs.remove('last_car_type');
    // ルート結果の鍵付きキャッシュ（home_screen.dart _kRouteCacheKey/_kRouteCacheJson）：
    // 前ユーザーの現場の金額が次ユーザーに見えるのを防ぐ
    await prefs.remove('route_cache_key');
    await prefs.remove('route_cache_json');
    await prefs.remove('last_tab_index_worker');
    await prefs.remove('last_tab_index_foreman');
    // 現行タブキー(v2)：旧キー削除だけでは残置するため追加（home_screen.dart:562/576）
    await prefs.remove('last_tab_index_v2_worker');
    await prefs.remove('last_tab_index_v2_foreman');
    // 日報：未送信キューとキャッシュ履歴（前ユーザーの日報が次ユーザーのトークンで
    // 送信される事故を防ぐ・main.dart _K.pendingReports/_K.reports）
    await prefs.remove('pending_reports');
    await prefs.remove('worker_reports_history');
    // 個人情報：別ユーザーへの引き継ぎ防止（profile_screen 保存/復元系）
    await prefs.remove('emergency_contact_name');
    await prefs.remove('emergency_contact_phone');
    await prefs.remove('profile_phone');
    await prefs.remove('profile_blood_type');
    await prefs.remove('home_address');
    await prefs.remove('work_address');
    await prefs.remove('health_check_date_iso');
    await prefs.remove('experience_years');
    await prefs.remove('worker_id');
    // device_id は削除しない → PINログイン画面へ

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: JsColors.gunmetal,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: 40, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout,
                  color: JsColors.gold, size: 56),
              const SizedBox(height: 20),
              const Text(
                'ログアウトしました',
                style: TextStyle(
                  color: JsColors.textStrong,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'またのご利用をお待ちしています',
                style: TextStyle(
                  color: JsColors.textMid,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JsColors.gold,
                    foregroundColor: JsColors.gunmetal,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('OK',
                      style: TextStyle(
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
          '/login', (route) => false);
    }
  }

  void _openEdit(_ProfileData p) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ProfileEditScreen(
          initial: p,
          onSaved: _loadProfile,
        ),
      ),
    );
  }

  Widget _buildPrivacyTile() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: JsColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JsColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.privacy_tip_outlined,
                color: JsColors.gold, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('法的情報',
                      style: TextStyle(
                          color: JsColors.silver,
                          fontSize: 10,
                          letterSpacing: 0.5)),
                  SizedBox(height: 2),
                  Text('プライバシーポリシー',
                      style: TextStyle(
                          color: JsColors.offWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: JsColors.silver, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSettingsTile() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: JsColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JsColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.notifications_active_outlined,
                color: JsColors.gold, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('通知',
                      style: TextStyle(
                          color: JsColors.silver,
                          fontSize: 10,
                          letterSpacing: 0.5)),
                  SizedBox(height: 2),
                  Text('通知設定',
                      style: TextStyle(
                          color: JsColors.offWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: JsColors.silver, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildConsentCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JsColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user, color: JsColors.gold, size: 16),
              SizedBox(width: 6),
              Text(
                '利用規約・同意状況',
                style: TextStyle(
                  color: JsColors.textStrong,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              Icon(Icons.lock, color: JsColors.textMid, size: 14),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _consentDate.isEmpty ? '同意日時：未取得' : '同意日時：$_consentDate',
            style: const TextStyle(color: JsColors.gold, fontSize: 12),
          ),
          Text(
            _consentVersion.isEmpty ? '' : 'バージョン：$_consentVersion',
            style: const TextStyle(color: JsColors.textMid, fontSize: 11),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConsentViewScreen()),
            ),
            child: const Row(
              children: [
                Text(
                  '同意内容を確認する',
                  style: TextStyle(
                    color: JsColors.silver,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
                Icon(Icons.chevron_right, color: JsColors.silver, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(_ProfileData p) {
    final color = p.badgeColor;
    final tier  = (p.role == 'worker' || p.role == 'boss')
        ? experienceTier(p.experienceYears)
        : '';

    return Column(children: [
      Container(
        width: 90, height: 90,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: JsColors.gunmetal,
          border: Border.all(color: color, width: 2),
        ),
        child: p.profileImageUrl != null
            ? ClipOval(child: _profileAvatarImage(p.profileImageUrl!))
            : const Icon(Icons.person, color: JsColors.silver, size: 48),
      ),
      const SizedBox(height: 12),
      Text(p.name.isEmpty ? '(氏名未設定)' : p.name,
          style: const TextStyle(
              color: JsColors.offWhite, fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      // 役割バッジ（色は経験年数に連動）
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(p.roleLabel,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.bold)),
      ),
      if (tier.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(tier,
            style: TextStyle(
                color: color.withValues(alpha: 0.8), fontSize: 11)),
      ],
    ]);
  }

  Widget _buildInfoCard(_ProfileData p) {
    final hcWarn = _healthWarnText(p.healthCheckDate);

    return Container(
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.divider),
      ),
      child: Column(children: [
        _InfoRow(icon: Icons.business,  label: '会社名',    value: p.companyName),
        const Divider(height: 1, color: JsColors.divider),
        _InfoRow(
          icon: Icons.badge,
          label: '職人ID',
          value: (p.workerId?.isNotEmpty ?? false) ? p.workerId! : '未発行',
        ),
        const Divider(height: 1, color: JsColors.divider),
        _InfoRow(
          icon: Icons.local_post_office_outlined,
          label: '郵便番号',
          value: (p.postalCode?.isNotEmpty ?? false) ? p.postalCode! : '未登録',
        ),
        const Divider(height: 1, color: JsColors.divider),
        _InfoRow(
          icon: Icons.home,
          label: '自宅住所',
          value: p.homeAddress.isEmpty ? '未登録' : p.homeAddress,
        ),
        const Divider(height: 1, color: JsColors.divider),
        _InfoRow(
          icon: Icons.phone,
          label: '連絡先',
          value: p.phone.isEmpty ? '未登録' : p.phone,
        ),
        const Divider(height: 1, color: JsColors.divider),
        _InfoRow(
          icon: Icons.water_drop,
          label: '血液型',
          value: p.bloodType.isEmpty ? '未登録' : p.bloodType,
        ),
        if (p.experienceYears != null) ...[
          const Divider(height: 1, color: JsColors.divider),
          _InfoRow(
            icon: Icons.star,
            label: '職人経験年数',
            value: '${p.experienceYears}年 (${experienceTier(p.experienceYears)})',
            valueColor: p.badgeColor,
          ),
        ],
        const Divider(height: 1, color: JsColors.divider),
        _InfoRow(
          icon: Icons.medical_services,
          label: '健康診断日',
          value: p.healthCheckDate != null
              ? _dateStr(p.healthCheckDate!)
              : '未登録',
          valueColor: hcWarn != null
              ? (hcWarn.startsWith('🔴') ? Colors.red[300]! : Colors.orange[300]!)
              : null,
        ),
        if (hcWarn != null) ...[
          const Divider(height: 1, color: JsColors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(hcWarn,
                style: TextStyle(
                    color: hcWarn.startsWith('🔴')
                        ? Colors.red[300]
                        : Colors.orange[300],
                    fontSize: 12)),
          ),
        ],
      ]),
    );
  }

  // 緊急連絡先（4項目を1カードに集約。DBに emergency 側の郵便番号列は無いため郵便番号は作らない）
  Widget _buildEmergencyCard(_ProfileData p) {
    final name  = p.emergencyName     ?? '';
    final rel   = p.emergencyRelation ?? '';
    final phone = p.emergencyPhone    ?? '';
    final addr  = p.emergencyAddress  ?? '';
    final allEmpty = name.isEmpty && rel.isEmpty && phone.isEmpty && addr.isEmpty;
    final nameLine = rel.isNotEmpty
        ? (name.isNotEmpty ? '$name（$rel）' : '（$rel）')
        : name;
    return Container(
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.contact_phone_outlined, color: JsColors.gold, size: 18),
              SizedBox(width: 12),
              Text('緊急連絡先',
                  style: TextStyle(color: JsColors.silver, fontSize: 11)),
            ]),
            const SizedBox(height: 8),
            if (allEmpty)
              const Text('未登録',
                  style: TextStyle(
                      color: JsColors.offWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w500))
            else ...[
              if (nameLine.isNotEmpty)
                Text(nameLine,
                    style: const TextStyle(
                        color: JsColors.offWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('☎ $phone',
                    style: const TextStyle(
                        color: JsColors.offWhite, fontSize: 13)),
              ],
              if (addr.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(addr,
                    style: const TextStyle(
                        color: JsColors.silver, fontSize: 12)),
              ],
            ],
          ],
        ),
      ),
    );
  }

}

// ─── 健康診断警告テキスト ───
String? _healthWarnText(DateTime? hcDate) {
  if (hcDate == null) return null;
  final next = DateTime(hcDate.year + 1, hcDate.month, hcDate.day);
  final days = next.difference(DateTime.now()).inDays;
  if (days <= 14) return '🔴 健康診断期限まで$days日 — 今すぐ予約を！';
  if (days <= 30) return '🟡 健康診断まで$days日 — 早めに予約を';
  return null;
}

String _dateStr(DateTime d) =>
    '${d.year}年${d.month}月${d.day}日';

// ─── 情報行ウィジェット ───
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, color: JsColors.gold, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: JsColors.silver, fontSize: 11)),
              const SizedBox(height: 3),
              Text(value,
                  style: TextStyle(
                      color: valueColor ?? JsColors.offWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// _ProfileEditScreen — 編集画面
// ─────────────────────────────────────────────
class _ProfileEditScreen extends StatefulWidget {
  const _ProfileEditScreen({
    required this.initial,
    required this.onSaved,
  });
  final _ProfileData initial;
  final VoidCallback onSaved;

  @override
  State<_ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<_ProfileEditScreen> {
  late final _nameCtrl    = TextEditingController(text: widget.initial.name);
  late final _addressCtrl = TextEditingController(text: widget.initial.homeAddress);
  late final _phoneCtrl   = TextEditingController(text: widget.initial.phone);
  late final _expCtrl     = TextEditingController(
      text: widget.initial.experienceYears?.toString() ?? '');

  // 郵便番号
  final _zipCtrl = TextEditingController();
  String? _zipError;
  bool _zipLoading = false;

  // 緊急連絡先
  final _emergencyNameCtrl  = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  // 血液型: ABO部 + RH部に分割
  String _bloodAbo = '';
  String _bloodRh  = '';
  DateTime? _healthCheckDate;

  String? _localImagePath;
  bool _saving     = false;
  bool _gpsLoading = false;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _parseBloodType(widget.initial.bloodType);
    _healthCheckDate = widget.initial.healthCheckDate;
    _loadEmergencyContact();
  }

  Future<void> _loadEmergencyContact() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _emergencyNameCtrl.text  = prefs.getString('emergency_contact_name')  ?? '';
    _emergencyPhoneCtrl.text = prefs.getString('emergency_contact_phone') ?? '';
  }

  void _parseBloodType(String bt) {
    if (bt.isEmpty) return;
    if (bt.endsWith('+') || bt.endsWith('-')) {
      _bloodRh  = bt.substring(bt.length - 1);
      _bloodAbo = bt.substring(0, bt.length - 1);
    } else {
      _bloodAbo = bt;
    }
  }

  String get _bloodTypeValue {
    if (_bloodAbo.isEmpty) return '';
    return '$_bloodAbo$_bloodRh';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _expCtrl.dispose();
    _zipCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: JsColors.gunmetal,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: JsColors.gold),
            title: const Text('カメラで撮影',
                style: TextStyle(color: JsColors.offWhite)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: JsColors.gold),
            title: const Text('フォトライブラリから選択',
                style: TextStyle(color: JsColors.offWhite)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final f = await _imagePicker.pickImage(
        source: source, imageQuality: 70, maxWidth: 400);
    if (f != null && mounted) setState(() => _localImagePath = f.path);
  }

  Future<void> _fetchAddressFromZip() async {
    final zip = _zipCtrl.text.replaceAll('-', '').trim();
    if (zip.length != 7) return;
    setState(() { _zipLoading = true; _zipError = null; });
    try {
      final res = await http.get(
        Uri.parse('https://zipcloud.ibsnet.co.jp/api/search?zipcode=$zip'),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results != null && results.isNotEmpty) {
        final r = results.first as Map<String, dynamic>;
        final addr =
            '${r['address1'] ?? ''}${r['address2'] ?? ''}${r['address3'] ?? ''}';
        setState(() { _addressCtrl.text = addr; _zipLoading = false; });
      } else {
        setState(() { _zipError = '住所が見つかりませんでした'; _zipLoading = false; });
      }
    } catch (_) {
      setState(() { _zipError = '住所が見つかりませんでした'; _zipLoading = false; });
    }
  }

  Future<void> _fetchGpsAddress() async {
    setState(() => _gpsLoading = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) showJsSnackbar(context, '位置情報の権限が必要です', isError: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      final placemarks =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final addr = [
          p.administrativeArea,
          p.locality,
          p.subLocality,
          p.thoroughfare,
          p.subThoroughfare,
        ].where((e) => e != null && e.isNotEmpty).join('');
        setState(() => _addressCtrl.text = addr);
      }
    } catch (e) {
      if (mounted) showJsSnackbar(context, 'GPS取得失敗: $e', isError: true);
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _pickHealthCheckDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _healthCheckDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: JsColors.gold,
            surface: JsColors.gunmetal,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _healthCheckDate = picked);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showJsSnackbar(context, '氏名を入力してください', isError: true);
      return;
    }

    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';

    final expStr = _expCtrl.text.trim();
    final expYears = expStr.isNotEmpty ? int.tryParse(expStr) : null;

    final body = <String, dynamic>{
      'name':             name,
      'home_address':     _addressCtrl.text.trim(),
      'phone':            _phoneCtrl.text.trim(),
      'blood_type':       _bloodTypeValue,
      if (expYears != null) 'experience_years': expYears,
      if (_healthCheckDate != null)
        'health_check_date':
            '${_healthCheckDate!.year.toString().padLeft(4,'0')}-'
            '${_healthCheckDate!.month.toString().padLeft(2,'0')}-'
            '${_healthCheckDate!.day.toString().padLeft(2,'0')}',
    };

    if (_localImagePath != null) {
      try {
        body['profile_image_base64'] =
            base64Encode(await File(_localImagePath!).readAsBytes());
      } catch (e) {
        debugPrint('プロフィール画像エンコード失敗: $e');
        if (mounted) {
          showJsSnackbar(context, '画像の読み込みに失敗しました。別の画像をお試しください。', isError: true);
        }
      }
    }

    try {
      final res = await http.put(
        Uri.parse('$API_URL/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type':  'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      // ローカルキャッシュ更新
      await prefs.setString('user_name',    name);
      await prefs.setString('home_address', _addressCtrl.text.trim());
      await prefs.setString('profile_phone', _phoneCtrl.text.trim());
      await prefs.setString('profile_blood_type', _bloodTypeValue);
      if (expYears != null) await prefs.setInt('experience_years', expYears);
      if (_healthCheckDate != null) {
        await prefs.setString('health_check_date_iso',
            '${_healthCheckDate!.year.toString().padLeft(4,'0')}-'
            '${_healthCheckDate!.month.toString().padLeft(2,'0')}-'
            '${_healthCheckDate!.day.toString().padLeft(2,'0')}');
      }
      await ProfileService().setHomeAddress(_addressCtrl.text.trim());
      await prefs.setString('emergency_contact_name',  _emergencyNameCtrl.text.trim());
      await prefs.setString('emergency_contact_phone', _emergencyPhoneCtrl.text.trim());

      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 204) {
        showJsSnackbar(context, '✅ プロフィールを保存しました');
      } else {
        showJsSnackbar(context, '⚠️ サーバー保存失敗。ローカルのみ保存しました',
            isWarning: true);
      }
      widget.onSaved();
      Navigator.pop(context);
    } catch (e) {
      debugPrint('プロフィール保存エラー: $e');
      await prefs.setString('user_name',    name);
      await prefs.setString('home_address', _addressCtrl.text.trim());
      await prefs.setString('profile_phone', _phoneCtrl.text.trim());
      await prefs.setString('profile_blood_type', _bloodTypeValue);
      if (expYears != null) await prefs.setInt('experience_years', expYears);
      if (_healthCheckDate != null) {
        await prefs.setString('health_check_date_iso',
            '${_healthCheckDate!.year.toString().padLeft(4,'0')}-'
            '${_healthCheckDate!.month.toString().padLeft(2,'0')}-'
            '${_healthCheckDate!.day.toString().padLeft(2,'0')}');
      }
      await ProfileService().setHomeAddress(_addressCtrl.text.trim());
      await prefs.setString('emergency_contact_name',  _emergencyNameCtrl.text.trim());
      await prefs.setString('emergency_contact_phone', _emergencyPhoneCtrl.text.trim());
      if (!mounted) return;
      showJsSnackbar(context, '⚠️ オフライン: ローカルのみ保存しました',
          isWarning: true);
      widget.onSaved();
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(
        title: const Text('プロフィール編集'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: JsColors.gold))
                : const Text('保存',
                    style: TextStyle(
                        color: JsColors.gold, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── プロフィール画像 ───
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 90, height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: JsColors.gunmetal,
                          border: Border.all(color: JsColors.gold, width: 2),
                        ),
                        child: _localImagePath != null
                            ? ClipOval(
                                child: Image.file(
                                    File(_localImagePath!), fit: BoxFit.cover))
                            : widget.initial.profileImageUrl != null
                                ? ClipOval(
                                    child: _profileAvatarImage(
                                        widget.initial.profileImageUrl!),
                                  )
                                : const Icon(Icons.person,
                                    color: JsColors.silver, size: 48),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                            color: JsColors.gold, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt,
                            color: JsPalette.onAccent, size: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text('タップして変更',
                    style: TextStyle(color: JsColors.silver, fontSize: 11)),
              ),
              const SizedBox(height: 28),

              // ─── 氏名 ───
              _fieldLabel('氏名'),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person, color: JsColors.silver),
                  hintText: '例：田中 太郎',
                ),
                style: const TextStyle(color: JsColors.offWhite),
              ),
              const SizedBox(height: 20),

              // ─── 連絡先（電話番号）───
              _fieldLabel('連絡先（電話番号）'),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\-\+\(\)]'))],
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.phone, color: JsColors.silver),
                  hintText: '例：090-1234-5678',
                ),
                style: const TextStyle(color: JsColors.offWhite),
              ),
              const SizedBox(height: 20),

              // ─── 郵便番号 ───
              _fieldLabel('郵便番号（住所自動反映）'),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _zipCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\-]')),
                    ],
                    maxLength: 8,
                    decoration: InputDecoration(
                      prefixIcon: _zipLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: JsColors.gold)))
                          : const Icon(Icons.local_post_office, color: JsColors.silver),
                      hintText: '例：6500000 または 650-0000',
                      counterText: '',
                    ),
                    style: const TextStyle(color: JsColors.offWhite),
                    onChanged: (v) {
                      final digits = v.replaceAll('-', '');
                      if (digits.length == 7) _fetchAddressFromZip();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _zipLoading ? null : _fetchAddressFromZip,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 52),
                  ),
                  child: const Text('検索'),
                ),
              ]),
              if (_zipError != null) ...[
                const SizedBox(height: 4),
                Text(_zipError!,
                    style: const TextStyle(color: JsColors.error, fontSize: 12)),
              ],
              const SizedBox(height: 20),

              // ─── 自宅住所 ───
              _fieldLabel('自宅住所'),
              TextField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.home, color: JsColors.silver),
                  alignLabelWithHint: true,
                  hintText: '例：兵庫県神戸市長田区',
                ),
                style: const TextStyle(color: JsColors.offWhite),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _gpsLoading ? null : _fetchGpsAddress,
                  icon: _gpsLoading
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: JsColors.gold))
                      : const Icon(Icons.location_on, size: 16),
                  label: Text(_gpsLoading ? 'GPS取得中...' : '現在地から自動入力'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ─── 血液型 ───
              _fieldLabel('血液型'),
              Row(children: [
                Expanded(
                  child: _DropdownField<String>(
                    icon: Icons.water_drop,
                    hint: 'ABO型',
                    value: _bloodAbo.isEmpty ? null : _bloodAbo,
                    items: const ['A', 'B', 'O', 'AB'],
                    onChanged: (v) => setState(() => _bloodAbo = v ?? ''),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DropdownField<String>(
                    icon: Icons.add_circle_outline,
                    hint: 'RH型',
                    value: _bloodRh.isEmpty ? null : _bloodRh,
                    items: const ['+', '-'],
                    onChanged: (v) => setState(() => _bloodRh = v ?? ''),
                  ),
                ),
              ]),
              const SizedBox(height: 20),

              // ─── 職人経験年数 ───
              _fieldLabel('職人経験年数'),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _expCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.star, color: JsColors.silver),
                      hintText: '例：10',
                      suffixText: '年',
                      suffixStyle: TextStyle(color: JsColors.silver),
                    ),
                    style: const TextStyle(color: JsColors.offWhite),
                  ),
                ),
                const SizedBox(width: 12),
                // 経験年数プレビューバッジ
                if (_expCtrl.text.isNotEmpty)
                  _ExperienceBadgePreview(years: int.tryParse(_expCtrl.text)),
              ]),
              const SizedBox(height: 20),

              // ─── 緊急連絡先 ───
              _fieldLabel('緊急連絡先 氏名'),
              TextField(
                controller: _emergencyNameCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_pin, color: JsColors.silver),
                  hintText: '例：田中 花子（続柄：妻）',
                ),
                style: const TextStyle(color: JsColors.offWhite),
              ),
              const SizedBox(height: 16),
              _fieldLabel('緊急連絡先 電話番号'),
              TextField(
                controller: _emergencyPhoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\-\+\(\)]')),
                ],
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.phone_in_talk, color: JsColors.silver),
                  hintText: '例：090-9876-5432',
                ),
                style: const TextStyle(color: JsColors.offWhite),
              ),
              const SizedBox(height: 20),

              // ─── 健康診断日 ───
              _fieldLabel('健康診断日'),
              GestureDetector(
                onTap: _pickHealthCheckDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: JsColors.gunmetal,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: JsColors.divider),
                  ),
                  child: Row(children: [
                    const Icon(Icons.medical_services,
                        color: JsColors.silver, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _healthCheckDate != null
                            ? _dateStr(_healthCheckDate!)
                            : '日付を選択してください',
                        style: TextStyle(
                          color: _healthCheckDate != null
                              ? JsColors.offWhite
                              : JsColors.silver,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Icon(Icons.calendar_today,
                        color: JsColors.silver, size: 16),
                  ]),
                ),
              ),
              if (_healthCheckDate != null) ...[
                const SizedBox(height: 8),
                Builder(builder: (ctx) {
                  final warn = _healthWarnText(_healthCheckDate);
                  if (warn == null) return const SizedBox.shrink();
                  return Text(warn,
                      style: TextStyle(
                          color: warn.startsWith('🔴')
                              ? Colors.red[300]
                              : Colors.orange[300],
                          fontSize: 12));
                }),
              ],
              const SizedBox(height: 32),

              // ─── 保存ボタン ───
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: JsPalette.onAccent))
                      : const Text('保存する'),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'v$kAppVersion',
                  style: TextStyle(color: JsColors.textMid, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(color: JsColors.silver, fontSize: 12)),
  );
}

// ─── ドロップダウン共通ウィジェット ───
class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.icon,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final IconData icon;
  final String hint;
  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JsColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: const TextStyle(color: JsColors.silver, fontSize: 14)),
          dropdownColor: JsColors.gunmetal,
          iconEnabledColor: JsColors.silver,
          isExpanded: true,
          items: items.map((e) => DropdownMenuItem<T>(
            value: e,
            child: Text('$e', style: const TextStyle(color: JsColors.offWhite, fontSize: 14)),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── 経験年数プレビューバッジ ───
class _ExperienceBadgePreview extends StatelessWidget {
  const _ExperienceBadgePreview({this.years});
  final int? years;

  @override
  Widget build(BuildContext context) {
    final color = experienceColor(years);
    final tier  = experienceTier(years);
    if (tier.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(tier,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

// ─────────────────────────────────────────────
// J's Tool 連携キー管理カード
// ─────────────────────────────────────────────
class _ToolKeyCard extends StatefulWidget {
  const _ToolKeyCard({required this.token});
  final String token;

  @override
  State<_ToolKeyCard> createState() => _ToolKeyCardState();
}

class _ToolKeyCardState extends State<_ToolKeyCard> {
  String _storedKey = '';
  bool _issuing = false;
  bool _showInput = false;
  final _inputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _storedKey = prefs.getString('tool_key') ?? '');
  }

  Future<void> _issueKey() async {
    setState(() => _issuing = true);
    try {
      final res = await http.post(
        Uri.parse('$API_URL/tool/issue-key'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final key = data['tool_key'] as String? ?? '';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('tool_key', key);
        setState(() {
          _storedKey = key;
          _issuing = false;
        });
        if (mounted) showJsSnackbar(context, '✅ 連携キーを発行しました');
      } else {
        if (mounted) {
          showJsSnackbar(context, 'キー発行に失敗しました（${res.statusCode}）',
              isError: true);
          setState(() => _issuing = false);
        }
      }
    } catch (_) {
      if (mounted) {
        showJsSnackbar(context, 'サーバーに接続できません', isError: true);
        setState(() => _issuing = false);
      }
    }
  }

  Future<void> _saveManualKey() async {
    final key = _inputCtrl.text.trim().toUpperCase();
    if (!RegExp(r'^JS-[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(key)) {
      showJsSnackbar(context, '形式が正しくありません（例：JS-ABCD-1234）',
          isError: true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tool_key', key);
    if (mounted) {
      setState(() {
        _storedKey = key;
        _showInput = false;
        _inputCtrl.clear();
      });
      showJsSnackbar(context, '✅ 連携キーを保存しました');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── ヘッダー行 ───
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(children: [
              const Icon(Icons.build_circle, color: JsColors.gold, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "J's Tool 連携キー",
                  style: TextStyle(
                      color: JsColors.offWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ),
              _issuing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: JsColors.gold))
                  : TextButton(
                      onPressed: _issueKey,
                      style: TextButton.styleFrom(
                          foregroundColor: JsColors.gold,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4)),
                      child: const Text('発行・更新',
                          style: TextStyle(fontSize: 12)),
                    ),
            ]),
          ),
          // ─── キー表示 ───
          const Divider(height: 1, color: JsColors.divider),
          if (_storedKey.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                const Icon(Icons.vpn_key, color: JsColors.silver, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _storedKey,
                    style: const TextStyle(
                        color: JsColors.gold,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _storedKey));
                    showJsSnackbar(context, 'クリップボードにコピーしました');
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.copy, color: JsColors.silver, size: 18),
                  ),
                ),
              ]),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                '未発行 — 「発行・更新」をタップしてキーを取得してください',
                style: TextStyle(color: JsColors.silver, fontSize: 12),
              ),
            ),
          // ─── 手動入力トグル ───
          const Divider(height: 1, color: JsColors.divider),
          InkWell(
            onTap: () => setState(() => _showInput = !_showInput),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 11),
              child: Row(children: [
                const Icon(Icons.edit_note,
                    color: JsColors.silver, size: 16),
                const SizedBox(width: 8),
                const Text('手動でキーを入力',
                    style:
                        TextStyle(color: JsColors.silver, fontSize: 13)),
                const Spacer(),
                Icon(
                    _showInput
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: JsColors.silver,
                    size: 16),
              ]),
            ),
          ),
          if (_showInput) ...[
            const Divider(height: 1, color: JsColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9\-]')),
                      _ToolKeyFormatter(),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'JS-XXXX-YYYY',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      counterText: '',
                    ),
                    style: const TextStyle(color: JsColors.offWhite),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveManualKey,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(56, 40),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: JsColors.gold,
                    foregroundColor: JsPalette.onAccent,
                  ),
                  child: const Text('保存'),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// JS-XXXX-YYYY 形式に自動フォーマット（両アプリ共通）
class _ToolKeyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final clean =
        newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final limited = clean.length > 10 ? clean.substring(0, 10) : clean;
    final sb = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      if (i == 2 || i == 6) sb.write('-');
      sb.write(limited[i]);
    }
    final result = sb.toString();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
