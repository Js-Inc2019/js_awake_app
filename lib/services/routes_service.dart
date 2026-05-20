import 'dart:convert';
import 'package:http/http.dart' as http;

const String API_URL = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

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
      distance: json['distance'] as String? ?? '',
      duration: json['duration'] as String? ?? '',
      estimatedGasCost: json['estimated_gas_cost'] as int?,
      fare: json['fare'] as String?,
    );
  }
}

class RoutesService {
  Future<RouteCalculationResult?> calculateRoute({
    required String origin,
    required String destination,
    required String authToken,
    String mode = 'driving',
  }) async {
    try {
      print('🔥 ルート計算API呼び出し...');
      final response = await http.post(
        Uri.parse('$API_URL/routes/calculate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'origin': origin,
          'destination': destination,
          'mode': mode,
        }),
      ).timeout(const Duration(seconds: 15));
      
      print('✅ ルート計算API: ${response.statusCode}');
      print('📦 レスポンス: ${response.body}');
      
      if (response.statusCode != 200) {
        print('ルート計算失敗: ${response.statusCode}');
        return null;
      }
      
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return RouteCalculationResult.fromJson(data);
    } catch (e) {
      print('ルート計算エラー: $e');
      return null;
    }
  }

  Future<Map<String, RouteCalculationResult>> compareRoutes({
    required String origin,
    required String destination,
    required String authToken,
  }) async {
    try {
      print('🔥 ルート比較API呼び出し...');
      final response = await http.post(
        Uri.parse('$API_URL/routes/compare'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'origin': origin,
          'destination': destination,
        }),
      ).timeout(const Duration(seconds: 15));
      
      print('✅ ルート比較API: ${response.statusCode}');
      print('📦 レスポンス: ${response.body}');
      
      if (response.statusCode != 200) {
        print('ルート比較失敗: ${response.statusCode}');
        return {};
      }
      
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as Map<String, dynamic>? ?? {};
      
      return routes.map((key, value) =>
          MapEntry(key, RouteCalculationResult.fromJson(value as Map<String, dynamic>)));
    } catch (e) {
      print('ルート比較エラー: $e');
      return {};
    }
  }
}
