// lib/utils/device_id.dart - 全プラットフォーム共通の一意 device_id
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:android_id/android_id.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 端末を一意に識別する device_id を返す。
///
/// 取得優先順（再インストールで消えない値を優先・Layer 1）:
///   (a) SharedPreferences に既存 device_id があればそのまま返す（既存登録端末を壊さない・最優先）
///   (b) Android → android_id パッケージで ANDROID_ID を採用
///   (c) iOS     → flutter_secure_storage の 'device_id' を読む。無ければ UUID v4 を生成して保存
///   (d) 採用値を SharedPreferences にもキャッシュしてから返す
///
/// ANDROID_ID が null/空、または対象外プラットフォーム（web/desktop 等）は
/// UUID v4 生成にフォールバックする（袋小路禁止）。
Future<String> getDeviceId() async {
  final prefs = await SharedPreferences.getInstance();

  // (a) 既存 device_id があればそのまま返す（最優先）
  final existing = prefs.getString('device_id');
  if (existing != null && existing.isNotEmpty) return existing;

  String? deviceId;

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    // (b) Android → ANDROID_ID にアプリ固有サフィックスを付与
    //     （同一署名鍵・同一端末でも FIELD/OFFICE の device_id 衝突を防ぐ。SCG32 対策）
    //     null/空判定は生の ANDROID_ID に対して行い、'null-field' 等を作らない。
    try {
      final androidId = await const AndroidId().getId();
      deviceId = (androidId != null && androidId.isNotEmpty)
          ? '$androidId-field'
          : null;
    } catch (_) {
      deviceId = null;
    }
  } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    // (c) iOS → secure_storage の 'device_id'。無ければ UUID v4 生成して保存
    const storage = FlutterSecureStorage();
    deviceId = await storage.read(key: 'device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await storage.write(key: 'device_id', value: deviceId);
    }
  }

  // ANDROID_ID が null/空、または対象外プラットフォーム → UUID v4 フォールバック
  if (deviceId == null || deviceId.isEmpty) {
    deviceId = const Uuid().v4();
  }

  // (d) 採用値を SharedPreferences にキャッシュしてから返す
  await prefs.setString('device_id', deviceId);
  return deviceId;
}
