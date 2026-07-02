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
//
// ── API 接続先（API_HOST）─────────────────────────────────
// 通常起動: 何も指定不要。自動で本番URL（下記 defaultValue）に接続する。
//
// E2E などでローカルAPIへ繋ぐ場合のみ dart-define で上書き:
//   flutter run --dart-define=API_HOST=http://<PCのLAN IP>:3000
//
// 天気キーと同時指定も可（複数 --dart-define 併用）:
//   flutter run --dart-define=API_HOST=http://192.168.0.10:3000 \
//               --dart-define=OPENWEATHER_API_KEY=<YOUR_KEY>
//
// リハ後に戻す作業は不要（ソースは無変更・値は起動時オプションのみのため）。

// ignore_for_file: constant_identifier_names
const String kWeatherApiKey = String.fromEnvironment(
  'OPENWEATHER_API_KEY',
  defaultValue: '',
);

const String _apiHost = String.fromEnvironment(
  'API_HOST',
  defaultValue: 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com',
);
const String kApiBaseUrl = '$_apiHost/api/v1';
const String kHealthUrl  = '$_apiHost/health';

const String kAppVersion  = '1.1.0';
const String kBuildNumber = '2';
