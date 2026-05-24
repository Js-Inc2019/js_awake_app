import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _C {
  static const black    = Color(0xFF111111);
  static const gunmetal = Color(0xFF2A2A2A);
  static const gold     = Color(0xFFD4AF37);
  static const silver   = Color(0xFF9E9E9E);
  static const offWhite = Color(0xFFF5F5F0);
  static const divider  = Color(0xFF3A3A3A);
  static const success  = Color(0xFF2E7D5E);
  static const navy     = Color(0xFF3949AB);
  static const warning  = Color(0xFFE65100);
}

class AfterReportScreen extends StatefulWidget {
  const AfterReportScreen({
    super.key,
    required this.workerName,
    required this.onMoveToNextSite,
    required this.onNightShift,
    required this.onOvertime,
  });
  final String workerName;
  final VoidCallback onMoveToNextSite;
  final VoidCallback onNightShift;
  final Future<void> Function() onOvertime;

  @override
  State<AfterReportScreen> createState() => _AfterReportScreenState();
}

class _AfterReportScreenState extends State<AfterReportScreen> {
  // 残業スライドをリセットするためのキー
  Key _overtimeKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _C.success.withValues(alpha: 0.15),
                  border: Border.all(color: _C.success, width: 2),
                ),
                child: const Icon(Icons.check, color: _C.success, size: 52),
              ),
              const SizedBox(height: 24),
              const Text('報告完了！',
                  style: TextStyle(color: _C.offWhite, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${widget.workerName}さんの報告を送信しました',
                  style: const TextStyle(color: _C.silver, fontSize: 14)),
              const SizedBox(height: 48),
              const Text('次のアクションを選択してください',
                  style: TextStyle(color: _C.silver, fontSize: 13)),
              const SizedBox(height: 16),

              // 🚗 現場移動 （スライド）
              _SlideBtn(
                icon: Icons.directions_car,
                label: '🚗  現場移動',
                subtitle: '別の現場へ移動してGPS再取得',
                color: _C.gold,
                onSlide: widget.onMoveToNextSite,
              ),
              const SizedBox(height: 12),

              // 🌙 夜勤継続（スライド）
              _SlideBtn(
                icon: Icons.nightlight_round,
                label: '🌙  夜勤継続',
                subtitle: 'そのまま夜勤へ移行',
                color: _C.navy,
                onSlide: widget.onNightShift,
              ),
              const SizedBox(height: 16),

              // ⏰ 残業（ボタン式）
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: widget.onOvertime,
                  icon: const Icon(Icons.more_time, size: 24),
                  label: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('⏰  残業', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('残業時間と内容を入力', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.warning,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),

              const Spacer(),
              const Text('← スライドして選択（残業はタップ）',
                  style: TextStyle(color: _C.silver, fontSize: 11)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// スライドボタン（現場移動・夜勤のみ）
// ============================================================
class _SlideBtn extends StatefulWidget {
  const _SlideBtn({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onSlide,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onSlide;

  @override
  State<_SlideBtn> createState() => _SlideBtnState();
}

class _SlideBtnState extends State<_SlideBtn> {
  double _offset = 0;
  bool _done = false;
  static const double _max = 220.0;

  void _onUpdate(DragUpdateDetails d) {
    if (_done) return;
    setState(() => _offset = (_offset + d.delta.dx).clamp(0.0, _max));
  }

  void _onEnd(DragEndDetails _) {
    if (_done) return;
    if (_offset > _max * 0.6) {
      setState(() { _done = true; _offset = _max; });
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 300), widget.onSlide);
    } else {
      setState(() => _offset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: _C.gunmetal,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.color.withValues(alpha: 0.5)),
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.label, style: TextStyle(
                color: widget.color, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 2),
            Text(widget.subtitle, style: const TextStyle(color: _C.silver, fontSize: 11)),
          ])),
          GestureDetector(
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(left: _offset + 4, top: 6, bottom: 6, right: 4),
              width: 56,
              decoration: BoxDecoration(
                color: _done ? _C.success : widget.color,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(
                    color: widget.color.withValues(alpha: 0.4),
                    blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Icon(_done ? Icons.check : widget.icon, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// OvertimeScreen — 残業入力画面
// ============================================================
class OvertimeScreen extends StatefulWidget {
  const OvertimeScreen({super.key, required this.workerName, required this.onSubmit});
  final String workerName;
  final void Function(String startTime, String endTime, String content) onSubmit;

  @override
  State<OvertimeScreen> createState() => _OvertimeScreenState();
}

class _OvertimeScreenState extends State<OvertimeScreen> {
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay? _endTime;
  final _contentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() { _contentCtrl.dispose(); super.dispose(); }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : (_endTime ?? TimeOfDay.now()),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
            primary: _C.gold, onSurface: _C.offWhite, surface: _C.gunmetal)),
        child: child!,
      ),
    );
    if (picked != null) setState(() { if (isStart) _startTime = picked; else _endTime = picked; });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('残業終了時刻を入力してください'),
          backgroundColor: Color(0xFFB71C1C)));
      return;
    }
    setState(() => _submitting = true);
    widget.onSubmit(_fmt(_startTime), _fmt(_endTime!), _contentCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.black,
      appBar: AppBar(
        backgroundColor: _C.black,
        foregroundColor: _C.gold,
        title: const Text('⏰ 残業報告',
            style: TextStyle(color: _C.gold, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.workerName}さんの残業を報告',
                  style: const TextStyle(color: _C.silver, fontSize: 13)),
              const SizedBox(height: 24),
              const Text('残業開始時刻', style: TextStyle(color: _C.silver, fontSize: 13)),
              const SizedBox(height: 8),
              _TimeField(label: _fmt(_startTime), onTap: () => _pickTime(true)),
              const SizedBox(height: 16),
              const Text('残業終了時刻（予定）', style: TextStyle(color: _C.silver, fontSize: 13)),
              const SizedBox(height: 8),
              _TimeField(
                  label: _endTime != null ? _fmt(_endTime!) : '-- : --',
                  onTap: () => _pickTime(false),
                  isEmpty: _endTime == null),
              const SizedBox(height: 16),
              const Text('残業内容', style: TextStyle(color: _C.silver, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _contentCtrl,
                maxLines: 3,
                style: const TextStyle(color: _C.offWhite),
                decoration: InputDecoration(
                  hintText: '例：2階電気配線追加工事',
                  hintStyle: const TextStyle(color: Color(0xFF666666)),
                  filled: true, fillColor: _C.gunmetal,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _C.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _C.divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _C.gold, width: 2)),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.warning, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('残業を報告する'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.label, required this.onTap, this.isEmpty = false});
  final String label;
  final VoidCallback onTap;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: _C.gunmetal, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _C.divider)),
        child: Row(children: [
          const Icon(Icons.access_time, color: _C.gold, size: 20),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(
              color: isEmpty ? _C.silver : _C.offWhite, fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          const Icon(Icons.edit, color: _C.silver, size: 16),
        ]),
      ),
    );
  }
}
