// lib/screens/day_reports_screen.dart
import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import 'monthly_history_screen.dart' show JsReportTile;

class DayReportsScreen extends StatefulWidget {
  const DayReportsScreen({
    super.key,
    required this.date,
    required this.reports,
    required this.myCompanyId,
  });
  final DateTime date;
  final List<Map<String, dynamic>> reports;
  final String myCompanyId;

  @override
  State<DayReportsScreen> createState() => _DayReportsScreenState();
}

class _DayReportsScreenState extends State<DayReportsScreen> {
  bool _isWorkerView = false;

  Map<String, List<Map<String, dynamic>>> _groupBySite(
      List<Map<String, dynamic>> reps) {
    final Map<String, List<Map<String, dynamic>>> g = {};
    for (final r in reps) {
      final key = (r['site_id'] as String?) ??
          (r['gps_address'] as String?) ??
          '住所未取得';
      g.putIfAbsent(key, () => []).add(r);
    }
    return g;
  }

  Map<String, List<Map<String, dynamic>>> _groupByWorker(
      List<Map<String, dynamic>> reps) {
    final Map<String, List<Map<String, dynamic>>> g = {};
    for (final r in reps) {
      final key = r['user_id'] as String? ??
          r['worker_name'] as String? ?? '不明';
      g.putIfAbsent(key, () => []).add(r);
    }
    return g;
  }

  Map<String, List<Map<String, dynamic>>> _groupByCompany(
      List<Map<String, dynamic>> reps) {
    final Map<String, List<Map<String, dynamic>>> g = {};
    for (final r in reps) {
      final key = r['company_id'] as String? ?? '不明';
      g.putIfAbsent(key, () => []).add(r);
    }
    return g;
  }

  String _siteLabel(List<Map<String, dynamic>> reps) {
    final r = reps.first;
    final name = r['site_name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    final addr = r['gps_address'] as String?;
    if (addr != null && addr.isNotEmpty) return addr;
    return '住所未取得';
  }

  String _workerLabel(List<Map<String, dynamic>> reps) =>
      reps.first['worker_name'] as String? ?? '不明';

  String _companyLabel(List<Map<String, dynamic>> reps) =>
      reps.first['worker_company'] as String? ?? '協力会社';

  int _sumParkingFee(List<Map<String, dynamic>> reps) {
    double total = 0;
    for (final r in reps) {
      final raw = r['parking_fee'];
      if (raw != null) {
        total += double.tryParse(raw.toString()) ?? 0;
      }
    }
    return total.toInt();
  }

  Widget _parkingChip(Map<String, dynamic> r) {
    final raw = r['parking_fee'];
    if (raw == null) return const SizedBox.shrink();
    final fee = (double.tryParse(raw.toString()) ?? 0).toInt();
    if (fee <= 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 10, bottom: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: FieldTokens.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: FieldTokens.accent.withValues(alpha: 0.5), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_parking, color: FieldTokens.accent, size: 9),
              const SizedBox(width: 2),
              Text('¥$fee',
                  style: const TextStyle(color: FieldTokens.accent, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feeFooter(int fee, {String prefix = '計'}) => Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 10, bottom: 8),
          child: Text('$prefix ¥$fee',
              style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
        ),
      );

  List<Widget> _buildOwnItems(List<Map<String, dynamic>> reps) {
    final items = <Widget>[];
    final grouped =
        _isWorkerView ? _groupByWorker(reps) : _groupBySite(reps);
    for (final entry in grouped.entries) {
      final label = _isWorkerView
          ? _workerLabel(entry.value)
          : _siteLabel(entry.value);
      final icon =
          _isWorkerView ? Icons.person_outline : Icons.location_on;
      final fee = _sumParkingFee(entry.value);
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, color: FieldTokens.accent, size: 13),
          const SizedBox(width: 4),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: FieldTokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text('${entry.value.length}件',
              style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
        ]),
      ));
      for (final r in entry.value) {
        items.add(JsReportTile(report: r, myCompanyId: widget.myCompanyId));
        items.add(_parkingChip(r));
      }
      if (fee > 0) {
        items.add(_feeFooter(fee));
      }
    }
    return items;
  }

  List<Widget> _buildCoopItems(List<Map<String, dynamic>> reps) {
    final items = <Widget>[];
    final byCompany = _groupByCompany(reps);
    for (final entry in byCompany.entries) {
      final compReps = entry.value;
      final companyName = _companyLabel(compReps);
      final workerCount =
          compReps.map((r) => r['user_id']).toSet().length;
      final fee = _sumParkingFee(compReps);
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const Icon(Icons.business_outlined,
              color: Color(0xFF4FC3F7), size: 13),
          const SizedBox(width: 4),
          Expanded(
            child: Text(companyName,
                style: const TextStyle(
                    color: Color(0xFF4FC3F7),
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text('${compReps.length}件',
              style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
          if (fee > 0) ...[
            const SizedBox(width: 8),
            Text('¥$fee',
                style: const TextStyle(
                    color: Color(0xFF4FC3F7), fontSize: 11)),
          ],
        ]),
      ));
      for (final r in compReps) {
        items.add(JsReportTile(report: r, myCompanyId: widget.myCompanyId));
      }
      if (workerCount > 1 && fee > 0) {
        items.add(_feeFooter(fee, prefix: '$companyName 計'));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.date;
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        iconTheme: const IconThemeData(color: FieldTokens.brand),
        title: Text(
          '${d.month}月${d.day}日の日報',
          style: const TextStyle(
              color: FieldTokens.brand,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final reports = widget.reports;
    if (reports.isEmpty) {
      return const Center(
        child: Text('この日の日報はありません',
            style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
      );
    }

    final myId = widget.myCompanyId;
    final ownReps = myId.isEmpty
        ? reports
        : reports.where((r) => r['company_id'] == myId).toList();
    final coopReps = myId.isEmpty
        ? <Map<String, dynamic>>[]
        : reports.where((r) => r['company_id'] != myId).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      children: [
        // ── ヘッダー行 + 現場/人 トグル ──
        Row(children: [
          Expanded(
            child: Text(
              '${reports.length}件',
              style: const TextStyle(
                  color: FieldTokens.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _isWorkerView = !_isWorkerView),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: FieldTokens.accent),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isWorkerView
                        ? Icons.person_outline
                        : Icons.location_on,
                    color: FieldTokens.accent,
                    size: 13,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _isWorkerView ? '人別' : '現場別',
                    style: const TextStyle(
                        color: FieldTokens.accent, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // ── 自社ブロック ──
        if (ownReps.isNotEmpty) ..._buildOwnItems(ownReps),
        // ── 区切り（自社＋協力両方あり） ──
        if (ownReps.isNotEmpty && coopReps.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(child: Divider(color: FieldTokens.outline)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('協力業者',
                    style: TextStyle(
                        color: FieldTokens.textSupport, fontSize: 11)),
              ),
              Expanded(child: Divider(color: FieldTokens.outline)),
            ]),
          ),
        // ── 協力ブロック ──
        if (coopReps.isNotEmpty) ..._buildCoopItems(coopReps),
      ],
    );
  }
}
