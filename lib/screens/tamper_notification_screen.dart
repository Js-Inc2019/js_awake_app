// lib/screens/tamper_notification_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, showJsSnackbar;
import '../config/constants.dart';

const String _API_URL = kApiBaseUrl;

class TamperNotificationScreen extends StatefulWidget {
  const TamperNotificationScreen({super.key});
  @override
  State<TamperNotificationScreen> createState() => _TamperNotificationScreenState();
}

class _TamperNotificationScreenState extends State<TamperNotificationScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http.get(
        Uri.parse('$_API_URL/reports/tamper/notifications'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data  = jsonDecode(res.body);
        final list  = (data['notifications'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        if (mounted) setState(() => _notifications = list);
      }
    } catch (e) {
      if (mounted) showJsSnackbar(context, '通知の取得に失敗しました', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(String notificationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      await http.patch(
        Uri.parse('$_API_URL/reports/tamper/$notificationId/read'),
        headers: {'Authorization': 'Bearer $token'},
      );
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => n['is_read'] != true).length;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('編集通知'),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: JsColors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
          : _notifications.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_user, size: 64, color: JsColors.success),
                      SizedBox(height: 16),
                      Text('編集通知はありません',
                          style: TextStyle(color: JsColors.silver, fontSize: 16)),
                      SizedBox(height: 8),
                      Text('日報のデータは改ざんされていません',
                          style: TextStyle(color: JsColors.silver, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _notifications.length,
                  itemBuilder: (_, i) {
                    final n      = _notifications[i];
                    final isRead = n['is_read'] as bool? ?? false;
                    final date   = n['report_date'] as String? ?? '';
                    final name   = n['worker_name'] as String? ?? '';
                    final notifId = n['notification_id'] as String;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isRead ? JsColors.gunmetal : JsColors.gunmetal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isRead ? JsColors.divider : JsColors.error,
                          width: isRead ? 1 : 2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(
                                isRead ? Icons.check_circle_outline : Icons.warning_amber,
                                color: isRead ? JsColors.silver : JsColors.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isRead ? '確認済み' : '⚠️ 日報が編集されました',
                                style: TextStyle(
                                  color: isRead ? JsColors.silver : JsColors.error,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            _InfoRow(label: '職人名', value: name),
                            _InfoRow(label: '日付',   value: date),
                            _InfoRow(
                              label: '作業内容',
                              value: (n['work_content'] as String? ?? '').isNotEmpty
                                  ? n['work_content'] as String
                                  : '（未入力）',
                            ),
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.fingerprint,
                                  color: JsColors.silver, size: 12),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '変更前: ${(n['hash_before'] as String).substring(0, 16)}...',
                                  style: const TextStyle(
                                      color: JsColors.silver,
                                      fontSize: 10,
                                      fontFamily: 'monospace'),
                                ),
                              ),
                            ]),
                            Row(children: [
                              const Icon(Icons.fingerprint,
                                  color: JsColors.gold, size: 12),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '変更後: ${(n['hash_after'] as String).substring(0, 16)}...',
                                  style: const TextStyle(
                                      color: JsColors.gold,
                                      fontSize: 10,
                                      fontFamily: 'monospace'),
                                ),
                              ),
                            ]),
                            if (!isRead) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => _markRead(notifId),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: JsColors.gold,
                                    side: const BorderSide(color: JsColors.gold),
                                    minimumSize: const Size(0, 40),
                                  ),
                                  child: const Text('確認済みにする'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      SizedBox(
        width: 60,
        child: Text(label,
            style: const TextStyle(color: JsColors.silver, fontSize: 12)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(color: JsColors.offWhite, fontSize: 13,
                fontWeight: FontWeight.w500)),
      ),
    ]),
  );
}
