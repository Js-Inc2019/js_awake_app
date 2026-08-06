// ============================================================
// lib/screens/inbox_screen.dart - 受信トレイ画面
// 他社から受信した日報を表示・改ざん検知
// ============================================================

import 'package:flutter/material.dart';
 import '../core/theme/field_tokens.dart';
import '../services/share_service.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  final ShareService _shareService = ShareService();
  late TabController _tabController;

  List<dynamic> _inbox  = [];
  List<dynamic> _outbox = [];
  bool _isLoading = true;
  int  _tamperedCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final inboxResult  = await _shareService.getInbox();
    final outboxResult = await _shareService.getOutbox();

    setState(() {
      _isLoading = false;
      if (inboxResult['success'] == true) {
        _inbox = inboxResult['shares'] as List<dynamic>;
        _tamperedCount = inboxResult['tampered_count'] as int? ?? 0;
      }
      if (outboxResult['success'] == true) {
        _outbox = outboxResult['shares'] as List<dynamic>;
      }
    });
  }

  // ============================================================
  // 既読にする
  // ============================================================

  Future<void> _markAsRead(String shareId) async {
    await _shareService.markAsRead(shareId);
    _loadData();
  }

  // ============================================================
  // 改ざんチェック
  // ============================================================

  Future<void> _checkTamper(String shareId) async {
    // チェック中のローディング表示（閉じられないバリア付き）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: FieldTokens.accent),
            SizedBox(width: 20),
            Expanded(
              child: Text('改ざんチェック中…',
                  style: TextStyle(color: FieldTokens.textBody)),
            ),
          ],
        ),
      ),
    );

    final result = await _shareService.checkTamper(shareId);
    if (!mounted) return;
    Navigator.pop(context); // ローディングを閉じる
    if (!mounted) return;

    // 三値分岐（'ok' / 'tampered' / 'error'）。
    // 確認失敗(error)は ✅正常 とは絶対に混同させず、不明表示＋再試行を出す。
    final status = result['status'];
    final String title;
    final Color titleColor;
    if (status == 'tampered') {
      title = '⚠️ 改ざん検知';
      titleColor = Colors.red;
    } else if (status == 'ok') {
      title = '✅ 正常';
      titleColor = FieldTokens.accent;
    } else {
      title = '⚠️ 確認できませんでした';
      titleColor = Colors.orange;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        title: Text(title, style: TextStyle(color: titleColor)),
        content: Text(
          result['message'] ?? 'チェック完了',
          style: const TextStyle(color: FieldTokens.textBody),
        ),
        actions: [
          if (status == 'error')
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _checkTamper(shareId); // 再試行の道
              },
              child: const Text('再試行',
                  style: TextStyle(color: FieldTokens.accent)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる',
                style: TextStyle(color: FieldTokens.accent)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 日報詳細ダイアログ
  // ============================================================

  void _showDetail(Map<String, dynamic> share, bool isInbox) {
    showModalBottomSheet(
      context: context,
      backgroundColor: FieldTokens.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  share['worker_name'] ?? '不明',
                  style: const TextStyle(
                    color: FieldTokens.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (share['is_tampered'] == true)
                  const Chip(
                    label: Text('⚠️ 改ざん',
                        style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.red,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailRow(label: '日付',
                value: share['report_date']?.toString() ?? '-'),
            _DetailRow(
              label: isInbox ? '送信元' : '送信先',
              value: isInbox
                  ? share['sender_company_name'] ?? '-'
                  : share['receiver_company_name'] ?? '-',
            ),
            _DetailRow(label: '現場',
                value: share['site_name'] ?? '-'),
            _DetailRow(label: '作業内容',
                value: share['work_content'] ?? '-'),
            _DetailRow(label: '送信方法',
                value: share['share_type'] ?? '-'),
            _DetailRow(label: 'ステータス',
                value: share['share_status'] ?? '-'),
            const SizedBox(height: 16),
            Row(
              children: [
                if (isInbox && share['share_status'] != 'read')
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FieldTokens.accent,
                        foregroundColor: FieldTokens.onAccent,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _markAsRead(share['share_id'] as String);
                      },
                      child: const Text('既読にする'),
                    ),
                  ),
                if (isInbox) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FieldTokens.accent,
                      side: const BorderSide(color: FieldTokens.accent),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _checkTamper(share['share_id'] as String);
                    },
                    child: const Text('改ざんチェック'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 受信リストUI
  // ============================================================

  Widget _buildInboxList() {
    if (_inbox.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, color: FieldTokens.textSupport, size: 64),
            SizedBox(height: 16),
            Text('受信した日報はありません',
                style: TextStyle(color: FieldTokens.textSupport)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _inbox.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final share = _inbox[i] as Map<String, dynamic>;
        final isTampered = share['is_tampered'] == true;
        final isUnread   = share['share_status'] != 'read';

        return ListTile(
          tileColor: isTampered
              ? const Color(0xFF3D1515)
              : FieldTokens.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isTampered
                  ? Colors.red
                  : isUnread
                      ? FieldTokens.accent
                      : Colors.transparent,
              width: isTampered || isUnread ? 1 : 0,
            ),
          ),
          leading: CircleAvatar(
            backgroundColor: isTampered
                ? Colors.red
                : FieldTokens.surfaceRaised,
            child: Icon(
              isTampered ? Icons.warning : Icons.inbox,
              color: isTampered
                  ? Colors.white
                  : FieldTokens.accent,
            ),
          ),
          title: Text(
            share['worker_name'] ?? '不明',
            style: TextStyle(
              color: FieldTokens.textBody,
              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${share['sender_company_name'] ?? '-'} | ${share['report_date'] ?? '-'}',
            style: const TextStyle(color: FieldTokens.textSupport),
          ),
          trailing: isTampered
              ? const Text('⚠️', style: TextStyle(fontSize: 20))
              : isUnread
                  ? const Icon(Icons.circle,
                      color: FieldTokens.accent, size: 10)
                  : null,
          onTap: () => _showDetail(share, true),
        );
      },
    );
  }

  // ============================================================
  // 送信リストUI
  // ============================================================

  Widget _buildOutboxList() {
    if (_outbox.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.outbox, color: FieldTokens.textSupport, size: 64),
            SizedBox(height: 16),
            Text('送信した日報はありません',
                style: TextStyle(color: FieldTokens.textSupport)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _outbox.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final share = _outbox[i] as Map<String, dynamic>;
        return ListTile(
          tileColor: FieldTokens.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          leading: const CircleAvatar(
            backgroundColor: FieldTokens.surfaceRaised,
            child: Icon(Icons.outbox, color: FieldTokens.accent),
          ),
          title: Text(
            share['worker_name'] ?? '不明',
            style: const TextStyle(color: FieldTokens.textBody),
          ),
          subtitle: Text(
            '${share['receiver_company_name'] ?? '-'} | ${share['report_date'] ?? '-'}',
            style: const TextStyle(color: FieldTokens.textSupport),
          ),
          trailing: _StatusChip(status: share['share_status'] as String?),
          onTap: () => _showDetail(share, false),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        title: Row(
          children: [
            const Text('報告トレイ'),
            if (_tamperedCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '⚠️ $_tamperedCount',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: FieldTokens.accent,
          unselectedLabelColor: FieldTokens.textSupport,
          indicatorColor: FieldTokens.accent,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inbox, size: 16),
                  const SizedBox(width: 4),
                  Text('受信 (${_inbox.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.outbox, size: 16),
                  const SizedBox(width: 4),
                  Text('送信 (${_outbox.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: FieldTokens.accent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildInboxList(),
                _buildOutboxList(),
              ],
            ),
    );
  }
}

// ============================================================
// サブウィジェット
// ============================================================

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(color: FieldTokens.textSupport)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: FieldTokens.textBody)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case 'read':
        color = Colors.green;
        label = '既読';
        break;
      case 'received':
        color = Colors.blue;
        label = '受信済';
        break;
      case 'tampered':
        color = Colors.red;
        label = '改ざん';
        break;
      default:
        color = const Color(0xFF9E9E9E);
        label = '送信済';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11)),
    );
  }
}