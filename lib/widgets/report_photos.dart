// lib/widgets/report_photos.dart - 日報写真 共通Widget
import 'package:flutter/material.dart';
import '../services/reports_service.dart';
import '../main.dart' show JsColors;

// ─── 日報写真（オンデマンド取得＋サムネ帯＋拡大） ──────────────────────
// 「写真を見る」タップで GET /reports/:id を叩き photos[] を取得。
// photos[] が空の種別は一覧itemの旧単数URL(site_photo_url/parking_photo_url)へフォールバック。
class ReportPhotos extends StatefulWidget {
  const ReportPhotos({super.key, required this.reportId, required this.report});
  final String reportId;
  final Map<String, dynamic> report;

  @override
  State<ReportPhotos> createState() => ReportPhotosState();
}

class ReportPhotosState extends State<ReportPhotos> {
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  List<String> _siteUrls = <String>[];
  List<String> _parkingUrls = <String>[];

  // 一覧itemの旧単数URL（フォールバック用・追加GET不要）。
  String get _fallbackSite =>
      ((widget.report['site_photo_url'] as String?) ?? '').trim();
  String get _fallbackParking =>
      ((widget.report['parking_photo_url'] as String?) ?? '').trim();

  Future<void> _fetch() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    List<String> site = <String>[];
    List<String> parking = <String>[];
    try {
      if (widget.reportId.isEmpty) throw Exception('report_id なし');
      final result = await ReportsService().getReportDetail(widget.reportId);
      if (result['success'] != true) throw Exception(result['error']?.toString() ?? '取得失敗');
      final photos = (result['photos'] as List?) ?? const [];
      for (final p in photos) {
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
    } catch (e) {
      // 非ブロック: 取得失敗でもフォールバックURLがあれば表示、無ければエラー文言。
      if (mounted) {
        final hasFallback =
            _fallbackSite.isNotEmpty || _fallbackParking.isNotEmpty;
        setState(() {
          _loading = false;
          _loaded = true;
          _error = hasFallback ? null : '写真の取得に失敗しました';
        });
      }
      return;
    }
    // 種別ごと: photos[] が空なら旧単数URLへフォールバック。
    if (site.isEmpty && _fallbackSite.isNotEmpty) site = <String>[_fallbackSite];
    if (parking.isEmpty && _fallbackParking.isNotEmpty) {
      parking = <String>[_fallbackParking];
    }
    if (mounted) {
      setState(() {
        _siteUrls = site;
        _parkingUrls = parking;
        _loading = false;
        _loaded = true;
      });
    }
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

  Widget _thumb(String url) {
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

  Widget _strip(String label, List<String> urls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: JsColors.silver, fontSize: 12)),
        const SizedBox(height: 4),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _thumb(urls[i]),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).colorScheme.primary;

    // 未取得: トリガーボタン
    if (!_loaded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _loading ? null : _fetch,
          icon: _loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: pc))
              : Icon(Icons.photo_camera_outlined, size: 18, color: pc),
          label: Text(_loading ? '読み込み中…' : '写真を見る',
              style: TextStyle(color: pc, fontSize: 13)),
        ),
      );
    }

    // 取得失敗（フォールバックも無し）: 非ブロックで再試行可
    if (_error != null) {
      return Row(
        children: [
          Expanded(
            child: Text(_error!,
                style: const TextStyle(color: JsColors.silver, fontSize: 12)),
          ),
          TextButton(
            onPressed: _loading ? null : _fetch,
            child: Text('再試行', style: TextStyle(color: pc, fontSize: 12)),
          ),
        ],
      );
    }

    // 写真なし
    if (_siteUrls.isEmpty && _parkingUrls.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('写真なし',
            style: TextStyle(color: JsColors.silver, fontSize: 12)),
      );
    }

    // サムネ帯（種別ごと）
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_siteUrls.isNotEmpty) _strip('作業写真', _siteUrls),
        if (_siteUrls.isNotEmpty && _parkingUrls.isNotEmpty)
          const SizedBox(height: 10),
        if (_parkingUrls.isNotEmpty) _strip('看板・領収書', _parkingUrls),
      ],
    );
  }
}
