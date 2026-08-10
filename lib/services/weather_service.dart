// ============================================================
// lib/services/weather_service.dart - 天気（BE統一エンジン）
//
// ★段7で新設。統一前は home_screen が外部の気象API2種を
//   端末から直接叩き、WBGT もアイコン変換も端末側で持っていた。
//   ・OWM の appid は --dart-define=OPENWEATHER_API_KEY で渡す作りだったが、
//     鍵はサーバの環境変数にしか無く、通常ビルドでは空文字＝OWM を呼ばず
//     常にフォールバック側へ倒れていた（＝2経路のうち片方しか動かない）。
//   ・同じ WBGT を FIELD と OFFICE が別の式で計算しており、同じ気温・湿度でも
//     2アプリで違う数字が出ていた。
//   BE が /tools/weather ひとつで気温・風速・降水確率・週間予報・WBGT・
//   アラートまで返すようになったため、天気の真実源をサーバ1本へ寄せる。
//
// ★応答契約の正は js-office-api の routes/tools_weather.js:29-47。
//   {
//     location: string,
//     current: { temp, feels_like, humidity, wind_speed, weather, icon,
//                rain_probability },
//     weekly:  [{ day, icon, max, min, rain_probability }],
//     alert:   { level: 'danger'|'warning'|'info', message },
//     wbgt:    { level: 'safe'|'caution'|'warning'|'severe'|'danger',
//                value, message }
//   }
//   ・icon は絵文字（weatherEngine.js:368）。端末で引き直さない。
//   ・wbgt は常時オブジェクト（tools_weather.js:45-47）。統一前は WBGT<21 で
//     null だったが、「安全」と「取得できていない」が区別できないため
//     level:'safe' を新設して null を廃した経緯がある。
//   ・alert も常時返る（weatherEngine.js:372 / :455）。
//
// ★このクラスは通信の運び屋。パースも表示判断もしない（data は応答そのまま）。
//   降水確率の 3状態（値/0/未取得）も、alert を出すか否かも呼び手が決める。
// ============================================================

import 'package:http/http.dart' as http;
import 'api_result.dart';
import 'auth_service.dart';
import '../config/constants.dart';

class WeatherService {
  static final WeatherService _instance = WeatherService._internal();

  factory WeatherService() => _instance;

  WeatherService._internal();

  final AuthService _auth = AuthService();

  /// GET /tools/weather?lat=&lon=
  ///
  /// ★認証必須（routes/tools_weather.js:49 の authenticateToken）。
  ///   未認証・トークン失効は 401 で返る＝呼び手は「天気だけ静かに出さない」に倒す
  ///   （天気の失敗でログイン画面へ飛ばさない）。
  /// ★lat/lon が無いと BE は 400（tools_weather.js:51）。測位できていないときに
  ///   呼ばないガードは呼び手側に残す（ここでは判断しない）。
  /// ★上流の気象API2種が両方落ちたときだけ BE が 502 を返す
  ///   （tools_weather.js:56-61）。フォールバックは BE 内で完結しており、
  ///   端末側に2経路を持つ必要はもう無い。
  Future<ApiResult<Map<String, dynamic>>> fetchWeather({
    required double lat,
    required double lon,
  }) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'WeatherService.fetchWeather',
      () => http.get(
        Uri.parse('$kApiBaseUrl/tools/weather?lat=$lat&lon=$lon'),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }
}
