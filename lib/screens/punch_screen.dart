// lib/screens/punch_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart' show fetchGpsAddress, showJsSnackbar;
import '../services/work_mode_service.dart';
import '../services/reports_service.dart';
import '../widgets/slide_to_confirm.dart';
import '../core/theme/js_colors.dart';
import '../utils/business_date.dart';
import 'rest_day_screen.dart';
import 'rest_day_done_screen.dart';

// ── Asphalt Dawn palette ──────────────────────────────────────────────────────
const _bg     = JsColors.background;
const _card   = JsColors.surface;
const _gold   = JsColors.accent;
const _text   = JsPalette.textBody;
const _label  = JsColors.textMid;
const _border = JsColors.border;

// ── file-level helpers ────────────────────────────────────────────────────────
String _hhmm(String? iso) {
  if (iso == null) return '--:--';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '--:--';
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

String _elapsed(String? punchInIso) {
  if (punchInIso == null) return '';
  final inTime = DateTime.tryParse(punchInIso)?.toLocal();
  if (inTime == null) return '';
  final d = DateTime.now().difference(inTime);
  return '${d.inHours}時間${d.inMinutes % 60}分';
}

// ── PunchScreen ───────────────────────────────────────────────────────────────
class PunchScreen extends StatefulWidget {
  const PunchScreen({
    super.key,
    this.onNavigateToReport,
    this.weatherPanel,
    required this.shiftType,
    required this.onShiftTypeChanged,
    this.revisionCount = 0,
    this.pendingApprovalCount = 0,
    this.onOpenRevisions,
    this.onOpenPendingApprovals,
  });
  final VoidCallback? onNavigateToReport;
  final Widget? weatherPanel;
  // ── 要対応の件数と遷移（値も遷移先も親 JsMainShell の既存資産をそのまま下ろす）──
  //   件数取得・遷移先はこの画面では一切作らない（home_screen.dart:1535-1560 を参照）。
  //   0件のときは行そのものを描画しない＝「無いものは見せない」。
  final int revisionCount;          // 差し戻し（home_screen.dart:382 _revisionCount）
  final int pendingApprovalCount;   // 承認待ち（同 :383・職長のときのみ非0が渡る）
  final VoidCallback? onOpenRevisions;
  final VoidCallback? onOpenPendingApprovals;
  // 勤務区分（日勤/夜勤）は親(JsMainShell)が真実を保持し、値+変更通知を下ろす。
  // 送信時の report_date 補正・shift_type 送出は親側で行う。
  final String shiftType;                       // 'day'|'night'
  final ValueChanged<String> onShiftTypeChanged;
  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen> with WidgetsBindingObserver {
  bool _loading = true;
  WorkModeSettings _settings = WorkModeSettings.defaults;
  Map<String, dynamic>? _record;
  bool _punchedIn  = false;
  bool _punchedOut = false;
  String _gpsAddress = '位置を取得中…';
  Timer? _timer;
  bool _busy = false;
  int? _standardBreakMin;
  int  _legalBreak6h = 45;
  int  _legalBreak8h = 60;

  // 本日休み状態（_RestDayButton から持ち上げ）。ボタン表示と日報報告ゲートが
  // 単一の状態を共有する（照会失敗は fail-open＝rested=false）。
  final ReportsService _reports = ReportsService();
  bool _restLoading = true;
  bool _rested      = false;
  String? _restReason;
  String _restPortion = 'full'; // full / am_half / pm_half（応答に無ければ full）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    _loadRestStatus();
  }

  Future<void> _loadRestStatus() async {
    final res = await _reports.getRestDayToday();
    if (!mounted) return;
    setState(() {
      _restLoading = false;
      if (res['success'] == true) {
        _rested      = res['rested'] == true;
        _restReason  = res['reason'] as String?;
        _restPortion = (res['portion'] as String?) ?? 'full';
      } else {
        _rested      = false; // fail-open
        _restReason  = null;
        _restPortion = 'full';
      }
    });
  }

  // 日報報告への遷移ゲート。終日休み(rested かつ portion=full)なら確認ダイアログを挟み、
  // 「取り消して続行」時のみ DELETE 成功後に従来遷移する（失敗は SnackBar で可視化）。
  // 半休(am_half/pm_half)は「働く日」なので日報は必要＝ゲートせず従来どおり即遷移。
  // rested=false のときも従来どおり即遷移（挙動不変）。
  Future<void> _onReportTap() async {
    if (!_rested || _restPortion != 'full') {
      widget.onNavigateToReport?.call();
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JsColors.surface,
        title: const Text('本日は休み登録済みです',
            style: TextStyle(color: JsColors.textStrong, fontSize: 16)),
        content: const Text('日報を出すには、本日の休み登録を取り消す必要があります。',
            style: TextStyle(color: JsColors.textStrong)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('戻る', style: TextStyle(color: JsColors.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('休みを取り消して続行',
                style: TextStyle(color: JsColors.accent)),
          ),
        ],
      ),
    );
    if (proceed != true) return;

    final res = await _reports.deleteRestDay(); // 既存メソッドを再利用
    if (!mounted) return;
    if (res['success'] == true) {
      await _loadRestStatus();               // ボタン表示も最新化
      if (!mounted) return;
      widget.onNavigateToReport?.call();      // 従来の日報報告へ
    } else {
      showJsSnackbar(
        context,
        '${res['error'] ?? '休みの取り消しに失敗しました'}'
        '${res['statusCode'] != null ? '（${res['statusCode']}）' : ''}',
        isError: true,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _init();
  }

  Future<void> _init() async {
    final (settings, today) = await (
      WorkModeService.instance.fetchFromServer(),
      WorkModeService.instance.fetchToday(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _settings = settings;
      if (today != null) {
        _record           = today.record;
        _punchedIn        = today.punchedIn;
        _punchedOut       = today.punchedOut;
        _standardBreakMin = today.standardBreakMin;
        _legalBreak6h     = today.legalBreak6h;
        _legalBreak8h     = today.legalBreak8h;
      }
      _loading = false;
    });
    if (_punchedIn && !_punchedOut) _startTimer();
    fetchGpsAddress().then((r) {
      if (mounted) setState(() => _gpsAddress = r.address);
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _doPunch(String type) async {
    if (_busy) return;
    setState(() => _busy = true);
    // 裁定(b): 退勤スライド確定直後は日報へ直行する（ホームに戻さない）。
    // 遷移先の出し分け（未提出=日報フォーム / 提出済=完了ビュー）は既存資産に委ねる:
    //   _onReportTap(:106) → widget.onNavigateToReport → home_screen:1506 `_setTab(1)`
    //   → home_screen:1760 `if (_todayReportDone) AfterReportBody`（提出済判定は
    //     home_screen:_readReportDone が単一の真実源）。判定式はここに複製しない。
    // _busy 解除後に呼ぶため finally の外へ出す（ゲート内のダイアログ中も操作可）。
    bool goReport = false;
    try {
      final gps    = await fetchGpsAddress();
      final result = await WorkModeService.instance.punch(
        type,
        lat:  gps.lat,
        lng:  gps.lon,
        addr: gps.address,
        shiftType: widget.shiftType,   // S5b: 勤務区分をBEへ送出（夜勤は始業日1行に収まる）
      );
      if (!mounted) return;
      if (result.ok) {
        final today = await WorkModeService.instance.fetchToday();
        if (!mounted) return;
        setState(() {
          if (today != null) {
            _record           = today.record;
            _punchedIn        = today.punchedIn;
            _punchedOut       = today.punchedOut;
            _standardBreakMin = today.standardBreakMin;
            _legalBreak6h     = today.legalBreak6h;
            _legalBreak8h     = today.legalBreak8h;
          }
        });
        if (_punchedIn && !_punchedOut) {
          _startTimer();
        } else {
          _timer?.cancel();
        }
        // 退勤打刻がサーバに反映された時だけ立てる（出勤時・反映漏れ時は従来どおり）
        goReport = type == 'out' && _punchedOut;
      } else {
        showJsSnackbar(
          context,
          result.errorMessage ?? 'エラーが発生しました',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (goReport && mounted) await _onReportTap();
  }

  String _breakLabel() {
    final status = _record?['break_override_status'] as String?;
    final min    = _record?['break_override_min']    as int?;
    if (status == 'approved' && min != null) return '休憩 $min分（申請承認済み）';
    if (status == 'pending')                return '休憩変更を申請中（${min ?? '--'}分）';
    // 却下の可視化。ここが無いと rejected は下の「会社設定」／「自動」へ黙って落ち、
    // 申請が却下された事実がどこにも出なかった（BE: attendanceCalculator.js:83-84 で
    // approved 以外は会社設定/法定値にフォールバックする＝計算からも静かに消える）。
    if (status == 'rejected') {
      return _standardBreakMin != null
          ? '休憩申請は却下されました（会社設定 $_standardBreakMin分）'
          : '休憩申請は却下されました';
    }
    if (_standardBreakMin != null)          return '休憩 $_standardBreakMin分（会社設定）';
    return '休憩は労働時間に応じて自動';
  }

  void _openBreakRequestSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BreakRequestSheet(
        record:       _record,
        legalBreak6h: _legalBreak6h,
        legalBreak8h: _legalBreak8h,
        onSubmitted:  _onBreakRequestSubmitted,
      ),
    );
  }

  Future<void> _onBreakRequestSubmitted() async {
    showJsSnackbar(context, '申請しました（承認待ち）');
    final today = await WorkModeService.instance.fetchToday();
    if (!mounted) return;
    setState(() {
      if (today != null) {
        _record           = today.record;
        _punchedIn        = today.punchedIn;
        _punchedOut       = today.punchedOut;
        _standardBreakMin = today.standardBreakMin;
        _legalBreak6h     = today.legalBreak6h;
        _legalBreak8h     = today.legalBreak8h;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }

    final isActual = _settings.mode == WorkModeType.actual;
    final now = DateTime.now();
    final dow = '日月火水木金土'[now.weekday % 7];
    final dateLabel =
        '${now.year}年'
        '${now.month.toString().padLeft(2, '0')}月'
        '${now.day.toString().padLeft(2, '0')}日（$dow）';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            if (widget.weatherPanel != null) widget.weatherPanel!,
            // ── 情報エリア（スクロール） ───────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 日付 + モードピル
                    Row(children: [
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: _text, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      _ModePill(isActual: isActual),
                    ]),
                    const SizedBox(height: 10),
                    // 住所
                    Row(children: [
                      const Icon(Icons.location_on_outlined, color: _label, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _gpsAddress,
                          style: const TextStyle(color: _label, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    const Divider(color: _border, thickness: 1, height: 1),
                    // ── 要対応行（0件の行は描画しない）────────────────
                    //   件数・遷移先は親から下ろした既存の値だけを使う。
                    if (widget.revisionCount > 0)
                      _AttentionRow(
                        accent: JsColors.warning,          // 差し戻し = warning系
                        label:  '差し戻し',
                        count:  widget.revisionCount,
                        onTap:  widget.onOpenRevisions,
                      ),
                    if (widget.pendingApprovalCount > 0)
                      _AttentionRow(
                        accent: JsColors.accent,           // 承認待ち = accent系
                        label:  '承認待ち',
                        count:  widget.pendingApprovalCount,
                        onTap:  widget.onOpenPendingApprovals,
                      ),
                    const SizedBox(height: 28),
                    // 状態表示
                    _StatusSection(
                      isActual:      isActual,
                      punchedIn:     _punchedIn,
                      punchedOut:    _punchedOut,
                      record:        _record,
                      breakLabel:    _breakLabel(),
                      onChangeBreak: _openBreakRequestSheet,
                      // みなしモードの表示に使う値。WorkModeService の取得ロジックは
                      // 一切変えず、既に _settings(:58) が持っている値を下ろすだけ。
                      deemedStart:   _settings.deemedStart,
                      deemedEnd:     _settings.deemedEnd,
                      breakMinutes:  _settings.breakMinutes,
                    ),
                    const SizedBox(height: 28),
                    // 勤務区分（日勤/夜勤・1タップ）＋ 送信される業務日
                    // isActual の分岐外＝みなし/実打刻の両モードで同一位置に出る
                    _ShiftTypeSelector(
                      selected: widget.shiftType,
                      businessDate: businessDateForShift(
                          widget.shiftType, DateTime.now()),
                      onChanged: widget.onShiftTypeChanged,
                    ),
                  ],
                ),
              ),
            ),
            // ── 操作エリア（親指ゾーン・固定） ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: _buildOperationArea(isActual),
            ),
          ],
        ),
      ),
    );
  }

  // ── 操作エリアの組み立て ─────────────────────────────────────────────
  // 「本日休み」ボタンの表示条件は旧 build 内 :390 の式をそのまま使う。
  // 式は1文字も変えていない（`!isActual || !_punchedIn` を変数へ束ねただけ）:
  //   ・みなしモード(!isActual): 表示（横2分割の右側）
  //   ・実打刻モード(isActual): 未出勤(!_punchedIn＝出勤スライド前)のみ表示。
  //     出勤中・退勤済(=_punchedIn)は非表示（働いた日に休み登録は矛盾）。
  //   ※ _punchedIn は _PunchScreenState の状態(:60)。出勤中判定
  //     `_punchedIn && !_punchedOut` と同じ状態変数を参照（判定式は複製しない）。
  Widget _buildOperationArea(bool isActual) {
    final showRestDay = !isActual || !_punchedIn;

    final opZone = _OperationZone(
      isActual:          isActual,
      punchedIn:         _punchedIn,
      punchedOut:        _punchedOut,
      busy:              _busy,
      onPunch:           _doPunch,
      // 日報報告への全経路（!isActual の「日報を報告」／出勤中・退勤済の「日報を報告」）
      // を単一のゲート _onReportTap 経由にする。
      onNavigateToReport: _onReportTap,
    );

    final restBtn = _RestDayButton(
      rested:    _rested,
      reason:    _restReason,
      portion:   _restPortion,
      loading:   _restLoading,
      onChanged: _loadRestStatus,
      // みなしは日報ボタンと横並びになるので高さを合わせる（実打刻は従来の48のまま）
      height:    isActual ? 48 : 56,
    );

    // みなしモード（案Z）: 下部は横2分割［日報を報告=主］［本日休み=二次］
    if (!isActual) {
      return Row(
        children: [
          Expanded(child: opZone),
          if (showRestDay) ...[
            const SizedBox(width: 10),
            Expanded(child: restBtn),
          ],
        ],
      );
    }

    // 実勤務モード: 従来どおり縦積み（スライダー等の下に「本日休み」）
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        opZone,
        if (showRestDay) ...[
          const SizedBox(height: 10),
          restBtn,
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ⓪ 勤務区分 2択（日勤 / 夜勤）＋ 業務日表示
//   タッチターゲット 44pt以上・選択=ゴールド / 非選択=沈み
//   （home_screen.dart から移設・見た目は変更なし）
// ─────────────────────────────────────────────
class _ShiftTypeSelector extends StatelessWidget {
  const _ShiftTypeSelector({
    required this.selected,
    required this.businessDate,
    required this.onChanged,
  });
  final String selected;        // 'day'|'night'
  final String businessDate;    // 送信される report_date（'YYYY-MM-DD'）
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String type, String label, IconData icon) {
      final sel = selected == type;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 46,                       // タッチターゲット 44pt以上
            decoration: BoxDecoration(
              color: sel
                  ? JsColors.gold.withValues(alpha: 0.15)
                  : JsColors.gunmetal,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(
                color: sel ? JsColors.gold : JsColors.divider,
                width: sel ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16,
                    color: sel ? JsColors.gold : JsColors.silver),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: sel ? JsColors.gold : JsColors.silver,
                    fontSize: 14,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          chip('day',   '日勤', Icons.wb_sunny_outlined),
          const SizedBox(width: 8),
          chip('night', '夜勤', Icons.nightlight_outlined),
        ]),
        const SizedBox(height: 4),
        Text(
          '業務日 $businessDate',
          textAlign: TextAlign.center,
          style: const TextStyle(color: JsColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

// ── _ModePill ─────────────────────────────────────────────────────────────────
class _ModePill extends StatelessWidget {
  const _ModePill({required this.isActual});
  final bool isActual;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isActual ? _gold.withValues(alpha: 0.15) : _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActual ? _gold : _border),
      ),
      child: Text(
        isActual ? '実勤務モード' : 'みなし',
        style: TextStyle(
          color: isActual ? _gold : _label,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── _StatusSection ────────────────────────────────────────────────────────────
class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.isActual,
    required this.punchedIn,
    required this.punchedOut,
    required this.record,
    required this.breakLabel,
    required this.onChangeBreak,
    required this.deemedStart,
    required this.deemedEnd,
    required this.breakMinutes,
  });

  final bool isActual;
  final bool punchedIn;
  final bool punchedOut;
  final Map<String, dynamic>? record;
  final String breakLabel;
  final VoidCallback onChangeBreak;
  // みなし表示用。WorkModeSettings(work_mode_service.dart:16-18) の値をそのまま受け取る。
  final String deemedStart;   // 'HH:mm'
  final String deemedEnd;     // 'HH:mm'
  final int    breakMinutes;

  @override
  Widget build(BuildContext context) {
    if (!isActual) {
      // みなしモード（案Z）: 時刻が主役（28px・中央）。
      return _ClockBlock(
        label:    'みなし勤務',
        time:     '$deemedStart − $deemedEnd',
        timeSize: 28,
        support: Text(
          '休憩 $breakMinutes分　実際の勤務に応じて修正されます',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _label, fontSize: 12),
        ),
      );
    }

    if (!punchedIn) {
      return const SizedBox(
        width: double.infinity,
        child: Text(
          '今日はまだ出勤していません',
          textAlign: TextAlign.center,
          style: TextStyle(color: _label, fontSize: 14),
        ),
      );
    }

    final punchInIso  = record?['punch_in']  as String?;
    final punchOutIso = record?['punch_out'] as String?;

    if (punchedOut) {
      return _ClockBlock(
        label:    '本日終了',
        time:     '${_hhmm(punchInIso)} − ${_hhmm(punchOutIso)}',
        timeSize: 34,
        support: _SupportLine(children: [
          _BreakInfoRow(label: breakLabel, onChange: onChangeBreak),
        ]),
      );
    }

    // 出勤中
    return _ClockBlock(
      label:    '出勤中',
      time:     '${_hhmm(punchInIso)} −',
      timeSize: 34,
      support: _SupportLine(children: [
        _InfoRow(label: '経過', value: _elapsed(punchInIso)),
        _BreakInfoRow(label: breakLabel, onChange: onChangeBreak),
      ]),
    );
  }
}

// ── _ClockBlock ───────────────────────────────────────────────────────────────
// 「ラベル（小・字間広め）＋ 時刻（最大の文字・中央）＋ 補助行」の共通の型。
// 色は意味だけに使う原則により、時刻は本文色(_text)固定＝状態はラベルで示す。
class _ClockBlock extends StatelessWidget {
  const _ClockBlock({
    required this.label,
    required this.time,
    required this.timeSize,
    this.support,
  });
  final String label;
  final String time;
  final double timeSize;
  final Widget? support;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _label,
              fontSize: 10,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            time,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _text,
              fontSize: timeSize,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.5,
              height: 1.1,
            ),
          ),
          if (support != null) ...[
            const SizedBox(height: 12),
            support!,
          ],
        ],
      ),
    );
  }
}

