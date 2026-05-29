// lib/screens/retention_screen.dart - 5年自動削除・通知
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, showJsSnackbar, showConfirmDialog;

const String _API_URL = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

class RetentionScreen extends StatefulWidget {
  const RetentionScreen({super.key});
  @override
  State<RetentionScreen> createState() => _RetentionScreenState();
}

class _RetentionScreenState extends State<RetentionScreen> {
  List<Map<String, dynamic>> _expired  = [];
  List<Map<String, dynamic>> _warning  = [];
  bool   _loading   = true;

  @override
  void initState() { super.initState(); _check(); }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  Future<void> _check() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('$_API_URL/retention/check'),
        headers: await _headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() {
          _expired = (data['expired'] as List? ?? [])
              .map((e) => e as Map<String, dynamic>).toList();
          _warning = (data['warning'] as List? ?? [])
              .map((e) => e as Map<String, dynamic>).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteExpired() async {
    final ok = await showConfirmDialog(
      context,
      title:       '⚠️ 5年経過データを削除',
      message:     '${_expired.length}件のデータを完全に削除します。\nこの操作は取り消せません。\n\n削除前にエクスポートしましたか？',
      confirmText: '削除する',
      isDanger:    true,
    );
    if (!ok) return;

    try {
      final res = await http.delete(
        Uri.parse('$_API_URL/retention/delete-expired'),
        headers: await _headers,
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          showJsSnackbar(context, '✅ ${data['message']}');
          await _check();
        }
      } else {
        if (mounted) showJsSnackbar(context, '削除に失敗しました', isError: true);
      }
    } catch (e) {
      if (mounted) showJsSnackbar(context, '通信エラー', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('データ保持管理'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _check)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 説明カード
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: JsColors.gunmetal,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: JsColors.divider),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.info_outline, color: JsColors.gold, size: 18),
                            SizedBox(width: 8),
                            Text('データ保持ポリシー',
                                style: TextStyle(color: JsColors.gold,
                                    fontWeight: FontWeight.bold)),
                          ]),
                          SizedBox(height: 8),
                          Text('日報データは送信日から5年間保持されます。\n5年経過後は自動削除対象となります。',
                              style: TextStyle(color: JsColors.silver,
                                  fontSize: 12, height: 1.5)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 5年経過データ
                    Row(children: [
                      const Icon(Icons.delete_forever, color: JsColors.error, size: 18),
                      const SizedBox(width: 8),
                      Text('削除対象（${_expired.length}件）',
                          style: const TextStyle(color: JsColors.error,
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
                    const SizedBox(height: 8),

                    if (_expired.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: JsColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: JsColors.success),
                        ),
                        child: const Row(children: [
                          Icon(Icons.check_circle, color: JsColors.success, size: 18),
                          SizedBox(width: 8),
                          Text('5年経過データはありません',
                              style: TextStyle(color: JsColors.success)),
                        ]),
                      )
                    else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: JsColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: JsColors.error),
                        ),
                        child: Column(
                          children: _expired.take(5).map((r) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              const Icon(Icons.warning_amber,
                                  color: JsColors.error, size: 14),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                '${r['worker_name']} - ${r['report_date']}（${r['days_old']}日経過）',
                                style: const TextStyle(color: JsColors.offWhite, fontSize: 12),
                              )),
                            ]),
                          )).toList(),
                        ),
                      ),
                      if (_expired.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('他${_expired.length - 5}件...',
                              style: const TextStyle(color: JsColors.silver, fontSize: 11)),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _deleteExpired,
                          icon: const Icon(Icons.delete_forever),
                          label: Text('${_expired.length}件を削除する'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: JsColors.error,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // 警告データ（もうすぐ5年）
                    if (_warning.isNotEmpty) ...[
                      Row(children: [
                        const Icon(Icons.warning_amber, color: JsColors.warning, size: 18),
                        const SizedBox(width: 8),
                        Text('まもなく削除対象（${_warning.length}件）',
                            style: const TextStyle(color: JsColors.warning,
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ]),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: JsColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: JsColors.warning),
                        ),
                        child: Column(
                          children: _warning.take(5).map((r) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              const Icon(Icons.schedule,
                                  color: JsColors.warning, size: 14),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                '${r['worker_name']} - ${r['report_date']}（${r['days_old']}日経過）',
                                style: const TextStyle(color: JsColors.offWhite, fontSize: 12),
                              )),
                            ]),
                          )).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
