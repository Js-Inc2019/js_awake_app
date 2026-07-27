// ============================================================
// lib/screens/rest_day_screen.dart - 本日休み（登録・修正 兼用）
// 色は必ず js_colors.dart のトークン（JsColors / JsPalette / JsFormTokens）を使う。
// Color(0x 直書き・Colors.* は使わない。
// ============================================================

import 'package:flutter/material.dart';
import '../core/theme/js_colors.dart';
import '../services/reports_service.dart';
import '../main.dart' show showJsSnackbar;
import 'rest_day_done_screen.dart';

// 理由4値（null=未選択）。表示ラベルと BE キーの対応。
const List<Map<String, String>> _kReasons = [
  {'key': 'paid_leave',     'label': '有給'},
  {'key': 'absence',        'label': '欠勤'},
  {'key': 'company_closed', 'label': '会社休業'},
  {'key': 'personal',       'label': '私用'},
];

// 区分3値（既定=full）。単一選択・解除不可（必ずどれか1つ）。
const List<Map<String, String>> _kPortions = [
  {'key': 'full',    'label': '終日'},
  {'key': 'am_half', 'label': '午前休'},
  {'key': 'pm_half', 'label': '午後休'},
];

const List<String> _kWeekdayJa = ['月', '火', '水', '木', '金', '土', '日'];

class RestDayScreen extends StatefulWidget {
  const RestDayScreen({
    super.key,
    this.editMode = false,
    this.initialReason,
    this.initialPortion = 'full',
  });

  final bool editMode;          // false=新規登録 / true=修正
  final String? initialReason;  // 修正モードの初期 reason（null許容）
  final String initialPortion;  // 修正モードの初期 portion（full/am_half/pm_half）

  @override
  State<RestDayScreen> createState() => _RestDayScreenState();
}

class _RestDayScreenState extends State<RestDayScreen> {
  final ReportsService _svc = ReportsService();

  String? _selectedReason;
  String _selectedPortion = 'full';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 新規=未選択 / 修正=現在のreason
    _selectedReason = widget.editMode ? widget.initialReason : null;
    // 区分: 新規=終日(full) / 修正=現在のportion
    _selectedPortion = widget.editMode ? widget.initialPortion : 'full';
  }

  String _dateLabel() {
    final d = DateTime.now(); // 端末JST（表示用）
    final w = _kWeekdayJa[d.weekday - 1]; // weekday: 1=月..7=日
    return '${d.month}月${d.day}日（$w）';
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = widget.editMode
          ? await _svc.updateRestDay(reason: _selectedReason, portion: _selectedPortion)
          : await _svc.createRestDay(reason: _selectedReason, portion: _selectedPortion);

      final ok = res['success'] == true;
      // 新規登録で 409 ALREADY_RESTED は「既に休み」なので成功扱い（ねぎらい画面へ）。
      final alreadyRested = !widget.editMode &&
          (res['statusCode'] == 409 || res['code'] == 'ALREADY_RESTED');

      if (ok || alreadyRested) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => RestDayDoneScreen(
              reason: _selectedReason,
              portion: _selectedPortion,
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      showJsSnackbar(
        context,
        '${res['error'] ?? '休みの登録に失敗しました'}'
        '${res['statusCode'] != null ? '（${res['statusCode']}）' : ''}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRest() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JsColors.surface,
        title: const Text('本日の休み登録を取り消しますか？',
            style: TextStyle(color: JsColors.textStrong, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('戻る', style: TextStyle(color: JsColors.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('取消する',
                style: TextStyle(color: JsPalette.statusWarning)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final res = await _svc.deleteRestDay();
      if (res['success'] == true) {
        if (!mounted) return;
        Navigator.of(context).popUntil((r) => r.isFirst); // ホームへ（スタックを畳む）
        return;
      }
      if (!mounted) return;
      showJsSnackbar(
        context,
        '${res['error'] ?? '取り消しに失敗しました'}'
        '${res['statusCode'] != null ? '（${res['statusCode']}）' : ''}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.background,
      appBar: AppBar(
        backgroundColor: JsColors.surface,
        foregroundColor: JsColors.textStrong,
        elevation: 0,
        title: const Text('本日休み'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 日付表示（端末JST・表示用）
              Text(
                _dateLabel(),
                style: const TextStyle(
                    color: JsColors.textStrong,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              // 区分チップ3択（単一選択・解除不可＝必ずどれか1つ。既定=終日）
              const Text('区分',
                  style: TextStyle(color: JsColors.textMid, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _kPortions.map((p) {
                  final selected = _selectedPortion == p['key'];
                  return ChoiceChip(
                    label: Text(p['label']!),
                    selected: selected,
                    showCheckmark: false,
                    backgroundColor: JsColors.surface,
                    selectedColor: JsFormTokens.chipSelected,
                    side: BorderSide(
                        color: selected
                            ? JsFormTokens.chipSelected
                            : JsFormTokens.chipBorder),
                    labelStyle: TextStyle(
                      color: selected ? JsColors.textStrong : JsColors.textMid,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    // 解除不可: 常に選択キーを設定（再タップでも維持）
                    onSelected: (_) => setState(() => _selectedPortion = p['key']!),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              const Text('理由（任意）',
                  style: TextStyle(color: JsColors.textMid, fontSize: 13)),
              const SizedBox(height: 10),

              // 理由チップ4択（単一選択・再タップで解除）
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _kReasons.map((r) {
                  final selected = _selectedReason == r['key'];
                  return ChoiceChip(
                    label: Text(r['label']!),
                    selected: selected,
                    showCheckmark: false,
                    backgroundColor: JsColors.surface,
                    selectedColor: JsFormTokens.chipSelected,
                    side: BorderSide(
                        color: selected
                            ? JsFormTokens.chipSelected
                            : JsFormTokens.chipBorder),
                    labelStyle: TextStyle(
                      color: selected ? JsColors.textStrong : JsColors.textMid,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() {
                      // 再タップで解除（未選択に戻る）
                      _selectedReason = selected ? null : r['key'];
                    }),
                  );
                }).toList(),
              ),

              const SizedBox(height: 14),
              const Text(
                '※理由は任意です。有給は事務の確認後に休暇の記録へ反映されます。',
                style: TextStyle(color: JsColors.textMid, fontSize: 12),
              ),

              const SizedBox(height: 32),

              // 主ボタン（accent面・onAccent文字・高さ52）
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  // 生成り抜き（画面内の主ボタン）
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: JsFormTokens.outlineButtonBorder,
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor:
                        JsFormTokens.outlineButtonDisabled,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ).copyWith(
                    side: WidgetStateProperty.resolveWith((states) =>
                        BorderSide(
                          color: states.contains(WidgetState.disabled)
                              ? JsFormTokens.outlineButtonDisabled
                              : JsFormTokens.outlineButtonBorder,
                          width: 1.5,
                        )),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          // 面が透明になったのでスピナーも枠色（生成り）へ
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: JsFormTokens.outlineButtonDisabled))
                      : Text(
                          widget.editMode ? '変更を保存' : '休みを登録する',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              // 修正モードのみ：休みを取り消す
              if (widget.editMode) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _cancelRest,
                  child: const Text('休みを取り消す',
                      style: TextStyle(color: JsPalette.statusWarning)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
