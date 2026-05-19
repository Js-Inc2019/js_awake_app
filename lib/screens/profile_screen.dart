// ============================================================
// lib/screens/profile_screen.dart - プロフィール画面
// 自宅住所登録・移動方法設定
// ============================================================

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/profile_service.dart';

const String API_URL = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

class JsColors {
  static const black    = Color(0xFF111111);
  static const gunmetal = Color(0xFF2A2A2A);
  static const gold     = Color(0xFFD4AF37);
  static const silver   = Color(0xFF9E9E9E);
  static const offWhite = Color(0xFFF5F5F0);
  static const surface  = Color(0xFF1E1E1E);
  static const divider  = Color(0xFF3A3A3A);
  static const success  = Color(0xFF2E7D5E);
}

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
      var status = await Permission.location.status;
      if (!status.isGranted) status = await Permission.location.request();
      if (!status.isGranted) {
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
                          style: TextStyle(
                            color: JsColors.silver,
                            fontSize: 12,
                          )),
                      const SizedBox(height: 8),
                      Text(_currentHomeAddress!,
                          style: const TextStyle(
                            color: JsColors.offWhite,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          )),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}