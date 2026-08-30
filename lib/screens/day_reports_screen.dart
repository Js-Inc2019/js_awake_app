// lib/screens/day_reports_screen.dart
import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import '../services/reports_service.dart';
import 'monthly_history_screen.dart' show JsReportTile;

class DayReportsScreen extends StatefulWidget {
  const DayReportsScreen({
    super.key,
    required this.date,
    required this.reports,
    required this.myCompanyId,
  });
  final DateTime date;
  final List<Map<String, dynamic>> reports;
  final String myCompanyId;

  @override
  State<DayReportsScreen> createState() => _DayReportsScreenState();
}

class _DayReportsScreenState extends State<DayReportsScreen> {
  bool _isWorkerView = false;

  // ── 取消の状態 ────────────────────────────────────────────────
  // ★取消済かどうかを report['status'] に書き戻さない。理由:
  //   この画面へ届く行の status は BE の reports.status ではなく、親が承認状態から
  //   作り直した3値（approved / rejected / pending）である
  //   （monthly_history_screen.dart の _load、home_screen.dart の _loadReports が
  //     どちらも `'status': approved ? 'approved' : revision ? 'rejected' : 'pending'`
  //     で上書きしている）。そして JsReportTile はその3値でバッジを描き、
  //   既定の分岐は「未承認」（monthly_history_screen.dart の JsReportTile の switch）。
  //   ここに 'cancelled' を書き込むと既定分岐に落ちて【取消済の日報が「未承認」と
  //   表示される】＝嘘になる。よって取消済は別の入れ物で持ち、この画面が自分で描く。
  // ★キーは report_id（BE の LIST_COLS が必ず載せる列）。
  final Set<String> _cancelledIds = <String>{};

  // 二重送信ガード。取消は勤怠の記録まで戻す操作なので、連打で2回投げない。
  bool _busy = false;

  // この画面で1件でも取り消したか。閉じるときに親へ返す（親が一覧を取り直す合図）。
  bool _didCancel = false;

  String _ridOf(Map<String, dynamic> r) =>
      (r['report_id'] ?? r['id'] ?? '').toString();

