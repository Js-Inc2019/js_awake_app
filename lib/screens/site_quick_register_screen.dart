// lib/screens/site_quick_register_screen.dart
// 職長の承認ゲートから開く「現場の仮登録」軽量フォーム（FIELD / Asphalt Dawn）。
//   ・入力: 現場名(必須) / 住所(任意)。lat/lng は任意（呼び出し元が渡せれば引き継ぐ）。
//   ・重複チェック(a案): 画面は即開き、表示後に非同期で gps_address→geocode→matchSites(50m)。
//     候補があれば上部に控えめに提示。候補タップ = 新規登録せずその現場を選択（site_id を返す）
//     ＝重複入口の封鎖。geocode失敗(not_found/error/offline)・候補なしは静かにスキップ
//     （ダイアログ/スナックバー禁止＝登録の摩擦を増やさない・袋小路なし）。
//   ・登録 = POST /sites（status はサーバが boss→pending 付与）→ 201 の site_id を返す。
//   ・戻り値契約: Navigator.pop(context, siteId)（キャンセル/失敗時は pop せず or null）。
import 'package:flutter/material.dart';
import '../services/site_service.dart';
import '../core/theme/js_colors.dart';

class SiteQuickRegisterScreen extends StatefulWidget {
  const SiteQuickRegisterScreen({
    super.key,
    this.initialAddress,
    this.lat,
    this.lng,
  });

  final String? initialAddress; // 日報の gps_address（あれば住所欄の初期値）
  final double? lat;            // 提出GPS緯度（あれば重複チェック＆登録座標に使用）
  final double? lng;            // 提出GPS経度

  @override
  State<SiteQuickRegisterScreen> createState() => _SiteQuickRegisterScreenState();
}

class _SiteQuickRegisterScreenState extends State<SiteQuickRegisterScreen> {
  final SiteService _siteService = SiteService();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _addrCtrl = TextEditingController();

  bool _submitting = false;
  List<Map<String, dynamic>> _nearby = []; // matchSites の候補（50m以内）

