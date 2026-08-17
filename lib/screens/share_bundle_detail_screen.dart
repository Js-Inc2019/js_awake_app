// ============================================================
// lib/screens/share_bundle_detail_screen.dart — 束詳細（FIELD・受信/送信 共用）
//
// 導線: 受信した日報の閲覧（share_receipt_detail_screen）の「この束の全体を見る」／
//       送信済み一覧（share_outbox_screen）の行タップ。
//
// BE: GET /bundles/:bundle_id（BundlesService.getBundle）。
//   ・自分がどちら側かは応答の viewer_role（'sender' / 'receiver'）を信じる
//     ＝FE で会社IDを見比べて推測しない（routes/bundles.js:1143）。
//   ・item_status（'tampered' / 'updated' / 'ok'）と bundle_integrity
//     （'ok' / 'broken'）は BE が算出済み。FE でハッシュを再計算しない。
//   ・★★この GET には副作用がある: 受信側が開くと封筒に received_at が入り、
//     原本の書き換えが見つかれば改ざん事件が台帳化されて通知が飛ぶ
//     （routes/bundles.js:1076-1114・fail-open）。だから【開いた1件だけ】を叩く。
//     一覧の見た目を整えるための先読みは絶対にしない。
//
// 「確認しました」: POST /bundles/:bundle_id/confirm（受信社のみ・送信社は404）。
//   ★束単位・人単位の事実（share_bundle_acks.confirmed_at）で、日報1枚ごとの
//     既読とは別物。冪等（初回時刻を保つ）。
//   ★この GET の応答には「自分が確認済みか」が入っていない
//     （my_confirmed_at を返すのは GET /bundles/inbox のみ）。よってこの画面は
//     「未確認」と名乗らない＝知らないことを表示しない。押した結果の
//     confirmed_at だけを事実として出す。
// ============================================================

import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import '../services/bundles_service.dart';
import '../main.dart' show showJsSnackbar;
import 'share_inbox_screen.dart'
    show kShareManageDeniedMessage, fmtShareDate, fmtShareDateTime;

class ShareBundleDetailScreen extends StatefulWidget {
  const ShareBundleDetailScreen({
    super.key,
    required this.bundleId,
    required this.canManage,
  });

  final String bundleId;

  /// 処理鍵。「確認しました」を押せるかの入口判定に使う（最終門番は BE）。
  final bool canManage;

  @override
  State<ShareBundleDetailScreen> createState() =>
      _ShareBundleDetailScreenState();
}

class _ShareBundleDetailScreenState extends State<ShareBundleDetailScreen> {
  final BundlesService _svc = BundlesService();

