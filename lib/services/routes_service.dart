// lib/services/routes_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

const String API_URL = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

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

// 旧互換用
class RouteCalculationResult {
  final String distance;
  final String duration;
  final int? estimatedGasCost;
  final String? fare;

  RouteCalculationResult({
    required this.distance,
    required this.duration,
    this.estimatedGasCost,
    this.fare,
  });

  factory RouteCalculationResult.fromJson(Map<String, dynamic> json) {
    return RouteCalculationResult(
      distance:         json['distance']           as String? ?? '',
      duration:         json['duration']           as String? ?? '',
      estimatedGasCost: json['estimated_gas_cost'] as int?,
      fare:             json['fare']               as String?,
    );
  }
}

class RoutesService {
  Future<Map<String, dynamic>> compareRoutesV2({
    required String origin,
    required String destination,
    required String authToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/routes/compare'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'origin': origin, 'destination': destination}),
      ).timeout(const Duration(seconds: 20));
      print('🚀 compareRoutesV2 origin=$origin dest=$destination status=${response.statusCode} body=${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');

      if (response.statusCode != 200) return {};
      final data   = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as Map<String, dynamic>? ?? {};

      final result = <String, dynamic>{};
      if (routes.containsKey('transit')) {
        result['transit'] = TransitRoute.fromJson(routes['transit'] as Map<String, dynamic>);
      }
      if (routes.containsKey('car')) {
        result['car'] = CarRoute.fromJson(routes['car'] as Map<String, dynamic>);
      }
      if (routes.containsKey('walking')) {
        result['walking'] = SimpleRoute.fromJson(routes['walking'] as Map<String, dynamic>);
      }
      if (routes.containsKey('bicycling')) {
        result['bicycling'] = SimpleRoute.fromJson(routes['bicycling'] as Map<String, dynamic>);
      }
      return result;
    } catch (e) {
      print('compareRoutesV2 error: $e');
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
      final response = await http.post(
        Uri.parse('$API_URL/routes/calculate'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'origin': origin, 'destination': destination, 'mode': mode}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return RouteCalculationResult.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, RouteCalculationResult>> compareRoutes({
    required String origin,
    required String destination,
    required String authToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/routes/compare'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'origin': origin, 'destination': destination}),
      ).timeout(const Duration(seconds: 20));
      print('🚀 compareRoutesV2 origin=$origin dest=$destination status=${response.statusCode} body=${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      if (response.statusCode != 200) return {};
      final data   = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as Map<String, dynamic>? ?? {};
      return routes.map((key, value) =>
          MapEntry(key, RouteCalculationResult.fromJson(value as Map<String, dynamic>)));
    } catch (e) {
      return {};
    }
  }
}
