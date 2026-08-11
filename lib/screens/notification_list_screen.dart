// ============================================================
// lib/screens/notification_list_screen.dart - 通知一覧（お知らせ）
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../main.dart' show showJsSnackbar;
import '../services/notification_service.dart';
import '../widgets/punch_remind_dialog.dart';
import 'home_screen.dart' show ReportTabNavigator;
import 'revision_inbox_screen.dart';
import 'tamper_incident_detail_screen.dart';

// ─────────────────────────────────────────────
// NotificationListBody — Scaffold なし（シェルのタブとして使う実体）
//   monthly_history_screen.dart の MonthlyHistoryBody(:17) / MonthlyHistoryScreen(:233) と同流儀。
//   State は公開する（RevisionInboxBodyState・revision_inbox_screen.dart:49 と同じ既存流儀）。
//   AppBar の「すべて既読」は表示側（Screen ラッパー / シェル）から
//   GlobalKey<NotificationListBodyState> 経由で hasItems / markAllRead() を使う。
//   ★中身（項目・並び・色）は1行も変更していない。Scaffold と AppBar を剥がしただけ。
// ─────────────────────────────────────────────
class NotificationListBody extends StatefulWidget {
  const NotificationListBody({super.key, this.onStateChanged});

  /// 一覧の読み込み・既読化で内部状態が変わったときに呼ぶ。
  /// 表示側の AppBar（すべて既読の活性/非活性）を追随させるためだけに使う。
  final VoidCallback? onStateChanged;

  @override
  State<NotificationListBody> createState() => NotificationListBodyState();
}

class NotificationListBodyState extends State<NotificationListBody> {
  /// 「すべて既読」ボタンの活性判定（旧 :123 の `_items.isEmpty` と同一の値）。
  bool get hasItems => _items.isNotEmpty;

  /// 「すべて既読」実行（旧 :123 の onPressed と同一の実体）。
  Future<void> markAllRead() => _markAllRead();

  final _svc = NotificationService();

  bool _loading = true;
  bool _error = false;
  List<Map<String, dynamic>> _items = [];
  final Set<String> _expanded = {}; // その場展開中のID（type=その他）

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final res = await _svc.fetchNotifications();
    if (!mounted) return;
    if (res.ok) {
      setState(() {
        _items = (res.data ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
        _error = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = true;
      });
    }
    // 表示側の AppBar「すべて既読」の活性/非活性を追随させる（描画内容には影響しない）
    widget.onStateChanged?.call();
  }

  Future<void> _markAllRead() async {
    final res = await _svc.markAllRead();
    if (!mounted) return;
    if (res.ok) {
      await _load();
    } else {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('既読化に失敗しました'),
          backgroundColor: FieldTokens.statusError,
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  // 行タップ: 全typeで統一の挙動。
  //  ①個別既読（ドット即消し=ローカルstate先行更新）＋②その場でインライン展開/折りたたみ。
  //  遷移はしない（遷移は展開部のアクションボタンから）。
  Future<void> _onTapItem(Map<String, dynamic> item) async {
    final id = (item['id'] ?? '').toString();
    final wasUnread = item['is_read'] != true;

    // ①展開トグル ＋ ②ドット即消し（ローカル先行更新）
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
      item['is_read'] = true;
    });

    // 元未読の初回タップ時のみサーバへ個別既読を反映
    // （失敗しても表示は既読のまま＝袋小路にしない・次回_loadで真実同期）
    if (wasUnread) {
      await _svc.markRead(id);
    }
  }

  // 展開部アクション: 日報を書く（一覧を閉じて日報タブへ）
  // ★この画面はボトム「通知」タブの実体としても使われる（home_screen.dart のタブ index2）。
  //   タブとして表示されているときは pop する相手が居らず、無条件 pop はシェルごと
  //   閉じてしまう。canPop() で守る（push されて開かれている従来経路の挙動は不変）。
  void _goReport() {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
    ReportTabNavigator.go();
  }