// ── _SupportLine ──────────────────────────────────────────────────────────────
// 時刻の下の補助行。Wrap なので長い休憩ラベルでも溢れず折り返す。
class _SupportLine extends StatelessWidget {
  const _SupportLine({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: children,
      );
}

// ── _AttentionRow ─────────────────────────────────────────────────────────────
// 要対応の1行。左に2pxの縦線・右に件数＋「›」。箱で囲まず、下は1pxの線で区切る。
// ★件数が0のときは呼び出し側で行ごと描画しない（punch_screen.dart の build を参照）。
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.accent,
    required this.label,
    required this.count,
    required this.onTap,
  });
  final Color accent;       // 意味の色（差し戻し=warning / 承認待ち=accent）
  final String label;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Container(width: 2, height: 28, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: _label, fontSize: 13),
                ),
              ),
              // 数字が主役: 件数20px / 単位11px
              Text(
                '$count',
                style: const TextStyle(
                  color: _text,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
              const Text('件',
                  style: TextStyle(color: _label, fontSize: 11)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: _label, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // 補助行(_SupportLine=Wrap)の子になるため mainAxisSize は min 固定。
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label  ', style: const TextStyle(color: _label, fontSize: 12)),
      Text(value,
          style: const TextStyle(
            color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _BreakInfoRow extends StatelessWidget {
  const _BreakInfoRow({required this.label, required this.onChange});
  final String   label;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    // 補助行(_SupportLine=Wrap)の子になるため Expanded をやめ mainAxisSize は min 固定。
    // ★label（値）の取得元は変えていない: 親から渡る _breakLabel()(:246-253) のまま。
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: const TextStyle(
            color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onChange,
        child: const Text(
          '変更',
          style: TextStyle(
            color: _gold, fontSize: 12,
            decoration: TextDecoration.underline,
            decorationColor: _gold,
          ),
        ),
      ),
    ]);
  }
}

// ── _OperationZone ────────────────────────────────────────────────────────────
class _OperationZone extends StatelessWidget {
  const _OperationZone({
    required this.isActual,
    required this.punchedIn,
    required this.punchedOut,
    required this.busy,
    required this.onPunch,
    this.onNavigateToReport,
  });

  final bool isActual;
  final bool punchedIn;
  final bool punchedOut;
  final bool busy;
  final Future<void> Function(String) onPunch;
  final VoidCallback? onNavigateToReport;

  @override
  Widget build(BuildContext context) {
    if (!isActual) {
      return _ReportOutlineButton(onPressed: onNavigateToReport);
    }

    if (punchedIn && punchedOut) {
      return _ReportOutlineButton(onPressed: onNavigateToReport);
    }

    final isCheckin = !punchedIn;
    // ★用途（出勤／退勤）ごとに別インスタンスにする。
    //   SlideToConfirm は確定後「いったきり」で操作を受け付けない終端状態
    //   (_fired/_confirmed) を持つ。key を分けないと出勤確定後に
    //   punchedIn:false→true でラベルだけ退勤へ変わり、State は出勤時の
    //   確定済みのまま再利用されて退勤スライドが操作不能になる。
    //   同一用途の間は key が不変なので「いったきり」は維持される。
    final slider = SlideToConfirm(
      key:       ValueKey(isCheckin ? 'punch-in' : 'punch-out'),
      filled:    isCheckin,
      icon:      isCheckin ? Icons.login : Icons.logout,
      label:     isCheckin ? 'スライドで出勤' : 'スライドで退勤',
      busy:      busy,
      onConfirm: () => onPunch(isCheckin ? 'in' : 'out'),
    );

    // 未出勤: 出勤スライダーだけ（1画面1主行動）
    if (isCheckin) return slider;

    // 出勤中: 退勤スライダー ＋「日報を報告」（生成り枠）
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        slider,
        const SizedBox(height: 10),
        _ReportOutlineButton(onPressed: onNavigateToReport),
      ],
    );
  }
}

