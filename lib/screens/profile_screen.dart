// ============================================================
// lib/screens/profile_screen.dart - プロフィール画面
// 自宅住所登録・移動方法設定
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, API_URL;
import '../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _service = ProfileService();
  final _homeAddressCtrl = TextEditingController();
  
  String? _currentHomeAddress;
  bool _isLoadingGps = false;

  @override
  void initState() {
    super.initState();
    _loadHomeAddress();
  }

  Future<void> _loadHomeAddress() async {
    final addr = await _service.getHomeAddress();
    setState(() => _currentHomeAddress = addr);
    if (addr != null) _homeAddressCtrl.text = addr;
  }

  Future<void> _fetchHomeLocationGps() async {
    setState(() => _isLoadingGps = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('位置情報の権限が必要です'), backgroundColor: Colors.red)
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.administrativeArea,
          p.locality,
          p.subLocality,
          p.thoroughfare,
          p.subThoroughfare,
        ].where((e) => e != null && e.isNotEmpty).toList();
        
        final address = parts.join('');
        if (mounted) {
          setState(() {
            _homeAddressCtrl.text = address;
            _currentHomeAddress = address;
          });
          await _service.setHomeAddress(address);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('自宅住所: $address'), backgroundColor: Colors.green)
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS取得失敗: $e'), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  Future<void> _saveHomeAddress() async {
    final addr = _homeAddressCtrl.text.trim();
    if (addr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('住所を入力してください'), backgroundColor: Colors.red)
      );
      return;
    }
    await _service.setHomeAddress(addr);
    setState(() => _currentHomeAddress = addr);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ 自宅住所を保存しました: $addr'), backgroundColor: Colors.green)
      );
    }
  }

  @override
  void dispose() {
    _homeAddressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(
        title: const Text('プロフィール'),
        backgroundColor: JsColors.black,
        foregroundColor: JsColors.gold,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('自宅住所',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: JsColors.gold,
                  )),
              const SizedBox(height: 16),

              TextField(
                controller: _homeAddressCtrl,
                decoration: InputDecoration(
                  labelText: '自宅住所を入力',
                  prefixIcon: const Icon(Icons.home, color: JsColors.silver),
                  filled: true,
                  fillColor: JsColors.gunmetal,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: JsColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: JsColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: JsColors.gold, width: 2),
                  ),
                ),
                style: const TextStyle(color: JsColors.offWhite),
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoadingGps ? null : _fetchHomeLocationGps,
                      icon: Icon(_isLoadingGps ? Icons.refresh : Icons.location_on),
                      label: Text(_isLoadingGps ? '取得中...' : 'GPS取得'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JsColors.gold,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveHomeAddress,
                      icon: const Icon(Icons.check),
                      label: const Text('保存'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JsColors.success,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ),
                ],
              ),

              if (_currentHomeAddress != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: JsColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: JsColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('現在の自宅住所',
                          style: TextStyle(color: JsColors.silver, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(_currentHomeAddress!,
                          style: const TextStyle(
                              color: JsColors.offWhite,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),
              const Divider(color: JsColors.divider),
              const SizedBox(height: 16),

              // ── 情報変更申請 ──────────────────────────────────
              const Text('情報変更申請',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: JsColors.gold)),
              const SizedBox(height: 8),
              const Text('住所・連絡先・緊急連絡先の変更は事務担当者への申請が必要です。\n承認後に反映されます。',
                  style: TextStyle(color: JsColors.silver, fontSize: 12, height: 1.5)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showChangeRequestDialog(context),
                icon: const Icon(Icons.edit_note),
                label: const Text('変更申請を送る'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JsColors.gold,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showChangeRequestDialog(BuildContext context) async {
    final addrCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    final eName     = TextEditingController();
    final eRel      = TextEditingController();
    final eAddr     = TextEditingController();
    final ePhone    = TextEditingController();
    final reasonCtrl = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JsColors.gunmetal,
        title: const Text('情報変更申請', style: TextStyle(color: JsColors.gold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dlgField(addrCtrl,  '新しい住所（変更する場合）'),
            const SizedBox(height: 8),
            _dlgField(phoneCtrl, '新しい電話番号（変更する場合）',
                keyboard: TextInputType.phone),
            const SizedBox(height: 16),
            const Text('緊急連絡先',
                style: TextStyle(color: JsColors.gold, fontSize: 13,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _dlgField(eName,  '緊急連絡先 氏名'),
            const SizedBox(height: 8),
            _dlgField(eRel,   '続柄（例：妻）'),
            const SizedBox(height: 8),
            _dlgField(eAddr,  '緊急連絡先 住所'),
            const SizedBox(height: 8),
            _dlgField(ePhone, '緊急連絡先 電話',
                keyboard: TextInputType.phone),
            const SizedBox(height: 16),
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

    if (submitted != true || !mounted) return;

    if (reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('変更理由を入力してください'),
          backgroundColor: JsColors.error));
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final body  = <String, String>{};
      if (addrCtrl.text.trim().isNotEmpty)  body['address']            = addrCtrl.text.trim();
      if (phoneCtrl.text.trim().isNotEmpty) body['phone']              = phoneCtrl.text.trim();
      if (eName.text.trim().isNotEmpty)     body['emergency_name']     = eName.text.trim();
      if (eRel.text.trim().isNotEmpty)      body['emergency_relation'] = eRel.text.trim();
      if (eAddr.text.trim().isNotEmpty)     body['emergency_address']  = eAddr.text.trim();
      if (ePhone.text.trim().isNotEmpty)    body['emergency_phone']    = ePhone.text.trim();
      body['reason'] = reasonCtrl.text.trim();

      final res = await http.post(
        Uri.parse('$API_URL/workers/self-change-request'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ 変更申請を送信しました。担当者確認後に反映されます。'),
            backgroundColor: JsColors.success));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('送信失敗: ${res.statusCode}'),
            backgroundColor: JsColors.error));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: const OutlineInputBorder(),
          enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: JsColors.divider)),
          focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: JsColors.gold, width: 2)),
        ),
      );
}