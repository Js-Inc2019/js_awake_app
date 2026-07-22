// ============================================================
// lib/screens/notification_list_screen.dart - 通知一覧（お知らせ）
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/js_colors.dart';
import '../services/notification_service.dart';
import 'home_screen.dart' show ReportTabNavigator;
import 'revision_inbox_screen.dart';

class NotificationListScreen extends StatefulWidget {
  const NotificationListScreen({super.key});

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
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
    if (res['success'] == true) {
      setState(() {
        _items = ((res['notifications'] as List?) ?? [])
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
  }

  Future<void> _markAllRead() async {
    final res = await _svc.markAllRead();
    if (!mounted) return;
    if (res['success'] == true) {
      await _load();
    } else {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('既読化に失敗しました'),
          backgroundColor: JsColors.error,
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
  void _goReport() {
    Navigator.of(context).pop();
    ReportTabNavigator.go();
  }

  // 展開部アクション: 修正依頼を開く
  void _openRevision() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RevisionInboxScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.background,
      appBar: AppBar(
        backgroundColor: JsColors.background,
        title: const Text('お知らせ'),
        actions: [
          TextButton(
            onPressed: _items.isEmpty ? null : _markAllRead,
            child: Text(
              'すべて既読',
              style: TextStyle(
                color: _items.isEmpty ? JsColors.textWeak : JsColors.accent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: JsColors.accent));
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: JsColors.textMid, size: 48),
            const SizedBox(height: 12),
            const Text('お知らせを読み込めませんでした',
                style: TextStyle(color: JsColors.textMid, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('再試行'),
              style: OutlinedButton.styleFrom(
                foregroundColor: JsColors.accent,
                side: const BorderSide(color: JsColors.accent),
              ),
            ),
          ],
        ),
      );
    }
    // 空・非空どちらも Pull-to-refresh 可能にする（空でもスクロール領域を確保）
    return RefreshIndicator(
      color: JsColors.accent,
      backgroundColor: JsColors.surface,
      onRefresh: _load,
      child: _items.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 160),
                Center(
                  child: Text('お知らせはありません',
                      style:
                          TextStyle(color: JsColors.textMid, fontSize: 14)),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: JsColors.border),
              itemBuilder: (_, i) => _NotificationRow(
                item: _items[i],
                expanded: _expanded.contains((_items[i]['id'] ?? '').toString()),
                onTap: () => _onTapItem(_items[i]),
                onReport: _goReport,
                onRevision: _openRevision,
              ),
            ),
    );
  }
}

// ─── 通知1行 ─────────────────────────────────────────────
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.expanded,
    required this.onTap,
    required this.onReport,
    required this.onRevision,
  });

  final Map<String, dynamic> item;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onReport;   // 'report_remind' 展開時「日報を書く」
  final VoidCallback onRevision; // 'revision_request' 展開時「修正依頼を開く」

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
        color: unread ? JsColors.surface : JsColors.background,
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
                  color: unread ? JsColors.accent : Colors.transparent,
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
                                ? JsColors.textStrong
                                : JsColors.textMid,
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
                            color: JsColors.textWeak, fontSize: 11),
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
                          color: JsColors.textMid,
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
                          color: JsColors.textWeak, fontSize: 11),
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
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: JsColors.accent,
        side: const BorderSide(color: JsColors.accent),
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
