// lib/services/routes_service.dart - ルート計算サービス（高速化版）
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_cache.dart';
import '../services/http_client.dart';

const String API_URL = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

// ─── モデル ──────────────────────────────────────────────────

class TransitRoute {
  final int time, fareIc;
  final String depStation, arrStation;
  final List<TransitSection> routes;
  const TransitRoute({required this.time, required this.fareIc,
    required this.depStation, required this.arrStation, required this.routes});
  factory TransitRoute.fromJson(Map<String, dynamic> j) => TransitRoute(
    time:        j['time']        as int?    ?? 0,
    fareIc:      j['fare_ic']     as int?    ?? 0,
    depStation:  j['dep_station'] as String? ?? '',
    arrStation:  j['arr_station'] as String? ?? '',
    routes:      ((j['routes'] as List?) ?? [])
        .map((r) => TransitSection.fromJson(r as Map<String, dynamic>)).toList(),
  );
}

class TransitSection {
  final String from, to, line;
  final int time;
  const TransitSection({required this.from, required this.to,
    required this.line, required this.time});
  factory TransitSection.fromJson(Map<String, dynamic> j) => TransitSection(
    from: j['from'] as String? ?? '',
    to:   j['to']   as String? ?? '',
    line: j['line'] as String? ?? '',
    time: j['time'] as int?    ?? 0,
  );
}

class CarRoute {
  final int time, distanceM, tollNormal, tollLight, gasCost, totalNormal, totalLight;
  final String distanceText;
  const CarRoute({required this.time, required this.distanceM,
    required this.distanceText, required this.tollNormal, required this.tollLight,
    required this.gasCost, required this.totalNormal, required this.totalLight});
  factory CarRoute.fromJson(Map<String, dynamic> j) => CarRoute(
    time:         j['time']          as int?    ?? 0,
    distanceM:    j['distance_m']    as int?    ?? 0,
    distanceText: j['distance_text'] as String? ?? '',
    tollNormal:   j['toll_normal']   as int?    ?? 0,
    tollLight:    j['toll_light']    as int?    ?? 0,
    gasCost:      j['gas_cost']      as int?    ?? 0,
    totalNormal:  j['total_normal']  as int?    ?? 0,
    totalLight:   j['total_light']   as int?    ?? 0,
  );
}

class SimpleRoute {
  final String distance, duration;
  final int distanceM;
  const SimpleRoute({required this.distance, required this.duration, required this.distanceM});
  factory SimpleRoute.fromJson(Map<String, dynamic> j) => SimpleRoute(
    distance:  j['distance']   as String? ?? '',
    duration:  j['duration']   as String? ?? '',
    distanceM: j['distance_m'] as int?    ?? 0,
  );
}

class RouteCalculationResult {
  final String distance, duration;
  final int? estimatedGasCost;
  final String? fare;
  const RouteCalculationResult({required this.distance, required this.duration,
    this.estimatedGasCost, this.fare});
  factory RouteCalculationResult.fromJson(Map<String, dynamic> j) => RouteCalculationResult(
    distance:         j['distance']           as String? ?? '',
    duration:         j['duration']           as String? ?? '',
    estimatedGasCost: j['estimated_gas_cost'] as int?,
    fare:             j['fare']               as String?,
  );
}

// ─── サービス ────────────────────────────────────────────────

class RoutesService {
  // ルート計算（10分キャッシュ - 同じ区間を何度も叩かない）
  Future<Map<String, dynamic>> compareRoutesV2({
    required String origin,
    required String destination,
    required String authToken,
  }) async {
    if (origin.isEmpty || destination.isEmpty) return {};

    final cacheKey = 'routes:${origin.hashCode}:${destination.hashCode}';
    final cached = ApiCache.instance.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    try {
      final response = await AppHttpClient.instance.authPost(
        '/routes/compare',
        token: authToken,
        body: jsonEncode({'origin': origin, 'destination': destination}),
        timeout: const Duration(seconds: 20),
      );
      if (response.statusCode != 200) return {};

      final data   = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as Map<String, dynamic>? ?? {};
      final result = <String, dynamic>{};

      if (routes.containsKey('transit'))  result['transit']  = TransitRoute.fromJson(routes['transit']  as Map<String, dynamic>);
      if (routes.containsKey('car'))      result['car']      = CarRoute.fromJson(routes['car']          as Map<String, dynamic>);
      if (routes.containsKey('walking'))  result['walking']  = SimpleRoute.fromJson(routes['walking']   as Map<String, dynamic>);
      if (routes.containsKey('bicycling')) result['bicycling'] = SimpleRoute.fromJson(routes['bicycling'] as Map<String, dynamic>);

      ApiCache.instance.set(cacheKey, result, const Duration(minutes: 10));
      return result;
    } catch (e) {
      debugPrint('compareRoutesV2 error: $e');
      return {};
    }
  }

  Future<RouteCalculationResult?> calculateRoute({
    required String origin,
    required String destination,
    required String authToken,
    String mode = 'driving',
  }) async {
    try {
      final response = await AppHttpClient.instance.authPost(
        '/routes/calculate',
        token: authToken,
        body: jsonEncode({'origin': origin, 'destination': destination, 'mode': mode}),
      );
      if (response.statusCode != 200) return null;
      return RouteCalculationResult.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) { return null; }
  }
}

