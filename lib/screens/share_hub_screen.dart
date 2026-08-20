// ============================================================
// lib/screens/share_hub_screen.dart — 共有タブ本体（FIELD・ボトム index2）
//
// 導線: home_screen.dart のボトム「共有」タブ（旧「通知」の位置）。
//   ★Scaffold を持たない Body 形式。シェル（home_screen）の AppBar が
//     _pageTitle の「共有」を出すため、自前 AppBar を持つと二重になる
//     （もう1枚のタブ Body・ProfileBody と同じ流儀）。
//
// 中身: タイル3枚（受信トレイ / 送信済み / 日報を送る）。
//   ★送信タイルは解禁済み（段階3-FIELD第2弾）。見る鍵があればタイルは必ず出し、
//     送る鍵が無い人はタップした時に案内を出す（袋小路にしない・下の送信タイルのタップ処理を参照）。
//     窓口は BundlesService.sendBundle（bundles_service.dart）。
//
// 権限: ProfileService.getProfile() の応答から共有2鍵を読む（専用メソッドは作らない
//   ＝二重取得口を作らないためのボス裁定）。★prefs へ長期キャッシュしない＝
//   共有タブを開くたびに取り直す。理由: 鍵は会社の管理者が後から付ける値で、
//   キャッシュすると「付与されたのに使えない」状態が残る。最終門番は BE
//   （bundles.js の blockShareViewer / blockShareManager が membership_id 起点で毎回 DB 直読み）。
// ============================================================

import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import '../services/bundles_service.dart';
import '../services/profile_service.dart';
import '../main.dart' show showJsSnackbar;
import 'share_inbox_screen.dart';
import 'share_outbox_screen.dart';
import 'share_send_screen.dart';

/// 共有2鍵の判定結果。
///
/// ★FE の役割は「入口を出すかどうか」だけ。BE の門番
/// （bundles.js の blockShareViewer / blockShareManager）を FE で完全再現はしない。再現できない理由を明記する:
///   ・cooperation（協力業者）の遮断は membership_type を見るが、FIELD は
///     この値をどこにも持っていない（lib 全体の grep で membership_type は
///     worker_service.dart の getWorkers のクエリ引数のみ＝自分の所属種別ではない）。
///   ・master の遮断は role で表現できるが、FIELD に master でログインする経路が無い。
///  よって FE の式は「事務・社長は鍵なしで通す／それ以外は鍵で判定」に留め、
///  漏れた場合は BE の 403 を画面に言い切って出す（袋小路にしない）。
class ShareKeys {
  const ShareKeys({
    required this.canView,
    required this.canManage,
    required this.canSend,
  });

  /// 共有を見られるか（受信トレイ・送信済み・束詳細）。
  final bool canView;

  /// 共有を処理できるか（現場紐付け・既読・確認）。
  final bool canManage;

  /// 共有を送れるか（日報を選んで他社へ送る）。
  final bool canSend;

  /// GET /profile の応答から組む。
  ///
  /// ★見る／処理する（BE bundles.js の blockShareViewer / blockShareManager）
  ///   ・admin_exec / admin_office は鍵なしで通過（両者の admin_exec / admin_office 分岐）。
  ///   ・boss / worker は can_share_view、処理はさらに can_share_manage も要る
  ///     （両者の boss / worker 分岐＝処理に見る鍵も要求する形をそのまま写す）。
  ///
  /// ★送る（BE bundles.js の requirePermission('can_share_send')）は
  ///   【条件が違う】。middleware/auth.js の requirePermission を実測した結果:
  ///   ・全権バイパスは admin_exec ただ一つ（requirePermission (c)）。
  ///     admin_office は見る／処理では鍵なしで通るが、送るときは
  ///     can_share_send の列を実際に持っていないと 403 になる。
  ///   ・cooperation は無条件 403（requirePermission (b)）。
  ///   ここを「事務も鍵なしで送れる」と書くと、事務のタイルが押せるのに
  ///   BE で 403 になる＝嘘の入口になる。よって officeSide でまとめない。
  ///
  /// ★キーが欠落・null・true 以外のときは false（fail-close）。
  factory ShareKeys.fromProfile(Map<String, dynamic> p) {
    final role = (p['role'] ?? '').toString();
    final isOfficeSide = role == 'admin_exec' || role == 'admin_office';
    final view   = p['can_share_view']   == true;
    final manage = p['can_share_manage'] == true;
    final send   = p['can_share_send']   == true;
    return ShareKeys(
      canView:   isOfficeSide || view,
      canManage: isOfficeSide || (view && manage),
      canSend:   role == 'admin_exec' || send,
    );
  }
}

