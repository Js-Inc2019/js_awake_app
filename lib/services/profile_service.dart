// // ============================================================
// lib/services/profile_service.dart - ユーザープロフィール管理
// 自宅住所・個人設定
// ============================================================

import 'package:shared_preferences/shared_preferences.dart';

const String API_URL = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();

  factory ProfileService() {
    return _instance;
  }

  ProfileService._internal();

  //  自宅住所を保存
  Future<void> setHomeAddress(String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_address', address);
  }

  // 自宅住所を取得
  Future<String?> getHomeAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('home_address');
  }

  // 現場住所を保存
  Future<void> setWorkAddress(String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('work_address', address);
  }

  // 現場住所を取得
  Future<String?> getWorkAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('work_address');
  }
}