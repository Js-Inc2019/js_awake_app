// ============================================================
// lib/services/routes_service.dart
//
// ★★ このファイルは ApiResult<T> 標準の「意図的な例外」である ★★
//
// 段4で他8本の Service は ApiResult<T>（{ok, statusCode, data, errorMessage,
// errorCode}）へ統一した。compareRoutesV2 だけは RouteCompareResult を維持する。
// 将来「統一漏れ」と誤認して置き換えないよう、理由を3点そのまま残す:
//
//   ① 「HTTP 200 だが失敗」を表現する必要がある。
//      BE は経路計算に失敗しても 200 + routes:{} を返す
//      （js-office-api routes/routes-calc.js:186）。ApiResult は 200系＝ok:true
//      なので、置き換えると RouteFailure.empty が ok:true に反転し、
//      呼び手（home_screen.dart の _routeFailed）が「空の結果」を成功として
//      描いてしまう＝金額欄が空のまま「取得できた」ことになる。
//
//   ② ペイロードが2つ要る。
//      routes（型付きパース済み・画面描画用）と rawRoutes（BE の素 JSON・
//      キャッシュ保存用）の両方を呼び手が使う（home_screen.dart の
//      _saveRouteCache）。ApiResult の data は1つしか持てない。
//
//   ③ timeout と network を区別する必要がある。
//      ApiResult はどちらも statusCode:0 に畳む。ここでは RouteFailure.timeout /
//      RouteFailure.network を分けて reasonLabel に出しており、
//      「8秒で切れた」のか「圏外」なのかがログで判別できる。
//
// ＝ RouteCompareResult は ApiResult の劣化版ではなく、ApiResult より
//    表現力が要る一点物。統一するなら ApiResult 側に①②③を足す議論が先。
//
// ※ 段4で実施したのは「手組み Authorization ヘッダの是正」のみ
//   （AuthService().getAuthHeaders() へ集約。トークンの出所が1か所になる）。
// ============================================================
import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../config/constants.dart';

const String _kApiUrl = kApiBaseUrl;

// 電車ルート情報
class TransitRoute {
  final int time;
  final int fareIc;
  final String depStation;
  final String arrStation;
  final List<TransitSection> routes;

  TransitRoute({
    required this.time,
    required this.fareIc,
    required this.depStation,
    required this.arrStation,
    required this.routes,
  });

