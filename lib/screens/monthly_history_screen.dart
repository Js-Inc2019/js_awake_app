// lib/screens/monthly_history_screen.dart — 月間履歴画面
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/field_tokens.dart';
import '../services/reports_service.dart';
import 'day_reports_screen.dart' show DayReportsScreen;
import 'revision_inbox_screen.dart';
// 作業3: 移動手段の複数対応。transport_types_json 優先 → 無ければ transport_type に
// フォールバックする読み方は revision_parser に実装済みのものを再利用する（新設しない）。
import '../utils/revision_parser.dart' show transportNamesOf;

// ─────────────────────────────────────────────
// MonthlyHistoryBody — Scaffold なし（Shell の IndexedStack で使用）
// ─────────────────────────────────────────────
class MonthlyHistoryBody extends StatefulWidget {
  const MonthlyHistoryBody({super.key, this.onHome});
  final VoidCallback? onHome;
  @override
  State<MonthlyHistoryBody> createState() => _MonthlyHistoryBodyState();
}

class _MonthlyHistoryBodyState extends State<MonthlyHistoryBody> {
  bool _loading = true;
  List<Map<String, dynamic>> _reports = [];
  DateTime _selectedMonth = DateTime.now();
  String? _error;
  // null = 全件, 'approved' / 'rejected' / 'pending' = 絞り込み中
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final m = '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';
      final res = await ReportsService().getReportsByMonth(m, limit: 200);
      if (!mounted) return;
      if (res.ok) {
        final raw = List<Map<String, dynamic>>.from(res.data ?? const []);
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
        await prefs.setBool('logged_out', true);
        if (mounted) {
          setState(() { _loading = false; _error = '認証の有効期限が切れました。再ログインしてください。'; });
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        }
      } else if (res.statusCode == 0) {
        // 通信不成立＝移設前の catch 相当。
        setState(() { _loading = false; _error = 'ネットワークエラー'; });
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
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      _filterStatus = null;
    });
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year && _selectedMonth.month == now.month) return;
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      _filterStatus = null;
    });
    _load();
  }

  void _toggleFilter(String? status) {
    setState(() => _filterStatus = (_filterStatus == status) ? null : status);
  }

  @override
  Widget build(BuildContext context) {
    final total    = _reports.length;
    final approved = _reports.where((r) => r['status'] == 'approved').length;
    final rejected = _reports.where((r) => r['status'] == 'rejected').length;
    final pending  = total - approved - rejected;
    final now      = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final displayed = _filterStatus == null
        ? _reports
        : _reports.where((r) => r['status'] == _filterStatus).toList();

    // 日付グループ化（絞る→畳む）新しい順
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final r in displayed) {
      final key = r['report_date'] as String? ?? '';
      grouped.putIfAbsent(key, () => []).add(r);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        // 月選択バー
        Container(
          color: FieldTokens.surfaceCard,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: FieldTokens.accent),
                onPressed: _prevMonth,
              ),
              Text(
                '${_selectedMonth.year}年${_selectedMonth.month}月',
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth ? FieldTokens.outline : FieldTokens.accent),
                onPressed: isCurrentMonth ? null : _nextMonth,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: FieldTokens.textSupport, size: 20),
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
              JsStatChip('合計', total, FieldTokens.textSupport,
                  selected: _filterStatus == null,
                  onTap: () => setState(() => _filterStatus = null)),
              const SizedBox(width: 8),
              JsStatChip('承認', approved, FieldTokens.statusSuccess,
                  selected: _filterStatus == 'approved',
                  onTap: () => _toggleFilter('approved')),
              const SizedBox(width: 8),
              JsStatChip('差戻', rejected, FieldTokens.statusError,
                  selected: _filterStatus == 'rejected',
                  onTap: () => _toggleFilter('rejected')),
              const SizedBox(width: 8),
              JsStatChip('未承認', pending, FieldTokens.statusWarning,
                  selected: _filterStatus == 'pending',
                  onTap: () => _toggleFilter('pending')),
            ]),
          ),
        // リスト
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: FieldTokens.accent))
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: FieldTokens.statusError)))
                  : _reports.isEmpty
                      ? const Center(
                          child: Text('この月の記録はありません',
                              style: TextStyle(color: FieldTokens.textSupport)))
                      : displayed.isEmpty
                          ? const Center(
                              child: Text('該当する記録はありません',
                                  style: TextStyle(color: FieldTokens.textSupport)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              itemCount: sortedDates.length,
                              itemBuilder: (ctx, i) {
                                final dateStr = sortedDates[i];
                                final reps    = grouped[dateStr]!;
                                final parts   = dateStr.split('-');
                                final date    = parts.length == 3
                                    ? DateTime(
                                        int.tryParse(parts[0]) ?? 0,
                                        int.tryParse(parts[1]) ?? 0,
                                        int.tryParse(parts[2]) ?? 0)
                                    : DateTime.now();
                                return _DateRow(
                                  dateStr: dateStr,
                                  date:    date,
                                  reports: reps,
                                  onTap:   () => Navigator.push(
                                    ctx,
                                    MaterialPageRoute(
                                      builder: (_) => DayReportsScreen(
                                        date:        date,
                                        reports:     reps,
                                        myCompanyId: '',
                                      ),
                                    ),
                                  ),
                                );
                              },
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
      backgroundColor: FieldTokens.bgBase,
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
class JsStatChip extends StatelessWidget {
  const JsStatChip(this.label, this.count, this.color, {
    super.key,
    this.selected = false,
    this.onTap,
    this.valueText,
  });
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  /// 単位付きの値（例 '288.0h'）を int に落とさず出すための任意指定。
  /// 省略時は従来どおり '$count' を描く＝レイアウト・サイズ・枠・色すべて不変。
  /// （home_screen.dart の _StaffStatChip が valueColor を足したのと同じ「追加だけ」の流儀。
  ///   実働(h) を int の count で表せないためだけに新部品を作ることを避ける。）
  final String? valueText;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.22) : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Column(children: [
          Text(valueText ?? '$count',
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ]),
      ),
    ),
  );
}

