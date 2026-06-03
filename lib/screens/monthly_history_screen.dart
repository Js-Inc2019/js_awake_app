// lib/screens/monthly_history_screen.dart — 月間履歴画面
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, API_URL;

// ─────────────────────────────────────────────
// MonthlyHistoryBody — Scaffold なし（Shell の IndexedStack で使用）
// ─────────────────────────────────────────────
class MonthlyHistoryBody extends StatefulWidget {
  const MonthlyHistoryBody({super.key});
  @override
  State<MonthlyHistoryBody> createState() => _MonthlyHistoryBodyState();
}

class _MonthlyHistoryBodyState extends State<MonthlyHistoryBody> {
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
        final raw = List<Map<String, dynamic>>.from(data['reports'] ?? []);
        // approved/revision_requested boolean → status 文字列に変換
        setState(() {
          _reports = raw.map((r) {
            final approved   = r['approved'] == true;
            final revision   = r['revision_requested'] == true;
            return {
              ...r,
              'status': approved ? 'approved' : revision ? 'rejected' : 'pending',
            };
          }).toList();
          _loading = false;
        });
      } else if (res.statusCode == 401) {
        // トークン切れ・無効 → ログアウトして再ログイン
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('auth_token');
        if (mounted) {
          setState(() { _loading = false; _error = '認証の有効期限が切れました。再ログインしてください。'; });
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        }
      } else {
        setState(() {
          _loading = false;
          _error = 'データの取得に失敗しました。\nしばらく経ってから再試行してください。';
        });
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
    final approved = _reports.where((r) => r['status'] == 'approved').length;
    final rejected = _reports.where((r) => r['status'] == 'rejected').length;
    final pending  = total - approved - rejected;
    final now      = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    return Column(
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
                style: const TextStyle(
                    color: JsColors.offWhite, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth ? JsColors.divider : JsColors.gold),
                onPressed: isCurrentMonth ? null : _nextMonth,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: JsColors.silver, size: 20),
                onPressed: _load,
                tooltip: '再読み込み',
              ),
            ],
          ),
        ),
        // 集計バー
        if (!_loading && _error == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
        // リスト
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: JsColors.error)))
                  : _reports.isEmpty
                      ? const Center(
                          child: Text('この月の記録はありません',
                              style: TextStyle(color: JsColors.silver)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: _reports.length,
                          itemBuilder: (ctx, i) => _ReportTile(report: _reports[i]),
                        ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// MonthlyHistoryScreen — 単体プッシュ用（Scaffold ラッパー）
// ─────────────────────────────────────────────
class MonthlyHistoryScreen extends StatelessWidget {
  const MonthlyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      appBar: AppBar(
        title: const Text('月間履歴'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const MonthlyHistoryBody(),
    );
  }
}

// ─────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────
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
        Text('$count',
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ]),
    ),
  );
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final status = report['status'] as String? ?? 'pending';
    late final Color sc;
    late final String sl;
    switch (status) {
      case 'approved': sc = JsColors.success; sl = '承認済'; break;
      case 'rejected': sc = JsColors.error;   sl = '差戻し'; break;
      default:         sc = JsColors.silver;  sl = '未承認'; break;
    }
    final date    = report['report_date'] as String? ?? '';
    final content = report['work_content'] as String? ?? '作業内容 未入力';
    final addr    = report['gps_address']  as String? ?? '';
    final trans   = report['transport_type'] as String? ?? '';

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: JsColors.gunmetal,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (_) => _ReportDetailSheet(report: report),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JsColors.gunmetal,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JsColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(date,
                        style: const TextStyle(color: JsColors.silver, fontSize: 12)),
                    if (trans.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(trans,
                          style: const TextStyle(color: JsColors.silver, fontSize: 11)),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(content,
                      style: const TextStyle(color: JsColors.offWhite, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (addr.isNotEmpty)
                    Text(addr,
                        style: const TextStyle(color: JsColors.silver, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: sc.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: sc),
              ),
              child: Text(sl,
                  style: TextStyle(
                      color: sc, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportDetailSheet extends StatelessWidget {
  const _ReportDetailSheet({required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final status = report['status'] as String? ?? 'pending';
    final Color sc;
    final String sl;
    switch (status) {
      case 'approved': sc = JsColors.success; sl = '承認済'; break;
      case 'rejected': sc = JsColors.error;   sl = '差戻し'; break;
      default:         sc = JsColors.silver;  sl = '未承認'; break;
    }

    final date        = report['report_date']    as String? ?? '';
    final content     = report['work_content']   as String? ?? '作業内容 未入力';
    final addr        = report['gps_address']    as String? ?? '';
    final trans       = report['transport_type'] as String? ?? '';
    final distKm      = report['distance_km'];
    final transCost   = report['transport_cost'];
    final otHours     = report['overtime_hours']   as int? ?? 0;
    final otMinutes   = report['overtime_minutes'] as int? ?? 0;
    final parking     = report['parking_fee'];

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: JsColors.divider,
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(date,
                    style: const TextStyle(
                        color: JsColors.silver, fontSize: 13)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: sc),
                  ),
                  child: Text(sl,
                      style: TextStyle(
                          color: sc, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(icon: Icons.work_outline,      label: '作業内容', value: content),
            if (addr.isNotEmpty)
              _DetailRow(icon: Icons.location_on_outlined, label: '現場住所', value: addr),
            if (trans.isNotEmpty)
              _DetailRow(icon: Icons.directions_car_outlined, label: '移動手段', value: trans),
            if (distKm != null)
              _DetailRow(icon: Icons.straighten, label: '距離',
                  value: '${distKm}km'),
            if (transCost != null)
              _DetailRow(icon: Icons.train_outlined, label: '交通費',
                  value: '¥$transCost'),
            if (parking != null)
              _DetailRow(icon: Icons.local_parking, label: '駐車料金',
                  value: '¥$parking'),
            if (otHours > 0 || otMinutes > 0)
              _DetailRow(icon: Icons.access_time, label: '残業時間',
                  value: '$otHours時間$otMinutes分'),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: JsColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: JsColors.silver, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: JsColors.offWhite, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