  Map<String, dynamic>? _data;   // 応答全体（null＝未取得 or 失敗）
  bool _loading = true;
  bool _busy = false;            // 確認の送信中（連打を止める）
  String? _error;
  String? _confirmedAt;          // 押して成功した時刻（押す前は知らない＝null）

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final r = await _svc.getBundle(widget.bundleId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok && r.data != null) {
        _data = r.data;
        _error = null;
      } else {
        _data = null;
        _error = r.statusCode == 403
            ? (r.errorMessage ?? '共有を見る権限がありません')
            : r.statusCode == 404
                ? '束が見つかりません'
                : r.statusCode == 0
                    ? '通信できませんでした'
                    : (r.errorMessage ?? '束を取得できませんでした');
      }
    });
  }

  Future<void> _confirm() async {
    if (!widget.canManage) {
      showJsSnackbar(context, kShareManageDeniedMessage, isError: true);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final r = await _svc.confirmBundle(widget.bundleId);
    if (!mounted) return;
    setState(() => _busy = false);

    if (r.ok) {
      setState(() =>
          _confirmedAt = (r.data?['confirmed_at'] ?? '').toString());
      showJsSnackbar(context, '確認しました');
      return;
    }
    final String msg;
    if (r.statusCode == 403) {
      msg = r.errorMessage ?? kShareManageDeniedMessage;
    } else if (r.statusCode == 404) {
      // 送信社が押した場合もここ（BE は関係者以外と同じ 404 で返す）。
      msg = 'この束は自社宛ではないため確認できません';
    } else if (r.statusCode == 0) {
      msg = '通信できませんでした';
    } else {
      msg = r.errorMessage ?? '確認できませんでした';
    }
    showJsSnackbar(context, msg, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        title: const Text('束の全体'),
        actions: [
          IconButton(
            onPressed: (_loading || _busy) ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: FieldTokens.accent))
          : _data == null
              ? _errorView()
              : _content(_data!),
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
              Text(_error ?? '束を取得できませんでした',
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

  Widget _content(Map<String, dynamic> d) {
    final bundle = (d['bundle'] as Map?)?.cast<String, dynamic>() ?? const {};
    final items = (d['items'] as List?) ?? const [];
    final receivers = (d['receivers'] as List?) ?? const [];
    final isReceiver = d['viewer_role'] == 'receiver';
    final broken = d['bundle_integrity'] == 'broken';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 束の整合性が壊れているときは最初に言う ──────────────
        if (broken) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: FieldTokens.statusError.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FieldTokens.statusError, width: 1.2),
            ),
            child: const Row(children: [
              Icon(Icons.gpp_bad_outlined,
                  color: FieldTokens.statusError, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text('束全体の照合が一致しません。中身が送信時と同じであることを保証できません。',
                    style: TextStyle(
                        color: FieldTokens.textBody,
                        fontSize: 13,
                        height: 1.4)),
              ),
            ]),
          ),
          const SizedBox(height: 20),
        ],

        // ── 束 ─────────────────────────────────────────
        _section('束'),
        if (_s(bundle['title']) != '-') _row('件名', _s(bundle['title'])),
        _row('送信者', _s(bundle['sender_name'])),
        _row('送信日時', fmtShareDateTime(bundle['created_at'])),
        _row('日報の数', '${items.length}件'),
        _row('写真', bundle['include_photos'] == true ? '含む' : '含まない'),
        if (_s(bundle['memo']) != '-') ...[
          const SizedBox(height: 10),
          const Text('メモ',
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_s(bundle['memo']),
              style: const TextStyle(
                  color: FieldTokens.textBody, fontSize: 13, height: 1.5)),
        ],
        const SizedBox(height: 22),

        // ── 明細 ───────────────────────────────────────
        _section('入っている日報'),
        if (items.isEmpty)
          const Text('日報がありません',
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 13))
        else
          for (final it in items)
            if (it is Map) _itemCard(it.cast<String, dynamic>()),
        const SizedBox(height: 22),

        // ── 受信社ごとの状況（送信側の関心事）───────────────────
        //   ★受信側には出さない。受信社が知りたいのは「自社に何が届いたか」で、
        //     同じ束が他にどこへ届いたかは自社の業務判断に使わない
        //     （BE は両側へ同じ構造を返すが、出す/出さないは画面の裁量）。
        if (!isReceiver) ...[
          _section('送信先ごとの状況'),
          if (receivers.isEmpty)
            const Text('送信先がありません',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 13))
          else
            for (final rc in receivers)
              if (rc is Map) _receiverRow(rc.cast<String, dynamic>()),
          const SizedBox(height: 22),
        ],

        // ── 確認しました（受信社のみ）──────────────────────────
        if (isReceiver) ...[
          if (_confirmedAt != null && _confirmedAt!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: FieldTokens.statusSuccess.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: FieldTokens.statusSuccess),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    color: FieldTokens.statusSuccess, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('確認しました（${fmtShareDateTime(_confirmedAt)}）',
                      style: const TextStyle(
                          color: FieldTokens.statusSuccess,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
            )
          else
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _confirm,
                icon: const Icon(Icons.check, size: 18),
                label: Text(_busy ? '送信中…' : '確認しました'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FieldTokens.accent,
                  foregroundColor: FieldTokens.onAccent,
                  disabledBackgroundColor: FieldTokens.outlineStrong,
                  disabledForegroundColor: FieldTokens.textFaint,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ── 明細1件 ─────────────────────────────────────────────
  Widget _itemCard(Map<String, dynamic> it) {
    final status = (it['item_status'] ?? '').toString();
    final (c, label) = switch (status) {
      'tampered' => (FieldTokens.statusError, '改ざん'),
      'updated' => (FieldTokens.statusError, '原本変更'),
      _ => (FieldTokens.statusSuccess, '一致'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FieldTokens.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(fmtShareDate(it['report_date']),
                style: const TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(_s(it['worker_name']),
                    style: const TextStyle(
                        color: FieldTokens.textBody, fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: c, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            const Icon(Icons.place_outlined,
                size: 12, color: FieldTokens.textSupport),
            const SizedBox(width: 4),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(_s(it['site_name']),
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 12)),
              ),
            ),
          ]),
          if (_s(it['work_content']) != '-') ...[
            const SizedBox(height: 6),
            Text(_s(it['work_content']),
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 12, height: 1.4)),
          ],
        ],
      ),
    );
  }

  // ── 受信社1件（read_count は【枚数】・confirmed_count は【人数】）──────
  Widget _receiverRow(Map<String, dynamic> rc) {
    final read = rc['read_count'];
    final total = rc['report_count'];
    final confirmed = rc['confirmed_count'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FieldTokens.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.business,
                size: 13, color: FieldTokens.externalBlue),
            const SizedBox(width: 5),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(_s(rc['company_name']),
                    style: const TextStyle(
                        color: FieldTokens.externalBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('$total枚中$read枚読了 ／ 確認$confirmed人',
              style: const TextStyle(
                  color: FieldTokens.textBody, fontSize: 12)),
          const SizedBox(height: 3),
          Text('届いた日時 ${fmtShareDateTime(rc['received_at'])}',
              style: const TextStyle(
                  color: FieldTokens.textFaint, fontSize: 11)),
        ],
      ),
    );
  }

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