// ── _ReportOutlineButton ──────────────────────────────────────────────────────
// 「日報を報告」＝生成り抜きの主ボタン（accent 塗りではなく枠1.5px）。
// 押下先は呼び出し側から渡る単一のゲート _onReportTap(:106) のみ。
class _ReportOutlineButton extends StatelessWidget {
  const _ReportOutlineButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: JsFormTokens.outlineButtonBorder,
          disabledForegroundColor: JsFormTokens.outlineButtonDisabled,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? JsFormTokens.outlineButtonDisabled
                    : JsFormTokens.outlineButtonBorder,
                width: 1.5,
              )),
        ),
        child: const Text(
          '日報を報告',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ── _RestDayButton ────────────────────────────────────────────────────────────
// 「本日休み」ボタン（表示は親から受け取る props 駆動）。状態(rested/reason)は
// 親 _PunchScreenState が単一の真実源として保持し、日報報告ゲートと共有する。
//   rested=true → 「本日休み 登録済み」＋タップでねぎらい画面
//   rested=false（or 照会失敗=fail-open）→ 「本日休み」＋タップで休み登録画面
// 序列は日報報告より下（OutlinedButton・textMid系の控えめ配色）。
class _RestDayButton extends StatelessWidget {
  const _RestDayButton({
    required this.rested,
    required this.reason,
    required this.portion,
    required this.loading,
    required this.onChanged,
    this.height = 48,
  });

  final bool rested;
  final String? reason;
  final String portion; // full / am_half / pm_half
  final bool loading;
  final Future<void> Function() onChanged; // 遷移から戻った後に親が状態を取り直す
  final double height; // みなしは日報ボタンと横並びになるため呼び出し側で高さを揃える

  // 登録済みボタン文言。半休は「午前休/午後休」を明示。
  String get _label {
    if (!rested) return '本日休み';
    switch (portion) {
      case 'am_half': return '本日午前休 登録済み';
      case 'pm_half': return '本日午後休 登録済み';
      default:        return '本日休み 登録済み';
    }
  }

  Future<void> _onTap(BuildContext context) async {
    if (rested) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RestDayDoneScreen(reason: reason, portion: portion)));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const RestDayScreen()));
    }
    await onChanged(); // 戻ったら状態を取り直す（親が mounted を判定）
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(
        // 暗枠1px・textMid系（日報＝生成り枠より一段下の序列）
        onPressed: loading ? null : () => _onTap(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: JsColors.textMid,
          side: const BorderSide(color: JsColors.textMid),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          _label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }
}

