import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../main.dart' show JsColors, TransportType;

/// 差戻しされた日報を職人が修正する専用画面（バッチ2）。
/// Step5a：作業内容＋移動手段＋写真(既存URL表示・撮り直し)＋備考の編集。
/// 再提出(PUT→resubmit)送信は Step5b で追加する。
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
  final _noteCtrl = TextEditingController();

  final _picker = ImagePicker();
  String? _workPhotoPath;
  String? _parkingPhotoPath;

  final Set<TransportType> _transports = {};
  String _carType = 'own';

  static const Map<TransportType, String> _transportLabels = {
    TransportType.car: '車',
    TransportType.train: '電車',
    TransportType.bus: 'バス',
    TransportType.other: 'その他',
  };

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
    _noteCtrl.dispose();
    super.dispose();
  }

  void _restoreFromRevision() {
    final r = widget.revision;
    var content = (r['work_content'] as String?)?.trim() ?? '';
    final names = _transportNames(r);

    for (final n in names) {
      final t = TransportType.values
          .firstWhere((e) => e.name == n, orElse: () => TransportType.none);
      if (t != TransportType.none) _transports.add(t);
    }

    content = content.replaceFirst(RegExp(r'\s*【残業[^】]*】\s*$'), '').trimRight();

    if (names.contains('car')) {
      final carpool = RegExp(r'^\[相乗り:([^\]]*)\]\s*').firstMatch(content);
      if (carpool != null) {
        _carType = 'carpool';
        _carpoolCtrl.text = carpool.group(1)!.trim();
        content = content.substring(carpool.end);
      } else {
        _carType = 'own';
        content = content.replaceFirst(RegExp(r'^\[駐車料金:[^\]]*\]\s*'), '');
        final fee = r['parking_fee'];
        if (fee != null) {
          _parkingCtrl.text =
              (fee is num) ? fee.toInt().toString() : fee.toString().trim();
        }
      }
    }

    if (names.contains('other')) {
      final other = RegExp(r'^\[その他:([^\]]*)\]\s*').firstMatch(content);
      if (other != null) {
        _otherCtrl.text = other.group(1)!.trim();
        content = content.substring(other.end);
      }
    }

    _workCtrl.text = content.trim();
  }

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

  void _toggleTransport(TransportType t) {
    setState(() {
      if (_transports.contains(t)) {
        _transports.remove(t);
      } else {
        _transports.add(t);
      }
    });
  }

  Future<void> _takeWorkPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (f != null && mounted) setState(() => _workPhotoPath = f.path);
  }

  Future<void> _takeParkingPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (f != null && mounted) setState(() => _parkingPhotoPath = f.path);
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

  // 写真: ローカル撮り直し優先→既存URL→なし。既存は消せない(撮り直しのみ)。
  Widget _photoBlock({
    required String label,
    required String? localPath,
    required String existingUrl,
    required VoidCallback onRetake,
  }) {
    Widget preview;
    if (localPath != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(localPath),
            height: 140, width: double.infinity, fit: BoxFit.cover),
      );
    } else if (existingUrl.isNotEmpty) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(existingUrl,
            height: 140, width: double.infinity, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                  height: 140,
                  width: double.infinity,
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const Text('写真を読み込めません',
                      style: TextStyle(color: JsColors.silver, fontSize: 11)),
                )),
      );
    } else {
      preview = Container(
        height: 80,
        width: double.infinity,
        decoration: BoxDecoration(
          color: JsColors.gunmetal,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JsColors.divider),
        ),
        alignment: Alignment.center,
        child: const Text('写真なし',
            style: TextStyle(color: JsColors.silver, fontSize: 12)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        preview,
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: onRetake,
            icon: const Icon(Icons.camera_alt, size: 16),
            label: Text(localPath != null ? '撮り直す（変更済）' : '撮り直す'),
            style: OutlinedButton.styleFrom(
              foregroundColor: JsColors.gold,
              side: const BorderSide(color: JsColors.gold),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.revision;
    final reportDate = (r['report_date'] as String?)?.trim() ?? '';
    final bossNote = (r['boss_note'] as String?)?.trim() ?? '';
    final siteUrl = (r['site_photo_url'] as String?) ?? '';
    final parkingUrl = (r['parking_photo_url'] as String?) ?? '';
    final isCar = _transports.contains(TransportType.car);
    final isOther = _transports.contains(TransportType.other);

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
            _sectionLabel('対象日'),
            Text(reportDate, style: const TextStyle(color: JsColors.offWhite, fontSize: 15)),
            const SizedBox(height: 16),
          ],
          _sectionLabel('作業内容'),
          TextField(
            controller: _workCtrl,
            maxLines: null,
            minLines: 3,
            style: const TextStyle(color: JsColors.offWhite, fontSize: 14),
            decoration: _fieldDeco('作業内容を入力'),
          ),
          const SizedBox(height: 16),
          _photoBlock(
            label: '作業写真',
            localPath: _workPhotoPath,
            existingUrl: siteUrl,
            onRetake: _takeWorkPhoto,
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
          if (isCar) ...[
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
          if (isOther) ...[
            const SizedBox(height: 16),
            _sectionLabel('その他の手段'),
            TextField(
              controller: _otherCtrl,
              style: const TextStyle(color: JsColors.offWhite, fontSize: 14),
              decoration: _fieldDeco('例: タクシー'),
            ),
          ],
          if (isCar || isOther) ...[
            const SizedBox(height: 16),
            _photoBlock(
              label: '看板/領収書（任意）',
              localPath: _parkingPhotoPath,
              existingUrl: parkingUrl,
              onRetake: _takeParkingPhoto,
            ),
          ],
          const SizedBox(height: 20),
          _sectionLabel('事務への申し送り（任意）'),
          TextField(
            controller: _noteCtrl,
            maxLines: null,
            minLines: 2,
            style: const TextStyle(color: JsColors.offWhite, fontSize: 14),
            decoration: _fieldDeco('指定外で気づいた点などがあれば記入'),
          ),
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
                  child: Text('再提出ボタンは次の更新で追加されます。',
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
