// ============================================================
// lib/screens/notification_settings_screen.dart - 通知設定
// 日報リマインダ ON/OFF・時刻1/時刻2（10分刻み・枠OFF=null送信）
// ============================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../main.dart' show showJsSnackbar;
import '../core/theme/js_colors.dart';
import '../services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _svc = NotificationService();

  bool _loading = true;
  bool _error = false;
  bool _saving = false;

  bool _remindEnabled = true;
  String? _time1; // null = 枠OFF（この時刻は通知しない）
  String? _time2;

  // 「通知しない」を解除したときに復元する直近の時刻
  String _lastTime1 = '12:00';
  String _lastTime2 = '15:00';

  // ── 打刻のお知らせ（BE: notification_settings.punch_remind_*）──────────
  //   方式は2択: 'after'=定刻後○分（10分刻み・10〜60）/ 'at'=○時に通知（分は00固定）。
  //   ★どちらの値が有効かは mode だけが決める（BE と同じ裁定者）。
  //   既定は 有効ON / 'after' / 30分（BE の DEFAULTS と同値）。
  bool   _punchInEnabled  = true;
  String _punchInMode     = 'after';
  int    _punchInAfterMin = 30;
  String? _punchInAt;                 // 'HH:00'。mode='after' の間は null でよい
  bool   _punchOutEnabled  = true;
  String _punchOutMode     = 'after';
  int    _punchOutAfterMin = 30;
  String? _punchOutAt;
  // 'at' へ切り替えたときの初期値。BE は 'at' に既定を持たないので画面側で用意する
  //（mode='at' かつ時刻なしの PUT は BE が 400 にする）。
  String _lastPunchInAt  = '08:00';
  String _lastPunchOutAt = '18:00';

  static const _afterPresets = [10, 20, 30, 40, 50, 60];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final res = await _svc.fetchNotificationSettings();
    if (!mounted) return;
    if (res['success'] == true) {
      final s = Map<String, dynamic>.from(res['settings'] as Map);
      setState(() {
        _remindEnabled = s['report_remind_enabled'] == true;
        _time1 = _asTime(s['remind_time1']);
        _time2 = _asTime(s['remind_time2']);
        if (_time1 != null) _lastTime1 = _time1!;
        if (_time2 != null) _lastTime2 = _time2!;
        // 打刻のお知らせ。BE が既定（行なし）を返す場合も同じ形で入ってくる。
        _punchInEnabled  = s['punch_remind_in_enabled'] != false;
        _punchInMode     = s['punch_remind_in_mode'] == 'at' ? 'at' : 'after';
        _punchInAfterMin = _asAfterMin(s['punch_remind_in_after_min']);
        _punchInAt       = _asTime(s['punch_remind_in_at']);
        _punchOutEnabled  = s['punch_remind_out_enabled'] != false;
        _punchOutMode     = s['punch_remind_out_mode'] == 'at' ? 'at' : 'after';
        _punchOutAfterMin = _asAfterMin(s['punch_remind_out_after_min']);
        _punchOutAt       = _asTime(s['punch_remind_out_at']);
        if (_punchInAt  != null) _lastPunchInAt  = _punchInAt!;
        if (_punchOutAt != null) _lastPunchOutAt = _punchOutAt!;
        _loading = false;
        _error = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  // 'HH:MM' または 'HH:MM:SS' → 'HH:MM'（それ以外/nullはnull）
  String? _asTime(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.length >= 5) return s.substring(0, 5);
    return null;
  }

  // BE の after_min（10〜60の10分刻み）を安全に受ける。想定外は既定30へ倒す。
  int _asAfterMin(dynamic v) {
    if (v is int && v >= 10 && v <= 60 && v % 10 == 0) return v;
    return 30;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final res = await _svc.saveNotificationSettings(
      reportRemindEnabled: _remindEnabled,
      remindTime1: _time1,
      remindTime2: _time2,
      // 打刻のお知らせ。mode='at' のときは時刻を必ず載せる（null だと BE が 400）。
      punchRemindInEnabled:  _punchInEnabled,
      punchRemindInMode:     _punchInMode,
      punchRemindInAfterMin: _punchInAfterMin,
      punchRemindInAt:       _punchInMode == 'at' ? (_punchInAt ?? _lastPunchInAt) : _punchInAt,
      punchRemindOutEnabled:  _punchOutEnabled,
      punchRemindOutMode:     _punchOutMode,
      punchRemindOutAfterMin: _punchOutAfterMin,
      punchRemindOutAt:       _punchOutMode == 'at' ? (_punchOutAt ?? _lastPunchOutAt) : _punchOutAt,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      showJsSnackbar(context, '保存しました');
      Navigator.pop(context);
    } else {
      // 失敗時はエラーSnackBarで留まる（袋小路なし）
      showJsSnackbar(context, '保存に失敗しました。通信環境をご確認ください',
          isError: true);
    }
  }

  // 10分刻みTimePicker（分は00,10,20,30,40,50のみ）
  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final parts = current.split(':');
    int hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 12;
    int minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    // 分を10分刻みに丸め
    minute = (minute ~/ 10) * 10;
    hour = hour.clamp(0, 23);

    int selHour = hour;
    int selMinIndex = (minute ~/ 10).clamp(0, 5);
    const minuteOptions = [0, 10, 20, 30, 40, 50];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JsColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('キャンセル',
                            style: TextStyle(color: JsColors.textMid)),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          final h = selHour.toString().padLeft(2, '0');
                          final m = minuteOptions[selMinIndex]
                              .toString()
                              .padLeft(2, '0');
                          onPicked('$h:$m');
                          Navigator.pop(ctx);
                        },
                        child: const Text('決定',
                            style: TextStyle(
                                color: JsColors.accent,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: JsColors.border),
                Expanded(
                  child: Row(
                    children: [
                      // 時
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                              initialItem: selHour),
                          itemExtent: 40,
                          backgroundColor: JsColors.surface,
                          onSelectedItemChanged: (i) => selHour = i,
                          children: [
                            for (int h = 0; h < 24; h++)
                              Center(
                                child: Text('${h.toString().padLeft(2, '0')}時',
                                    style: const TextStyle(
                                        color: JsColors.textStrong,
                                        fontSize: 20)),
                              ),
                          ],
                        ),
                      ),
                      // 分（10分刻み）
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                              initialItem: selMinIndex),
                          itemExtent: 40,
                          backgroundColor: JsColors.surface,
                          onSelectedItemChanged: (i) => selMinIndex = i,
                          children: [
                            for (final m in minuteOptions)
                              Center(
                                child: Text('${m.toString().padLeft(2, '0')}分',
                                    style: const TextStyle(
                                        color: JsColors.textStrong,
                                        fontSize: 20)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 1時間刻みピッカー（分は00固定）。打刻のお知らせの 'at' 方式で使う。
  // ★_pickTime(:98) は日報リマインダ用（10分刻み）でそのまま。あちらは1文字も変えない。
  //   様式（BottomSheet・キャンセル/決定・CupertinoPicker・トークン）は _pickTime に合わせる。
  Future<void> _pickHour(String current, ValueChanged<String> onPicked) async {
    final parts = current.split(':');
    int selHour = (int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8).clamp(0, 23);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JsColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('キャンセル',
                            style: TextStyle(color: JsColors.textMid)),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          onPicked('${selHour.toString().padLeft(2, '0')}:00');
                          Navigator.pop(ctx);
                        },
                        child: const Text('決定',
                            style: TextStyle(
                                color: JsColors.accent,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: JsColors.border),
                Expanded(
                  child: CupertinoPicker(
                    scrollController:
                        FixedExtentScrollController(initialItem: selHour),
                    itemExtent: 40,
                    backgroundColor: JsColors.surface,
                    onSelectedItemChanged: (i) => selHour = i,
                    children: [
                      for (int h = 0; h < 24; h++)
                        Center(
                          child: Text('${h.toString().padLeft(2, '0')}時',
                              style: const TextStyle(
                                  color: JsColors.textStrong, fontSize: 20)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.background,
      appBar: AppBar(
        backgroundColor: JsColors.background,
        title: const Text('通知設定'),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: JsColors.accent));
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: JsColors.textMid, size: 48),
            const SizedBox(height: 12),
            const Text('設定を読み込めませんでした',
                style: TextStyle(color: JsColors.textMid, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('再試行'),
              style: OutlinedButton.styleFrom(
                foregroundColor: JsColors.accent,
                side: const BorderSide(color: JsColors.accent),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // a. 日報リマインダ ON/OFF
        Container(
          decoration: BoxDecoration(
            color: JsColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JsColors.border),
          ),
          child: SwitchListTile(
            value: _remindEnabled,
            onChanged: (v) => setState(() => _remindEnabled = v),
            activeThumbColor: JsColors.accent,
            title: const Text('日報リマインダ',
                style: TextStyle(
                    color: JsColors.textStrong,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            subtitle: const Text('未提出の日に通知でお知らせします',
                style: TextStyle(color: JsColors.textMid, fontSize: 12)),
          ),
        ),
        const SizedBox(height: 20),

        // b. 時刻1・時刻2
        Text('通知する時刻',
            style: TextStyle(
                color: _remindEnabled
                    ? JsColors.textMid
                    : JsColors.textWeak,
                fontSize: 12)),
        const SizedBox(height: 8),
        _TimeRow(
          label: '時刻1',
          time: _time1,
          enabled: _remindEnabled,
          onTapTime: () => _pickTime(_time1 ?? _lastTime1, (v) {
            setState(() {
              _time1 = v;
              _lastTime1 = v;
            });
          }),
          onToggleOff: (off) {
            setState(() {
              if (off) {
                if (_time1 != null) _lastTime1 = _time1!;
                _time1 = null; // 枠OFF
              } else {
                _time1 = _lastTime1;
              }
            });
          },
        ),
        const SizedBox(height: 10),
        _TimeRow(
          label: '時刻2',
          time: _time2,
          enabled: _remindEnabled,
          onTapTime: () => _pickTime(_time2 ?? _lastTime2, (v) {
            setState(() {
              _time2 = v;
              _lastTime2 = v;
            });
          }),
          onToggleOff: (off) {
            setState(() {
              if (off) {
                if (_time2 != null) _lastTime2 = _time2!;
                _time2 = null; // 枠OFF
              } else {
                _time2 = _lastTime2;
              }
            });
          },
        ),
        const SizedBox(height: 16),

        // d. 注記
        const Text('日報を提出済みの日は通知されません',
            style: TextStyle(color: JsColors.textWeak, fontSize: 12)),
        const SizedBox(height: 32),

        // ── 打刻のお知らせ（出勤／退勤）────────────────────────────
        const Text('打刻のお知らせ',
            style: TextStyle(color: JsColors.textMid, fontSize: 12)),
        const SizedBox(height: 8),
        _PunchRemindCard(
          title: '出勤の打刻',
          subtitle: '出勤の打刻が無いときにお知らせします',
          enabled: _punchInEnabled,
          onEnabled: (v) => setState(() => _punchInEnabled = v),
          mode: _punchInMode,
          onMode: (m) => setState(() {
            _punchInMode = m;
            // 'at' へ切り替えたら時刻を確定させる（BE は 'at' に既定を持たない）
            if (m == 'at') _punchInAt ??= _lastPunchInAt;
          }),
          afterMin: _punchInAfterMin,
          afterPresets: _afterPresets,
          onAfterMin: (v) => setState(() => _punchInAfterMin = v),
          at: _punchInAt ?? _lastPunchInAt,
          onTapAt: () => _pickHour(_punchInAt ?? _lastPunchInAt, (v) {
            setState(() {
              _punchInAt = v;
              _lastPunchInAt = v;
            });
          }),
        ),
        const SizedBox(height: 10),
        _PunchRemindCard(
          title: '退勤の打刻',
          subtitle: '退勤の打刻が無いときにお知らせします',
          enabled: _punchOutEnabled,
          onEnabled: (v) => setState(() => _punchOutEnabled = v),
          mode: _punchOutMode,
          onMode: (m) => setState(() {
            _punchOutMode = m;
            if (m == 'at') _punchOutAt ??= _lastPunchOutAt;
          }),
          afterMin: _punchOutAfterMin,
          afterPresets: _afterPresets,
          onAfterMin: (v) => setState(() => _punchOutAfterMin = v),
          at: _punchOutAt ?? _lastPunchOutAt,
          onTapAt: () => _pickHour(_punchOutAt ?? _lastPunchOutAt, (v) {
            setState(() {
              _punchOutAt = v;
              _lastPunchOutAt = v;
            });
          }),
        ),
        const SizedBox(height: 16),
        const Text('※定時はOFFICEの勤怠設定で登録します',
            style: TextStyle(color: JsColors.textWeak, fontSize: 12)),
        const SizedBox(height: 32),

        // 保存ボタン（52px / 角丸10 / ゴールド）
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            // 生成り抜き（画面内の主ボタン）
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: JsFormTokens.outlineButtonBorder,
              disabledBackgroundColor: Colors.transparent,
              disabledForegroundColor: JsFormTokens.outlineButtonDisabled,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) => BorderSide(
                    color: states.contains(WidgetState.disabled)
                        ? JsFormTokens.outlineButtonDisabled
                        : JsFormTokens.outlineButtonBorder,
                    width: 1.5,
                  )),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    // 面が透明になったのでスピナーも枠色（生成り）へ
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: JsFormTokens.outlineButtonDisabled),
                  )
                : const Text('保存する',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}

// ─── 打刻のお知らせカード（出勤／退勤で共用）─────────────────────
// 構成は既存カード（:248-266 の SwitchListTile カード）と同じ器:
//   Container(surface / radius 12 / border) の中に SwitchListTile。
//   ON のときだけ「方式2択」と「値」を下に出す（OFF で操作欄を残さない）。
// 色は既存トークンのみ（JsColors.accent / border / surface / textStrong / textMid / textWeak）。
class _PunchRemindCard extends StatelessWidget {
  const _PunchRemindCard({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onEnabled,
    required this.mode,          // 'after' | 'at'
    required this.onMode,
    required this.afterMin,
    required this.afterPresets,
    required this.onAfterMin,
    required this.at,            // 'HH:00'（表示用・null は呼び出し側で解決済み）
    required this.onTapAt,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onEnabled;
  final String mode;
  final ValueChanged<String> onMode;
  final int afterMin;
  final List<int> afterPresets;
  final ValueChanged<int> onAfterMin;
  final String at;
  final VoidCallback onTapAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JsColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: onEnabled,
            activeThumbColor: JsColors.accent,
            title: Text(title,
                style: const TextStyle(
                    color: JsColors.textStrong,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle,
                style: const TextStyle(color: JsColors.textMid, fontSize: 12)),
          ),
          if (enabled) ...[
            const Divider(height: 1, color: JsColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('知らせ方',
                      style: TextStyle(color: JsColors.textMid, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _modeButton('定刻後に知らせる', 'after')),
                    const SizedBox(width: 8),
                    Expanded(child: _modeButton('時刻で知らせる', 'at')),
                  ]),
                  const SizedBox(height: 16),
                  if (mode == 'after') ...[
                    const Text('定刻から',
                        style:
                            TextStyle(color: JsColors.textMid, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in afterPresets) _afterChip(m),
                      ],
                    ),
                  ] else ...[
                    const Text('知らせる時刻',
                        style:
                            TextStyle(color: JsColors.textMid, fontSize: 12)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: onTapAt,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 48, // タッチターゲット 44pt以上
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: JsColors.border),
                        ),
                        child: Row(children: [
                          Text(at,
                              style: const TextStyle(
                                  color: JsColors.textStrong,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          const Icon(Icons.expand_more,
                              color: JsColors.textMid, size: 18),
                        ]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 方式の2択。選択＝accent 枠＋accent 文字（既存の再試行ボタン :234-237 と同じ配色）。
  Widget _modeButton(String label, String value) {
    final sel = mode == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onMode(value),
      child: Container(
        height: 44, // タッチターゲット 44pt
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: sel ? JsColors.accent : JsColors.border,
              width: sel ? 1.5 : 1),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1,
                style: TextStyle(
                  color: sel ? JsColors.accent : JsColors.textMid,
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                )),
          ),
        ),
      ),
    );
  }

  // 「定刻後○分」のプリセット。10分刻み（BE の CHECK と一致）。
  Widget _afterChip(int m) {
    final sel = afterMin == m;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onAfterMin(m),
      child: Container(
        constraints: const BoxConstraints(minWidth: 64, minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: sel ? JsColors.accent : JsColors.border,
              width: sel ? 1.5 : 1),
        ),
        child: Text('$m分',
            style: TextStyle(
              color: sel ? JsColors.accent : JsColors.textMid,
              fontSize: 14,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }
}

// ─── 時刻行（現在値表示＋タップでピッカー＋「通知しない」トグル）───
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.time,
    required this.enabled,
    required this.onTapTime,
    required this.onToggleOff,
  });

  final String label;
  final String? time; // null = この時刻は通知しない（枠OFF）
  final bool enabled; // 日報リマインダ全体がONか（OFFならグレーアウト）
  final VoidCallback onTapTime;
  final ValueChanged<bool> onToggleOff; // true=通知しない

  @override
  Widget build(BuildContext context) {
    final off = time == null;
    // 全体OFF時はグレーアウト（操作不可）
    final Color labelColor = enabled ? JsColors.textMid : JsColors.textWeak;
    final Color valueColor = !enabled
        ? JsColors.textWeak
        : (off ? JsColors.textWeak : JsColors.textStrong);

    return Container(
      decoration: BoxDecoration(
        color: JsColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JsColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          // 時刻表示（タップでピッカー・OFF時/全体OFF時は操作不可）
          Expanded(
            child: InkWell(
              onTap: (enabled && !off) ? onTapTime : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Text(label,
                        style: TextStyle(color: labelColor, fontSize: 13)),
                    const SizedBox(width: 14),
                    Text(
                      off ? 'オフ' : time!,
                      style: TextStyle(
                        color: valueColor,
                        fontSize: off ? 15 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (enabled && !off) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.expand_more,
                          color: JsColors.textMid, size: 18),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 「この時刻は通知しない」トグル
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('通知しない',
                  style: TextStyle(
                      color: enabled ? JsColors.textWeak : JsColors.textWeak,
                      fontSize: 10)),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: off,
                  onChanged: enabled ? onToggleOff : null,
                  activeThumbColor: JsColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