  // 日報の取消。PATCH /reports/:report_id/cancel。
  //
  // ★確認の文面は日常語で、実際に起きること3つを必ず書く（BE の実装が根拠）:
  //   ・勤怠の記録も戻る … routes/reports.js の巻き戻しブロックが report_flag と
  //     source='deemed' の deemed 列を解除する
  //   ・実際に打刻した時刻は残る … 同ブロックが「punch_in / punch_out /
  //     punch_*_lat/lng/addr（実打刻）には絶対に触れない」と明記
  //   ・日報の行は消えない … `UPDATE reports SET status = 'cancelled'` だけで、
  //     DELETE はしない
  Future<void> _cancelReport(Map<String, dynamic> r) async {
    final reportId = _ridOf(r);
    if (reportId.isEmpty || _busy) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        title: const Text('この日報を取り消しますか',
            style: TextStyle(color: FieldTokens.statusError, fontSize: 17)),
        content: const Text(
          '取り消すと、この日報から書かれた勤怠の記録（出面と、みなし勤務の時刻）も'
          '一緒に戻ります。\n\n'
          '実際に打刻した出勤・退勤の時刻はそのまま残ります。\n\n'
          '日報そのものは消えません。取消済として残ります。',
          style: TextStyle(color: FieldTokens.textBody, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('やめる',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: FieldTokens.statusError,
                foregroundColor: Colors.white),
            child: const Text('取り消す'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    // 理由は集めない。この画面に理由の入力欄が無く、BE 側で reason は任意のため
    // 送らない＝「書かなかった」を正しく伝える（空文字を送ると区別が消える）。
    final res = await ReportsService().cancelReport(reportId);
    if (!mounted) return;

    if (!res.ok) {
      setState(() => _busy = false);
      // ★BE の文言をそのまま出す。握り潰さない・言い換えない。
      //   ALREADY_CANCELLED / BOSS_CANNOT_CANCEL / APPROVED_ADMIN_ONLY /
      //   FORBIDDEN / 404 のどれであっても BE は人が読める日本語で答えている
      //   （api_result.dart の規約2 が errorMessage へそのまま載せている）。
      //   「取り消せませんでした」へ丸めると、なぜ駄目で次に誰へ頼めばよいかが消える。
      final msg = res.errorMessage?.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg == null || msg.isEmpty ? '取り消せませんでした' : msg),
          backgroundColor: FieldTokens.statusError,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    // ★成功後は「その日報だけ」を単体で取り直す。既存の口 getReportDetail
    //   （GET /reports/:report_id）を使う＝新しい取得の口を作らない。
    //   親の取得条件（月範囲・締め日・会社スコープ）はこの画面に渡っていないので、
    //   ここで一覧を取り直そうとすると条件を推測することになる。それはしない。
    // ★取り直した本体の status（BE の生の値）だけを見る。行そのものは
    //   書き換えない（上の _cancelledIds のコメントの理由）。
    // ★取り直しに失敗しても取消は成立している。その場合は「取り消した」という
    //   こちらの事実を採って取消済にする（成功したのに画面が変わらない方が嘘）。
    final detail = await ReportsService().getReportDetail(reportId);
    if (!mounted) return;
    final fresh = detail.ok ? detail.data?.report : null;
    final freshStatus =
        (fresh is Map) ? fresh['status']?.toString() : null;

    setState(() {
      _busy = false;
      _didCancel = true;
      if (freshStatus == null || freshStatus == 'cancelled') {
        _cancelledIds.add(reportId);
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('日報を取り消しました'),
        backgroundColor: FieldTokens.statusSuccess,
      ),
    );
  }

  // 1件ぶんの取消の導線。JsReportTile の直下に置く。
  //
  // ★出す条件は状態だけ。役割（職長かどうか）や承認済みかどうかでは出し分けない。
  //   取り消せるかを決めるのは BE の門番ただ一つで、FE が同じ判定を持つと必ず
  //   食い違う。とくに 403 でボタンを消さない＝押せば BE が理由を人の言葉で
  //   答えてくれる道を塞がない。
  // ★取消済のときだけボタンを引っ込めて「取消済」と出す。これは権限ではなく状態で、
  //   もう一度押しても BE が「既に取消済みです」と返すだけの空押しになるため。
  Widget _cancelRow(Map<String, dynamic> r) {
    final cancelled = _cancelledIds.contains(_ridOf(r));
    return Padding(
      padding: const EdgeInsets.only(right: 10, bottom: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: cancelled
            ? const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cancel_outlined,
                    color: FieldTokens.textSupport, size: 13),
                SizedBox(width: 4),
                Text('取消済（日報は残ります）',
                    style: TextStyle(
                        color: FieldTokens.textSupport, fontSize: 11)),
              ])
            : TextButton.icon(
                onPressed: _busy ? null : () => _cancelReport(r),
                icon: const Icon(Icons.cancel_outlined, size: 14),
                label: const Text('取り消す', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: FieldTokens.statusError,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupBySite(
      List<Map<String, dynamic>> reps) {
    final Map<String, List<Map<String, dynamic>>> g = {};
    for (final r in reps) {
      final key = (r['site_id'] as String?) ??
          (r['gps_address'] as String?) ??
          '住所未取得';
      g.putIfAbsent(key, () => []).add(r);
    }
    return g;
  }

  Map<String, List<Map<String, dynamic>>> _groupByWorker(
      List<Map<String, dynamic>> reps) {
    final Map<String, List<Map<String, dynamic>>> g = {};
    for (final r in reps) {
      final key = r['user_id'] as String? ??
          r['worker_name'] as String? ?? '不明';
      g.putIfAbsent(key, () => []).add(r);
    }
    return g;
  }

  Map<String, List<Map<String, dynamic>>> _groupByCompany(
      List<Map<String, dynamic>> reps) {
    final Map<String, List<Map<String, dynamic>>> g = {};
    for (final r in reps) {
      final key = r['company_id'] as String? ?? '不明';
      g.putIfAbsent(key, () => []).add(r);
    }
    return g;
  }

  String _siteLabel(List<Map<String, dynamic>> reps) {
    final r = reps.first;
    final name = r['site_name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    final addr = r['gps_address'] as String?;
    if (addr != null && addr.isNotEmpty) return addr;
    return '住所未取得';
  }

  String _workerLabel(List<Map<String, dynamic>> reps) =>
      reps.first['worker_name'] as String? ?? '不明';

  String _companyLabel(List<Map<String, dynamic>> reps) =>
      reps.first['worker_company'] as String? ?? '協力会社';

  int _sumParkingFee(List<Map<String, dynamic>> reps) {
    double total = 0;
    for (final r in reps) {
      final raw = r['parking_fee'];
      if (raw != null) {
        total += double.tryParse(raw.toString()) ?? 0;
      }
    }
    return total.toInt();
  }

  Widget _parkingChip(Map<String, dynamic> r) {
    final raw = r['parking_fee'];
    if (raw == null) return const SizedBox.shrink();
    final fee = (double.tryParse(raw.toString()) ?? 0).toInt();
    if (fee <= 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 10, bottom: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: FieldTokens.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: FieldTokens.accent.withValues(alpha: 0.5), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_parking, color: FieldTokens.accent, size: 9),
              const SizedBox(width: 2),
              Text('¥$fee',
                  style: const TextStyle(color: FieldTokens.accent, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feeFooter(int fee, {String prefix = '計'}) => Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 10, bottom: 8),
          child: Text('$prefix ¥$fee',
              style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
        ),
      );

  List<Widget> _buildOwnItems(List<Map<String, dynamic>> reps) {
    final items = <Widget>[];
    final grouped =
        _isWorkerView ? _groupByWorker(reps) : _groupBySite(reps);
    for (final entry in grouped.entries) {
      final label = _isWorkerView
          ? _workerLabel(entry.value)
          : _siteLabel(entry.value);
      final icon =
          _isWorkerView ? Icons.person_outline : Icons.location_on;
      final fee = _sumParkingFee(entry.value);
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, color: FieldTokens.accent, size: 13),
          const SizedBox(width: 4),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: FieldTokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text('${entry.value.length}件',
              style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
        ]),
      ));
      for (final r in entry.value) {
        items.add(JsReportTile(report: r, myCompanyId: widget.myCompanyId));
        items.add(_parkingChip(r));
        items.add(_cancelRow(r));
      }
      if (fee > 0) {
        items.add(_feeFooter(fee));
      }
    }
    return items;
  }

  List<Widget> _buildCoopItems(List<Map<String, dynamic>> reps) {
    final items = <Widget>[];
    final byCompany = _groupByCompany(reps);
    for (final entry in byCompany.entries) {
      final compReps = entry.value;
      final companyName = _companyLabel(compReps);
      final workerCount =
          compReps.map((r) => r['user_id']).toSet().length;
      final fee = _sumParkingFee(compReps);
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const Icon(Icons.business_outlined,
              color: FieldTokens.externalBlue, size: 13),
          const SizedBox(width: 4),
          Expanded(
            child: Text(companyName,
                style: const TextStyle(
                    color: FieldTokens.externalBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text('${compReps.length}件',
              style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
          if (fee > 0) ...[
            const SizedBox(width: 8),
            Text('¥$fee',
                style: const TextStyle(
                    color: FieldTokens.externalBlue, fontSize: 11)),
          ],
        ]),
      ));
      for (final r in compReps) {
        items.add(JsReportTile(report: r, myCompanyId: widget.myCompanyId));
        // ★協力業者の行にも同じ導線を出す。会社の境界で出し分けない。
        //   理由: 会社の境界を判定できるのは BE だけで（他社の日報は 404
        //   「日報が見つかりません」を返す）、しかも myCompanyId は
        //   monthly_history_screen からの遷移では空文字で渡る＝FE 側に
        //   「自社かどうか」の確かな材料が無い。ここで自前の判定を作ると、
        //   どの画面から来たかで出たり出なかったりする不安定な導線になる。
        items.add(_cancelRow(r));
      }
      if (workerCount > 1 && fee > 0) {
        items.add(_feeFooter(fee, prefix: '$companyName 計'));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.date;
    // ★戻るときに「取り消したかどうか」を親へ返す。
    //   この画面の一覧は親から受け取ったコピーで、親（monthly_history_screen /
    //   home_screen）は自分の取得条件（月・締め日）で一覧を持っている。取消を
    //   反映するのは親の仕事なので、こちらは合図だけ返す＝新しい取得の口を作らない。
    //   形は approval_day_screen.dart の PopScope（戻り時に必ず結果を投げる）を写した。
    //   ★あちらは常に true を返すが、こちらは _didCancel を返す。取り消していない
    //     ときまで親に取り直させると、見ただけで毎回通信が走る。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _didCancel);
      },
      child: Scaffold(
        backgroundColor: FieldTokens.bgBase,
        appBar: AppBar(
          backgroundColor: FieldTokens.bgBase,
          iconTheme: const IconThemeData(color: FieldTokens.brand),
          title: Text(
            '${d.month}月${d.day}日の日報',
            style: const TextStyle(
                color: FieldTokens.brand,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final reports = widget.reports;
    if (reports.isEmpty) {
      return const Center(
        child: Text('この日の日報はありません',
            style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
      );
    }

    final myId = widget.myCompanyId;
    final ownReps = myId.isEmpty
        ? reports
        : reports.where((r) => r['company_id'] == myId).toList();
    final coopReps = myId.isEmpty
        ? <Map<String, dynamic>>[]
        : reports.where((r) => r['company_id'] != myId).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      children: [
        // ── ヘッダー行 + 現場/人 トグル ──
        Row(children: [
          Expanded(
            child: Text(
              '${reports.length}件',
              style: const TextStyle(
                  color: FieldTokens.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _isWorkerView = !_isWorkerView),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: FieldTokens.accent),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isWorkerView
                        ? Icons.person_outline
                        : Icons.location_on,
                    color: FieldTokens.accent,
                    size: 13,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _isWorkerView ? '人別' : '現場別',
                    style: const TextStyle(
                        color: FieldTokens.accent, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // ── 自社ブロック ──
        if (ownReps.isNotEmpty) ..._buildOwnItems(ownReps),
        // ── 区切り（自社＋協力両方あり） ──
        if (ownReps.isNotEmpty && coopReps.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(child: Divider(color: FieldTokens.outline)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('協力業者',
                    style: TextStyle(
                        color: FieldTokens.textSupport, fontSize: 11)),
              ),
              Expanded(child: Divider(color: FieldTokens.outline)),
            ]),
          ),
        // ── 協力ブロック ──
        if (coopReps.isNotEmpty) ..._buildCoopItems(coopReps),
      ],
    );
  }
}
