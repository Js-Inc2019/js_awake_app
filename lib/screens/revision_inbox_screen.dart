// lib/screens/revision_inbox_screen.dart - 是正依頼受信画面
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, showJsSnackbar;

const String _apiUrl = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

class RevisionInboxScreen extends StatefulWidget {
  const RevisionInboxScreen({super.key});
  @override
  State<RevisionInboxScreen> createState() => _RevisionInboxScreenState();
}

class _RevisionInboxScreenState extends State<RevisionInboxScreen> {
  List<Map<String, dynamic>> _revisions = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('auth_token') ?? ''}',
      'Content-Type': 'application/json',
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('$_apiUrl/revisions/mine'),
        headers: await _headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _revisions = (data['revisions'] as List? ?? [])
                .map((e) => e as Map<String, dynamic>).toList();
            _loading = false;
          });
        }
      } else {
        if (mounted) { setState(() => _loading = false); }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('是正依頼'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
          : _revisions.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: JsColors.gold,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _revisions.length,
                    itemBuilder: (ctx, i) => _RevisionCard(
                      revision: _revisions[i],
                      onResubmit: () => _showResubmitSheet(_revisions[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _empty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, color: JsColors.success, size: 64),
          SizedBox(height: 16),
          Text('是正依頼はありません',
              style: TextStyle(color: JsColors.silver, fontSize: 16)),
        ],
      ),
    );
  }

  void _showResubmitSheet(Map<String, dynamic> revision) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JsColors.gunmetal,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('修正内容を入力',
                style: TextStyle(color: JsColors.gold, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '修正内容・コメント',
                labelStyle: TextStyle(color: JsColors.silver),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
              ),
              style: const TextStyle(color: JsColors.offWhite),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _resubmit(revision['revision_id'], controller.text.trim());
                },
                child: const Text('再提出する'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resubmit(String revisionId, String comment) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiUrl/revisions/$revisionId/resubmit'),
        headers: await _headers,
        body: jsonEncode({'comment': comment}),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        showJsSnackbar(context, '再提出しました');
        await _load();
      } else {
        final body = jsonDecode(res.body);
        showJsSnackbar(context, body['error'] ?? '再提出に失敗しました', isError: true);
      }
    } catch (_) {
      if (mounted) showJsSnackbar(context, '通信エラー', isError: true);
    }
  }
}

class _RevisionCard extends StatelessWidget {
  const _RevisionCard({required this.revision, required this.onResubmit});
  final Map<String, dynamic> revision;
  final VoidCallback onResubmit;

  @override
  Widget build(BuildContext context) {
    final status   = revision['status'] as String? ?? 'pending';
    final overdue  = revision['is_overdue'] == true;
    final reasons  = (revision['reasons'] as List? ?? []).cast<String>();
    final deadline = revision['deadline'] as String?;
    final reportDate = revision['report_date'] as String? ?? '';
    final comment  = revision['comment'] as String? ?? '';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'approved':    statusColor = JsColors.success; statusLabel = '承認済'; break;
      case 'rejected':    statusColor = JsColors.error;   statusLabel = '却下';   break;
      case 'resubmitted': statusColor = JsColors.warning; statusLabel = '再提出済'; break;
      default:            statusColor = overdue ? JsColors.error : JsColors.gold; statusLabel = overdue ? '期限超過' : '対応待ち';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: overdue && status == 'pending' ? JsColors.error : JsColors.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('日報: $reportDate',
                    style: const TextStyle(color: JsColors.offWhite, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: reasons.map((r) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: JsColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: JsColors.warning.withValues(alpha: 0.5)),
                  ),
                  child: Text(r, style: const TextStyle(color: JsColors.warning, fontSize: 11)),
                )).toList(),
              ),
            ],
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(comment, style: const TextStyle(color: JsColors.silver, fontSize: 12)),
            ],
            if (deadline != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.schedule,
                    size: 13,
                    color: overdue ? JsColors.error : JsColors.silver),
                const SizedBox(width: 4),
                Text(
                  '期限: ${deadline.substring(0, 10)}',
                  style: TextStyle(
                    color: overdue ? JsColors.error : JsColors.silver,
                    fontSize: 11,
                  ),
                ),
              ]),
            ],
            if (status == 'pending' || status == 'resubmitted') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onResubmit,
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('修正して再提出'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: JsColors.gold,
                    side: const BorderSide(color: JsColors.gold),
                    minimumSize: const Size(0, 40),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