class JsReportTile extends StatelessWidget {
  const JsReportTile({super.key, required this.report, this.myCompanyId = ''});
  final Map<String, dynamic> report;
  final String myCompanyId;

  bool get _isOwn =>
      myCompanyId.isNotEmpty && report['company_id'] == myCompanyId;

  @override
  Widget build(BuildContext context) {
    final status = report['status'] as String? ?? 'pending';
    late final Color sc;
    late final String sl;
    switch (status) {
      case 'approved': sc = FieldTokens.statusSuccess; sl = '承認済'; break;
      case 'rejected': sc = FieldTokens.statusError;   sl = '差戻し'; break;
      default:         sc = FieldTokens.textSupport;  sl = '未承認'; break;
    }
    final date       = report['report_date']   as String? ?? '';
    final content    = report['work_content']  as String? ?? '作業内容 未入力';
    final addr       = report['gps_address']   as String? ?? '';
    // 作業3: 複数選択に対応（'・' 区切り＝確認画面と同じ流儀）
    final trans      = transportNamesOf(report).join('・');
    final workerName = report['worker_name']   as String? ?? '';

    final isRejected  = status == 'rejected';
    final accentColor = myCompanyId.isEmpty
        ? null
        : (_isOwn ? FieldTokens.accent : FieldTokens.externalBlue);

    return GestureDetector(
      onTap: () {
        if (isRejected) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RevisionInboxScreen()),
          );
        } else {
          showModalBottomSheet(
            context: context,
            backgroundColor: FieldTokens.surfaceCard,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            builder: (_) => JsReportDetailSheet(report: report),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isRejected ? FieldTokens.statusError : FieldTokens.outline),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (accentColor != null)
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(9),
                      bottomLeft: Radius.circular(9),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(date,
                                  style: const TextStyle(
                                      color: FieldTokens.textSupport, fontSize: 12)),
                              if (trans.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(trans,
                                    style: const TextStyle(
                                        color: FieldTokens.textSupport, fontSize: 11)),
                              ],
                              if (accentColor != null && workerName.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(workerName,
                                    style: TextStyle(
                                        color: accentColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ]),
                            const SizedBox(height: 4),
                            Text(content,
                                style: const TextStyle(
                                    color: FieldTokens.textBody, fontSize: 14),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            if (addr.isNotEmpty)
                              Text(addr,
                                  style: const TextStyle(
                                      color: FieldTokens.textSupport, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            if (isRejected) ...[
                              const SizedBox(height: 6),
                              const Row(children: [
                                Icon(Icons.arrow_forward,
                                    color: FieldTokens.statusError, size: 13),
                                SizedBox(width: 4),
                                Text('是正依頼を確認',
                                    style: TextStyle(
                                        color: FieldTokens.statusError,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ]),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: sc.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: sc),
                        ),
                        child: Text(sl,
                            style: TextStyle(
                                color: sc,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JsReportDetailSheet extends StatelessWidget {
  const JsReportDetailSheet({super.key, required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final status = report['status'] as String? ?? 'pending';
    final Color sc;
    final String sl;
    switch (status) {
      case 'approved': sc = FieldTokens.statusSuccess; sl = '承認済'; break;
      case 'rejected': sc = FieldTokens.statusError;   sl = '差戻し'; break;
      default:         sc = FieldTokens.textSupport;  sl = '未承認'; break;
    }

    final date        = report['report_date']    as String? ?? '';
    final content     = report['work_content']   as String? ?? '作業内容 未入力';
    final addr        = report['gps_address']    as String? ?? '';
    // 作業3: 複数選択に対応（'・' 区切り）
    final trans       = transportNamesOf(report).join('・');
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
                  color: FieldTokens.outline,
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(date,
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 13)),
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
            JsDetailRow(icon: Icons.work_outline,      label: '作業内容', value: content),
            if (addr.isNotEmpty)
              JsDetailRow(icon: Icons.location_on_outlined, label: '現場住所', value: addr),
            if (trans.isNotEmpty)
              JsDetailRow(icon: Icons.directions_car_outlined, label: '移動手段', value: trans),
            if (distKm != null)
              JsDetailRow(icon: Icons.straighten, label: '距離',
                  value: '${distKm}km'),
            if (transCost != null)
              JsDetailRow(icon: Icons.train_outlined, label: '交通費',
                  value: '¥$transCost'),
            if (parking != null)
              JsDetailRow(icon: Icons.local_parking, label: '駐車料金',
                  value: '¥$parking'),
            if (otHours > 0 || otMinutes > 0)
              JsDetailRow(icon: Icons.access_time, label: '残業時間',
                  value: '$otHours時間$otMinutes分'),
          ],
        ),
      ),
    );
  }
}

class JsDetailRow extends StatelessWidget {
  const JsDetailRow({super.key, required this.icon, required this.label, required this.value});
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
          Icon(icon, color: FieldTokens.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: FieldTokens.textBody, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 日付グループ行（月間履歴リスト用）
// ─────────────────────────────────────────────
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.dateStr,
    required this.date,
    required this.reports,
    required this.onTap,
  });
  final String dateStr;
  final DateTime date;
  final List<Map<String, dynamic>> reports;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasRejected = reports.any((r) => r['status'] == 'rejected');
    final allApproved = reports.every((r) => r['status'] == 'approved');
    final Color sc;
    final String sl;
    if (hasRejected) {
      sc = FieldTokens.statusError;   sl = '差戻';
    } else if (allApproved) {
      sc = FieldTokens.statusSuccess; sl = '承認済';
    } else {
      sc = FieldTokens.statusWarning; sl = '未承認';
    }

    final parts = dateStr.split('-');
    final label = parts.length == 3
        ? '${int.tryParse(parts[1]) ?? 0}月${int.tryParse(parts[2]) ?? 0}日'
        : dateStr;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: hasRejected ? FieldTokens.statusError : FieldTokens.outline),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: FieldTokens.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('${reports.length}件',
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 12)),
              ],
            ),
          ),
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
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: FieldTokens.textSupport, size: 18),
        ]),
      ),
    );
  }
}
