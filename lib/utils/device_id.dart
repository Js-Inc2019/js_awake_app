// lib/utils/device_id.dart - 全プラットフォーム共通の一意 device_id
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 端末を一意に識別する device_id を返す。
///
/// SharedPreferences のキー 'device_id' を再利用し、無ければ UUID v4 を
/// 生成して保存する。プラットフォームでは分岐せず、全端末で UUID を用いる。
Future<String> getDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString('device_id');
  if (existing != null && existing.isNotEmpty) return existing;
  final deviceId = const Uuid().v4();
  await prefs.setString('device_id', deviceId);
  return deviceId;
}