  // 展開部アクション: 修正依頼を開く
  void _openRevision() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RevisionInboxScreen()),
    );
  }

  // 展開部アクション: 改ざんの詳細を開く（tamper_detected / tamper_status_changed）
  //   ★事件の識別子は ref_id（BE services/notify.js が refId: incident_id で積む）。
  //     欠落していれば遷移先が決まらないので、推測せずここで止めて理由を出す
  //     （_openPunchRemind:154-159 と同じ流儀）。
  void _openTamperIncident(Map<String, dynamic> item) {
    final incidentId = (item['ref_id'] ?? '').toString();
    if (incidentId.isEmpty) {
      showJsSnackbar(context, '対象の事案を特定できませんでした。事務へご連絡ください。',
          isError: true);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TamperIncidentDetailScreen(incidentId: incidentId),
      ),
    );
  }

  // ── 展開部アクション: 打刻を申告する（punch_remind_in / punch_remind_out）──
  //   ★今回追加した経路だけの多重送信ガード。この画面には元々ガードフラグが
  //     1つも無いため新設した。既存の _onTapItem / _markAllRead / _goReport /
  //     _openRevision には一切かけていない（挙動を変えないため）。
  bool _punchRemindBusy = false;

  //   ★ダイアログ本体は FCM経路（fcm_service → home_screen）と同一の
  //     showPunchRemindFlow を呼ぶ＝同じ機能を2つ作らない。
  //     context は当 State のもの（lib 配下の既存 showDialog と同じ流儀）。
  Future<void> _openPunchRemind(Map<String, dynamic> item) async {
    if (_punchRemindBusy) return;

    final refId  = (item['ref_id'] ?? '').toString();
    final type   = (item['type']   ?? '').toString();
    final parsed = _parsePunchRemindRefId(refId, type);

    // 解析失敗＝対象日が特定できない。推測で埋めずにここで止める。
    // 文言は punch_remind_dialog.dart:51 と同一（同じ事象は同じ言葉で言う）。
    if (parsed == null) {
      debugPrint('punch_remind: ref_id を解析できません ref_id=$refId type=$type');
      showJsSnackbar(context, '対象日を特定できませんでした。事務へご連絡ください。',
          isError: true);
      return;
    }

    setState(() => _punchRemindBusy = true);
    try {
      await showPunchRemindFlow(
        context,
        side:      parsed.side,
        shiftType: parsed.shiftType,
        bizDate:   parsed.bizDate,
      );
    } finally {
      if (mounted) setState(() => _punchRemindBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: _buildBody());
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: FieldTokens.accent));
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: FieldTokens.textSupport, size: 48),
            const SizedBox(height: 12),
            const Text('お知らせを読み込めませんでした',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('再試行'),
              style: OutlinedButton.styleFrom(
                foregroundColor: FieldTokens.accent,
                side: const BorderSide(color: FieldTokens.accent),
              ),
            ),
          ],
        ),
      );
    }
    // 空・非空どちらも Pull-to-refresh 可能にする（空でもスクロール領域を確保）
    return RefreshIndicator(
      color: FieldTokens.accent,
      backgroundColor: FieldTokens.surfaceCard,
      onRefresh: _load,
      child: _items.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 160),
                Center(
                  child: Text('お知らせはありません',
                      style:
                          TextStyle(color: FieldTokens.textSupport, fontSize: 14)),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: FieldTokens.outline),
              itemBuilder: (_, i) => _NotificationRow(
                item: _items[i],
                expanded: _expanded.contains((_items[i]['id'] ?? '').toString()),
                onTap: () => _onTapItem(_items[i]),
                onReport: _goReport,
                onRevision: _openRevision,
                onPunchRemind: () => _openPunchRemind(_items[i]),
                punchRemindBusy: _punchRemindBusy,
                onTamper: () => _openTamperIncident(_items[i]),
              ),
            ),
    );
  }
}

