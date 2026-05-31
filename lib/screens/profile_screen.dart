// lib/screens/profile_screen.dart - プロフィール画面（完全版）
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, API_URL, showJsSnackbar;
import '../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _service = ProfileService();

  // 自宅住所（通勤ルート計算用・ローカル保存）
  final _homeAddressCtrl = TextEditingController();
  bool _isLoadingGps = false;

  // プロフィール API フィールド
  final _postalCtrl       = TextEditingController();
  final _addressCtrl      = TextEditingController();
  final _emgNameCtrl      = TextEditingController();
  final _emgRelCtrl       = TextEditingController();
  final _emgPhoneCtrl     = TextEditingController();
  final _emgAddressCtrl   = TextEditingController();

  String? _bloodType;
  DateTime? _birthDate;
  DateTime? _healthCheckDate;
  bool _profileLoading = true;
  bool _profileSaving = false;
  bool _postalLoading = false;

  static const _bloodTypes = ['A', 'B', 'O', 'AB'];

  @override
  void initState() {
    super.initState();
    _loadHomeAddress();
    _loadProfile();
  }

  @override
  void dispose() {
    _homeAddressCtrl.dispose();
    _postalCtrl.dispose();
    _addressCtrl.dispose();
    _emgNameCtrl.dispose();
    _emgRelCtrl.dispose();
    _emgPhoneCtrl.dispose();
    _emgAddressCtrl.dispose();
    super.dispose();
  }

  // ─── 自宅住所（ローカル） ─────────────────────────────────

  Future<void> _loadHomeAddress() async {
    final addr = await _service.getHomeAddress();
    if (mounted && addr != null) {
      setState(() => _homeAddressCtrl.text = addr);
    }
  }

  Future<void> _fetchHomeLocationGps() async {
    setState(() => _isLoadingGps = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) showJsSnackbar(context, '位置情報の権限が必要です', isError: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.administrativeArea, p.locality, p.subLocality,
                       p.thoroughfare, p.subThoroughfare]
            .where((e) => e != null && e.isNotEmpty).toList();
        final address = parts.join('');
        if (mounted) {
          setState(() => _homeAddressCtrl.text = address);
          await _service.setHomeAddress(address);
          showJsSnackbar(context, 'GPS から自宅住所を取得しました');
        }
      }
    } catch (e) {
      if (mounted) showJsSnackbar(context, 'GPS取得失敗: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  Future<void> _saveHomeAddress() async {
    final addr = _homeAddressCtrl.text.trim();
    if (addr.isEmpty) {
      showJsSnackbar(context, '住所を入力してください', isError: true);
      return;
    }
    await _service.setHomeAddress(addr);
    if (mounted) showJsSnackbar(context, '自宅住所を保存しました');
  }

  // ─── プロフィール API ────────────────────────────────────

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http.get(
        Uri.parse('$API_URL/workers/me'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['profile'] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _postalCtrl.text     = data['postal_code'] as String? ?? '';
            _addressCtrl.text    = data['address'] as String? ?? '';
            _bloodType           = data['blood_type'] as String?;
            _emgNameCtrl.text    = data['emergency_name'] as String? ?? '';
            _emgRelCtrl.text     = data['emergency_relation'] as String? ?? '';
            _emgPhoneCtrl.text   = data['emergency_phone'] as String? ?? '';
            _emgAddressCtrl.text = data['emergency_address'] as String? ?? '';
            final bd = data['birth_date'] as String?;
            if (bd != null) _birthDate = DateTime.tryParse(bd);
            final hd = data['health_check_date'] as String?;
            if (hd != null) _healthCheckDate = DateTime.tryParse(hd);
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _profileLoading = false);
  }

  Future<void> _saveProfile() async {
    setState(() => _profileSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final body = <String, dynamic>{
        'blood_type':         _bloodType,
        'birth_date':         _birthDate?.toIso8601String().substring(0, 10),
        'health_check_date':  _healthCheckDate?.toIso8601String().substring(0, 10),
        'postal_code':        _postalCtrl.text.trim().isEmpty ? null : _postalCtrl.text.trim(),
        'address':            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'emergency_name':     _emgNameCtrl.text.trim().isEmpty ? null : _emgNameCtrl.text.trim(),
        'emergency_relation': _emgRelCtrl.text.trim().isEmpty ? null : _emgRelCtrl.text.trim(),
        'emergency_phone':    _emgPhoneCtrl.text.trim().isEmpty ? null : _emgPhoneCtrl.text.trim(),
        'emergency_address':  _emgAddressCtrl.text.trim().isEmpty ? null : _emgAddressCtrl.text.trim(),
      };
      final res = await http.put(
        Uri.parse('$API_URL/workers/me'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      if (mounted) {
        if (res.statusCode == 200) {
          showJsSnackbar(context, 'プロフィールを保存しました');
        } else {
          final err = jsonDecode(res.body)['error'] as String? ?? '保存失敗';
          showJsSnackbar(context, err, isError: true);
        }
      }
    } catch (e) {
      if (mounted) showJsSnackbar(context, 'エラー: $e', isError: true);
    } finally {
      if (mounted) setState(() => _profileSaving = false);
    }
  }

  // ─── 郵便番号→住所（zipcloud） ────────────────────────────

  Future<void> _lookupPostalCode() async {
    final code = _postalCtrl.text.trim().replaceAll('-', '');
    if (code.length != 7 || int.tryParse(code) == null) {
      showJsSnackbar(context, '郵便番号は7桁で入力してください', isWarning: true);
      return;
    }
    setState(() => _postalLoading = true);
    try {
      final res = await http.get(
        Uri.parse('https://zipcloud.ibsnet.co.jp/api/search?zipcode=$code'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final r = results[0];
          final address =
              '${r['address1'] ?? ''}${r['address2'] ?? ''}${r['address3'] ?? ''}';
          if (mounted) {
            setState(() => _addressCtrl.text = address);
            showJsSnackbar(context, '住所を取得しました');
          }
        } else {
          if (mounted) showJsSnackbar(context, '該当する住所が見つかりません', isWarning: true);
        }
      }
    } catch (e) {
      if (mounted) showJsSnackbar(context, '住所取得失敗: $e', isError: true);
    } finally {
      if (mounted) setState(() => _postalLoading = false);
    }
  }

  // ─── 日付ピッカー ────────────────────────────────────────

  Future<DateTime?> _pickDate({DateTime? initial, DateTime? firstDate, DateTime? lastDate}) async {
    return showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: firstDate ?? DateTime(1920),
      lastDate: lastDate ?? DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: JsColors.gold,
            surface: JsColors.gunmetal,
            onSurface: JsColors.offWhite,
          ),
        ),
        child: child!,
      ),
    );
  }

  // ─── 変更申請ダイアログ ──────────────────────────────────

  Future<void> _showChangeRequestDialog() async {
    final addrCtrl   = TextEditingController();
    final phoneCtrl  = TextEditingController();
    final reasonCtrl = TextEditingController();
    final messenger  = ScaffoldMessenger.of(context);

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JsColors.gunmetal,
        title: const Text('情報変更申請', style: TextStyle(color: JsColors.gold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('氏名・電話番号の変更は事務担当者への申請が必要です。',
                style: TextStyle(color: JsColors.silver, fontSize: 12, height: 1.4)),
            const SizedBox(height: 12),
            _dlgField(addrCtrl, '新しい住所（変更する場合）'),
            const SizedBox(height: 8),
            _dlgField(phoneCtrl, '新しい電話番号', keyboard: TextInputType.phone),
            const SizedBox(height: 8),
            _dlgField(reasonCtrl, '変更理由（必須）'),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル', style: TextStyle(color: JsColors.silver)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('申請する'),
          ),
        ],
      ),
    );
    if (submitted != true) return;
    if (reasonCtrl.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('変更理由を入力してください'),
          backgroundColor: JsColors.error));
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final body = <String, String>{'reason': reasonCtrl.text.trim()};
      if (addrCtrl.text.trim().isNotEmpty)  body['address'] = addrCtrl.text.trim();
      if (phoneCtrl.text.trim().isNotEmpty) body['phone']   = phoneCtrl.text.trim();
      final res = await http.post(
        Uri.parse('$API_URL/workers/self-change-request'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        messenger.showSnackBar(const SnackBar(
            content: Text('変更申請を送信しました。担当者確認後に反映されます。'),
            backgroundColor: JsColors.success));
      } else {
        messenger.showSnackBar(SnackBar(
            content: Text('送信失敗: ${res.statusCode}'),
            backgroundColor: JsColors.error));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('エラー: $e'), backgroundColor: JsColors.error));
    }
  }

  Widget _dlgField(TextEditingController ctrl, String label,
      {TextInputType? keyboard}) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(color: JsColors.offWhite, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: JsColors.silver, fontSize: 12),
          filled: true,
          fillColor: JsColors.surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: const OutlineInputBorder(),
          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: JsColors.divider)),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: JsColors.gold, width: 2)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(title: const Text('プロフィール')),
      body: _profileLoading
          ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── 自宅住所（ローカル保存・通勤ルート用） ──────────────
                  _sectionHeader('自宅住所', Icons.home_outlined),
                  const Text('通勤ルート計算に使用します。デバイス内に保存されます。',
                      style: TextStyle(color: JsColors.silver, fontSize: 11, height: 1.4)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _homeAddressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '自宅住所',
                      prefixIcon: Icon(Icons.home, color: JsColors.silver),
                    ),
                    style: const TextStyle(color: JsColors.offWhite),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoadingGps ? null : _fetchHomeLocationGps,
                        icon: Icon(_isLoadingGps ? Icons.refresh : Icons.location_on, size: 16),
                        label: Text(_isLoadingGps ? '取得中...' : 'GPS取得'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveHomeAddress,
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('保存'),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),
                  const Divider(color: JsColors.divider),
                  const SizedBox(height: 16),

                  // ── 個人情報（API保存） ────────────────────────────────
                  _sectionHeader('個人情報', Icons.person_outline),
                  const Text('血液型・生年月日・健診日はサーバーに保存されます。',
                      style: TextStyle(color: JsColors.silver, fontSize: 11, height: 1.4)),
                  const SizedBox(height: 16),

                  // 血液型
                  _label('血液型'),
                  const SizedBox(height: 8),
                  Row(children: _bloodTypes.map((t) {
                    final sel = _bloodType == t;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _bloodType = sel ? null : t),
                        child: Container(
                          width: 56,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: sel ? JsColors.gold : JsColors.gunmetal,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: sel ? JsColors.gold : JsColors.divider),
                          ),
                          child: Center(
                            child: Text(t,
                                style: TextStyle(
                                    color: sel ? Colors.black : JsColors.offWhite,
                                    fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                          ),
                        ),
                      ),
                    );
                  }).toList()),
                  const SizedBox(height: 16),

                  // 生年月日
                  _DateField(
                    label: '生年月日',
                    value: _birthDate,
                    onTap: () async {
                      final d = await _pickDate(initial: _birthDate ?? DateTime(1990));
                      if (d != null && mounted) setState(() => _birthDate = d);
                    },
                    onClear: () => setState(() => _birthDate = null),
                  ),
                  const SizedBox(height: 12),

                  // 健康診断日
                  _DateField(
                    label: '最終健康診断日',
                    value: _healthCheckDate,
                    onTap: () async {
                      final d = await _pickDate(initial: _healthCheckDate);
                      if (d != null && mounted) setState(() => _healthCheckDate = d);
                    },
                    onClear: () => setState(() => _healthCheckDate = null),
                  ),

                  const SizedBox(height: 24),
                  const Divider(color: JsColors.divider),
                  const SizedBox(height: 16),

                  // ── 住所（郵便番号→自動入力） ──────────────────────────
                  _sectionHeader('登録住所', Icons.location_city_outlined),
                  const SizedBox(height: 12),

                  // 郵便番号
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _postalCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(7),
                        ],
                        decoration: const InputDecoration(
                          labelText: '郵便番号（7桁）',
                          prefixIcon: Icon(Icons.local_post_office, color: JsColors.silver),
                          hintText: '1234567',
                        ),
                        style: const TextStyle(color: JsColors.offWhite),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _postalLoading ? null : _lookupPostalCode,
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(72, 52)),
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

                  const SizedBox(height: 24),
                  const Divider(color: JsColors.divider),
                  const SizedBox(height: 16),

                  // ── 緊急連絡先 ─────────────────────────────────────────
                  _sectionHeader('緊急連絡先', Icons.emergency_outlined),
                  const SizedBox(height: 12),
                  _formField(_emgNameCtrl,    '氏名',   Icons.person),
                  const SizedBox(height: 10),
                  _formField(_emgRelCtrl,     '続柄（例：妻）', Icons.family_restroom),
                  const SizedBox(height: 10),
                  _formField(_emgPhoneCtrl,   '電話番号', Icons.phone,
                      keyboard: TextInputType.phone),
                  const SizedBox(height: 10),
                  _formField(_emgAddressCtrl, '住所',    Icons.location_on, maxLines: 2),

                  const SizedBox(height: 28),

                  // 保存ボタン
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _profileSaving ? null : _saveProfile,
                      icon: _profileSaving
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(_profileSaving ? '保存中...' : 'プロフィールを保存'),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 変更申請ボタン（氏名・電話番号は申請必要）
                  OutlinedButton.icon(
                    onPressed: _showChangeRequestDialog,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('氏名・電話番号の変更申請'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, color: JsColors.gold, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  color: JsColors.gold, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _label(String text) =>
      Text(text, style: const TextStyle(color: JsColors.silver, fontSize: 13));

  Widget _formField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboard, int maxLines = 1}) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: const TextStyle(color: JsColors.offWhite),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: JsColors.silver),
          alignLabelWithHint: maxLines > 1,
        ),
      );
}

// ─── 日付フィールドウィジェット ──────────────────────────────

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  String _fmt(DateTime d) =>
      '${d.year}年${d.month.toString().padLeft(2, '0')}月${d.day.toString().padLeft(2, '0')}日';

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
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
                value != null ? _fmt(value!) : label,
                style: TextStyle(
                    color: value != null ? JsColors.offWhite : const Color(0xFF666666),
                    fontSize: 14),
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, color: JsColors.silver, size: 18),
              )
            else
              const Icon(Icons.chevron_right, color: JsColors.silver, size: 18),
          ]),
        ),
      );
}
