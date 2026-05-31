// lib/services/http_client.dart - シングルトン持続HTTP接続
import 'dart:async';
import 'package:http/http.dart' as http;

class AppHttpClient {
  static final AppHttpClient _instance = AppHttpClient._();
  AppHttpClient._() : _client = http.Client();
  static AppHttpClient get instance => _instance;

  http.Client _client;

  static const _kBaseUrl =
      'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

  static const _kReadTimeout = Duration(seconds: 12);

  // Heroku dyno warm-up（ログイン前に fire & forget で叩く）
  static Future<void> warmUp() async {
    try {
      await _instance._client.get(
        Uri.parse('$_kBaseUrl/health'),
        headers: const {'Connection': 'keep-alive'},
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  // 認証付き GET
  Future<http.Response> authGet(
    String path, {
    required String token,
    Map<String, String>? extra,
    Duration timeout = _kReadTimeout,
  }) {
    return _client.get(
      Uri.parse('$_kBaseUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Connection': 'keep-alive',
        if (extra != null) ...extra,
      },
    ).timeout(timeout);
  }

  // 認証付き POST
  Future<http.Response> authPost(
    String path, {
    required String token,
    required String body,
    Duration timeout = _kReadTimeout,
  }) {
    return _client.post(
      Uri.parse('$_kBaseUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Connection': 'keep-alive',
      },
      body: body,
    ).timeout(timeout);
  }

  // 認証なし GET
  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = _kReadTimeout,
  }) {
    return _client.get(
      Uri.parse('$_kBaseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Connection': 'keep-alive',
        if (headers != null) ...headers,
      },
    ).timeout(timeout);
  }

  // 認証なし POST
  Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    required String body,
    Duration timeout = _kReadTimeout,
  }) {
    return _client.post(
      Uri.parse('$_kBaseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Connection': 'keep-alive',
        if (headers != null) ...headers,
      },
      body: body,
    ).timeout(timeout);
  }

  // 接続をリセット（エラー後の再接続用）
  void reset() {
    _client.close();
    _client = http.Client();
  }
}