  factory TransitRoute.fromJson(Map<String, dynamic> json) {
    return TransitRoute(
      time:        json['time'] as int? ?? 0,
      fareIc:      json['fare_ic'] as int? ?? 0,
      depStation:  json['dep_station'] as String? ?? '',
      arrStation:  json['arr_station'] as String? ?? '',
      routes:      ((json['routes'] as List?) ?? [])
          .map((r) => TransitSection.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TransitSection {
  final String from;
  final String to;
  final String line;
  final int time;

  TransitSection({required this.from, required this.to, required this.line, required this.time});

  factory TransitSection.fromJson(Map<String, dynamic> json) {
    return TransitSection(
      from: json['from'] as String? ?? '',
      to:   json['to']   as String? ?? '',
      line: json['line'] as String? ?? '',
      time: json['time'] as int?    ?? 0,
    );
  }
}

// 車ルート情報
class CarRoute {
  final int time;
  final int distanceM;
  final String distanceText;
  final int tollNormal;
  final int tollLight;
  final int gasCost;
  final int totalNormal;
  final int totalLight;

  CarRoute({
    required this.time,
    required this.distanceM,
    required this.distanceText,
    required this.tollNormal,
    required this.tollLight,
    required this.gasCost,
    required this.totalNormal,
    required this.totalLight,
  });

  factory CarRoute.fromJson(Map<String, dynamic> json) {
    return CarRoute(
      time:         json['time']          as int?    ?? 0,
      distanceM:    json['distance_m']    as int?    ?? 0,
      distanceText: json['distance_text'] as String? ?? '',
      tollNormal:   json['toll_normal']   as int?    ?? 0,
      tollLight:    json['toll_light']    as int?    ?? 0,
      gasCost:      json['gas_cost']      as int?    ?? 0,
      totalNormal:  json['total_normal']  as int?    ?? 0,
      totalLight:   json['total_light']   as int?    ?? 0,
    );
  }
}

// 徒歩・自転車
class SimpleRoute {
  final String distance;
  final String duration;
  final int distanceM;

  SimpleRoute({required this.distance, required this.duration, required this.distanceM});

  factory SimpleRoute.fromJson(Map<String, dynamic> json) {
    return SimpleRoute(
      distance:  json['distance']   as String? ?? '',
      duration:  json['duration']   as String? ?? '',
      distanceM: json['distance_m'] as int?    ?? 0,
    );
  }
}

/// ルート比較の失敗理由。UIに出す文言はここでは決めず、種別だけを返す。
enum RouteFailure {
  /// タイムアウト（8秒）
  timeout,
  /// ネットワークに届かない（SocketException 等）
  network,
  /// HTTP 200 以外
  httpError,
  /// 200 だが JSON として読めない／形が違う
  badResponse,
  /// 200 で読めたが routes が空＝BE がどの手段も取得できなかった
  empty,
}

/// compareRoutesV2 の結果。
/// ★従来は失敗を全て `{}` に潰していたため、
///   「取れなかった」と「そもそも呼んでいない」が呼び出し側から区別できなかった。
///   成否と理由を持たせて、UIが正直に出せるようにする。
class RouteCompareResult {
  const RouteCompareResult.ok(this.routes, {this.rawRoutes = const {}})
      : failure = null,
        statusCode = 200;
  const RouteCompareResult.failed(this.failure, {this.statusCode})
      : routes = const {},
        rawRoutes = const {};

  /// 成功時のみ中身がある。キー: 'transit' | 'car' | 'walking' | 'bicycling'
  final Map<String, dynamic> routes;

  /// BE から受け取った素の JSON（`data['routes']`）。
  /// キャッシュ保存用。型付きオブジェクトは JSON に戻せないため素を持ち回る。
  final Map<String, dynamic> rawRoutes;

  /// null = 成功
  final RouteFailure? failure;

  /// httpError のときのみ意味を持つ
  final int? statusCode;

  bool get isOk => failure == null;

  /// ログ・デバッグ用の短い理由（★秘匿値は一切含めない：URL・トークン・本文を出さない）
  String get reasonLabel {
    switch (failure) {
      case RouteFailure.timeout:     return 'timeout';
      case RouteFailure.network:     return 'network';
      case RouteFailure.httpError:   return 'http_$statusCode';
      case RouteFailure.badResponse: return 'bad_response';
      case RouteFailure.empty:       return 'empty';
      case null:                     return 'ok';
    }
  }
}

class RoutesService {
  /// 応答性のため 8 秒で打ち切る（旧 60 秒）。
  /// 現場で「ルート計算中...」が数分残る原因が長すぎる timeout ＋ リトライだったため。
  static const Duration kTimeout = Duration(seconds: 8);

  final AuthService _auth = AuthService();

  /// ★段4: authToken 引数を撤去した。呼び手が prefs から取り出して渡していたが、
  ///   トークンの出所は AuthService 一本にする（画面がトークンを持ち回らない）。
  ///   送るヘッダの中身は統一前と同一（Content-Type + Bearer <auth_token>）。
  Future<RouteCompareResult> compareRoutesV2({
    required String origin,
    required String destination,
  }) async {
    final headers = await _auth.getAuthHeaders();
    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_kApiUrl/routes/compare'),
        headers: headers,
        body: jsonEncode({'origin': origin, 'destination': destination}),
      ).timeout(kTimeout);
    } on TimeoutException {
      debugPrint('compareRoutesV2: timeout');
      return const RouteCompareResult.failed(RouteFailure.timeout);
    } catch (e) {
      // SocketException / HandshakeException など。メッセージに接続先が載り得るので型名だけ出す。
      debugPrint('compareRoutesV2: network error (${e.runtimeType})');
      return const RouteCompareResult.failed(RouteFailure.network);
    }

    debugPrint('compareRoutesV2 status=${response.statusCode}');
    if (response.statusCode != 200) {
      return RouteCompareResult.failed(
        RouteFailure.httpError, statusCode: response.statusCode);
    }

    final Map<String, dynamic> routes;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      routes = data['routes'] as Map<String, dynamic>? ?? {};
    } catch (e) {
      debugPrint('compareRoutesV2: bad response (${e.runtimeType})');
      return const RouteCompareResult.failed(RouteFailure.badResponse);
    }

    final Map<String, dynamic> result;
    try {
      result = parseRoutes(routes);
    } catch (e) {
      debugPrint('compareRoutesV2: parse error (${e.runtimeType})');
      return const RouteCompareResult.failed(RouteFailure.badResponse);
    }

    // ★BE は取得に失敗しても 200 + routes:{} を返す（js-office-api routes/routes-calc.js:186）。
    //   200 だから成功、とは判定しない。中身が空なら失敗として扱う。
    if (result.isEmpty) {
      return const RouteCompareResult.failed(RouteFailure.empty);
    }
    return RouteCompareResult.ok(result, rawRoutes: routes);
  }

  /// BE の素 JSON（`data['routes']`）→ 型付き Map。
  /// 通信直後とキャッシュ復元の両方で使うため公開している（同じ解釈を2箇所に書かない）。
  static Map<String, dynamic> parseRoutes(Map<String, dynamic> routes) {
    final result = <String, dynamic>{};
    if (routes['transit'] is Map) {
      result['transit'] = TransitRoute.fromJson(
          Map<String, dynamic>.from(routes['transit'] as Map));
    }
    if (routes['car'] is Map) {
      result['car'] = CarRoute.fromJson(
          Map<String, dynamic>.from(routes['car'] as Map));
    }
    if (routes['walking'] is Map) {
      result['walking'] = SimpleRoute.fromJson(
          Map<String, dynamic>.from(routes['walking'] as Map));
    }
    if (routes['bicycling'] is Map) {
      result['bicycling'] = SimpleRoute.fromJson(
          Map<String, dynamic>.from(routes['bicycling'] as Map));
    }
    return result;
  }
}
