// ============================================================
// lib/screens/share_outbox_screen.dart — 送信済み（FIELD）
//
// 導線: 共有タブ（share_hub_screen.dart）の「送信済み」タイル。
//
// BE: GET /bundles/outbox（BundlesService.getOutbox）。
//   ・スコープは sender_company_id = 自社。並びは created_at DESC（BE 確定・
//     routes/bundles.js:653）なので FE で並べ替え直さない。
//   ・門番は【見る門番】blockShareViewer（:620）。旧 blockOutboxViewer
//     （can_share_send OR 役職）は段階3で退役＝送る鍵が無くても送信履歴は見える。
//   ・1件 = {bundle_id, title, initial_axis, include_photos, bundle_hash,
//            created_at, report_count, receivers:[...]}（:625-650）
//     receivers[] = {receiver_company_id, company_name, bundle_status,
//                    received_at, read_count, report_count, confirmed_count}
//     ★read_count / report_count は【枚数】（受信社宛の受信明細を数える）。
//       confirmed_count だけ【人数】（acks・確認は既読と別の事実）。
//       この画面はその区別を文言でも保つ＝「n枚中m枚読了」「確認n人」。
//     ★受信社側の report_count（受信明細の行数）と束の report_count
//       （束に入っている日報の総数）は別の事実。行の見出しは束側、
//       会社ごとの行は受信社側を使う。
//
// ★行タップで束詳細（GET /bundles/:bundle_id）へ。先読みはしない
//   （受信側で開くと副作用があるエンドポイントなので、開いた1件だけを叩く流儀を
//     送信側でも崩さない）。
// ============================================================

import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import '../services/bundles_service.dart';
import 'share_bundle_detail_screen.dart';
import 'share_inbox_screen.dart' show fmtShareDateTime;

class ShareOutboxScreen extends StatefulWidget {
  const ShareOutboxScreen({super.key});

  @override
  State<ShareOutboxScreen> createState() => _ShareOutboxScreenState();
}

class _ShareOutboxScreenState extends State<ShareOutboxScreen> {
  final BundlesService _svc = BundlesService();

  List<Map<String, dynamic>> _bundles = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final r = await _svc.getOutbox();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _bundles = r.data ?? const [];
        _error = null;
      } else {
        _bundles = const [];
        _error = r.statusCode == 403
            ? (r.errorMessage ?? '共有を見る権限がありません')
            : r.statusCode == 0
                ? '通信できませんでした'
                : (r.errorMessage ?? '送信済みを取得できませんでした');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        title: const Text('送信済み'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: FieldTokens.accent))
          : _error != null
              ? _errorView()
              : _list(),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: FieldTokens.statusError),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 15)),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('再試行'),
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
        ),
      );

  Widget _list() {
    if (_bundles.isEmpty) {
      return RefreshIndicator(
        color: FieldTokens.accent,
        backgroundColor: FieldTokens.surfaceCard,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 320,
              child: Center(
                child: Text('送信した束はありません',
                    style: TextStyle(
                        color: FieldTokens.textSupport, fontSize: 14)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: FieldTokens.accent,
      backgroundColor: FieldTokens.surfaceCard,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        itemCount: _bundles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _OutboxCard(
          bundle: _bundles[i],
          onTap: () async {
            final id = (_bundles[i]['bundle_id'] ?? '').toString();
            if (id.isEmpty) return;
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  ShareBundleDetailScreen(bundleId: id, canManage: false),
            ));
            // 戻ったら読了数が動いている可能性があるので取り直す。
            // ★canManage:false を渡すのは送信側からの入口だから。送信社は
            //   POST /confirm を叩けない（BE は 404 で返す）ので、押せる形にしない。
            if (mounted) _load();
          },
        ),
      ),
    );
  }
}

// ─── 束1件（送信側の見え方）────────────────────────────────
class _OutboxCard extends StatelessWidget {
  const _OutboxCard({required this.bundle, required this.onTap});

  final Map<String, dynamic> bundle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final receivers = (bundle['receivers'] as List?) ?? const [];
    final reportCount = bundle['report_count'];
    final title = (bundle['title'] ?? '').toString().trim();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FieldTokens.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1段目: 送信日時 ＋ 日報の数
            Row(children: [
              const Icon(Icons.schedule,
                  size: 13, color: FieldTokens.textSupport),
              const SizedBox(width: 5),
              Text(fmtShareDateTime(bundle['created_at']),
                  style: const TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('日報$reportCount件',
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  size: 18, color: FieldTokens.textSupport),
            ]),
            // 2段目: 件名（付いていれば）
            if (title.isNotEmpty) ...[
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: const TextStyle(
                        color: FieldTokens.brand, fontSize: 13)),
              ),
            ],
            // 3段目〜: 送信先ごとの状況
            const SizedBox(height: 8),
            if (receivers.isEmpty)
              const Text('送信先がありません',
                  style: TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12))
            else
              for (final rc in receivers)
                if (rc is Map) _receiverLine(rc.cast<String, dynamic>()),
          ],
        ),
      ),
    );
  }

  // 「n枚中m枚読了 ／ 確認k人」。枚数と人数の別を文言で崩さない。
  Widget _receiverLine(Map<String, dynamic> rc) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          const Icon(Icons.business, size: 12, color: FieldTokens.externalBlue),
          const SizedBox(width: 5),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                (rc['company_name'] ?? '-').toString(),
                style: const TextStyle(
                    color: FieldTokens.externalBlue, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${rc['report_count']}枚中${rc['read_count']}枚読了 ／ 確認${rc['confirmed_count']}人',
            style: const TextStyle(color: FieldTokens.textBody, fontSize: 11),
          ),
        ]),
      );
}
