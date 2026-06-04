// ビルド時に --dart-define で渡すこと。渡さない場合は空文字になり天気が非表示。
//
// iOSリリースビルド（Mac上で実行）:
//   flutter build ios --dart-define=OPENWEATHER_API_KEY=<YOUR_KEY>
//
// Webビルド:
//   flutter build web --dart-define=OPENWEATHER_API_KEY=<YOUR_KEY>
//
// デバッグ実行:
//   flutter run --dart-define=OPENWEATHER_API_KEY=<YOUR_KEY>

// ignore_for_file: constant_identifier_names
const String kWeatherApiKey = String.fromEnvironment(
  'OPENWEATHER_API_KEY',
  defaultValue: '',
);

const String kApiBaseUrl =
    'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';
const String kHealthUrl = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/health';

const String kAppVersion  = '1.1.0';
const String kBuildNumber = '2';
