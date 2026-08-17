// ============================================================
// lib/screens/share_receipt_detail_screen.dart — 受信した日報の閲覧（FIELD）
//
// 導線: 受信トレイ（share_inbox_screen.dart）の行タップ。
//
// ★本文は【受信トレイの行が持っている18キーだけで描く】。追加の GET は写真のためだけ。
//   理由: GET /bundles/receipts の白リスト射影（routes/bundles.js:793-812）に
//   worker_name / report_date / site_name / work_content / gps_address /
//   report_created_at まで載っているため、本文を出すのに原本を取り直す必要が無い。
//   取り直すと「受信社に見せる範囲」を FE 側で2通りに持つことになる。
//
// 自動既読: 開いた瞬間に PATCH /bundles/receipts/:id/read を1回だけ叩く（冪等）。
//   ★処理鍵が無い人の 403 はエラー表示しない（debugPrint に残すだけ）。
//     「読めるが既読は付けられない」は権限設計どおりの正常な状態で、
//     日報の閲覧そのものは成功しているため、赤い文言を出すと嘘になる。
//   ★通信断・その他の失敗も同様に表示は継続する（閲覧を止める理由が無い）。
//
// 写真: 束が include_photos=true で送られていた場合だけ原本から見える
//   （BE routes/reports.js:2294-2305 の束経路＝include_photos=true かつ自社が受信社）。
//   ★共通の ReportPhotos ウィジェットは使わない。あちらは取得失敗を
//     「写真の取得に失敗しました」の一文で表すため（report_photos.dart:62）、
//     写真を含めずに送られた束（＝404 が正常）でも「失敗」と言ってしまう。
//     受信側では 404/403 を「共有されていない」と言い切る必要があるので、
//     この画面専用に持つ。ReportPhotos 自体は日報・履歴の経路（home_screen:5545 /
//     revision_inbox_screen:372）で現役なので触らない。
// ============================================================

import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import '../services/bundles_service.dart';
import '../services/reports_service.dart';
import 'share_bundle_detail_screen.dart';
import 'share_inbox_screen.dart'
    show ReceiptMark, receiptMarkOf, fmtShareDate, fmtShareDateTime;

class ShareReceiptDetailScreen extends StatefulWidget {
  const ShareReceiptDetailScreen({
    super.key,
    required this.receipt,
    required this.canManage,
  });

  /// GET /bundles/receipts の1行（18キー）。呼び手がコピーを渡す。
  final Map<String, dynamic> receipt;

  /// 処理鍵。束詳細の「確認しました」の出し分けにそのまま渡す。
  final bool canManage;

  @override
  State<ShareReceiptDetailScreen> createState() =>
      _ShareReceiptDetailScreenState();
}

class _ShareReceiptDetailScreenState extends State<ShareReceiptDetailScreen> {
  final BundlesService _bundles = BundlesService();
  final ReportsService _reports = ReportsService();

  late Map<String, dynamic> _r;

  // 写真の状態。_photoNote は「なぜ出せないか」を言い切るための1文
  //   （null＝出せない理由が無い＝写真がある or まだ取得中）。
  bool _photoLoading = true;
  List<String> _sitePhotos = const [];
  List<String> _parkingPhotos = const [];
  String? _photoNote;

  @override
  void initState() {
    super.initState();
    _r = widget.receipt;
    _markRead();
    _loadPhotos();
  }

  // ── 自動既読（冪等・失敗しても表示は継続）──────────────────────
  Future<void> _markRead() async {
    final receiptId = (_r['receipt_id'] ?? '').toString();
    if (receiptId.isEmpty) {
      debugPrint('share receipt: receipt_id が無い — 既読を送らない');
      return;
    }
    final res = await _bundles.markReceiptRead(receiptId);
    if (!mounted) return;
    if (res.ok) {
      // 応答の receipt（RECEIPT_FIELDS 7キー）で手元の印を更新する。
      final receipt = res.data?['receipt'];
      if (receipt is Map) {
        setState(() {
          _r['read_at'] = receipt['read_at'];
          _r['receipt_status'] = receipt['receipt_status'];
        });
      }
      return;
    }
    // ★ここでは画面に出さない（上のヘッダの理由）。ただし黙って消さない。
    debugPrint('share receipt: 既読を付けられなかった '
        'receipt_id=$receiptId status=${res.statusCode} code=${res.errorCode}');
  }

