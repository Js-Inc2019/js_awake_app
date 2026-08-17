// ============================================================
// test/share_gates_test.dart — 会社間共有（束）の判定ロジック
//
// 検査対象は「間違えると画面が嘘をつく」3点だけに絞ってある:
//   ① ShareKeys.fromProfile … 共有タブの入口を出すかどうか（13鍵＋役職）
//   ② receiptMarkOf         … 受信トレイの行の印（改ざん / 既読 / 未読）
//   ③ fmtShareDate(Time)    … 日付・日時の整形（生ISOを出さない）
// HTTP は一切叩かない（既存 test/ 4本と同じ純ロジック方式）。
//
// ★期待値は実装から import せずここへ直書きしている。実装を写すと
//   「実装が変わったらテストも一緒に変わる」＝何も検査していない状態になる。
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:js_awake_app/screens/share_hub_screen.dart' show ShareKeys;
import 'package:js_awake_app/screens/share_inbox_screen.dart'
    show ReceiptMark, receiptMarkOf, fmtShareDate, fmtShareDateTime;

void main() {
  // ──────────────────────────────────────────────────────────
  // ① 共有2鍵の判定（BE routes/bundles.js:458-508 の門番を FE 側で写したもの）
  //    見る   = admin_exec / admin_office は鍵なし可、他は can_share_view
  //    処理する= 同上、他は can_share_view AND can_share_manage
  // ──────────────────────────────────────────────────────────
  group('ShareKeys.fromProfile', () {
    test('社長(admin_exec)は鍵なしで見る・処理の両方が通る', () {
      final k = ShareKeys.fromProfile({'role': 'admin_exec'});
      expect(k.canView, isTrue);
      expect(k.canManage, isTrue);
    });

    test('事務(admin_office)は鍵なしで見る・処理の両方が通る', () {
      final k = ShareKeys.fromProfile({'role': 'admin_office'});
      expect(k.canView, isTrue);
      expect(k.canManage, isTrue);
    });

    test('職長(boss)は鍵ゼロなら見るも処理も通らない', () {
      final k = ShareKeys.fromProfile({'role': 'boss'});
      expect(k.canView, isFalse);
      expect(k.canManage, isFalse);
    });

    test('職人(worker)は can_share_view だけなら「見るのみ」', () {
      final k = ShareKeys.fromProfile({
        'role': 'worker',
        'can_share_view': true,
      });
      expect(k.canView, isTrue);
      expect(k.canManage, isFalse);
    });

    test('職人(worker)は view+manage の両方で処理まで通る', () {
      final k = ShareKeys.fromProfile({
        'role': 'worker',
        'can_share_view': true,
        'can_share_manage': true,
      });
      expect(k.canView, isTrue);
      expect(k.canManage, isTrue);
    });

    // ★これが本命。処理鍵だけ持っていても通してはいけない
    //   （見られない人が中身を書き換えられる状態を作らない＝BE :477-479 と同趣旨）。
    test('manage だけ持っていて view が無い場合は処理も通らない', () {
      final k = ShareKeys.fromProfile({
        'role': 'boss',
        'can_share_manage': true,
      });
      expect(k.canView, isFalse);
      expect(k.canManage, isFalse);
    });

    test('キーが応答に無い（旧BE等）なら false へ倒す', () {
      final k = ShareKeys.fromProfile({'role': 'worker'});
      expect(k.canView, isFalse);
      expect(k.canManage, isFalse);
    });

    test('true 以外の値（文字列 "true" / 1 / null）は全て false へ倒す', () {
      for (final v in <Object?>['true', 1, 0, null, '']) {
        final k = ShareKeys.fromProfile({
          'role': 'worker',
          'can_share_view': v,
          'can_share_manage': v,
        });
        expect(k.canView, isFalse, reason: 'can_share_view=$v');
        expect(k.canManage, isFalse, reason: 'can_share_manage=$v');
      }
    });

    test('role が空・未知なら鍵が無い限り通らない', () {
      expect(ShareKeys.fromProfile(const {}).canView, isFalse);
      expect(ShareKeys.fromProfile({'role': ''}).canView, isFalse);
      expect(ShareKeys.fromProfile({'role': 'unknown_role'}).canView, isFalse);
    });

    // ★既知の差分を明文化しておく検査。master の遮断と協力業者の遮断は
    //   BE だけが持つ（FIELD は membership_type を保持しておらず、master で
    //   ログインする経路も無い）。ここが true になるのは仕様どおりで、
    //   実際の遮断は BE の blockMaster / blockCooperation が行う。
    //   この検査が落ちたら「FE 側でも遮断するようにした」ということなので、
    //   その時はこのコメントごと書き換えること。
    test('master が view 鍵を持つ場合、FE は入口を出す（遮断はBEの責務）', () {
      final k = ShareKeys.fromProfile({
        'role': 'master',
        'can_share_view': true,
      });
      expect(k.canView, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────
  // ② 行の印（3段階）。優先順は 改ざん > 既読/未読。
  // ──────────────────────────────────────────────────────────
  group('receiptMarkOf', () {
    test('receipt_status=tampered は既読でも「改ざん」が勝つ', () {
      expect(
        receiptMarkOf({
          'receipt_status': 'tampered',
          'read_at': '2026-08-17T10:00:00',
          'is_updated': false,
        }),
        ReceiptMark.tampered,
      );
    });

    test('is_updated=true は receipt_status が read でも「改ざん」枠', () {
      expect(
        receiptMarkOf({
          'receipt_status': 'read',
          'read_at': '2026-08-17T10:00:00',
          'is_updated': true,
        }),
        ReceiptMark.tampered,
      );
    });

    test('read_at があれば既読', () {
      expect(
        receiptMarkOf({
          'receipt_status': 'read',
          'read_at': '2026-08-17T10:00:00',
          'is_updated': false,
        }),
        ReceiptMark.read,
      );
    });

    test('read_at が null なら未読', () {
      expect(
        receiptMarkOf({
          'receipt_status': 'sent',
          'read_at': null,
          'is_updated': false,
        }),
        ReceiptMark.unread,
      );
    });

    test('is_updated が欠落していても落ちず、read_at で決まる', () {
      expect(receiptMarkOf({'receipt_status': 'sent'}), ReceiptMark.unread);
      expect(
        receiptMarkOf({'receipt_status': 'read', 'read_at': '2026-08-17T10:00:00'}),
        ReceiptMark.read,
      );
    });

    test('is_updated が true 以外（文字列 "true" 等）なら改ざん枠にしない', () {
      expect(
        receiptMarkOf({'receipt_status': 'sent', 'is_updated': 'true'}),
        ReceiptMark.unread,
      );
    });
  });

  // ──────────────────────────────────────────────────────────
  // ③ 整形。生ISOを画面へ出さないことと、空を「-」と言い切ること。
  //    ★TZ 依存を持ち込まないため Z 無しの文字列で検査する
  //      （Z 付きは端末TZで結果が変わるので、テストの期待値にできない）。
  // ──────────────────────────────────────────────────────────
  group('fmtShareDate', () {
    test('YYYY-MM-DD → MM/DD', () {
      expect(fmtShareDate('2026-08-17'), '08/17');
    });

    test('ISO日時でも日付部だけ MM/DD', () {
      expect(fmtShareDate('2026-01-05T23:45:00'), '01/05');
    });

    test('空・null は「-」', () {
      expect(fmtShareDate(''), '-');
      expect(fmtShareDate(null), '-');
    });

    test('解析できない文字列は推測せずそのまま返す', () {
      expect(fmtShareDate('不明'), '不明');
    });
  });

  group('fmtShareDateTime', () {
    test('ISO（TZ指定なし＝端末時刻）→ MM/DD HH:mm', () {
      expect(fmtShareDateTime('2026-08-17T09:05:00'), '08/17 09:05');
    });

    test('0埋めされる', () {
      expect(fmtShareDateTime('2026-01-02T03:04:00'), '01/02 03:04');
    });

    test('空・null は「-」', () {
      expect(fmtShareDateTime(''), '-');
      expect(fmtShareDateTime(null), '-');
    });

    test('解析できない文字列は推測せずそのまま返す', () {
      expect(fmtShareDateTime('たぶん昨日'), 'たぶん昨日');
    });
  });
}