  @override
  void initState() {
    super.initState();
    if (widget.initialAddress != null && widget.initialAddress!.trim().isNotEmpty) {
      _addrCtrl.text = widget.initialAddress!.trim();
    }
    _checkDuplicatesSilently();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  // 表示時の重複チェック（a案・画面は既に開いている＝完全非同期）。
  //   1) 座標が渡っていればそれを使用。無ければ gps_address を geocode して座標化。
  //   2) matchSites(50m) で近隣候補を取得し、あれば上部に提示。
  //   すべての失敗（geocode not_found/error/offline・match ok:false・材料なし）は
  //   静かにスキップ（ダイアログ/スナックバー禁止＝登録の摩擦を増やさない・袋小路なし）。
  Future<void> _checkDuplicatesSilently() async {
    double? lat = widget.lat;
    double? lng = widget.lng;

    if (lat == null || lng == null) {
      final addr = widget.initialAddress?.trim() ?? '';
      if (addr.isEmpty) return; // 材料なし＝チェック不可（登録は可能）
      final g = await _siteService.geocode(addr);
      if (!mounted) return;
      if (g['status'] != 'ok') return; // not_found/error/offline → 静かにスキップ
      lat = g['lat'] as double?;
      lng = g['lng'] as double?;
      if (lat == null || lng == null) return;
    }

    final res = await _siteService.matchSites(lat, lng);
    if (!mounted) return;
    if (res['ok'] == true) {
      final sites = (res['sites'] as List).cast<Map<String, dynamic>>();
      if (sites.isNotEmpty) setState(() => _nearby = sites);
    }
    // res['ok']==false（非200/通信断）は静かにスキップ（登録をブロックしない）
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現場名を入力してください'), backgroundColor: JsColors.error),
      );
      return;
    }
    setState(() => _submitting = true);
    final siteId = await _siteService.createSiteReturningId(
      siteName: name,
      address: _addrCtrl.text.trim().isEmpty ? null : _addrCtrl.text.trim(),
      lat: widget.lat,
      lng: widget.lng,
    );
    if (!mounted) return;
    if (siteId != null && siteId.isNotEmpty) {
      Navigator.pop(context, siteId); // 登録成功 → site_id を呼び出し元へ返す
      return;
    }
    // 非200/通信断は無言禁止：エラー表示して留まる（袋小路なし）
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('現場の登録に失敗しました。通信状況を確認して再試行してください'),
        backgroundColor: JsColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.background,
      appBar: AppBar(
        backgroundColor: JsColors.surface,
        foregroundColor: JsColors.gold,
        title: const Text('現場の仮登録',
            style: TextStyle(color: JsColors.gold, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 近くの既存現場（重複回避）
            if (_nearby.isNotEmpty) ...[
              _nearbyCard(),
              const SizedBox(height: 16),
            ],
            // 現場名（必須）
            const Text('現場名 *',
                style: TextStyle(color: JsColors.textMid, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: JsColors.textWhite, fontSize: 15),
              decoration: _deco('例: ○○様邸 新築工事'),
            ),
            const SizedBox(height: 16),
            // 住所（任意）
            const Text('住所（任意）',
                style: TextStyle(color: JsColors.textMid, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _addrCtrl,
              style: const TextStyle(color: JsColors.textWhite, fontSize: 15),
              decoration: _deco('日報のGPS住所を初期表示（編集可）'),
            ),
            const SizedBox(height: 20),
            // 仮登録の説明（心理的負担軽減）
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x2EFFB800), // warning 約18%
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: JsColors.warning),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: JsColors.warning, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text('仮登録として登録されます（事務が後で確認します）',
                      style: TextStyle(color: JsColors.warning, fontSize: 13, height: 1.4)),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_location_alt),
                label: Text(_submitting ? '登録中…' : '仮登録して紐づけ'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JsColors.success,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nearbyCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JsColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JsColors.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.near_me, color: JsColors.gold, size: 16),
            SizedBox(width: 6),
            Expanded(
              child: Text('📍 近くに登録済みの現場があります',
                  style: TextStyle(color: JsColors.gold, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 2),
          const Text('タップすると新規登録せずにその現場へ紐づけます（提案）',
              style: TextStyle(color: JsColors.textMid, fontSize: 11)),
          const SizedBox(height: 4),
          ..._nearby.map((s) {
            final id = s['site_id'] as String?;
            final name = s['site_name'] as String? ?? '(名称未設定)';
            final addr = (s['address'] as String? ?? '').trim();
            final dist = s['distance_m'];
            final distStr = (dist is num) ? '約${dist.round()}m' : '';
            final isPending = (s['status'] as String?) == 'pending';
            final sub = [if (addr.isNotEmpty) addr, if (distStr.isNotEmpty) distStr].join('　');
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_on, color: JsColors.gold, size: 18),
              // 現場名＋（pending 現場は仮登録バッジ併記）
              title: Row(children: [
                Flexible(
                  child: Text(name,
                      style: const TextStyle(color: JsColors.textWhite, fontSize: 14)),
                ),
                if (isPending) ...[
                  const SizedBox(width: 6),
                  _pendingBadge(),
                ],
              ]),
              subtitle: sub.isNotEmpty
                  ? Text(sub, style: const TextStyle(color: JsColors.textMid, fontSize: 11))
                  : null,
              trailing: const Text('これを選ぶ',
                  style: TextStyle(color: JsColors.gold, fontSize: 12)),
              // 候補タップ = 新規登録せず既存 site_id を返す（承認ゲートの紐づけ経路へ合流）
              onTap: id == null ? null : () => Navigator.pop(context, id),
            );
          }),
        ],
      ),
    );
  }

  // 仮登録(pending)現場のバッジ（本ファイル:140 の warning 約18% リテラルと同型）。
  Widget _pendingBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0x2EFFB800),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: JsColors.warning),
    ),
    child: const Text('仮登録',
        style: TextStyle(color: JsColors.warning, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: JsColors.textWeak, fontSize: 13),
        filled: true,
        fillColor: JsColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: JsColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: JsColors.gold),
        ),
      );
}