class ShareHubBody extends StatefulWidget {
  const ShareHubBody({super.key});

  @override
  State<ShareHubBody> createState() => ShareHubBodyState();
}

class ShareHubBodyState extends State<ShareHubBody> {
  final ProfileService _profile = ProfileService();
  final BundlesService _bundles = BundlesService();

  bool _loading = true;
  String? _error;        // 鍵の取得に失敗した理由（言い切る）
  ShareKeys? _keys;      // null＝未取得
  String _role = '';     // GET /profile の role。送信画面の職人カード判定に渡す
  int _unread = 0;       // 受信トレイの未読【枚数】（read_at が null の受信明細数）
  String? _unreadError;  // 未読件数だけ取れなかった場合の理由（タイルは出す）

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// 共有タブへ進入するたびシェルから呼ばれる（home_screen の _setTab）。
  Future<void> reload() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    final pr = await _profile.getProfile();
    if (!mounted) return;
    if (!pr.ok || pr.data == null) {
      setState(() {
        _loading = false;
        _keys = null;
        _error = pr.statusCode == 0
            ? '通信できませんでした'
            : (pr.errorMessage ?? '権限を確認できませんでした');
      });
      return;
    }

    final keys = ShareKeys.fromProfile(pr.data!);
    final role = (pr.data!['role'] ?? '').toString();
    // 鍵が無いなら受信明細は叩かない（403 を取りに行くだけの通信をしない）。
    if (!keys.canView) {
      setState(() {
        _loading = false;
        _keys = keys;
        _role = role;
        _unread = 0;
        _unreadError = null;
      });
      return;
    }

