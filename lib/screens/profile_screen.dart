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

import '../main.dart' show JsColors, API_URL, showJsSnackbar;
import '../services/profile_service.dart';

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
    if (role == 'boss')   return const Color(0xFF4FC3F7);
    if (role.startsWith('admin')) return const Color(0xFFEF9A9A);
    return experienceColor(experienceYears);
  }
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

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<_ProfileData> _localProfile(SharedPreferences prefs) {
    final hcIso = prefs.getString('health_check_date_iso');
    return Future.value(_ProfileData(
      name:            prefs.getString('user_name')    ?? '',
      role:            prefs.getString('user_role')    ?? 'worker',
      companyName:     prefs.getString('company_name') ?? '株式会社J\'s',
      homeAddress:     prefs.getString('home_address') ?? '',
      phone:           prefs.getString('profile_phone') ?? '',
      bloodType:       prefs.getString('profile_blood_type') ?? '',
      experienceYears: prefs.getInt('experience_years'),
      healthCheckDate: hcIso != null ? DateTime.tryParse(hcIso) : null,
    ));
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final token  = prefs.getString('auth_token') ?? '';

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

        // SharedPreferences にキャッシュ
        if (homeAddr.isNotEmpty)  await prefs.setString('home_address', homeAddr);
        if (phone.isNotEmpty)     await prefs.setString('profile_phone', phone);
        if (bloodType.isNotEmpty) await prefs.setString('profile_blood_type', bloodType);
        if (expYears != null)     await prefs.setInt('experience_years', expYears);
        if (hcDate != null)       await prefs.setString('health_check_date_iso', hcStr!);

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
          );
        });
      }
    } catch (_) {}
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
                        _buildEditButton(p),
                      ],
                    ),
                  ),
                ),
    );
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
            ? ClipOval(
                child: Image.network(
                  p.profileImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.person, color: JsColors.silver, size: 48),
                ),
              )
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

  Widget _buildEditButton(_ProfileData p) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _openEdit(p),
        icon: const Icon(Icons.edit, size: 16),
        label: const Text('プロフィールを編集する'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
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
                      fontWeight: FontWeight.w500)),
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
      } catch (_) {}
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

      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 204) {
        showJsSnackbar(context, '✅ プロフィールを保存しました');
      } else {
        showJsSnackbar(context, '⚠️ サーバー保存失敗。ローカルのみ保存しました',
            isWarning: true);
      }
      widget.onSaved();
      Navigator.pop(context);
    } catch (_) {
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
                                    child: Image.network(
                                      widget.initial.profileImageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.person,
                                          color: JsColors.silver,
                                          size: 48),
                                    ),
                                  )
                                : const Icon(Icons.person,
                                    color: JsColors.silver, size: 48),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                            color: JsColors.gold, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.black, size: 14),
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

              // ─── 自宅住所 ───
              _fieldLabel('自宅住所'),
              TextField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.home, color: JsColors.silver),
                  alignLabelWithHint: true,
                  hintText: '例：兵庫県神戸市中央区三宮町1丁目',
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
                              strokeWidth: 2.5, color: Colors.black))
                      : const Text('保存する'),
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
