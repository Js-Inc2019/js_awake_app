// lib/screens/monthly_history_screen.dart — 月間履歴画面
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/field_tokens.dart';
import '../services/reports_service.dart';
import '../widgets/closing_period_dialog.dart';
import 'day_reports_screen.dart' show DayReportsScreen;
import 'revision_inbox_screen.dart';
// 作業3: 移動手段の複数対応。transport_types_json 優先 → 無ければ transport_type に
// フォールバックする読み方は revision_parser に実装済みのものを再利用する（新設しない）。
import '../utils/revision_parser.dart' show transportNamesOf;
// 取消済の判定と4状態の決定は lib/utils/report_cancel_gate.dart の1本だけを使う。
// この画面に判定式を手書きしない（同じ式を3画面に書いていたことが取消済消失の原因）。
import '../utils/report_cancel_gate.dart'
    show isCancelledReport, reportStatusOf, withReportStatus;
// 状態→色・語も1本だけを使う。この画面に switch を手書きしない
// （同じ switch が3箇所にあり、未承認の色が箇所によって違っていた）。
import '../utils/report_status_style.dart' show reportStatusStyleForState;

// ─────────────────────────────────────────────
// MonthlyHistoryBody — Scaffold なし（Shell の IndexedStack で使用）
// ─────────────────────────────────────────────
class MonthlyHistoryBody extends StatefulWidget {
  const MonthlyHistoryBody({super.key, this.onHome});
  final VoidCallback? onHome;
  @override
  State<MonthlyHistoryBody> createState() => _MonthlyHistoryBodyState();
}

class _MonthlyHistoryBodyState extends State<MonthlyHistoryBody> {
  bool _loading = true;
  List<Map<String, dynamic>> _reports = [];
  DateTime _selectedMonth = DateTime.now();
  String? _error;

  // 締め日を変えた月の「どちらの期間か」を人に選ばせる受け皿。
  //   ★_error とは別に持つ。_error は人が画面の中では直せない事情、
  //     こちらは選べば直る事情＝混ぜると次の道が消える。
  final ClosingPeriodGate _closing = ClosingPeriodGate();

