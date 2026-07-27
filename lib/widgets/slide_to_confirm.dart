// lib/widgets/slide_to_confirm.dart
import 'package:flutter/material.dart';
 import '../core/theme/js_colors.dart';

const _sliderGold = JsColors.accent;
const _sliderDark = JsPalette.onAccent;

class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirm,
    required this.busy,
    required this.icon,
    this.filled = true,
  });

  final String label;
  final Future<void> Function() onConfirm;
  final bool busy;
  final IconData icon;
  /// true = gold-filled handle (出勤・送信), false = outlined handle (退勤)
  final bool filled;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
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
            color: widget.filled
                ? _sliderGold.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _sliderGold, width: 1.5),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Text(
                  '→ ${widget.label}',
                  style: TextStyle(
                    color: _sliderGold.withValues(alpha: 0.45),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Positioned(
                left: cx + 4,
                top:  (88 - _handleH) / 2,
                child: Container(
                  width:  _handleSz,
                  height: _handleH,
                  decoration: BoxDecoration(
                    color: widget.filled ? _sliderGold : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: widget.filled
                        ? null
                        : Border.all(color: _sliderGold, width: 2),
                  ),
                  child: widget.busy
                      ? Center(
                          child: SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                              color: widget.filled ? _sliderDark : _sliderGold,
                              strokeWidth: 2.5,
                            ),
                          ),
                        )
                      : Icon(
                          widget.icon,
                          color: widget.filled ? _sliderDark : _sliderGold,
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
