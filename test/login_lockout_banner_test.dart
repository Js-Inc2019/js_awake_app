// ============================================================
// test/login_lockout_banner_test.dart — 締め出しの理由が本人に届くか（widget テスト）
//
// ★何を縛るか:
//   ① 端末に保存された理由が、ログイン画面で赤い帯として【必ず】出る
//      （_init は warmUp から始まり読込中が数秒続く。帯が画面状態の分岐の
//        中に入ると、その間ずっと理由が隠れる＝今回直した「黙って飛ぶ」に戻る）
//   ② 出したら端末からは消える（同じ理由を何度も出さない）
//   ③ 理由が無い時は帯を出さない
//
// ★HTTP は flutter_test が既定で全て 400 に落とすため、warmUp は失敗して
//   処理続行する（この画面の元々の挙動）。帯の表示はそれと独立している。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/screens/login_screen.dart';

/// 退職の文言（実装から import せずここへ直書きする）。
const String _retiredReason =
    'この会社での登録が終了しました。詳しくは会社のご担当者にご確認ください。';

/// 画面を出して、warmUp の再試行（最大3回・失敗時2秒待ち）を通り越すまで進める。
Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('保存された理由は読込中でも赤い帯で出る', (tester) async {
    SharedPreferences.setMockInitialValues({
      'session_lockout_reason': _retiredReason,
      'consent_agreed': true,
      'device_id': 'dev-1',
      'logged_out': true,
    });

    await _open(tester);

    expect(find.text(_retiredReason), findsOneWidget);
  });

  testWidgets('一度出した理由は端末から消える', (tester) async {
    SharedPreferences.setMockInitialValues({
      'session_lockout_reason': _retiredReason,
      'consent_agreed': true,
      'device_id': 'dev-1',
      'logged_out': true,
    });

    await _open(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session_lockout_reason'), isNull);
  });

  testWidgets('帯に触ると閉じる', (tester) async {
    SharedPreferences.setMockInitialValues({
      'session_lockout_reason': _retiredReason,
      'consent_agreed': true,
      'device_id': 'dev-1',
      'logged_out': true,
    });

    await _open(tester);
    expect(find.text(_retiredReason), findsOneWidget);

    await tester.tap(find.text(_retiredReason));
    await tester.pump();
    expect(find.text(_retiredReason), findsNothing);
  });

  testWidgets('理由が無い時は帯を出さない', (tester) async {
    SharedPreferences.setMockInitialValues({
      'consent_agreed': true,
      'device_id': 'dev-1',
      'logged_out': true,
    });

    await _open(tester);

    expect(find.byIcon(Icons.error_outline), findsNothing);
  });
}