  // null = 全件, 'approved' / 'rejected' / 'pending' = 絞り込み中
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _closing.beginRound();
    setState(() { _loading = true; _error = null; });
    try {
      final m = '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';
      final res = await _closing.send(
        months: [m],
        run: (dates) => ReportsService()
            .getReportsByMonth(m, limit: 200, closingDates: dates),
      );
      if (!mounted) return;
      // 締め日が決まっていない＝「この月の記録はありません」と嘘をつかず、理由と選ぶ道を出す。
      if (_closing.isPending) {
        setState(() { _loading = false; _reports = []; _error = null; });
        return;
      }
      if (res.ok) {
        final raw = List<Map<String, dynamic>>.from(res.data ?? const []);
        // approved/revision_requested/status → 画面の4状態に変換。
        // ★式は report_cancel_gate.dart の1本だけ。ここに書き戻さない。
        //   旧実装はこの場で approved/revision の2値だけを見て status を作り直しており、
        //   BE が載せてきた 'cancelled'（LIST_COLS の r.status）をその場で捨てていた。
        setState(() {
          _reports = raw.map(withReportStatus).toList();
          _loading = false;
        });
      } else if (res.statusCode == 401) {
        // トークン切れ・無効 → ログアウトして再ログイン
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('auth_token');
        await prefs.setBool('logged_out', true);
        if (mounted) {
          setState(() { _loading = false; _error = '認証の有効期限が切れました。再ログインしてください。'; });
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        }
      } else if (res.statusCode == 0) {
        // 通信不成立＝移設前の catch 相当。
        setState(() { _loading = false; _error = 'ネットワークエラー'; });
      } else {
        setState(() {
          _loading = false;
          _error = 'データの取得に失敗しました。\nしばらく経ってから再試行してください。';
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'ネットワークエラー'; });
    }
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      _filterStatus = null;
    });
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year && _selectedMonth.month == now.month) return;
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      _filterStatus = null;
    });
    _load();
  }

  void _toggleFilter(String? status) {
    setState(() => _filterStatus = (_filterStatus == status) ? null : status);
  }

  @override
  Widget build(BuildContext context) {
    // ★件数は4状態を1つずつ数える。旧実装の pending は
    //   「合計 − 承認 − 差戻」の引き算だったため、取消済が画面へ届くように
    //   なった今そのままにすると、取消済がまるごと未承認に足し込まれる。
    // ★合計は「生きている日報」＝承認＋差戻＋未承認。取消済は混ぜず別に数える
    //   （取消済を合計に入れると、4つの数字が合計と合わなくなる）。
    final approved  = _reports.where((r) => r['status'] == 'approved').length;
    final rejected  = _reports.where((r) => r['status'] == 'rejected').length;
    final pending   = _reports.where((r) => r['status'] == 'pending').length;
    final cancelled = _reports.where(isCancelledReport).length;
    final total     = approved + rejected + pending;
    final now      = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    // ★絞り込みなし（合計）のときは取消済を出さない。
    //   「今日やる仕事」ではないこの画面でも、取消済は承認待ちや差戻しと
    //   同じ並びに混ざると取り違えるため、見るときは取消チップで選んで出す。
    //   ＝取消済だけが並ぶ一覧と、生きている日報の一覧が必ず別になる。
    final displayed = _filterStatus == null
        ? _reports.where((r) => !isCancelledReport(r)).toList()
        : _reports.where((r) => r['status'] == _filterStatus).toList();

    // 日付グループ化（絞る→畳む）新しい順
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final r in displayed) {
      final key = r['report_date'] as String? ?? '';
      grouped.putIfAbsent(key, () => []).add(r);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        // 月選択バー
        Container(
          color: FieldTokens.surfaceCard,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: FieldTokens.accent),
                onPressed: _prevMonth,
              ),
              Text(
                '${_selectedMonth.year}年${_selectedMonth.month}月',
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth ? FieldTokens.outline : FieldTokens.accent),
                onPressed: isCurrentMonth ? null : _nextMonth,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: FieldTokens.textSupport, size: 20),
                onPressed: _load,
                tooltip: '再読み込み',
              ),
            ],
          ),
        ),
        // 集計バー
        if (!_loading && _error == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            // ★状態を持つ4枚の色は対応表から採る（手書きのトークン名を置かない）。
            //   ここが手書きだったせいで、未承認がチップでは橙・日報1行では
            //   温グレーという食い違いが生まれていた。語は短い形のまま変えない
            //   （'承認' '差戻' '取消' はチップだけの語で、バッジの
            //     '承認済' '差戻し' '取消済' とは別の文字列）。
            //   '合計' は状態ではないので対応表に載せず textSupport のまま。
            child: Row(children: [
              JsStatChip('合計', total, FieldTokens.textSupport,
                  selected: _filterStatus == null,
                  onTap: () => setState(() => _filterStatus = null)),
              const SizedBox(width: 8),
              JsStatChip('承認', approved,
                  reportStatusStyleForState('approved').color,
                  selected: _filterStatus == 'approved',
                  onTap: () => _toggleFilter('approved')),
              const SizedBox(width: 8),
              JsStatChip('差戻', rejected,
                  reportStatusStyleForState('rejected').color,
                  selected: _filterStatus == 'rejected',
                  onTap: () => _toggleFilter('rejected')),
              const SizedBox(width: 8),
              JsStatChip('未承認', pending,
                  reportStatusStyleForState('pending').color,
                  selected: _filterStatus == 'pending',
                  onTap: () => _toggleFilter('pending')),
              const SizedBox(width: 8),
              // ★取消済を見る道。置き方は「同じ画面の中で切り替える」＝この行の
              //   既存の絞り込みチップ（合計/承認/差戻/未承認 と _filterStatus）を
              //   そのまま使う。根拠: このアプリで一覧を分けている作りは2つあり、
              //     ・TabBar/TabBarView … 別々の画面を束ねる器
              //       (management_history_screen.dart の _labels と views、
              //        home_screen.dart の ForemanManagementBody)
              //     ・JsStatChip + _filterStatus … 1つの一覧を状態で分ける
              //       (この画面の _toggleFilter と displayed の where)
              //   今回分けたいのは「同じ月の同じ一覧を状態で分ける」なので後者。
              //   新しい画面もタブも部品も色も増やしていない（増えたのはチップ1枚）。
              JsStatChip('取消', cancelled,
                  reportStatusStyleForState('cancelled').color,
                  selected: _filterStatus == 'cancelled',
                  onTap: () => _toggleFilter('cancelled')),
            ]),
          ),
        // リスト
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: FieldTokens.accent))
              // 締め日の変更で期間が2つある月。理由を出し、押されたときだけ選ばせる。
              : _closing.isPending
                  ? ClosingPeriodNotice(gate: _closing, onResolved: _load)
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: FieldTokens.statusError)))
                  : _reports.isEmpty
                      ? const Center(
                          child: Text('この月の記録はありません',
                              style: TextStyle(color: FieldTokens.textSupport)))
                      : displayed.isEmpty
                          ? const Center(
                              child: Text('該当する記録はありません',
                                  style: TextStyle(color: FieldTokens.textSupport)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              itemCount: sortedDates.length,
                              itemBuilder: (ctx, i) {
                                final dateStr = sortedDates[i];
                                final reps    = grouped[dateStr]!;
                                final parts   = dateStr.split('-');
                                final date    = parts.length == 3
                                    ? DateTime(
                                        int.tryParse(parts[0]) ?? 0,
                                        int.tryParse(parts[1]) ?? 0,
                                        int.tryParse(parts[2]) ?? 0)
                                    : DateTime.now();
                                return _DateRow(
                                  dateStr: dateStr,
                                  date:    date,
                                  reports: reps,
                                  // ★戻り値を待つ。DayReportsScreen で日報を取り消すと
                                  //   true が返る。手元の _reports は取消前のままなので、
                                  //   既存の _load() をそのまま呼び直して取り直す
                                  //   （新しい取得の口は作らない＝締め日の解決も
                                  //     _load の中の _closing.send が今までどおり通る）。
                                  //   true 以外（見ただけで戻った・null）では何もしない。
                                  onTap:   () async {
                                    final changed = await Navigator.push<bool>(
                                      ctx,
                                      MaterialPageRoute(
                                        builder: (_) => DayReportsScreen(
                                          date:        date,
                                          reports:     reps,
                                          myCompanyId: '',
                                        ),
                                      ),
                                    );
                                    if (changed == true && mounted) _load();
                                  },
                                );
                              },
                            ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// MonthlyHistoryScreen — 単体プッシュ用（Scaffold ラッパー）
// ─────────────────────────────────────────────
class MonthlyHistoryScreen extends StatelessWidget {
  const MonthlyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        title: const Text('月間履歴'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const MonthlyHistoryBody(),
    );
  }
}

// ─────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────
class JsStatChip extends StatelessWidget {
  const JsStatChip(this.label, this.count, this.color, {
    super.key,
    this.selected = false,
    this.onTap,
    this.valueText,
  });
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  /// 単位付きの値（例 '288.0h'）を int に落とさず出すための任意指定。
  /// 省略時は従来どおり '$count' を描く＝レイアウト・サイズ・枠・色すべて不変。
  /// （home_screen.dart の _StaffStatChip が valueColor を足したのと同じ「追加だけ」の流儀。
  ///   実働(h) を int の count で表せないためだけに新部品を作ることを避ける。）
  final String? valueText;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.22) : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Column(children: [
          Text(valueText ?? '$count',
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ]),
      ),
    ),
  );
}

