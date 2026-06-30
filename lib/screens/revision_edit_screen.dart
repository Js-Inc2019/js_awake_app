import 'dart:convert';
import 'package:flutter/material.dart';
import '../main.dart' show JsColors, TransportType;

/// 差戻しされた日報を職人が修正する専用画面（バッチ2）。
/// Step4a：差戻し理由(boss_note)＋作業内容の編集（接頭辞を剥がした本文をTextField化）。
/// 移動手段・写真の編集、PUT/resubmit送信は後続ステップで追加する。
class RevisionEditScreen extends StatefulWidget {
  const RevisionEditScreen({super.key, required this.revision});
  final Map<String, dynamic> revision;

  @override
  State<RevisionEditScreen> createState() => _RevisionEditScreenState();
}

class _RevisionEditScreenState extends State<RevisionEditScreen> {
  final _workCtrl = TextEditingController();
  final _carpoolCtrl = TextEditingController();
  final _otherCtrl = TextEditingController();
  final _parkingCtrl = TextEditingController();

  final Set<TransportType> _transports = {};
  String _carType = 'own'; // 'own' | 'carpool'

  static const Map<TransportType, String> _transportLabels = {
    TransportType.car: '車',
    TransportType.train: '電車',
    TransportType.bus: 'バス',
    TransportType.other: 'その他',
  };

