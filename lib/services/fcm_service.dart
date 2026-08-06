import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../screens/revision_inbox_screen.dart';
import '../screens/notification_list_screen.dart';
import '../screens/home_screen.dart'
    show ReportTabNavigator, PunchRemindDialogNavigator;
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
          if (payload == null) {
            debugPrint('FCM tap: local notification payload is null — no navigation');
            return;
          }
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            handleNotificationTap(data);
          } catch (e) {
            debugPrint('FCM tap: payload decode failed — no navigation: $e');
          }
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
        if (notification == null) {
          // data-only メッセージ。表示するものが無いので何も出ない（＝仕様）。
          debugPrint('FCM onMessage: notification block is null (data-only) — nothing shown');
          return;
        }
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

      var initialTimedOut = false;
      final initial = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 10), onTimeout: () {
        initialTimedOut = true;
        return null;
      });
      if (initialTimedOut) {
        // 「コールド起動タップ無し」と区別が付かないまま10秒待って諦めた状態。
        debugPrint('FCM init: getInitialMessage timed out after 10s — cold-start tap (if any) is lost');
      }
      if (initial != null) pendingTapData = initial.data;
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  // ─── iOS: APNs トークンの到着待ち ──────────────────────────────
  // iOS では FCM トークンは APNs トークンの上に発行される。APNs 登録が
  // 済む前に getToken() を呼ぶと null か例外になり、以後トークンが
  // BE に載らない＝「無言で通知が来ない」状態になる（沈黙障害）。
  // そこで getToken() の前に getAPNSToken() を待つ。
  //   ・null の間は 500ms 間隔でリトライ、上限 20 回（＝約10秒）
  //   ・上限到達しても例外は投げず、debugPrint で明示して先へ進む（fail-soft）
  // Android はこの経路を一切通らない（呼び出し側で Platform.isIOS 分岐）。
  static const _apnsMaxAttempts = 20;
  static const _apnsInterval    = Duration(milliseconds: 500);

  Future<String?> _awaitApnsToken() async {
    for (var i = 1; i <= _apnsMaxAttempts; i++) {
      String? apns;
      try {
        apns = await FirebaseMessaging.instance.getAPNSToken();
      } catch (e) {
        // 取得自体が投げるケース（未登録・権限未確定など）。握り潰さず出す。
        debugPrint('FCM getAPNSToken threw (attempt $i/$_apnsMaxAttempts): $e');
        apns = null;
      }
      if (apns != null && apns.isNotEmpty) {
        // ★秘匿: APNs トークンの生値は出さない。長さと試行回数のみ。
        debugPrint('FCM APNs token ready (attempt $i/$_apnsMaxAttempts, len=${apns.length})');
        return apns;
      }
      if (i < _apnsMaxAttempts) await Future.delayed(_apnsInterval);
    }
    debugPrint(
        'FCM APNs token still null after ~${_apnsMaxAttempts * _apnsInterval.inMilliseconds ~/ 1000}s '
        '— continuing to getToken() anyway (fail-soft; push may not arrive on this device)');
    return null;
  }

  Future<void> registerToken() async {
    if (kIsWeb) return;
    try {
      // iOS のみ APNs 待ち。Android の経路・タイミングは不変。
      if (Platform.isIOS) await _awaitApnsToken();

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        // 旧実装はここを無言で素通りしていた（token 未登録に気付けない）。
        debugPrint('FCM registerToken: getToken() returned null — token NOT registered');
        return;
      }
      // ★秘匿: 末尾4文字と長さのみ。全文は出さない。
      final tail = token.length >= 4 ? token.substring(token.length - 4) : '****';
      debugPrint('FCM registerToken: token acquired (…$tail, len=${token.length})');
      await _postToken(token);
    } catch (e) {
      debugPrint('FCM registerToken error: $e');
    }
  }

  Future<void> requestNotificationPermission() async {
    if (kIsWeb) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert:       true,
        badge:       true,
        sound:       true,
        provisional: false,
      );
      // 旧実装は結果を捨てていた＝拒否されても無言。何が起きたか出す。
      debugPrint('FCM permission: ${settings.authorizationStatus}');
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('FCM permission: NOT granted — push will not be shown on this device');
      }
    } catch (e) {
      debugPrint('FCM requestPermission error: $e');
    }
  }

  Future<void> handleNotificationTap(Map<String, dynamic> data) async {
    final type = data['type'];
    if (type != 'revision_request' &&
        type != 'report_reminder' &&
        type != 'punch_remind_in' &&
        type != 'punch_remind_out') {
      debugPrint('FCM tap: unknown type "$type" — ignored (no navigation)');
      return;
    }
    final loggedIn = await AuthService().isLoggedIn();
    if (!loggedIn) {
      debugPrint('FCM tap: not logged in — navigation for type "$type" skipped');
      return;
    }

    // ── 打刻のお知らせ（punch_remind_in / punch_remind_out）──
    // 下の既存2type の分岐を1バイトも変えないため、ここで処理して return する。
    // payload の値は全て String（BE utils/fcm.js が String() 化して送る）。
    if (type == 'punch_remind_in' || type == 'punch_remind_out') {
      final rawSide = data['side']?.toString() ?? '';
      // side は payload を正とし、欠落・不正時だけ type から導く
      // （BE は type と side を同じ判定から作るため両者は一致する）。
      final side = (rawSide == 'in' || rawSide == 'out')
          ? rawSide
          : (type == 'punch_remind_in' ? 'in' : 'out');
      // 不正値はここで 'day' に倒す（work_mode_service の流儀と同じ）。
      final shiftType = data['shift_type']?.toString() == 'night' ? 'night' : 'day';
      final bizDate   = data['biz_date']?.toString() ?? '';
      // シェル未生成＝ダイアログを出せる画面が無いときは通知一覧へ。
      // 直下の report_reminder のフォールバックと同型。
      if (!PunchRemindDialogNavigator.go(side, shiftType, bizDate)) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const NotificationListScreen()),
        );
      }
      return;
    }

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

  // ★段③: 新API へ切替。URL から user_id が消え、BE は JWT の membership_id を
  //   基準に保存する。旧 /workers/:user_id/fcm-token は踏まない。
  //   getUserId() はここでは不要になったため撤去（approval_day_screen.dart:68 /
  //   revision_inbox_screen.dart:71 で使うため AuthService 側のメソッドは残す）。
  //   ただし「未ログインなら送らない」ガードは旧実装の性質なので isLoggedIn() で維持する
  //   （空 Bearer を BE に投げないため）。headers/timeout/fail-soft は不変。
  Future<void> _postToken(String token) async {
    try {
      if (!await AuthService().isLoggedIn()) {
        debugPrint('FCM token post: not logged in — token NOT sent to BE');
        return;
      }
      final headers = await AuthService().getAuthHeaders();
      final res = await http.post(
        Uri.parse('$kApiBaseUrl/notifications/fcm-token'),
        headers: headers,
        body: jsonEncode({'fcm_token': token}),
      ).timeout(const Duration(seconds: 10));
      // 旧実装はレスポンスを捨てていた＝400/500 でも成功と区別が付かなかった。
      // ★秘匿: body は BE のエラーメッセージのみ想定だが、念のため status だけ出す。
      if (res.statusCode != 200) {
        debugPrint('FCM token post: BE returned ${res.statusCode} — token NOT registered');
      } else {
        debugPrint('FCM token post: OK (200)');
      }
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
