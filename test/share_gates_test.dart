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
import 'package:js_awake_app/screens/share_send_screen.dart'
    show ShareSendScreen, kSiteNone;

void main() {
  // ──────────────────────────────────────────────────────────
  // ① 共有2鍵の判定（BE routes/bundles.js の blockShareViewer / blockShareManager を FE 側で写したもの）
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
  // ①' 送る鍵。★見る／処理とは条件が違う。
  //    BE middleware/auth.js の requirePermission('can_share_send'):
  //      全権バイパスは admin_exec ただ一つ（:187-189）。admin_office は
  //      見る／処理では鍵なしで通るが、送るときは列を持っていないと 403。
  //    ここを取り違えると「事務のタイルが押せるのに BE で 403」＝嘘の入口になる。
  // ──────────────────────────────────────────────────────────
  group('ShareKeys.canSend（送る門番は条件が違う）', () {
    test('社長(admin_exec)は鍵なしでも送れる（全権バイパス）', () {
      expect(ShareKeys.fromProfile({'role': 'admin_exec'}).canSend, isTrue);
    });

    // ★本命。事務は「見る・処理」は鍵なしで通るが「送る」は鍵が要る。
    test('事務(admin_office)は鍵なしでは送れない（見る・処理とは違う）', () {
      final k = ShareKeys.fromProfile({'role': 'admin_office'});
      expect(k.canView, isTrue);    // 見るは通る
      expect(k.canManage, isTrue);  // 処理も通る
      expect(k.canSend, isFalse);   // 送るだけ通らない
    });

    test('事務(admin_office)は can_share_send があれば送れる', () {
      final k = ShareKeys.fromProfile({
        'role': 'admin_office',
        'can_share_send': true,
      });
      expect(k.canSend, isTrue);
    });

    test('職長・職人は can_share_send があれば送れる（view/manage は不要）', () {
      for (final role in ['boss', 'worker']) {
        final k = ShareKeys.fromProfile({
          'role': role,
          'can_share_send': true,
        });
        expect(k.canSend, isTrue, reason: role);
      }
    });

    test('鍵ゼロの職長・職人は送れない', () {
      for (final role in ['boss', 'worker']) {
        expect(ShareKeys.fromProfile({'role': role}).canSend, isFalse,
            reason: role);
      }
    });

    test('can_share_send が true 以外なら送れない（fail-close）', () {
      for (final v in <Object?>['true', 1, null, '']) {
        expect(
          ShareKeys.fromProfile({'role': 'boss', 'can_share_send': v}).canSend,
          isFalse,
          reason: 'can_share_send=$v',
        );
      }
    });

    test('view/manage を持っていても send 鍵が無ければ送れない', () {
      final k = ShareKeys.fromProfile({
        'role': 'boss',
        'can_share_view': true,
        'can_share_manage': true,
      });
      expect(k.canView, isTrue);
      expect(k.canManage, isTrue);
      expect(k.canSend, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────
  // ①'' 送信画面の role 判定。2つの集合が違うことを固定する。
  //    ・職人カードを出すか   … role != 'worker'（BE reports.js の GET /reports の scopeClause）
  //    ・職人候補APIを叩けるか … boss/admin_office/admin_exec（BE workers.js の GET /workers の requireRole）
  //    master は「会社軸だが職人候補は取れない」＝この2つが食い違う唯一の顔。
  // ──────────────────────────────────────────────────────────
  group('ShareSendScreen の role 判定', () {
    test('worker は会社軸ではなく、職人候補も取れない', () {
      const w = ShareSendScreen(role: 'worker');
      expect(w.isCompanyScope, isFalse);
      expect(w.canListWorkers, isFalse);
    });

    test('boss / 事務 / 社長は会社軸で職人候補も取れる', () {
      for (final role in ['boss', 'admin_office', 'admin_exec']) {
        final w = ShareSendScreen(role: role);
        expect(w.isCompanyScope, isTrue, reason: role);
        expect(w.canListWorkers, isTrue, reason: role);
      }
    });

    test('master は会社軸だが職人候補は取れない（2つの集合は別物）', () {
      const w = ShareSendScreen(role: 'master');
      expect(w.isCompanyScope, isTrue);
      expect(w.canListWorkers, isFalse);
    });

    test('空・未知の role は会社軸扱いになる（BEが403で断る）', () {
      // ★FE は role で入口を作らない。GET /reports の想定外role は
      //   BE が 403 ROLE_SCOPE_FORBIDDEN で断る（reports.js）。
      const w = ShareSendScreen(role: '');
      expect(w.isCompanyScope, isTrue);
      expect(w.canListWorkers, isFalse);
    });
  });

  // BE の予約語トークン。sites マスタには存在しない擬似ID。
  test('kSiteNone は BE の site_ids=none と同一の文字列', () {
    expect(kSiteNone, 'none');
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