// ── _BreakRequestSheet ────────────────────────────────────────────────────────
class _BreakRequestSheet extends StatefulWidget {
  const _BreakRequestSheet({
    required this.record,
    required this.legalBreak6h,
    required this.legalBreak8h,
    required this.onSubmitted,
  });
  final Map<String, dynamic>? record;
  final int legalBreak6h;
  final int legalBreak8h;
  final Future<void> Function() onSubmitted;

  @override
  State<_BreakRequestSheet> createState() => _BreakRequestSheetState();
}

class _BreakRequestSheetState extends State<_BreakRequestSheet> {
  static const _presets = [0, 30, 45, 60, 90];
  int _selectedMin = 60;
  final _reasonCtrl = TextEditingController();
  bool _submitting  = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  int? _legalFloor() {
    final punchIn  = widget.record?['punch_in']  as String?;
    final punchOut = widget.record?['punch_out'] as String?;
    if (punchIn == null || punchOut == null) return null;
    final inDt  = DateTime.tryParse(punchIn);
    final outDt = DateTime.tryParse(punchOut);
    if (inDt == null || outDt == null) return null;
    var gross = outDt.difference(inDt).inMinutes;
    if (gross < 0) gross += 1440;
    if (gross > 480) return widget.legalBreak8h;
    if (gross > 360) return widget.legalBreak6h;
    return 0;
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await WorkModeService.instance.breakRequest(
        breakMinutes: _selectedMin,
        reason: reason,
      );
      if (!mounted) return;
      if (result.ok) {
        Navigator.of(context).pop();
        await widget.onSubmitted();
      } else {
        showJsSnackbar(
          context,
          result.errorMessage ?? 'エラーが発生しました',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final floor      = _legalFloor();
    final belowLegal = floor != null && floor > 0 && _selectedMin < floor;

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '休憩時間の変更を申請',
            style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          const Text('実休憩', style: TextStyle(color: _label, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((min) {
              final selected = _selectedMin == min;
              return GestureDetector(
                onTap: () => setState(() => _selectedMin = min),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? _gold.withValues(alpha: 0.15) : _card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: selected ? _gold : _border),
                  ),
                  child: Text(
                    '$min 分',
                    style: TextStyle(
                      color: selected ? _gold : _label,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (belowLegal) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.shield_outlined, color: Color(0xFFE05252), size: 14),
              const SizedBox(width: 4),
              Text(
                '⚠️ これは法定休憩($floor分)を下回ります',
                style: const TextStyle(color: Color(0xFFE05252), fontSize: 12),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          const Text('理由（必須）', style: TextStyle(color: _label, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonCtrl,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: _text, fontSize: 14),
            decoration: InputDecoration(
              hintText: '例）現場の都合で休憩を取れなかった',
              hintStyle: TextStyle(color: _label.withValues(alpha: 0.6), fontSize: 13),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _gold),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_reasonCtrl.text.trim().isEmpty || _submitting) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                disabledBackgroundColor: _border,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(color: _bg, strokeWidth: 2.5),
                    )
                  : const Text(
                      '申請する',
                      style: TextStyle(
                        color: _bg, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

