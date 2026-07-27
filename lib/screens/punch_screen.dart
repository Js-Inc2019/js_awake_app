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
const _bg     = Color(0xFF080806);
const _card   = Color(0xFF181810);
const _gold   = Color(0xFFA89868);
const _text   = JsPalette.textBody;
const _label  = Color(0xFF686040);
const _border = Color(0xFF242418);

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
  });
  final VoidCallback? onNavigateToReport;
  final Widget? weatherPanel;
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
  }

  String _breakLabel() {
    final status = _record?['break_override_status'] as String?;
    final min    = _record?['break_override_min']    as int?;
    if (status == 'approved' && min != null) return '休憩 $min分（申請承認済み）';
    if (status == 'pending')                return '休憩変更を申請中（${min ?? '--'}分）';
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
                    const SizedBox(height: 16),
                    const Divider(color: _border, thickness: 1),
                    const SizedBox(height: 20),
                    // 状態表示
                    _StatusSection(
                      isActual:      isActual,
                      punchedIn:     _punchedIn,
                      punchedOut:    _punchedOut,
                      record:        _record,
                      breakLabel:    _breakLabel(),
                      onChangeBreak: _openBreakRequestSheet,
                    ),
                    const SizedBox(height: 20),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OperationZone(
                    isActual:          isActual,
                    punchedIn:         _punchedIn,
                    punchedOut:        _punchedOut,
                    busy:              _busy,
                    onPunch:           _doPunch,
                    // 日報報告への全経路（!isActual の「日報報告」／退勤済の「追加で日報を出す」）
                    // を単一のゲート _onReportTap 経由にする。
                    onNavigateToReport: _onReportTap,
                  ),
                  // 「本日休み」ボタン（序列を下げた OutlinedButton・textMid系）。
                  // 表示条件（裁定）:
                  //   ・みなしモード(!isActual): 日報報告ボタンの直下（現状どおり）
                  //   ・実打刻モード(isActual): 未出勤(!_punchedIn＝出勤スライド前)のみ表示。
                  //     出勤中・退勤済(=_punchedIn)は非表示（働いた日に休み登録は矛盾）。
                  //   ※ _punchedIn は _PunchScreenState の状態(:60)。出勤中判定 :99
                  //     `_punchedIn && !_punchedOut` と同じ状態変数を参照（判定式は複製しない）。
                  if (!isActual || !_punchedIn) ...[
                    const SizedBox(height: 10),
                    _RestDayButton(
                      rested:    _rested,
                      reason:    _restReason,
                      portion:   _restPortion,
                      loading:   _restLoading,
                      onChanged: _loadRestStatus,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
  });

  final bool isActual;
  final bool punchedIn;
  final bool punchedOut;
  final Map<String, dynamic>? record;
  final String breakLabel;
  final VoidCallback onChangeBreak;

  @override
  Widget build(BuildContext context) {
    if (!isActual) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'みなし労働時間制（参考集計）',
            style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text(
            '実際の勤務状況に応じて修正されます',
            style: TextStyle(color: _label, fontSize: 12),
          ),
        ],
      );
    }

    if (!punchedIn) {
      return const Text(
        '今日はまだ出勤していません',
        style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w600),
      );
    }

    final punchInIso  = record?['punch_in']  as String?;
    final punchOutIso = record?['punch_out'] as String?;

    if (punchedOut) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本日終了  ${_hhmm(punchInIso)} – ${_hhmm(punchOutIso)}',
            style: const TextStyle(
              color: _text, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _BreakInfoRow(label: breakLabel, onChange: onChangeBreak),
        ],
      );
    }

    // 出勤中
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_hhmm(punchInIso)}  出勤を記録しました',
          style: const TextStyle(
            color: _gold, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _InfoRow(label: '経過', value: _elapsed(punchInIso)),
        const SizedBox(height: 4),
        _BreakInfoRow(label: breakLabel, onChange: onChangeBreak),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text('$label  ', style: const TextStyle(color: _label, fontSize: 13)),
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
    return Row(children: [
      const Text('休憩  ', style: TextStyle(color: _label, fontSize: 13)),
      Expanded(
        child: Text(label,
            style: const TextStyle(
              color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
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
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: OutlinedButton(
          onPressed: onNavigateToReport,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _gold),
            foregroundColor: _gold,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text(
            '日報報告',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    if (punchedIn && punchedOut) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: TextButton(
          onPressed: onNavigateToReport,
          style: TextButton.styleFrom(
            foregroundColor: _label,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _border),
            ),
          ),
          child: const Text('追加で日報を出す', style: TextStyle(fontSize: 15)),
        ),
      );
    }

    final isCheckin = !punchedIn;
    return SlideToConfirm(
      filled:    isCheckin,
      icon:      isCheckin ? Icons.login : Icons.logout,
      label:     isCheckin ? 'スライドで出勤' : 'スライドで退勤',
      busy:      busy,
      onConfirm: () => onPunch(isCheckin ? 'in' : 'out'),
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
  });

  final bool rested;
  final String? reason;
  final String portion; // full / am_half / pm_half
  final bool loading;
  final Future<void> Function() onChanged; // 遷移から戻った後に親が状態を取り直す

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
      height: 48,
      child: OutlinedButton(
        onPressed: loading ? null : () => _onTap(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: JsColors.textMid,
          side: const BorderSide(color: JsColors.textMid),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          _label,
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

