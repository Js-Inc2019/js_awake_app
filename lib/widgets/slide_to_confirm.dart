// lib/widgets/slide_to_confirm.dart
 import 'package:flutter/material.dart';
 import '../core/theme/field_tokens.dart';

// ── 配色（新原則）─────────────────────────────────────────────────────────
//   枠＝生成り（押せるもの）／ポイント＝エメラルド（つまみ・満ちた面）。
//   トラック: 塗り無し・枠1.5px 生成り／ラベル: 生成り
//   つまみ  : accent 塗り・矢印 onAccent
//   完了時  : トラック全面 accent 塗り＋文言 onAccent＋
//             つまみは onAccent 地に accent のチェック（「満ちる」表現）
const _trackBorder = FieldTokens.textBody;
const _trackLabel  = FieldTokens.textBody;
const _knobFill    = FieldTokens.accent;
const _knobOn      = FieldTokens.onAccent;

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

  /// 呼び出し側のシグネチャ保全のため残している引数。
  /// 新配色ではトラック＝生成り枠／つまみ＝accent 塗りに一本化したため、
  /// 見た目の分岐には使っていない（出勤・退勤とも同一の見た目）。
  final bool filled;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dragX = 0;
  late final AnimationController _ctrl;
  Animation<double>? _anim;

  /// 確定コールバックを撃ったか。生涯1回だけ true になり、二度と false へ戻さない。
  /// _advance() の入口でこのフラグを見て弾くため、onConfirm の呼び出しは必ず1回。
  bool _fired = false;

  /// 確定済み＝「いったきり」。以後つまみは端に留まり、ドラッグを受け付けない。
  bool _confirmed = false;

  static const _handleSz  = 64.0;
  static const _handleH   = 72.0;

  /// この割合を超えたら、指を離さなくても端まで自動で走って確定する。
  static const _threshold = 0.60;

  static const _advanceMs = 150; // 自動で端まで走る
  static const _returnMs  = 250; // 始点へ戻る（キャンセル）

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _returnMs),
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

  // ── 確定（いったきり）────────────────────────────────────────────────
  // 端まで自動アニメ（150ms・easeOut）→ そのまま確定コールバックを発火。
  // 到達したつまみは戻さない。
  void _advance(double maxDrag) {
    if (_fired) return;          // ★発火は1回だけ。以降の呼び出しはここで落ちる。
    _fired = true;               // ★撃つ前に立てる（await 前に立てるので再入も不可）
    setState(() => _confirmed = true);
    _anim = Tween<double>(begin: _dragX, end: maxDrag).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.duration = const Duration(milliseconds: _advanceMs);
    _ctrl.forward(from: 0);
    widget.onConfirm().ignore(); // ★onConfirm の呼び出し箇所はこの1行のみ
  }

  // ── キャンセル（60%未満で指を離した時だけ）────────────────────────────
  void _snapBack() {
    _anim = Tween<double>(begin: _dragX, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.duration = const Duration(milliseconds: _returnMs);
    _ctrl.forward(from: 0);
  }

  bool get _locked => widget.busy || _confirmed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxDrag = constraints.maxWidth - _handleSz - 8.0;
      final cx      = _dragX.clamp(0.0, maxDrag < 0 ? 0.0 : maxDrag);

      return GestureDetector(
        // ハンドラは常に渡し、可否は中の _locked で判定する。
        // （ドラッグ中に確定してハンドラが null に差し替わると、
        //   進行中ジェスチャの終端が取りこぼされるため）
        onHorizontalDragStart: (_) {
          if (_locked) return;
          _ctrl.stop();
        },
        onHorizontalDragUpdate: (d) {
          if (_locked) return;
          final next = (_dragX + d.delta.dx).clamp(0.0, maxDrag < 0 ? 0.0 : maxDrag);
          setState(() => _dragX = next);
          // 指を離さなくても、60%を超えた瞬間に自動で端まで走って確定する
          if (maxDrag > 0 && next / maxDrag >= _threshold) _advance(maxDrag);
        },
        onHorizontalDragEnd: (_) {
          if (_locked) return; // 確定済みなら戻さない＝いったきり
          _snapBack();         // 60%未満で離した時だけ始点へ戻る
        },
        child: Container(
          width: double.infinity,
          height: 88,
          decoration: BoxDecoration(
            // 通常＝面は透明・枠1.5px 生成り／完了＝全面 accent 塗り
            color: _confirmed ? _knobFill : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _confirmed ? _knobFill : _trackBorder,
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Text(
                  '→ ${widget.label}',
                  style: TextStyle(
                    color: _confirmed ? _knobOn : _trackLabel,
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
                    // 通常＝accent 塗り／完了＝onAccent 地（accent 面に沈める）
                    color: _confirmed ? _knobOn : _knobFill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: widget.busy
                      ? Center(
                          child: SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                              color: _confirmed ? _knobFill : _knobOn,
                              strokeWidth: 2.5,
                            ),
                          ),
                        )
                      : Icon(
                          _confirmed ? Icons.check : widget.icon,
                          color: _confirmed ? _knobFill : _knobOn,
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