  void _toggleTransport(TransportType t) {
    setState(() {
      if (_transports.contains(t)) {
        _transports.remove(t);
      } else {
        _transports.add(t);
      }
    });
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(color: JsColors.silver, fontSize: 12)),
      );

  InputDecoration _fieldDeco(String hint) => InputDecoration(
        filled: true,
        fillColor: JsColors.gunmetal,
        hintText: hint,
        hintStyle: const TextStyle(color: JsColors.silver),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JsColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JsColors.gold),
        ),
      );

  Widget _carTypeChip(String value, String label) {
    final sel = _carType == value;
    return GestureDetector(
      onTap: () => setState(() => _carType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? JsColors.gold.withValues(alpha: 0.15) : JsColors.gunmetal,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? JsColors.gold : JsColors.divider),
        ),
        child: Text(label,
            style: TextStyle(
              color: sel ? JsColors.gold : JsColors.offWhite,
              fontSize: 13,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _restoreFromRevision();
  }

  @override
  void dispose() {
    _workCtrl.dispose();
    _carpoolCtrl.dispose();
    _otherCtrl.dispose();
    _parkingCtrl.dispose();
    super.dispose();
  }

  // 保存済み work_content から接頭辞/接尾辞を剥がし各入力欄へ復元する。
  // 方針: parking_fee と残業は「列が真実」。相乗り/その他は列に無いので regex 抽出。
  //       transport_types_json(無ければ transport_type)で在るはずの接頭辞を絞り狙い撃ちで剥がす。
  void _restoreFromRevision() {
    final r = widget.revision;
    var content = (r['work_content'] as String?)?.trim() ?? '';
    final transports = _transportNames(r);

    for (final n in transports) {
      final t = TransportType.values
          .firstWhere((e) => e.name == n, orElse: () => TransportType.none);
      if (t != TransportType.none) _transports.add(t);
    }
    if (transports.contains('car')) {
      _carType = RegExp(r'^\[相乗り:').hasMatch(content) ? 'carpool' : 'own';
    }

    // 1) 末尾の残業接尾辞は退避(編集対象外・送信時に原文から再付与)
    content = content.replaceFirst(RegExp(r'\s*【残業[^】]*】\s*$'), '').trimRight();

    // 2) car 系(相乗り or 駐車料金)を先頭から剥がす(car選択時のみ)
    if (transports.contains('car')) {
      final carpool = RegExp(r'^\[相乗り:([^\]]*)\]\s*').firstMatch(content);
      if (carpool != null) {
        _carpoolCtrl.text = carpool.group(1)!.trim();
        content = content.substring(carpool.end);
      } else {
        // 駐車料金は parking_fee 列が真実。接頭辞は捨てる。
        content = content.replaceFirst(RegExp(r'^\[駐車料金:[^\]]*\]\s*'), '');
        final fee = r['parking_fee'];
        if (fee != null) {
          _parkingCtrl.text = (fee is num) ? fee.toInt().toString() : fee.toString().trim();
        }
      }
    }

    // 3) その他を先頭から剥がす(other選択時のみ)
    if (transports.contains('other')) {
      final other = RegExp(r'^\[その他:([^\]]*)\]\s*').firstMatch(content);
      if (other != null) {
        _otherCtrl.text = other.group(1)!.trim();
        content = content.substring(other.end);
      }
    }

    // 4) 残り＝本文
    _workCtrl.text = content.trim();
  }

  // transport_types_json(List or JSON文字列) か transport_type から手段名集合を得る。
  Set<String> _transportNames(Map<String, dynamic> r) {
    final names = <String>{};
    final raw = r['transport_types_json'];
    if (raw is List) {
      for (final e in raw) {
        names.add(e.toString());
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            names.add(e.toString());
          }
        }
      } catch (_) {}
    }
    if (names.isEmpty) {
      final single = (r['transport_type'] as String?)?.trim() ?? '';
      if (single.isNotEmpty) names.add(single);
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.revision;
    final reportDate = (r['report_date'] as String?)?.trim() ?? '';
    final bossNote = (r['boss_note'] as String?)?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('日報の修正'),
        backgroundColor: JsColors.gunmetal,
        foregroundColor: JsColors.offWhite,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (bossNote.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: JsColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JsColors.gold),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.feedback_outlined, color: JsColors.gold, size: 18),
                      SizedBox(width: 6),
                      Text('事務からの修正依頼',
                          style: TextStyle(color: JsColors.gold, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(bossNote,
                      style: const TextStyle(color: JsColors.offWhite, fontSize: 14, height: 1.5)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (reportDate.isNotEmpty) ...[
            const Text('対象日', style: TextStyle(color: JsColors.silver, fontSize: 12)),
            const SizedBox(height: 4),
            Text(reportDate, style: const TextStyle(color: JsColors.offWhite, fontSize: 15)),
            const SizedBox(height: 16),
          ],
          const Text('作業内容', style: TextStyle(color: JsColors.silver, fontSize: 12)),
          const SizedBox(height: 4),
          TextField(
            controller: _workCtrl,
            maxLines: null,
            minLines: 3,
            style: const TextStyle(color: JsColors.offWhite, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: JsColors.gunmetal,
              hintText: '作業内容を入力',
              hintStyle: const TextStyle(color: JsColors.silver),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: JsColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: JsColors.gold),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionLabel('移動手段'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _transportLabels.entries.map((e) {
              final sel = _transports.contains(e.key);
              return GestureDetector(
                onTap: () => _toggleTransport(e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? JsColors.gold : JsColors.gunmetal,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? JsColors.gold : JsColors.divider),
                  ),
                  child: Text(e.value,
                      style: TextStyle(
                        color: sel ? Colors.black : JsColors.offWhite,
                        fontSize: 14,
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      )),
                ),
              );
            }).toList(),
          ),
          if (_transports.contains(TransportType.car)) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _carTypeChip('own', '自分で運転')),
                const SizedBox(width: 8),
                Expanded(child: _carTypeChip('carpool', '相乗り')),
              ],
            ),
            const SizedBox(height: 12),
            if (_carType == 'own') ...[
              _sectionLabel('駐車料金（円）'),
              TextField(
                controller: _parkingCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: JsColors.offWhite, fontSize: 14),
                decoration: _fieldDeco('例: 500'),
              ),
            ] else ...[
              _sectionLabel('相乗り相手（任意）'),
              TextField(
                controller: _carpoolCtrl,
                style: const TextStyle(color: JsColors.offWhite, fontSize: 14),
                decoration: _fieldDeco('誰の相乗りか'),
              ),
            ],
          ],
          if (_transports.contains(TransportType.other)) ...[
            const SizedBox(height: 16),
            _sectionLabel('その他の手段'),
            TextField(
              controller: _otherCtrl,
              style: const TextStyle(color: JsColors.offWhite, fontSize: 14),
              decoration: _fieldDeco('例: タクシー'),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JsColors.gunmetal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JsColors.divider),
            ),
            child: const Row(
              children: [
                Icon(Icons.construction, color: JsColors.silver, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('写真の修正と再提出は次の更新で追加されます。',
                      style: TextStyle(color: JsColors.silver, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
