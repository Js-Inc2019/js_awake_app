// ============================================================
// test/session_lockout_wiring_test.dart — 締め出し部品の「差し込み忘れ」検査
//
// ★何を守るか:
//   締め出し（退職・無効化・役割変更）は、判定を1本に閉じても
//   「受け皿に差し込むのを忘れる」と丸ごと死ぬ。しかも死んでも画面は
//   何も言わない（今回直したのがまさにその形）。よって差し込みの有無を
//   人の目ではなく検査で押さえる。
//
//   ① 受け皿：runApiCall の非200が実際に締め出しを起こすか（挙動で見る）
//   ② 戻る先：main() が Navigator を差しているか（起動しないと確かめられないため文字で見る）
//   ③ 抜け道：lib/ の直 http 呼び出しが runApiCall を通らずに出ていないか
//
// ★期待値は実装から import せずここへ直書きする（実装を写すと何も検査しない）。
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/config/constants.dart';
import 'package:js_awake_app/services/api_result.dart';
import 'package:js_awake_app/utils/session_lockout.dart';

/// 行コメントを落としたソース。
/// ★これが無いと「差し込みをコメントアウトしただけ」で検査が通ってしまう
///   （実際に一度その形で素通りした）。検査は生きているコードだけを見る。
String _codeOnly(File f) => f
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 非200 の応答を1つ作る。request を載せるのは、締め出しの判定が
/// 【URL】で行われるため（ラベルではなく実際に叩いた先で決める）。
http.Response _res(
  int status,
  String body, {
  required String method,
  required String url,
  String token = 'token-a',
}) {
  final req = http.Request(method, Uri.parse(url));
  if (token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
  return http.Response(
    body,
    status,
    request: req,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

Future<ApiResult<Map<String, dynamic>>> _call(http.Response res) =>
    runApiCall<Map<String, dynamic>>('Test', () async => res, apiJsonMap);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'token-a'});
    resetLockoutGuardForTest();
  });

  // ──────────────────────────────────────────────────────────
  // ① 受け皿：runApiCall の非200が締め出し部品を通っているか
  // ──────────────────────────────────────────────────────────
  group('差し込み検査① runApiCall の非200が締め出しを起こす', () {
    test('退職(RETIRED)の401で理由が端末に残り、トークンが捨てられる', () async {
      final r = await _call(_res(401, '{"error":"x","code":"RETIRED"}',
          method: 'GET', url: '$kApiBaseUrl/reports/today'));

      expect(r.ok, isFalse);
      expect(r.statusCode, 401);
      expect(r.errorCode, 'RETIRED');

      final reason = await takeLockoutReason();
      expect(reason, isNotNull,
          reason: 'runApiCall の非200が締め出し部品を通っていない'
              '（lib/services/api_result.dart の非200分岐を確認）');
      expect(reason, contains('この会社での登録が終了しました'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getBool('logged_out'), isTrue);
    });

    test('送信中(GET以外)の締め出しは作成中の内容が消えることも伝える', () async {
      await _call(_res(401, '{"code":"TOKEN_EXPIRED"}',
          method: 'POST', url: '$kApiBaseUrl/reports'));
      final reason = await takeLockoutReason();
      expect(reason, contains('認証の有効期限が切れました'));
      expect(reason, contains('作成中の内容は保存されていません'));
    });

    test('入力のやり直しで済むコード(INVALID_PIN)では理由を残さない', () async {
      await _call(_res(401, '{"code":"INVALID_PIN"}',
          method: 'POST', url: '$kApiBaseUrl/workers/me/pin'));
      expect(await takeLockoutReason(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'token-a');
    });

    test('名簿に無いコードでは締め出さない（理由は ApiResult で呼び手に返る）', () async {
      final r = await _call(_res(403,
          '{"error":"このアクションを実行する権限がありません","code":"FORBIDDEN"}',
          method: 'GET', url: '$kApiBaseUrl/reports'));
      expect(await takeLockoutReason(), isNull);
      expect(r.errorCode, 'FORBIDDEN');
      expect(r.errorMessage, 'このアクションを実行する権限がありません');
    });
  });

  // ──────────────────────────────────────────────────────────
  // 判定そのもの（E〜J）。部品1本に閉じていることを直接押さえる。
  // ──────────────────────────────────────────────────────────
  group('判定の名簿', () {
    const backTo = [
      'NO_TOKEN', 'TOKEN_EXPIRED', 'LEGACY_TOKEN', 'ACCOUNT_DISABLED',
      'RETIRED', 'ROLE_CHANGED', 'PERMISSION_CHANGED', 'MEMBERSHIP_INVALID',
      'NO_USER',
    ];
    const stay = [
      'INVALID_PIN', 'USER_NOT_FOUND', 'DEVICE_DISABLED',
      'DEVICE_NOT_FOUND', 'ANCHOR_MISMATCH',
    ];

    for (final code in backTo) {
      test('$code は戻す＋文言がある', () {
        final v = judgeLockout(
            url: Uri.parse('$kApiBaseUrl/reports'),
            method: 'GET',
            errorCode: code);
        expect(v.lockOut, isTrue);
        expect(v.message, isNotNull);
        expect(v.message!.isNotEmpty, isTrue);
      });
    }

    for (final code in stay) {
      test('$code は戻さない', () {
        final v = judgeLockout(
            url: Uri.parse('$kApiBaseUrl/reports'),
            method: 'GET',
            errorCode: code);
        expect(v.lockOut, isFalse);
      });
    }

    test('未知のコード・code なしは戻さない', () {
      for (final code in <String?>[null, '', 'SOMETHING_NEW']) {
        expect(
            judgeLockout(
                    url: Uri.parse('$kApiBaseUrl/reports'),
                    method: 'GET',
                    errorCode: code)
                .lockOut,
            isFalse);
      }
    });

    test('戻す9と戻さない5は重ならない', () {
      for (final code in stay) {
        expect(backTo.contains(code), isFalse);
      }
      expect(backTo.length, 9);
      expect(stay.length, 5);
    });
  });

  group('除外するURL', () {
    const retired = 'RETIRED';
    bool locks(String url) => judgeLockout(
        url: Uri.parse(url), method: 'GET', errorCode: retired).lockOut;

    test('自社BE以外は戻さない', () {
      expect(locks('https://api.openweathermap.org/data/2.5/weather'), isFalse);
      expect(locks('http://localhost:3000/api/v1/reports'), isFalse);
    });

    test('API の土台の外（/health）は戻さない', () {
      expect(locks(kHealthUrl), isFalse);
    });

    test('/auth/ 配下は戻さない', () {
      expect(locks('$kApiBaseUrl/auth/verify-token'), isFalse);
      expect(locks('$kApiBaseUrl/auth/verify-pin'), isFalse);
      expect(locks('$kApiBaseUrl/auth/verify-device?device_id=x'), isFalse);
    });

    test('まだ資格を持たない人の通信は戻さない', () {
      expect(locks('$kApiBaseUrl/workers/activate'), isFalse);
      expect(locks('$kApiBaseUrl/workers/self-register'), isFalse);
    });

    test('背景で走る fcm-token は戻さない', () {
      expect(locks('$kApiBaseUrl/notifications/fcm-token'), isFalse);
    });

    test('URL が取れない応答は戻さない', () {
      expect(judgeLockout(url: null, method: 'GET', errorCode: retired).lockOut,
          isFalse);
    });

    test('通常の業務APIは戻す', () {
      expect(locks('$kApiBaseUrl/reports/today'), isTrue);
      expect(locks('$kApiBaseUrl/workers/me'), isTrue);
      expect(locks('$kApiBaseUrl/notifications'), isTrue);
    });
  });

  group('多重発火の防止', () {
    test('同じトークンでの2度目は締め出しを起こさない', () async {
      await _call(_res(401, '{"code":"RETIRED"}',
          method: 'GET', url: '$kApiBaseUrl/reports'));
      expect(await takeLockoutReason(), isNotNull);

      // 同時に返ってきた別の401（同じトークン）→ 理由を上書きしない
      await _call(_res(401, '{"code":"MEMBERSHIP_INVALID"}',
          method: 'GET', url: '$kApiBaseUrl/notifications'));
      expect(await takeLockoutReason(), isNull);
    });

    test('ログインし直した後（別トークン）は改めて締め出せる', () async {
      await _call(_res(401, '{"code":"RETIRED"}',
          method: 'GET', url: '$kApiBaseUrl/reports', token: 'token-a'));
      expect(await takeLockoutReason(), isNotNull);

      await _call(_res(401, '{"code":"RETIRED"}',
          method: 'GET', url: '$kApiBaseUrl/reports', token: 'token-b'));
      expect(await takeLockoutReason(), isNotNull);
    });
  });

  group('理由の受け渡し', () {
    test('読んだら消える（次に読むと空）', () async {
      await saveLockoutReason('テスト理由');
      expect(await takeLockoutReason(), 'テスト理由');
      expect(await takeLockoutReason(), isNull);
    });

    test('手動ログアウト用の消去で前回の理由が残らない', () async {
      await saveLockoutReason('テスト理由');
      await clearLockoutReason();
      expect(await takeLockoutReason(), isNull);
    });

    test('認証系（対象外URL）でも理由だけは残せる', () async {
      expect(await recordLockoutReason('RETIRED'), isTrue);
      expect(await takeLockoutReason(), contains('この会社での登録が終了しました'));
      expect(await recordLockoutReason('INVALID_PIN'), isFalse);
      expect(await takeLockoutReason(), isNull);
    });
  });

  // ──────────────────────────────────────────────────────────
  // ② 戻る先：main() の差し込み
  // ──────────────────────────────────────────────────────────
  group('差し込み検査② 戻る先の Navigator', () {
    test('main() が Navigator を差している', () {
      final src = _codeOnly(File('lib/main.dart'));
      expect(
        RegExp(r'lockoutNavigatorLookup\s*=').hasMatch(src),
        isTrue,
        reason: 'lib/main.dart が lockoutNavigatorLookup を差していない'
            '（締め出しても画面が戻らない）',
      );
    });
  });

  // ──────────────────────────────────────────────────────────
  // ③ 抜け道：runApiCall を通らない通信
  // ──────────────────────────────────────────────────────────
  group('差し込み検査③ runApiCall を通らない通信', () {
    // 今回の対象外（指示により触らない）。ここに載っている＝
    // 締め出しの受け皿を通っていないことを承知している、という印。
    const knownOutside = <String, int>{
      'lib/services/routes_service.dart': 1, // POST /routes/compare
    };

    // ファイルの道の区切りを「/」に揃える。
    // ★Directory.listSync が返す path の区切りは OS で違う（Windows は円記号、
    //   macOS/Linux はスラッシュ）。名簿 knownOutside はスラッシュで書いてあるため、
    //   生の path で引くと Windows でだけ名簿に当たらず、対象外と承知している
    //   ファイルが違反として数えられていた＝同じコードが Mac では緑・Windows では赤に
    //   なる検査になっていた。環境で結果が変わる検査は検査として信用できないので、
    //   引く前に区切りを1つへ揃える。
    // ★揃えるのは【名簿の引き方と表示】だけ。何を違反とみなすかの式は変えていない。
    String slashPath(File f) => f.path.replaceAll(r'\', '/');

    test('直 http 呼び出しは全て runApiCall を通っている', () {
      final verb = RegExp(
          r'\bhttp\.(get|post|put|patch|delete|head|read|readBytes)\s*\(');
      // runApiCall 本体と、AuthService がそれを包んでいる _run。
      final gate = RegExp(r'\brunApiCall\s*[<(]|\b_run\s*[<(]');

      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src   = _codeOnly(f);
        final calls = verb.allMatches(src).length;
        if (calls == 0) continue;

        final expectedOutside = knownOutside[slashPath(f)] ?? 0;
        final gates = gate.allMatches(src).length;
        if (calls - expectedOutside > gates) {
          // 出す名前も揃える（どの OS で走らせても同じ文字列で報告される）。
          offenders.add('${slashPath(f)}: http $calls本 / runApiCall $gates本'
              '（対象外として承知しているのは $expectedOutside本）');
        }
      }
      expect(offenders, isEmpty,
          reason: '締め出しの受け皿(runApiCall)を通らない通信がある:\n'
              '${offenders.join('\n')}');
    });
  });
}
