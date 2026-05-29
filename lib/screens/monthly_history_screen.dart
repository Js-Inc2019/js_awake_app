// lib/screens/monthly_history_screen.dart — 月間履歴画面
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, API_URL;

class MonthlyHistoryScreen extends StatefulWidget {
  const MonthlyHistoryScreen({super.key});
  @override
  State<MonthlyHistoryScreen> createState() => _MonthlyHistoryScreenState();
}

class _MonthlyHistoryScreenState extends State<MonthlyHistoryScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _reports = [];
  DateTime _selectedMonth = DateTime.now();
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final m = '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';
      final res = await http.get(
        Uri.parse('$API_URL/reports?date=$m&limit=200'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _reports = List<Map<String, dynamic>>.from(data['reports'] ?? []);
          _loading = false;
        });
      } else {
        setState(() { _loading = false; _error = 'データの取得に失敗しました'; });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'ネットワークエラー'; });
    }
  }

  void _prevMonth() {
    setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1));
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year && _selectedMonth.month == now.month) return;
    setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final total    = _reports.length;
    final approved = _reports.where((r) => r['approved'] == true).length;
    final rejected = _reports.where((r) => r['revision_requested'] == true).length;
    final pending  = total - approved - rejected;
    final now      = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(title: const Text('月間履歴')),
      body: Column(
        children: [
          // 月選択バー
          Container(
            color: JsColors.gunmetal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: JsColors.gold),
                  onPressed: _prevMonth,
                ),
                Text(
                  '${_selectedMonth.year}年${_selectedMonth.month}月',
                  style: const TextStyle(color: JsColors.offWhite, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right,
                      color: isCurrentMonth ? JsColors.divider : JsColors.gold),
                  onPressed: isCurrentMonth ? null : _nextMonth,
                ),
              ],
            ),
          ),
          // 集計バー
          if (!_loading && _error == null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(children: [
                _StatChip('合計', total, JsColors.silver),
                const SizedBox(width: 8),
                _StatChip('承認', approved, JsColors.success),
                const SizedBox(width: 8),
                _StatChip('差戻', rejected, JsColors.error),
                const SizedBox(width: 8),
                _StatChip('未承認', pending, JsColors.warning),
              ]),
            ),
            // 残業集計・警告
            Builder(builder: (ctx) {
              final otHours = _reports.fold<double>(
                  0, (s, r) => s + ((r['overtime_hours'] as num?)?.toDouble() ?? 0));
              if (otHours <= 0) return const SizedBox.shrink();
              final isOver = otHours >= 45;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (isOver ? JsColors.error : JsColors.warning).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isOver ? JsColors.error : JsColors.warning),
                  ),
                  child: Row(children: [
                    Icon(Icons.access_time_filled,
                        color: isOver ? JsColors.error : JsColors.warning, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      isOver
                          ? '⚠️ 今月の残業合計: ${otHours}h（45時間超過！）'
                          : '残業合計: ${otHours}h',
                      style: TextStyle(
                          color: isOver ? JsColors.error : JsColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ]),
                ),
              );
            }),
          ],
          // リスト
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: JsColors.error)))
                    : _reports.isEmpty
                        ? const Center(
                            child: Text('この月の記録はありません', style: TextStyle(color: JsColors.silver)))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: _reports.length,
                            itemBuilder: (ctx, i) => _ReportTile(
                              report: _reports[i],
                              onEdited: _load,
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Text('$count', style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ]),
    ),
  );
}

class _ReportTile extends StatefulWidget {
  const _ReportTile({required this.report, required this.onEdited});
  final Map<String, dynamic> report;
  final VoidCallback onEdited;
  @override
  State<_ReportTile> createState() => _ReportTileState();
}

class _ReportTileState extends State<_ReportTile> {
  bool _editing = false;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _reasonCtrl;

  @override
  void initState() {
    super.initState();
    _contentCtrl = TextEditingController(
        text: widget.report['work_content'] as String? ?? '');
    _reasonCtrl  = TextEditingController();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitEdit() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('修正理由を入力してください'),
          backgroundColor: JsColors.error));
      return;
    }
    final reportId = widget.report['report_id'] as String? ?? '';
    if (reportId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http.put(
        Uri.parse('$API_URL/reports/$reportId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'work_content': _contentCtrl.text.trim(),
          'edit_reason':  reason,
        }),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _editing = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('修正しました'),
            backgroundColor: JsColors.success));
        widget.onEdited();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('修正失敗: ${res.statusCode}'),
            backgroundColor: JsColors.error));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('エラー: $e'), backgroundColor: JsColors.error));
    }
  }

  get report => widget.report;

  @override
  @override
  Widget build(BuildContext context) {
    final approved         = report['approved'] as bool? ?? false;
    final revisionRequested = report['revision_requested'] as bool? ?? false;
    final Color sc;
    final String sl;
    if (approved) { sc = JsColors.success; sl = '承認済'; }
    else if (revisionRequested) { sc = JsColors.error; sl = '是正依頼'; }
    else { sc = JsColors.silver; sl = '未承認'; }
    final date    = report['report_date'] as String? ?? '';
    final addr    = report['gps_address']  as String? ?? '';
    final trans   = report['transport_type'] as String? ?? '';

    // 当日のみ修正可能
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final isToday = date.startsWith(today);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _editing ? JsColors.gold : JsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(date, style: const TextStyle(color: JsColors.silver, fontSize: 12)),
                  if (trans.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(trans, style: const TextStyle(color: JsColors.silver, fontSize: 11)),
                  ],
                ]),
                const SizedBox(height: 4),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: sc.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: sc),
              ),
              child: Text(sl, style: TextStyle(color: sc, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            if (isToday && !approved) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _editing = !_editing),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: JsColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: JsColors.gold),
                  ),
                  child: Text(_editing ? 'キャンセル' : '修正',
                      style: const TextStyle(color: JsColors.gold, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ]),
          if (!_editing) ...[
            Text(_contentCtrl.text.isEmpty ? '作業内容 未入力' : _contentCtrl.text,
                style: const TextStyle(color: JsColors.offWhite, fontSize: 14),
                maxLines: 3, overflow: TextOverflow.ellipsis),
            if (addr.isNotEmpty)
              Text(addr,
                  style: const TextStyle(color: JsColors.silver, fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          if (_editing) ...[
            TextField(
              controller: _contentCtrl,
              maxLines: 3,
              style: const TextStyle(color: JsColors.offWhite, fontSize: 13),
              decoration: const InputDecoration(
                labelText: '作業内容を修正',
                labelStyle: TextStyle(color: JsColors.silver),
                filled: true, fillColor: JsColors.surface,
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: JsColors.divider)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: JsColors.gold, width: 2)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonCtrl,
              style: const TextStyle(color: JsColors.offWhite, fontSize: 13),
              decoration: const InputDecoration(
                labelText: '修正理由（必須）',
                labelStyle: TextStyle(color: JsColors.silver),
                filled: true, fillColor: JsColors.surface,
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: JsColors.divider)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: JsColors.gold, width: 2)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitEdit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: JsColors.gold,
                    foregroundColor: Colors.black),
                child: const Text('修正を送信'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