  // ── 写真（束経路で見えるのは include_photos=true のときだけ）─────────
  Future<void> _loadPhotos() async {
    final reportId = (_r['report_id'] ?? '').toString();
    if (reportId.isEmpty) {
      setState(() {
        _photoLoading = false;
        _photoNote = '対象の日報を特定できませんでした';
      });
      return;
    }
    final res = await _reports.getReportDetail(reportId);
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _photoLoading = false;
        // 404/403 は「写真つきで送られていない」＝正常。失敗と混ぜない。
        _photoNote = (res.statusCode == 404 || res.statusCode == 403)
            ? 'この束は写真を含めずに送られています'
            : res.statusCode == 0
                ? '写真を取得できませんでした（通信できませんでした）'
                : '写真を取得できませんでした（${res.errorMessage ?? "理由不明"}）';
      });
      return;
    }
    final site = <String>[];
    final parking = <String>[];
    for (final p in (res.data?.photos ?? const [])) {
      if (p is! Map) continue;
      final url = (p['photo_url'] ?? '').toString().trim();
      if (url.isEmpty) continue;
      if (p['photo_type'] == 'site') {
        site.add(url);
      } else if (p['photo_type'] == 'parking') {
        parking.add(url);
      }
    }
    setState(() {
      _photoLoading = false;
      _sitePhotos = site;
      _parkingPhotos = parking;
      _photoNote =
          (site.isEmpty && parking.isEmpty) ? 'この日報に写真はありません' : null;
    });
  }

  void _openBundle() {
    final bundleId = (_r['bundle_id'] ?? '').toString();
    if (bundleId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShareBundleDetailScreen(
        bundleId: bundleId,
        canManage: widget.canManage,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final mark = receiptMarkOf(_r);
    final (markColor, markLabel) = switch (mark) {
      ReceiptMark.tampered => (
          FieldTokens.statusError,
          _r['receipt_status'] == 'tampered' ? '改ざん' : '原本変更'
        ),
      ReceiptMark.unread => (FieldTokens.statusWarning, '未読'),
      ReceiptMark.read => (FieldTokens.textFaint, '既読'),
    };

    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        title: const Text('受信した日報'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 状態（印）───────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: markColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: markColor, width: 1.2),
            ),
            child: Row(children: [
              Icon(
                mark == ReceiptMark.tampered
                    ? Icons.gpp_maybe_outlined
                    : mark == ReceiptMark.read
                        ? Icons.mark_email_read_outlined
                        : Icons.mark_email_unread_outlined,
                color: markColor,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(markLabel,
                        style: TextStyle(
                            color: markColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    if (mark == ReceiptMark.tampered) ...[
                      const SizedBox(height: 4),
                      Text(
                        _r['receipt_status'] == 'tampered'
                            ? '受信後に原本の改ざんが検知されています。内容をそのまま信用しないでください。'
                            : '送信後に送信社が原本を変更しています。届いた時点の内容と一致しません。',
                        style: const TextStyle(
                            color: FieldTokens.textBody,
                            fontSize: 12,
                            height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 22),

          // ── 送信元 ─────────────────────────────────────
          _section('送信元'),
          _row('会社', _s(_r['sender_company_name'])),
          _row('送信者', _s(_r['sender_name'])),
          _row('届いた日', fmtShareDateTime(_r['sent_at'])),
          const SizedBox(height: 22),

          // ── 日報 ───────────────────────────────────────
          _section('日報'),
          _row('日付', fmtShareDate(_r['report_date'])),
          _row('職人', _s(_r['worker_name'])),
          _row('現場', _s(_r['site_name'])),
          // 提出時刻は report_created_at（束の作成時刻ではない）。
          _row('提出', fmtShareDateTime(_r['report_created_at'])),
          if (_s(_r['gps_address']) != '-') _row('報告場所', _s(_r['gps_address'])),
          if (_s(_r['work_content']) != '-') ...[
            const SizedBox(height: 10),
            const Text('作業内容',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
            const SizedBox(height: 4),
            Text(_s(_r['work_content']),
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 13, height: 1.5)),
          ],
          const SizedBox(height: 22),

          // ── 自社の現場紐付け（この画面では表示のみ・変更は一覧の行から）──
          _section('自社の現場'),
          _row('紐付け', _s(_r['link_site_name'])),
          const Text('※紐付けの設定・変更・解除は受信トレイの一覧から行います',
              style: TextStyle(color: FieldTokens.textFaint, fontSize: 11)),
          const SizedBox(height: 22),

          // ── 写真 ───────────────────────────────────────
          _section('写真'),
          if (_photoLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: FieldTokens.accent),
              ),
            )
          else if (_photoNote != null)
            Text(_photoNote!,
                style: const TextStyle(
                    color: FieldTokens.textSupport, fontSize: 12, height: 1.4))
          else ...[
            if (_sitePhotos.isNotEmpty) _strip('現場写真', _sitePhotos),
            if (_parkingPhotos.isNotEmpty) ...[
              const SizedBox(height: 12),
              _strip('駐車場写真', _parkingPhotos),
            ],
          ],
          const SizedBox(height: 26),

          // ── 束へ ───────────────────────────────────────
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _openBundle,
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('この束の全体を見る'),
              style: OutlinedButton.styleFrom(
                foregroundColor: FieldTokens.accent,
                side: const BorderSide(color: FieldTokens.accent),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 写真の帯（サムネ横並び＋タップで拡大）────────────────────────
  Widget _strip(String label, List<String> urls) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: FieldTokens.textSupport, fontSize: 12)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final u in urls) ...[
                  _thumb(u),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      );

  Widget _thumb(String url) => GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (dctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Stack(alignment: Alignment.topRight, children: [
              InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
              IconButton(
                onPressed: () => Navigator.of(dctx).pop(),
                icon: const Icon(Icons.close, color: FieldTokens.textBody),
              ),
            ]),
          ),
        ),
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
              color: FieldTokens.scrimWeak,
              alignment: Alignment.center,
              child: const Text('読込不可',
                  style: TextStyle(
                      color: FieldTokens.textSupport, fontSize: 10)),
            ),
          ),
        ),
      );

  // 体裁は tamper_incident_detail_screen.dart:400-424 と同型。
  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: const TextStyle(
                color: FieldTokens.textBody,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(
                    color: FieldTokens.textSupport, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 13)),
          ),
        ]),
      );
}

String _s(Object? v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? '-' : s;
}
