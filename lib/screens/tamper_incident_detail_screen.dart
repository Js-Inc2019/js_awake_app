// lib/screens/tamper_incident_detail_screen.dart — 改ざん事件の詳細と対処（FIELD）
//
// 導線: お知らせ（GET /notifications）の type='tamper_detected' / 'tamper_status_changed'
//       の展開部ボタン、および FCM タップ（fcm_service.handleNotificationTap）から。
//       いずれも ref_id / data['incident_id'] が incident_id。
//
// BE: TamperService（GET /tamper/incidents/:id・PATCH /tamper/incidents/:id/status）。
//   遷移規則の真実源は BE:
//     open → investigating / open → resolved / investigating → resolved
//     resolved は終着（409 ALREADY_RESOLVED）。門番は admin_exec + can_audit（403）。
//   本画面は規則を持たず、返ってきた status でボタンを出し分けるだけ。
//
// 配色は FieldTokens（Asphalt Dawn）。状態は3語固定（未対応 / 調査中 / 解決済み）。
import 'package:flutter/material.dart';
import '../services/tamper_service.dart';
import '../core/theme/field_tokens.dart';
import '../main.dart' show showJsSnackbar;

// 状態→表示3語。この3語以外の言い方をしない。
const Map<String, String> _kStatusLabel = {
  'open': '未対応',
  'investigating': '調査中',
  'resolved': '解決済み',
};

Color _statusColor(String? status) {
  switch (status) {
    case 'open':          return FieldTokens.statusError;
    case 'investigating': return FieldTokens.statusWarning;
    case 'resolved':      return FieldTokens.statusSuccess;
    default:              return FieldTokens.textSupport;
  }
}

// 日時を JST「MM/DD HH:mm」へ整形（端末TZ=Asia/Tokyo前提）。
String _fmtJst(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(dt.month)}/${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
}

class TamperIncidentDetailScreen extends StatefulWidget {
  const TamperIncidentDetailScreen({super.key, required this.incidentId});
  final String incidentId;

  @override
  State<TamperIncidentDetailScreen> createState() =>
      _TamperIncidentDetailScreenState();
}

