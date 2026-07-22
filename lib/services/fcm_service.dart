import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../screens/revision_inbox_screen.dart';
import '../screens/notification_list_screen.dart';
import '../screens/home_screen.dart' show ReportTabNavigator;
import 'auth_service.dart';

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  static final navigatorKey = GlobalKey<NavigatorState>();

  static Map<String, dynamic>? pendingTapData;
  static final _ready = Completer<void>();
  static Future<void> get ready => _ready.future;

  static const _channelId   = 'js_fcm';
  static const _channelName = '通知';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (kIsWeb || _initialized) {
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    _initialized = true;

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit     = DarwinInitializationSettings();
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload == null) return;
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            handleNotificationTap(data);
          } catch (_) {}
        },
      );

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
          data:      message.data,
        );
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        handleNotificationTap(message.data);
      });

      FirebaseMessaging.instance.onTokenRefresh.listen(_postToken);

      final initial = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (initial != null) pendingTapData = initial.data;
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
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

  Future<void> handleNotificationTap(Map<String, dynamic> data) async {
    final type = data['type'];
    if (type != 'revision_request' && type != 'report_reminder') return;
    final loggedIn = await AuthService().isLoggedIn();
    if (!loggedIn) return;

    if (type == 'revision_request') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const RevisionInboxScreen()),
      );
    } else {
      // report_reminder → 日報作成画面（JsMainShell 日報タブ index0）へ。
      // ■2 と同一ルート（ReportTabNavigator）。シェル未生成時は通知一覧へフォールバック。
      if (!ReportTabNavigator.go()) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const NotificationListScreen()),
        );
      }
    }
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

  Future<void> _showLocal({
    required String title,
    required String body,
    String? messageId,
    Map<String, dynamic>? data,
  }) async {
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
        payload: data != null ? jsonEncode(data) : null,
      );
    } catch (e) {
      debugPrint('FCM local show error: $e');
    }
  }
}