    // 未読バッジ（モック承認済み）。read_at が null の受信明細を数える＝【枚数】。
    // ★件数だけのAPIは無いので一覧を1回引く。失敗してもタイルは出す（バッジだけ諦める）
    //   ＝「取れなかった」を 0 と言い切らないため _unreadError に理由を持つ。
    final rr = await _bundles.getReceipts();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _keys = keys;
      _role = role;
      if (rr.ok) {
        _unread = (rr.data ?? const []).where((e) => e['read_at'] == null).length;
        _unreadError = null;
      } else {
        _unread = 0;
        _unreadError = rr.statusCode == 0
            ? '通信できませんでした'
            : (rr.errorMessage ?? '未読件数を取得できませんでした');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: FieldTokens.accent));
    }
    if (_keys == null) return _errorView();
    if (!_keys!.canView) return _lockedView();
    return _tiles(_keys!);
  }

  // ── 鍵の取得に失敗（袋小路にしない: 理由＋再試行）──────────────
  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: FieldTokens.statusError),
              const SizedBox(height: 16),
              Text(_error ?? '権限を確認できませんでした',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 15)),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('再試行'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FieldTokens.accent,
                    side: const BorderSide(color: FieldTokens.accent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  // ── 見る鍵なし（🔒案内・モック承認済みの文言をそのまま出す）────────
  //   ★タイルは1枚も出さない。押しても403になる入口を見せない。
  Widget _lockedView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline,
                  size: 56, color: FieldTokens.textFaint),
              const SizedBox(height: 20),
              const Text('共有を見る権限がありません',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                '日報の共有を使うには『共有閲覧』の権限が必要です。\n会社の管理者に付与を依頼してください。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: FieldTokens.textSupport, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              const Text('※権限が付与されると自動で使えるようになります',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: FieldTokens.textFaint, fontSize: 12)),
              const SizedBox(height: 24),
              // 付与直後に自分で確かめられる口（鍵はタブ進入ごとに取り直すが、
              // 開いたまま待つ人のために明示の再確認も置く）。
              SizedBox(
                width: 200,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('権限を再確認'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FieldTokens.accent,
                    side: const BorderSide(color: FieldTokens.accent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  // ── タイル2枚（受信トレイ / 送信済み）─────────────────────────
  Widget _tiles(ShareKeys keys) => RefreshIndicator(
        color: FieldTokens.accent,
        backgroundColor: FieldTokens.surfaceCard,
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // 未読件数だけ取れなかったときは黙らない（バッジを 0 と言い切らない）。
            if (_unreadError != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: FieldTokens.statusWarning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: FieldTokens.statusWarning),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: FieldTokens.statusWarning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('未読件数を表示できません（$_unreadError）',
                        style: const TextStyle(
                            color: FieldTokens.textBody, fontSize: 12)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            _ShareTile(
              icon: Icons.inbox_outlined,
              title: '受信トレイ',
              subtitle: '他社から届いた日報',
              badge: _unread,
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ShareInboxScreen(canManage: keys.canManage),
                ));
                // 戻ったら未読が減っている可能性があるので取り直す。
                if (mounted) reload();
              },
            ),
            const SizedBox(height: 12),
            _ShareTile(
              icon: Icons.outbox_outlined,
              title: '送信済み',
              subtitle: '自社が他社へ送った日報',
              badge: 0,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ShareOutboxScreen(),
              )),
            ),
            const SizedBox(height: 12),
            // ── 送信（解禁済み）───────────────────────────────
            //   ★見る鍵があれば【タイルは必ず見せる】。送る鍵が無い人には
            //     タップした時に「何が足りないか」を言う（袋小路にしない）。
            //     タイルごと隠すと「自分は送れないのか、機能が無いのか」が
            //     区別できず、管理者に依頼する当てが付かない。
            //   ★送る門番は見る／処理と条件が違う（事務も鍵が必要）。
            //     判定の根拠は ShareKeys.fromProfile のコメント参照。
            _ShareTile(
              icon: Icons.send_outlined,
              title: '日報を送る',
              subtitle: keys.canSend
                  ? '条件で選んで他社へ共有する'
                  : '『共有送信』の権限が必要です',
              badge: 0,
              locked: !keys.canSend,
              onTap: () {
                if (!keys.canSend) {
                  showJsSnackbar(
                      context, '共有を送る権限がありません（『共有送信』が必要）',
                      isError: true);
                  return;
                }
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ShareSendScreen(role: _role),
                ));
              },
            ),
          ],
        ),
      );
}

// ─── タイル1枚 ────────────────────────────────────────────
// 未読バッジの見た目は home_screen.dart の _badgeDot と同型
// （丸・statusError 地・textBody 文字・bold）。同じ意味の記号を2つの形で出さない。
class _ShareTile extends StatelessWidget {
  const _ShareTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int badge;
  final VoidCallback onTap;

  /// 鍵が足りず実行できないタイル。押せるままにして案内を出すため
  /// onTap は無効化せず、見た目だけ落として🔒を添える。
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FieldTokens.outline),
        ),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(icon,
                color: locked ? FieldTokens.textFaint : FieldTokens.accent,
                size: 28),
            if (badge > 0)
              Positioned(
                top: -4, right: -6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: FieldTokens.statusError, shape: BoxShape.circle),
                  child: Text('$badge',
                      style: const TextStyle(
                          color: FieldTokens.textBody,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
          const SizedBox(width: 16),
          // ★1行に収める必要がある文字は FittedBox で縮める（ellipsis / clip 禁止）。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(title,
                      style: TextStyle(
                          color: locked
                              ? FieldTokens.textSupport
                              : FieldTokens.textBody,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(subtitle,
                      style: const TextStyle(
                          color: FieldTokens.textSupport, fontSize: 12)),
                ),
              ],
            ),
          ),
          Icon(locked ? Icons.lock_outline : Icons.chevron_right,
              color: FieldTokens.textSupport,
              size: locked ? 18 : 24),
        ]),
      ),
    );
  }
}