class JsReportTile extends StatelessWidget {
  const JsReportTile({super.key, required this.report, this.myCompanyId = ''});
  final Map<String, dynamic> report;
  final String myCompanyId;

  bool get _isOwn =>
      myCompanyId.isNotEmpty && report['company_id'] == myCompanyId;

  @override
  Widget build(BuildContext context) {
    // ★行の状態は report_cancel_gate の判定で決める。行に載っている 'status' を
    //   そのまま読まない。理由: この部品は親が status を作り直した行
    //   （月間履歴・カレンダー）と、BE の生の行（notification_list_screen が
    //   GET /reports/:id の結果をそのまま渡す経路）の両方を受け取る。
    //   生の行の status は 'open' で、旧実装の既定分岐に落ちて必ず「未承認」と
    //   出ていた。判定を1本に寄せると、どちらの経路でも同じ答えになる。
    final status = reportStatusOf(report);
    // ★色と語は report_status_style の対応表1本から採る。ここに switch を書かない。
    //   以前はここに手書きの switch があり、取消済と未承認が同じ温グレーで、
    //   さらに同じ「未承認」を絞り込みチップは橙で描いていた（＝同じ状態が
    //   画面の中で2色あった）。取消済は藤・未承認は橙に揃えたのが対応表の側。
    //   語は対応表へ写しただけで1文字も変えていない。
    final style = reportStatusStyleForState(status);
    final Color sc = style.color;
    final String sl = style.label;
    // 取消済。バッジと、下の『取消済（日報は残ります）』の1行に使う。
    final isCancelled = status == 'cancelled';
    final date       = report['report_date']   as String? ?? '';
    final content    = report['work_content']  as String? ?? '作業内容 未入力';
    final addr       = report['gps_address']   as String? ?? '';
    // 作業3: 複数選択に対応（'・' 区切り＝確認画面と同じ流儀）
    final trans      = transportNamesOf(report).join('・');
    final workerName = report['worker_name']   as String? ?? '';

    final isRejected  = status == 'rejected';
    final accentColor = myCompanyId.isEmpty
        ? null
        : (_isOwn ? FieldTokens.accent : FieldTokens.externalBlue);

    return GestureDetector(
      // ★取消済の行も必ず開ける。タップを止めない。
      //   ・タップできない行は「押しても何も起きない行」になり、嘘の記号になる。
      //     一覧に出ている以上、押せば中身が読めなければならない。
      //   ・記録は消さず、見れば取消済と分かる形にする。それがこのアプリの芯。
      //     取消済を開けなくすると「残っているのに読めない記録」になり、
      //     残す裁定と矛盾する。
      // ★行き先は詳細（下の else 側）。是正依頼へは送らない。
      //   isRejected は reportStatusOf が取消済を先に返すため、取消済の行では
      //   必ず false になる。ここで是正依頼へ送ると、その一覧は取消済を
      //   載せていないので「飛んだ先に無い」行き止まりになる。
      //   ＝押せてはいけない導線を出さない（day_reports_screen.dart が
      //     取消済のときだけ取消ボタンを引っ込めるのと同じ考え方）。
      onTap: () {
        if (isRejected) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RevisionInboxScreen()),
          );
        } else {
          showModalBottomSheet(
            context: context,
            backgroundColor: FieldTokens.surfaceCard,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            builder: (_) => JsReportDetailSheet(report: report),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          // 差戻しの枠も状態の色。トークン名を手書きせず対応表から採る
          //   （差戻しの色を変える日に、ここだけ取り残されないため）。
          border: Border.all(
              color: isRejected
                  ? reportStatusStyleForState('rejected').color
                  : FieldTokens.outline),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (accentColor != null)
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(9),
                      bottomLeft: Radius.circular(9),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(date,
                                  style: const TextStyle(
                                      color: FieldTokens.textSupport, fontSize: 12)),
                              if (trans.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(trans,
                                    style: const TextStyle(
                                        color: FieldTokens.textSupport, fontSize: 11)),
                              ],
                              if (accentColor != null && workerName.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(workerName,
                                    style: TextStyle(
                                        color: accentColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ]),
                            const SizedBox(height: 4),
                            Text(content,
                                style: const TextStyle(
                                    color: FieldTokens.textBody, fontSize: 14),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            if (addr.isNotEmpty)
                              Text(addr,
                                  style: const TextStyle(
                                      color: FieldTokens.textSupport, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            // 色はバッジと同じ sc（＝対応表の差戻しの色）。
                            //   同じ行の中で差戻しが2色にならないようにする。
                            if (isRejected) ...[
                              const SizedBox(height: 6),
                              Row(children: [
                                Icon(Icons.arrow_forward,
                                    color: sc, size: 13),
                                const SizedBox(width: 4),
                                Text('是正依頼を確認',
                                    style: TextStyle(
                                        color: sc,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ]),
                            ],
                            // ★取消済の印。バッジだけだと文字が小さく、
                            //   承認済だった行が取消済に変わったことを見落とす。
                            //   文言は業務で使う名詞で言い切る（勧誘も疑問形もしない）。
                            //   「日報は残ります」は取消の確認ダイアログの
                            //   『日報そのものは消えません。取消済として残ります。』
                            //   （day_reports_screen.dart）と同じ言い方にしてある
                            //   ＝取り消す前に約束したことを、取り消した後の画面でも
                            //   同じ言葉で示す。
                            // 色はバッジと同じ sc（＝対応表の取消済の色）を使う。
                            //   同じ行の中で取消済が2色になると、どちらが状態の
                            //   色なのか読めなくなる。
                            if (isCancelled) ...[
                              const SizedBox(height: 6),
                              Row(children: [
                                Icon(Icons.cancel_outlined,
                                    color: sc, size: 13),
                                const SizedBox(width: 4),
                                Text('取消済（日報は残ります）',
                                    style: TextStyle(
                                        color: sc,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ]),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: sc.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: sc),
                        ),
                        child: Text(sl,
                            style: TextStyle(
                                color: sc,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JsReportDetailSheet extends StatelessWidget {
  const JsReportDetailSheet({super.key, required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    // 判定・色・文言は JsReportTile と同じ1本（report_cancel_gate）から採る。
    // この画面にも生の行が届く（notification_list_screen が GET /reports/:id の
    // 結果をそのまま渡す）ため、行の 'status' を直に読まない。
    final status = reportStatusOf(report);
    // 色と語は行（JsReportTile）と同じ対応表から採る。ここにも switch を書かない。
    final style = reportStatusStyleForState(status);
    final Color sc = style.color;
    final String sl = style.label;

    final date        = report['report_date']    as String? ?? '';
    final content     = report['work_content']   as String? ?? '作業内容 未入力';
    final addr        = report['gps_address']    as String? ?? '';
    // 作業3: 複数選択に対応（'・' 区切り）
    final trans       = transportNamesOf(report).join('・');
    final distKm      = report['distance_km'];
    final transCost   = report['transport_cost'];
    final otHours     = report['overtime_hours']   as int? ?? 0;
    final otMinutes   = report['overtime_minutes'] as int? ?? 0;
    final parking     = report['parking_fee'];

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: FieldTokens.outline,
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(date,
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 13)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: sc),
                  ),
                  child: Text(sl,
                      style: TextStyle(
                          color: sc, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            // ★開いた詳細にも取消済の印を出す。右上のバッジだけだと文字が小さく、
            //   取り消された日報が普通の日報に見える＝これも嘘の記号になる。
            //   文言・アイコン・色は一覧の行（JsReportTile）と同じものを使う
            //   （画面ごとに言い換えない）。
            // ★この画面には押せる操作が1つも無い（下は読み取り専用の行だけ）ので、
            //   取消済のときに引っ込めるボタンは存在しない。操作を足すときは
            //   day_reports_screen.dart の先例（取消済のときだけ引っ込める）に従うこと。
            // 色は上のバッジと同じ sc（＝対応表の取消済の色）。行と同じ扱い。
            if (status == 'cancelled') ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.cancel_outlined, color: sc, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('取消済（日報は残ります）',
                      style: TextStyle(
                          color: sc,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            JsDetailRow(icon: Icons.work_outline,      label: '作業内容', value: content),
            if (addr.isNotEmpty)
              JsDetailRow(icon: Icons.location_on_outlined, label: '現場住所', value: addr),
            if (trans.isNotEmpty)
              JsDetailRow(icon: Icons.directions_car_outlined, label: '移動手段', value: trans),
            if (distKm != null)
              JsDetailRow(icon: Icons.straighten, label: '距離',
                  value: '${distKm}km'),
            if (transCost != null)
              JsDetailRow(icon: Icons.train_outlined, label: '交通費',
                  value: '¥$transCost'),
            if (parking != null)
              JsDetailRow(icon: Icons.local_parking, label: '駐車料金',
                  value: '¥$parking'),
            if (otHours > 0 || otMinutes > 0)
              JsDetailRow(icon: Icons.access_time, label: '残業時間',
                  value: '$otHours時間$otMinutes分'),
          ],
        ),
      ),
    );
  }
}

class JsDetailRow extends StatelessWidget {
  const JsDetailRow({super.key, required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: FieldTokens.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: FieldTokens.textBody, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 日付グループ行（月間履歴リスト用）
// ─────────────────────────────────────────────
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.dateStr,
    required this.date,
    required this.reports,
    required this.onTap,
  });
  final String dateStr;
  final DateTime date;
  final List<Map<String, dynamic>> reports;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // ★日の印は「生きている日報」だけで決める。取消済を混ぜると
    //   承認済1件＋取消済1件の日が allApproved=false になって「未承認」と出る。
    // ★生きている日報が1件も無い日（その日の全部を取り消した）は取消済と出す。
    //   ここで差戻や未承認へ倒すと、取り消したのに仕事が残っているように見える。
    final live        = reports.where((r) => !isCancelledReport(r)).toList();
    final cancelled   = reports.length - live.length;
    final hasRejected = live.any((r) => r['status'] == 'rejected');
    final allApproved = live.isNotEmpty && live.every((r) => r['status'] == 'approved');
    // ★色だけを対応表から採り、語はこの行が持っていたものをそのまま残す。
    //   理由: ここの差戻しの語は '差戻'（送り仮名なし）で、日報1枚のバッジの
    //   '差戻し' とは別の文字列である。語を変えないという裁定に従い、
    //   語を揃えることは今回しない。色だけを揃える
    //   （未承認はここも対応表と同じ橙で、見た目は変わらない）。
    final String dayState = live.isEmpty
        ? 'cancelled'
        : hasRejected
            ? 'rejected'
            : allApproved
                ? 'approved'
                : 'pending';
    const Map<String, String> dayLabels = <String, String>{
      'cancelled': '取消済',
      'rejected':  '差戻',
      'approved':  '承認済',
      'pending':   '未承認',
    };
    final Color sc = reportStatusStyleForState(dayState).color;
    final String sl = dayLabels[dayState]!;
    // ★件数も同じ。生きている件数を出し、取消済は足さずに並べて書く
    //   （足すと「3件」なのに開くと2件しか仕事が無い、というずれになる）。
    final countLabel = live.isEmpty
        ? '取消済$cancelled件'
        : '${live.length}件${cancelled > 0 ? '・取消済$cancelled件' : ''}';

    final parts = dateStr.split('-');
    final label = parts.length == 3
        ? '${int.tryParse(parts[1]) ?? 0}月${int.tryParse(parts[2]) ?? 0}日'
        : dateStr;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          // 日報1行と同じ扱い。差戻しの枠の色も対応表から採る。
          border: Border.all(
              color: hasRejected
                  ? reportStatusStyleForState('rejected').color
                  : FieldTokens.outline),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: FieldTokens.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(countLabel,
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sc.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: sc),
            ),
            child: Text(sl,
                style: TextStyle(
                    color: sc, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: FieldTokens.textSupport, size: 18),
        ]),
      ),
    );
  }
}
