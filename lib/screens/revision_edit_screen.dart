import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show TransportType, showJsSnackbar;
import '../core/theme/js_colors.dart';
import '../config/constants.dart';
import '../utils/revision_parser.dart';
import '../widgets/photo_strip_field.dart';

/// 差戻しされた日報を職人が修正する専用画面（バッチ2 完成）。
/// 作業内容/移動手段/写真/備考を編集し、PUT→resubmit の2段で再提出する。
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

  // 撮り直しで新規撮影したローカルパス（種別ごと・複数枚）。
  final List<String> _workPhotoPaths = <String>[];
  final List<String> _parkingPhotoPaths = <String>[];
  // 撮り直しモード（ON=PhotoStripFieldで撮影 / OFF=既存写真を表示）。
  bool _retakeWork = false;
  bool _retakeParking = false;

  // GET /reports/:id で取得した既存active写真URL（種別ごと・複数枚）。
  // 失敗/空なら build 側で旧単数URL(site_photo_url/parking_photo_url)へフォールバック。
  List<String> _existingSiteUrls = <String>[];
  List<String> _existingParkingUrls = <String>[];
  bool _photosLoaded = false;

  final Set<TransportType> _transports = {};
  String _carType = 'own';
  String _overtimeSuffix = ''; // 残業接尾辞(編集対象外・退避→再付与)
  bool _submitting = false;

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
    _loadExistingPhotos();
  }

  // 既存写真(フォールバック込み): GET結果があればそれ、無ければ旧単数URLを1要素に。
  List<String> get _effectiveExistingSiteUrls {
    if (_existingSiteUrls.isNotEmpty) return _existingSiteUrls;
    final u = ((widget.revision['site_photo_url'] as String?) ?? '').trim();
    return u.isEmpty ? const <String>[] : <String>[u];
  }

  List<String> get _effectiveExistingParkingUrls {
    if (_existingParkingUrls.isNotEmpty) return _existingParkingUrls;
    final u = ((widget.revision['parking_photo_url'] as String?) ?? '').trim();
    return u.isEmpty ? const <String>[] : <String>[u];
  }

  // GET /reports/:id はトップレベルに photos:[{photo_type,photo_url,...}] を返す
  // （一覧LISTは互換カラムのみで photos[] 無し）。種別ごとにURLを集める。失敗時は build 側でフォールバック。
  Future<void> _loadExistingPhotos() async {
    final reportId = widget.revision['report_id'] as String?;
    if (reportId == null) {
      if (mounted) setState(() => _photosLoaded = true);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final res = await http.get(
        Uri.parse('$kApiBaseUrl/reports/$reportId'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['photos'] as List?) ?? const [];
        final site = <String>[];
        final parking = <String>[];
        for (final p in list) {
          if (p is! Map) continue;
          final type = p['photo_type']?.toString();
          final url = (p['photo_url']?.toString() ?? '').trim();
          if (url.isEmpty) continue;
          if (type == 'site') {
            site.add(url);
          } else if (type == 'parking') {
            parking.add(url);
          }
        }
        if (mounted) {
          setState(() {
            _existingSiteUrls = site;
            _existingParkingUrls = parking;
            _photosLoaded = true;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('既存写真の取得に失敗: $e');
    }
    if (mounted) setState(() => _photosLoaded = true);
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
    final p = parseRevision(widget.revision);
    for (final n in p.transportNames) {
      final t = TransportType.values
          .firstWhere((e) => e.name == n, orElse: () => TransportType.none);
      if (t != TransportType.none) _transports.add(t);
    }
    _carType = p.carType;
    _overtimeSuffix = p.overtimeSuffix;
    _workCtrl.text = p.workContent;
    _carpoolCtrl.text = p.carpoolText;
    _parkingCtrl.text = p.parkingText;
    _otherCtrl.text = p.otherText;
  }


  // 保存形式に合わせ work_content を組み立て直す(home_screen と同じ接頭辞順)。
  String _composeWorkContent() {
    final body = _workCtrl.text.trim();
    final hasCar = _transports.contains(TransportType.car);
    final hasOther = _transports.contains(TransportType.other);
    var carpoolPrefix = '';
    var parkingPrefix = '';
    if (hasCar && _carType == 'carpool') {
      final who = _carpoolCtrl.text.trim().isEmpty ? '未記入' : _carpoolCtrl.text.trim();
      carpoolPrefix = '[相乗り:$who] ';
    }
    if (hasCar && _carType == 'own' && _parkingCtrl.text.trim().isNotEmpty) {
      parkingPrefix = '[駐車料金:${_parkingCtrl.text.trim()}円] ';
    }
    final otherPrefix = (hasOther && _otherCtrl.text.trim().isNotEmpty)
        ? '[その他:${_otherCtrl.text.trim()}] '
        : '';
    final suffix = _overtimeSuffix.isEmpty ? '' : ' ${_overtimeSuffix.trim()}';
    return '$carpoolPrefix$parkingPrefix$otherPrefix$body$suffix';
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

  Future<void> _submit() async {
    if (_submitting) return;
    if (_workCtrl.text.trim().isEmpty) {
      showJsSnackbar(context, '作業内容を入力してください', isError: true);
      return;
    }

    final reportId = widget.revision['report_id'] as String?;
    if (reportId == null) {
      showJsSnackbar(context, '対象の日報が特定できません', isError: true);
      return;
    }

    // 未添付ダイアログ: 車/その他 かつ 駐車写真が実質ゼロ
    //（撮り直しON→新規0枚 / 撮り直しOFF→既存(フォールバック込み)なし）。
    // home_screen と同文言・同構造。
    final hasCarOrOther = _transports.contains(TransportType.car) ||
        _transports.contains(TransportType.other);
    final parkingEmpty = _retakeParking
        ? _parkingPhotoPaths.isEmpty
        : _effectiveExistingParkingUrls.isEmpty;
    if (hasCarOrOther && parkingEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('写真が添付されていません'),
          content: const Text(
              '駐車場の看板または領収書の写真が添付されていません。このまま送信しますか？\n\n※戻ったら、駐車場写真の「撮り直す」→「＋撮影」から撮影できます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('戻って撮影する'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('このまま送信'),
            ),
          ],
        ),
      );
      if (proceed != true) return; // 「戻って撮影する」→送信中断
    }

    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final body = <String, dynamic>{
        'edit_reason': '差戻し対応',
        'work_content': _composeWorkContent(),
        'transport_type':
            _transports.isNotEmpty ? _transports.first.name : null,
        'transport_types_json': _transports.map((t) => t.name).toList(),
        'parking_fee': (_transports.contains(TransportType.car) &&
                _carType == 'own' &&
                _parkingCtrl.text.trim().isNotEmpty)
            ? double.tryParse(_parkingCtrl.text.trim())
            : null,
      };
      // 写真は「撮り直しON かつ 新規1枚以上」の種別だけ photos[] で送る。
      // 通常提出(main.dart)と同一構造 [{photo_type,base64}]。BE側で該当種別の既存を
      // 無効化→新規追記(置換)。未送信種別は温存。
      final photos = <Map<String, dynamic>>[];
      if (_retakeWork) {
        for (final p in _workPhotoPaths) {
          try {
            photos.add({
              'photo_type': 'site',
              'base64': base64Encode(await File(p).readAsBytes()),
            });
          } catch (e) {
            debugPrint('作業写真エンコード失敗: $e');
          }
        }
      }
      if (_retakeParking) {
        for (final p in _parkingPhotoPaths) {
          try {
            photos.add({
              'photo_type': 'parking',
              'base64': base64Encode(await File(p).readAsBytes()),
            });
          } catch (e) {
            debugPrint('駐車写真エンコード失敗: $e');
          }
        }
      }
      if (photos.isNotEmpty) body['photos'] = photos;

      final putRes = await http
          .put(Uri.parse('$kApiBaseUrl/reports/$reportId'),
              headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      if (putRes.statusCode != 200) {
        if (!mounted) return;
        setState(() => _submitting = false);
        showJsSnackbar(context, '保存に失敗しました（${putRes.statusCode}）', isError: true);
        return;
      }

      final resubmitRes = await http
          .post(Uri.parse('$kApiBaseUrl/reports/$reportId/resubmit'),
              headers: headers,
              body: jsonEncode({'worker_revision_note': _noteCtrl.text.trim()}))
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (resubmitRes.statusCode >= 200 && resubmitRes.statusCode < 300) {
        showJsSnackbar(context, '✅ 修正して再提出しました');
        Navigator.pop(context, true);
      } else {
        setState(() => _submitting = false);
        showJsSnackbar(context,
            '保存はできましたが再提出に失敗しました。もう一度「再提出」を押してください（${resubmitRes.statusCode}）',
            isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showJsSnackbar(context, '通信エラーが発生しました', isError: true);
    }
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

  // 種別ごとの写真ブロック。撮り直しOFF=既存写真(複数)を表示、ON=複数撮影の帯へ切替。
  Widget _photoSection({
    required String label,
    required List<String> existingUrls,
    required List<String> newPaths,
    required bool retake,
    required VoidCallback onRetakeStart,
    required VoidCallback onRestoreExisting,
    required ValueChanged<List<String>> onChanged,
  }) {
    if (retake) {
      // 撮り直しモード: 既存widget(PhotoStripField・上限5)を再利用。「既存に戻す」で袋小路防止。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhotoStripField(
            label: label,
            paths: newPaths,
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRestoreExisting,
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('既存に戻す'),
              style: TextButton.styleFrom(foregroundColor: JsColors.silver),
            ),
          ),
        ],
      );
    }
    // 既存表示モード
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('$label（既存）'),
        if (existingUrls.isEmpty)
          Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: JsColors.gunmetal,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: JsColors.divider),
            ),
            alignment: Alignment.center,
            child: Text(_photosLoaded ? '写真なし' : '読み込み中…',
                style: const TextStyle(color: JsColors.silver, fontSize: 12)),
          )
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: existingUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _existingThumb(existingUrls[i]),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: onRetakeStart,
            icon: const Icon(Icons.camera_alt, size: 16),
            label: const Text('撮り直す'),
            style: OutlinedButton.styleFrom(
              foregroundColor: JsColors.gold,
              side: const BorderSide(color: JsColors.gold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _existingThumb(String url) {
    return GestureDetector(
      onTap: () => _previewNetwork(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 88,
            height: 88,
            color: Colors.black26,
            alignment: Alignment.center,
            child: const Text('読込不可',
                style: TextStyle(color: JsColors.silver, fontSize: 10)),
          ),
        ),
      ),
    );
  }

  void _previewNetwork(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            IconButton(
              onPressed: () => Navigator.of(ctx).pop(),
              icon: const Icon(Icons.close, color: JsColors.offWhite),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.revision;
    final reportDate = (r['report_date'] as String?)?.trim() ?? '';
    final bossNote = (r['boss_note'] as String?)?.trim() ?? '';
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
          _photoSection(
            label: '作業写真',
            existingUrls: _effectiveExistingSiteUrls,
            newPaths: _workPhotoPaths,
            retake: _retakeWork,
            onRetakeStart: () => setState(() {
              _retakeWork = true;
              _workPhotoPaths.clear();
            }),
            onRestoreExisting: () => setState(() {
              _retakeWork = false;
              _workPhotoPaths.clear();
            }),
            onChanged: (v) => setState(() {
              _workPhotoPaths
                ..clear()
                ..addAll(v);
            }),
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
            _photoSection(
              label: '看板/領収書（任意）',
              existingUrls: _effectiveExistingParkingUrls,
              newPaths: _parkingPhotoPaths,
              retake: _retakeParking,
              onRetakeStart: () => setState(() {
                _retakeParking = true;
                _parkingPhotoPaths.clear();
              }),
              onRestoreExisting: () => setState(() {
                _retakeParking = false;
                _parkingPhotoPaths.clear();
              }),
              onChanged: (v) => setState(() {
                _parkingPhotoPaths
                  ..clear()
                  ..addAll(v);
              }),
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
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: JsColors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                  : const Text('修正して再提出する',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