// ─── 通知1行 ─────────────────────────────────────────────
// ─────────────────────────────────────────────
// NotificationListScreen — 単体プッシュ用（Scaffold ラッパー）
//   monthly_history_screen.dart:233 の MonthlyHistoryScreen と同流儀。
//   AppBar（背景色・タイトル・すべて既読ボタンの文言/色/太さ/サイズ）は
//   切り出し前（旧 :116-136）と同一。1文字も変えていない。
// ─────────────────────────────────────────────
class NotificationListScreen extends StatefulWidget {
  const NotificationListScreen({super.key});

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
  final _bodyKey = GlobalKey<NotificationListBodyState>();

  @override
  Widget build(BuildContext context) {
    final hasItems = _bodyKey.currentState?.hasItems ?? false;
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        title: const Text('お知らせ'),
        actions: [
          TextButton(
            onPressed: hasItems ? () => _bodyKey.currentState?.markAllRead() : null,
            child: Text(
              'すべて既読',
              style: TextStyle(
                color: hasItems ? FieldTokens.accent : FieldTokens.textFaint,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: NotificationListBody(
        key: _bodyKey,
        onStateChanged: () { if (mounted) setState(() {}); },
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.expanded,
    required this.onTap,
    required this.onReport,
    required this.onRevision,
    required this.onPunchRemind,
    required this.punchRemindBusy,
    required this.onTamper,
  });

  final Map<String, dynamic> item;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onReport;   // 'report_remind' 展開時「日報を書く」
  final VoidCallback onRevision; // 'revision_request' 展開時「修正依頼を開く」
  final VoidCallback onPunchRemind; // 'punch_remind_*' 展開時「打刻を申告する」
  final bool punchRemindBusy;       // 上のボタンの連打防止（実行中は押せない）
  final VoidCallback onTamper;      // 'tamper_*' 展開時「改ざんの詳細を開く」

  @override
  Widget build(BuildContext context) {
    final unread = item['is_read'] != true;
    final title = (item['title'] ?? '').toString();
    final body = (item['body'] ?? '').toString();
    final createdAt = (item['created_at'] ?? '').toString();
    final type = (item['type'] ?? '').toString();

    return InkWell(
      onTap: onTap,
      child: Container(
        // 未読=surface明るめ／既読=沈み(background)。既読でも展開・ボタンは使える。
        color: unread ? FieldTokens.surfaceCard : FieldTokens.bgBase,
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左端8pxゴールドドット（未読のみ）
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 8),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: unread ? FieldTokens.accent : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title.isEmpty ? '(無題)' : title,
                          style: TextStyle(
                            color: unread
                                ? FieldTokens.textBody
                                : FieldTokens.textSupport,
                            fontSize: 15,
                            fontWeight:
                                unread ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _relativeTime(createdAt),
                        style: const TextStyle(
                            color: FieldTokens.textFaint, fontSize: 11),
                      ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    // 折りたたみ時=1行ellipsis／展開時=全文
                    Text(
                      body,
                      maxLines: expanded ? null : 1,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: FieldTokens.textSupport,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ],
                  // ─── 展開部: 絶対日時 ＋ typeに応じたアクションボタン ───
                  if (expanded) ...[
                    const SizedBox(height: 8),
                    Text(
                      _absoluteTime(createdAt),
                      style: const TextStyle(
                          color: FieldTokens.textFaint, fontSize: 11),
                    ),
                    if (type == 'report_remind') ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _ActionButton(
                          icon: Icons.edit_note,
                          label: '日報を書く',
                          onPressed: onReport,
                        ),
                      ),
                    ] else if (type == 'revision_request') ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _ActionButton(
                          icon: Icons.fact_check_outlined,
                          label: '修正依頼を開く',
                          onPressed: onRevision,
                        ),
                      ),
                    ],
                    // 打刻のお知らせ。上の if/else if 連鎖には手を入れず独立した
                    // if で足している（type は互いに排他のため挙動は同じ）。
                    if (type == 'punch_remind_in' ||
                        type == 'punch_remind_out') ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _ActionButton(
                          icon: Icons.how_to_reg_outlined,
                          label: '打刻を申告する',
                          // 連打防止: 実行中は押せなくする（実体側にも
                          // _punchRemindBusy の早期returnガードがある）。
                          onPressed: punchRemindBusy ? null : onPunchRemind,
                        ),
                      ),
                    ],
                    // 改ざんのお知らせ（検知＝tamper_detected / 対処＝tamper_status_changed）。
                    // 打刻と同様、既存の if/else if 連鎖には手を入れず独立した if で足す。
                    if (type == 'tamper_detected' ||
                        type == 'tamper_status_changed') ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _ActionButton(
                          icon: Icons.gpp_maybe_outlined,
                          label: '改ざんの詳細を開く',
                          onPressed: onTamper,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 展開部の小さめアクションボタン（幅いっぱいにしない）───
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  // null 可（＝無効化）。既存の呼び手2箇所は常に非nullを渡すため挙動は不変。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: FieldTokens.accent,
        side: const BorderSide(color: FieldTokens.accent),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ─── 打刻のお知らせ ref_id の解析 ────────────────────────────────────────
// BE services/punchRemind.js:217 が作る形:
//     punch_remind:{業務日}:{シフト}:{側}
//   実例: punch_remind:2026-07-21:day:in
//   業務日 'YYYY-MM-DD' にコロンは含まれないため ':' 区切りで必ず4要素になる。
// BE routes/notifications.js の SELECT に ref_id が含まれるため FE まで届く。
//
// ★1つでも条件を満たさなければ null（＝解析失敗）を返す。推測で埋めない。
//   bizDate と shiftType は絶対に補完しない（黙って別の日・別のシフトへ
//   申告してしまうため）。side だけは ref_id が壊れていたときに限り
//   通知の type から導く（BE は type と side を同じ判定から作るので一致する。
//   fcm_service.dart:126-131 と同じ流儀）。
({String bizDate, String shiftType, String side})? _parsePunchRemindRefId(
    String refId, String type) {
  final parts = refId.split(':');
  if (parts.length != 4) return null;
  if (parts[0] != 'punch_remind') return null;

  final bizDate   = parts[1];
  final shiftType = parts[2];
  final rawSide   = parts[3];

  // 業務日は 'YYYY-MM-DD'（4桁-2桁-2桁）であること。
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(bizDate)) return null;
  // シフトは 'day' | 'night' であること（補完しない）。
  if (shiftType != 'day' && shiftType != 'night') return null;

  // 側は 'in' | 'out'。ref_id を正とし、不正なときだけ type から導く。
  final side = (rawSide == 'in' || rawSide == 'out')
      ? rawSide
      : (type == 'punch_remind_in'
          ? 'in'
          : type == 'punch_remind_out'
              ? 'out'
              : '');
  if (side.isEmpty) return null;

  return (bizDate: bizDate, shiftType: shiftType, side: side);
}

// ─── 相対時刻（created_at: timestamptz ISO → toLocal()でJST表示）───
String _relativeTime(String iso) {
  if (iso.isEmpty) return '';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  final dt = parsed.toLocal();
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.isNegative) return 'たった今';
  if (diff.inMinutes < 1) return 'たった今';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
  if (diff.inHours < 24) return '${diff.inHours}時間前';

  // 「昨日」判定はカレンダー日付差で行う（時刻差24hだけだと境界がずれるため）
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(dt.year, dt.month, dt.day);
  final dayDiff = today.difference(thatDay).inDays;
  if (dayDiff == 1) return '昨日';
  if (dayDiff < 7) return '$dayDiff日前';
  return '${dt.year}/${dt.month}/${dt.day}';
}

// ─── 絶対日時（展開部用・toLocal()でJST・yyyy/M/d HH:mm）───
String _absoluteTime(String iso) {
  if (iso.isEmpty) return '';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  final dt = parsed.toLocal();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${dt.year}/${dt.month}/${dt.day} $hh:$mm';
}
