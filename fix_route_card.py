with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    lines = f.readlines()

# 1854行目から1907行目を新しい_RouteResultCardに置換
new_card = """class _RouteResultCard extends StatelessWidget {
  const _RouteResultCard({required this.comparisons, required this.selectedTransport});
  final Map<String, dynamic> comparisons;
  final TransportType selectedTransport;

  @override
  Widget build(BuildContext context) {
    if (selectedTransport == TransportType.train || selectedTransport == TransportType.bus) {
      return _buildTransit();
    } else if (selectedTransport == TransportType.car || selectedTransport == TransportType.moto) {
      return _buildCar();
    } else if (selectedTransport == TransportType.bike) {
      return _buildSimple('bicycling', '\u81ea\u8ee2\u8eca');
    } else {
      return _buildSimple('walking', '\u5f92\u6b69');
    }
  }

  Widget _buildTransit() {
    final t = comparisons['transit'];
    if (t == null) return const SizedBox.shrink();
    final sections = t.routes as List<dynamic>;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.train, color: JsColors.gold, size: 16),
          const SizedBox(width: 6),
          Text('\u6240\u8981\u6642\u9593: ${t.time}\u5206',
              style: const TextStyle(color: JsColors.offWhite, fontSize: 13)),
          const Spacer(),
          Text('\u00a5${t.fareIc}',
              style: const TextStyle(color: JsColors.gold, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        if (t.depStation.isNotEmpty || t.arrStation.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('${t.depStation} \u2192 ${t.arrStation}',
              style: const TextStyle(color: JsColors.silver, fontSize: 12)),
        ],
        if (sections.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...sections.map((s) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('  ${s.from} \u2192 [${s.line}] \u2192 ${s.to}',
                style: const TextStyle(color: JsColors.silver, fontSize: 11)),
          )),
        ],
        const SizedBox(height: 4),
        const Text('\u203b\u5b9f\u969b\u306e\u6599\u91d1\u30fb\u6642\u9593\u3068\u7570\u306a\u308b\u5834\u5408\u304c\u3042\u308a\u307e\u3059',
            style: TextStyle(color: JsColors.silver, fontSize: 10)),
      ]),
    );
  }

  Widget _buildCar() {
    final c = comparisons['car'];
    if (c == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.directions_car, color: JsColors.gold, size: 16),
          const SizedBox(width: 6),
          Text('${c.distanceText}  ${c.time}\u5206',
              style: const TextStyle(color: JsColors.offWhite, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          _CostChip(label: '\u30ac\u30bd\u30ea\u30f3\u4ee3', value: '\u00a5${c.gasCost}'),
          if (c.tollNormal > 0)
            _CostChip(label: '\u9ad8\u901f(\u666e\u901a)', value: '\u00a5${c.tollNormal}'),
          if (c.tollLight > 0)
            _CostChip(label: '\u9ad8\u901f(\u8efd)', value: '\u00a5${c.tollLight}'),
        ]),
        const SizedBox(height: 6),
        if (c.totalNormal > 0)
          Row(children: [
            Text('\u5408\u8a08(\u666e\u901a): ', style: const TextStyle(color: JsColors.silver, fontSize: 12)),
            Text('\u00a5${c.totalNormal}',
                style: const TextStyle(color: JsColors.gold, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(width: 12),
            Text('\u8efd: ', style: const TextStyle(color: JsColors.silver, fontSize: 12)),
            Text('\u00a5${c.totalLight}',
                style: const TextStyle(color: JsColors.gold, fontWeight: FontWeight.bold, fontSize: 13)),
          ])
        else
          Text('\u5408\u8a08: \u00a5${c.gasCost}',
              style: const TextStyle(color: JsColors.gold, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        const Text('\u203b\u5b9f\u969b\u306e\u6599\u91d1\u30fb\u6642\u9593\u3068\u7570\u306a\u308b\u5834\u5408\u304c\u3042\u308a\u307e\u3059',
            style: TextStyle(color: JsColors.silver, fontSize: 10)),
      ]),
    );
  }

  Widget _buildSimple(String key, String label) {
    final s = comparisons[key];
    if (s == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.route, color: JsColors.gold, size: 16),
        const SizedBox(width: 8),
        Text('$label  ${s.distance}  ${s.duration}',
            style: const TextStyle(color: JsColors.offWhite, fontSize: 13)),
      ]),
    );
  }
}

class _CostChip extends StatelessWidget {
  const _CostChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: JsColors.surface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: JsColors.divider),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(color: JsColors.silver, fontSize: 9)),
      Text(value, style: const TextStyle(color: JsColors.gold, fontWeight: FontWeight.bold, fontSize: 12)),
    ]),
  );
}

"""

new_lines = lines[:1853] + [new_card] + lines[1907:]

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
print('OK')