class _TamperIncidentDetailScreenState
    extends State<TamperIncidentDetailScreen> {
  final TamperService _svc = TamperService();

  Map<String, dynamic>? _incident; // null＝未取得 or 取得失敗
  bool _loading = true;
  bool _busy = false;              // 対処送信中（連打を止める）
  String? _error;                  // 取得失敗の理由を言い切る

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final r = await _svc.getIncidentDetail(widget.incidentId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok && r.data != null) {
        _incident = r.data;
        _error = null;
      } else {
        _incident = null;
        // 権限・不在・通信断を混ぜない（statusCode 0 は通信不成立の印）。
        _error = r.statusCode == 403
            ? '事件の閲覧には監査権限が必要です'
            : r.statusCode == 404
                ? '事件が見つかりません'
                : r.statusCode == 0
                    ? '通信できませんでした'
                    : (r.errorMessage ?? '詳細を取得できませんでした');
      }
    });
  }

  // ── 対処（状態遷移）──────────────────────────────────────
  Future<void> _changeStatus(String next) async {
    final note = await _askNote(next);
    // null＝送らない（キャンセル／バリア外タップ）。'' は「メモ無しで確定」なので送る。
    if (note == null) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final r = await _svc.updateIncidentStatus(
      widget.incidentId,
      status: next,
      resolutionNote: note.isEmpty ? null : note,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (r.ok) {
      Navigator.of(context).pop(true); // 呼び出し元が必要なら再読込する
      return;
    }
    // ★非200を成功風に見せない。statusCode + errorCode の組で言い切る（規約6）。
    final String msg;
    if (r.statusCode == 409 || r.errorCode == 'ALREADY_RESOLVED') {
      msg = 'すでに解決済みです';
    } else if (r.statusCode == 403) {
      msg = '監査権限が必要です';
    } else {
      msg = '更新できませんでした';
    }
    showJsSnackbar(context, msg, isError: true);
    // 409＝他の誰かが先に片付けた。最新状態へ引き直す。
    if (r.statusCode == 409) _load();
  }

  // 戻り値: null＝送らない（キャンセル／バリア外タップ）／文字列＝送る（'' はメモ無し確定）。
  Future<String?> _askNote(String next) async {
    final ctrl = TextEditingController();
    final isResolve = next == 'resolved';
    return showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        title: Text(isResolve ? '解決にする' : '調査を開始',
            style: const TextStyle(
                color: FieldTokens.textBody, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isResolve
                  ? '対応状況を「解決済み」に変更します。解決済みにすると以後は変更できません。'
                  : '対応状況を「調査中」に変更します。',
              style: const TextStyle(
                  color: FieldTokens.textSupport, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              maxLines: 4,
              minLines: 2,
              style: const TextStyle(color: FieldTokens.textBody),
              decoration: const InputDecoration(
                labelText: '対処メモ（任意）',
                labelStyle: TextStyle(color: FieldTokens.textSupport),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: FieldTokens.outline)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: FieldTokens.accent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(), // null＝送らない
            style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
            child: const Text('キャンセル',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dctx).pop(ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(112, 44),
              backgroundColor:
                  isResolve ? FieldTokens.statusSuccess : FieldTokens.accent,
              foregroundColor: FieldTokens.onAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(isResolve ? '解決にする' : '調査を開始'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        title: const Text('改ざんの詳細'),
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
          : _incident == null
              ? _errorView()
              : _content(_incident!),
    );
  }

  // 取得失敗は袋小路にしない（理由＋再試行）。
  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: FieldTokens.statusError),
              const SizedBox(height: 16),
              Text(_error ?? '詳細を取得できませんでした',
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

  Widget _content(Map<String, dynamic> inc) {
    final status = inc['status'] as String?;
    final c = _statusColor(status);
    final isBundle = inc['target_type'] == 'bundle';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 状態バッジ（大）────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c, width: 1.2),
          ),
          child: Row(children: [
            Icon(
              status == 'resolved'
                  ? Icons.check_circle_outline
                  : status == 'investigating'
                      ? Icons.search
                      : Icons.error_outline,
              color: c, size: 24,
            ),
            const SizedBox(width: 12),
            Text(_kStatusLabel[status] ?? '不明',
                style: TextStyle(
                    color: c, fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 24),

        // ── 対象日報 ──────────────────────────────────────
        _section('対象日報'),
        _row('日付', (inc['report_date'] ?? '-').toString()),
        _row('職人', _s(inc['worker_name'])),
        _row('現場', _s(inc['site_name'])),
        if (_s(inc['work_content']) != '-') ...[
          const SizedBox(height: 8),
          const Text('作業内容',
              style:
                  TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_s(inc['work_content']),
              style: const TextStyle(
                  color: FieldTokens.textBody, fontSize: 13, height: 1.4)),
        ],
        if (_s(inc['gps_address']) != '-') _row('報告場所', _s(inc['gps_address'])),
        const SizedBox(height: 24),

        // ── 共有の種別 ────────────────────────────────────
        _section('共有の種別'),
        _row('種別', isBundle ? 'まとめ共有' : '単発共有'),
        _row('送信社', _s(inc['sender_company_name'])),
        if (isBundle)
          _row('まとめ名', _s(inc['bundle_title']))
        else
          _row('受信社', _s(inc['receiver_company_name'])),
        const SizedBox(height: 24),

        // ── 検知情報 ──────────────────────────────────────
        _section('検知情報'),
        _row('検知日時', _fmtJst(inc['detected_at'] as String?)),
        _row('検知者', _s(inc['detected_by_name'])),
        _row('検知方法',
            inc['detected_via'] == 'bundle_view' ? '閲覧時の自動検知' : '手動チェック'),
        const SizedBox(height: 8),
        _hashRow('共有時のハッシュ', inc['hash_before'] as String?),
        _hashRow('現在のハッシュ', inc['hash_after'] as String?),
        const SizedBox(height: 8),
        const Text('※ ハッシュは先頭12文字のみ表示しています。',
            style: TextStyle(color: FieldTokens.textFaint, fontSize: 11)),
        const SizedBox(height: 24),

        // ── 対処記録（解決済みのときだけ）──────────────────
        if (status == 'resolved') ...[
          _section('対処記録'),
          _row('対応者', _s(inc['resolved_by_name'])),
          _row('対応日時', _fmtJst(inc['resolved_at'] as String?)),
          const SizedBox(height: 8),
          const Text('対処メモ',
              style:
                  TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_s(inc['resolution_note']),
              style: const TextStyle(
                  color: FieldTokens.textBody, fontSize: 13, height: 1.4)),
          const SizedBox(height: 24),
        ],

        // ── 対処操作（status で出し分け）────────────────────
        ..._actions(status),
        const SizedBox(height: 32),
      ],
    );
  }

  List<Widget> _actions(String? status) {
    if (status == 'resolved') {
      return const [
        Text('※ 解決済みの事案は変更できません。',
            style: TextStyle(color: FieldTokens.textFaint, fontSize: 12)),
      ];
    }
    final out = <Widget>[];
    if (status == 'open') {
      out.add(SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          onPressed: _busy ? null : () => _changeStatus('investigating'),
          style: OutlinedButton.styleFrom(
            foregroundColor: FieldTokens.statusWarning,
            side: const BorderSide(color: FieldTokens.statusWarning),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('調査を開始',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ));
      out.add(const SizedBox(height: 16));
    }
    out.add(SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _busy ? null : () => _changeStatus('resolved'),
        style: ElevatedButton.styleFrom(
          backgroundColor: FieldTokens.statusSuccess,
          foregroundColor: FieldTokens.onAccent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: const Text('解決にする',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    ));
    out.add(const SizedBox(height: 8));
    out.add(const Text('※ 解決済みにすると以後は変更できません。',
        style: TextStyle(color: FieldTokens.textFaint, fontSize: 11)));
    return out;
  }

  // ── 部品 ──────────────────────────────────────────────
  static String _s(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? '-' : s;
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

  Widget _hashRow(String label, String? hash) {
    final h = (hash ?? '').trim();
    final shown =
        h.length > 12 ? '${h.substring(0, 12)}…' : (h.isEmpty ? '-' : h);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: const TextStyle(
                  color: FieldTokens.textSupport, fontSize: 12)),
        ),
        Expanded(
          child: Text(shown,
              style: const TextStyle(
                color: FieldTokens.textBody,
                fontSize: 13,
                fontFamily: 'monospace',
              )),
        ),
      ]),
    );
  }
}
