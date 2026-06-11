import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import 'auth_service.dart';

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  static const _channelId   = 'js_fcm';
  static const _channelName = '通知';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit     = DarwinInitializationSettings();
    await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit));

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;
      _showLocal(
        title:     notification.title ?? '',
        body:      notification.body  ?? '',
        messageId: message.messageId,
      );
    });

    FirebaseMessaging.instance.onTokenRefresh.listen(_postToken);
  }

  Future<void> registerToken() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _postToken(token);
    } catch (e) {
      debugPrint('FCM registerToken error: $e');
    }
  }

  Future<void> requestNotificationPermission() async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert:       true,
        badge:       true,
        sound:       true,
        provisional: false,
      );
    } catch (_) {}
  }

  Future<void> _postToken(String token) async {
    try {
      final userId = await AuthService().getUserId();
      if (userId == null || userId.isEmpty) return;
      final headers = await AuthService().getAuthHeaders();
      await http.post(
        Uri.parse('$kApiBaseUrl/workers/$userId/fcm-token'),
        headers: headers,
        body: jsonEncode({'token': token}),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('FCM token post error: $e');
    }
  }

  Future<void> _showLocal({required String title, required String body, String? messageId}) async {
    final notifId = messageId != null
        ? messageId.hashCode.abs() % 2147483647
        : DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
    try {
      await _plugin.show(
        notifId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId, _channelName,
            importance: Importance.high,
            priority:   Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('FCM local show error: $e');
    }
  }
}
