// ── API 接続先（API_HOST）─────────────────────────────────
// 通常起動: 何も指定不要。自動で本番URL（下記 defaultValue）に接続する。
//
// E2E などでローカルAPIへ繋ぐ場合のみ dart-define で上書き:
//   flutter run --dart-define=API_HOST=http://<PCのLAN IP>:3000
//
// リハ後に戻す作業は不要（ソースは無変更・値は起動時オプションのみのため）。
//
// ★天気の OPENWEATHER_API_KEY は段7で退役した。天気は BE の統一エンジン
//   （GET /tools/weather）から取るようになり、OpenWeather の鍵はサーバの
//   環境変数にしか無い。端末へ鍵を配る必要そのものが無くなった。

// ignore_for_file: constant_identifier_names

const String _apiHost = String.fromEnvironment(
  'API_HOST',
  defaultValue: 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com',
);
const String kApiBaseUrl = '$_apiHost/api/v1';
const String kHealthUrl  = '$_apiHost/health';

const String kAppVersion  = '1.1.0';
const String kBuildNumber = '2';
