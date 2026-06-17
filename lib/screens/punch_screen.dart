// lib/screens/punch_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart' show fetchGpsAddress, showJsSnackbar;
import '../services/work_mode_service.dart';

// ── Asphalt Dawn palette ──────────────────────────────────────────────────────
const _bg     = Color(0xFF080806);
const _card   = Color(0xFF181810);
const _gold   = Color(0xFFA89868);
const _text   = Color(0xFFEDE8DC);
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
  const PunchScreen({super.key});
  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen> {
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final (settings, today) = await (
      WorkModeService.instance.load(),
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
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _text,
        elevation: 0,
        title: const Text(
          '打刻',
          style: TextStyle(color: _text, fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
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
                  ],
                ),
              ),
            ),
            // ── 操作エリア（親指ゾーン・固定） ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: _OperationZone(
                isActual:   isActual,
                punchedIn:  _punchedIn,
                punchedOut: _punchedOut,
                busy:       _busy,
                onPunch:    _doPunch,
              ),
            ),
          ],
        ),
      ),
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
  });

  final bool isActual;
  final bool punchedIn;
  final bool punchedOut;
  final bool busy;
  final Future<void> Function(String) onPunch;

  @override
  Widget build(BuildContext context) {
    if (!isActual) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: OutlinedButton(
          onPressed: () {
            // TODO: 日報報告画面へ遷移
          },
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
          onPressed: () {
            // TODO: 追加日報提出フロー
          },
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
    return _SlideToConfirm(
      isCheckin: isCheckin,
      label:     isCheckin ? 'スライドで出勤' : 'スライドで退勤',
      busy:      busy,
      onConfirm: () => onPunch(isCheckin ? 'in' : 'out'),
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

// ── _SlideToConfirm ───────────────────────────────────────────────────────────
class _SlideToConfirm extends StatefulWidget {
  const _SlideToConfirm({
    required this.isCheckin,
    required this.label,
    required this.busy,
    required this.onConfirm,
  });

  final bool     isCheckin;
  final String   label;
  final bool     busy;
  final Future<void> Function() onConfirm;

  @override
  State<_SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<_SlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dragX = 0;
  late final AnimationController _ctrl;
  Animation<double>? _anim;

  static const _handleSz  = 64.0;
  static const _handleH   = 72.0;
  static const _threshold = 0.70;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(_tick);
  }

  void _tick() {
    final v = _anim?.value;
    if (v != null && mounted) setState(() => _dragX = v);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _snap() {
    _anim = Tween<double>(begin: _dragX, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxDrag = constraints.maxWidth - _handleSz - 8.0;
      final cx      = _dragX.clamp(0.0, maxDrag);

      return GestureDetector(
        onHorizontalDragStart: widget.busy ? null : (_) => _ctrl.stop(),
        onHorizontalDragUpdate: widget.busy
            ? null
            : (d) => setState(
                () => _dragX = (_dragX + d.delta.dx).clamp(0.0, maxDrag)),
        onHorizontalDragEnd: widget.busy
            ? null
            : (_) {
                if (cx / maxDrag >= _threshold) widget.onConfirm().ignore();
                _snap();
              },
        child: Container(
          width: double.infinity,
          height: 88,
          decoration: BoxDecoration(
            color: widget.isCheckin
                ? _gold.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _gold, width: 1.5),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // ヒントテキスト（中央）
              Center(
                child: Text(
                  '→ ${widget.label}',
                  style: TextStyle(
                    color: _gold.withValues(alpha: 0.45),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // ドラッグハンドル
              Positioned(
                left: cx + 4,
                top:  (88 - _handleH) / 2,
                child: Container(
                  width:  _handleSz,
                  height: _handleH,
                  decoration: BoxDecoration(
                    color: widget.isCheckin ? _gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: widget.isCheckin
                        ? null
                        : Border.all(color: _gold, width: 2),
                  ),
                  child: widget.busy
                      ? const Center(
                          child: SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                              color: _gold, strokeWidth: 2.5),
                          ),
                        )
                      : Icon(
                          widget.isCheckin ? Icons.login : Icons.logout,
                          color: widget.isCheckin ? _bg : _gold,
                          size: 28,
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
