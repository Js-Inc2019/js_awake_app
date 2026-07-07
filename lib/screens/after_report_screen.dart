import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _C {
  static const black    = Color(0xFF111111);
  static const gunmetal = Color(0xFF2A2A2A);
  static const gold     = Color(0xFFD4AF37);
  static const silver   = Color(0xFF9E9E9E);
  static const offWhite = Color(0xFFF5F5F0);
  static const success  = Color(0xFF2E7D5E);
  static const navy     = Color(0xFF3949AB);
  static const warning  = Color(0xFFE65100);
}

class AfterReportScreen extends StatefulWidget {
  const AfterReportScreen({
    super.key,
    required this.workerName,
    required this.sent,
    required this.onMoveToNextSite,
    required this.onNightShift,
    required this.onOvertime,
    this.onRetry,
  });
  final String workerName;
  final bool sent;                       // 送信APIの成否（正直ゲート用）
  final VoidCallback onMoveToNextSite;
  final VoidCallback onNightShift;
  final Future<void> Function() onOvertime;
  final VoidCallback? onRetry;           // sent==false時の「今すぐ再送」

  @override
  State<AfterReportScreen> createState() => _AfterReportScreenState();
}

class _AfterReportScreenState extends State<AfterReportScreen> {
  bool _overtimeDone = false;  // 残業送信後に丸ボタンを消す

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,  // バックボタンで報告画面に戻れないようにする
      child: Scaffold(
        backgroundColor: _C.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 32),
                // ── 頭の表示は送信成否(sent)で正直に出し分け ──
                if (widget.sent) ...[
                  Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _C.success.withValues(alpha: 0.15),
                      border: Border.all(color: _C.success, width: 2),
                    ),
                    child: const Icon(Icons.check, color: _C.success, size: 48),
                  ),
                  const SizedBox(height: 20),
                  const Text('報告完了！',
                      style: TextStyle(color: _C.offWhite, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('${widget.workerName}さんの報告を送信しました',
                      style: const TextStyle(color: _C.silver, fontSize: 13)),
                ] else ...[
                  Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _C.warning.withValues(alpha: 0.15),
                      border: Border.all(color: _C.warning, width: 2),
                    ),
                    child: const Icon(Icons.schedule, color: _C.warning, size: 48),
                  ),
                  const SizedBox(height: 20),
                  const Text('未送信（再送待ち）',
                      style: TextStyle(color: _C.offWhite, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('${widget.workerName}さんの報告は保存されました',
                      style: const TextStyle(color: _C.silver, fontSize: 13)),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '通信状況により未送信です。電波の良い場所で自動再送されます。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _C.warning, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => widget.onRetry?.call(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('今すぐ再送'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _C.warning,
                      side: const BorderSide(color: _C.warning),
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                const Text('次のアクションを選択してください',
                    style: TextStyle(color: _C.silver, fontSize: 13)),
                const SizedBox(height: 16),

                // ⏰ 残業（丸ボタン・最上段）送信後に消える
                if (!_overtimeDone) ...[
                  GestureDetector(
                    onTap: () async {
                      await widget.onOvertime();
                      if (mounted) setState(() => _overtimeDone = true);
                    },
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _C.warning.withValues(alpha: 0.15),
                        border: Border.all(color: _C.warning, width: 2),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.more_time, color: _C.warning, size: 28),
                          SizedBox(height: 2),
                          Text('残業', style: TextStyle(color: _C.warning, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // 🚗 現場移動（スライド）
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

                const Spacer(),
                const Text('← スライドして選択',
                    style: TextStyle(color: _C.silver, fontSize: 11)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
  final bool _animating = false;
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
              duration: _animating ? const Duration(milliseconds: 120) : Duration.zero,
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

// OvertimeScreenはmain.dartの_OvertimeDialogに移行済み
// このファイルには不要
