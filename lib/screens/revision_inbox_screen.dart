// lib/screens/revision_inbox_screen.dart - 是正依頼受信画面
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, showJsSnackbar;
import '../config/constants.dart';

const String _apiUrl = kApiBaseUrl;

class RevisionInboxScreen extends StatefulWidget {
  const RevisionInboxScreen({super.key});
  @override
  State<RevisionInboxScreen> createState() => _RevisionInboxScreenState();
}

class _RevisionInboxScreenState extends State<RevisionInboxScreen> {
  List<Map<String, dynamic>> _revisions = [];
  bool _loading = true;
  bool _hasError = false;

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
    setState(() { _loading = true; _hasError = false; });
    try {
      final res = await http.get(
        Uri.parse('$_apiUrl/reports?revision_requested=true'),
        headers: await _headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _revisions = (data['reports'] as List? ?? [])
                .map((e) => e as Map<String, dynamic>).toList();
            _loading = false;
          });
        }
      } else {
        if (mounted) { setState(() { _loading = false; _hasError = true; }); }
      }
    } catch (e) {
      debugPrint('差し戻し一覧取得失敗: $e');
      if (mounted) {
        showJsSnackbar(context, '差し戻し一覧の取得に失敗しました。再度お試しください。', isError: true);
        setState(() { _loading = false; _hasError = true; });
      }
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
          : _hasError
              ? _errorView()
              : _revisions.isEmpty
                  ? _emptyView()
                  : RefreshIndicator(
                  onRefresh: _load,
                  color: JsColors.gold,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _revisions.length,
                    itemBuilder: (ctx, i) => _RevisionCard(
                      revision: _revisions[i],
                      onResubmit: () => showJsSnackbar(context, '編集画面は準備中です'),
                    ),
                  ),
                ),
    );
  }

  Widget _emptyView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, color: JsColors.silver, size: 64),
          SizedBox(height: 16),
          Text('差し戻しはありません',
              style: TextStyle(color: JsColors.silver, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: JsColors.error, size: 64),
          const SizedBox(height: 16),
          const Text('取得に失敗しました',
              style: TextStyle(color: JsColors.error, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('再試行'),
          ),
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
    ).whenComplete(controller.dispose);
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
    final reportDate  = revision['report_date'] as String? ?? '';
    final workContent = revision['work_content'] as String? ?? '';
    final bossNote    = revision['boss_note'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('日報: $reportDate',
                style: const TextStyle(color: JsColors.offWhite, fontWeight: FontWeight.bold)),
            if (workContent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                workContent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: JsColors.silver, fontSize: 12),
              ),
            ],
            if (bossNote.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: JsColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.comment_outlined, size: 14, color: JsColors.gold),
                      SizedBox(width: 6),
                      Text('差戻し理由',
                          style: TextStyle(color: JsColors.gold, fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 6),
                    Text(bossNote, style: const TextStyle(color: JsColors.offWhite, fontSize: 13)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onResubmit,
                icon: const Icon(Icons.send, size: 16),
                label: const Text('直して再提出'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: JsColors.gold,
                  side: const BorderSide(color: JsColors.gold),
                  minimumSize: const Size(0, 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
