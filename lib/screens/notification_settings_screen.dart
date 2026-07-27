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

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final res = await _svc.saveNotificationSettings(
      reportRemindEnabled: _remindEnabled,
      remindTime1: _time1,
      remindTime2: _time2,
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

        // 保存ボタン（52px / 角丸10 / ゴールド）
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: JsColors.accent,
              foregroundColor: JsPalette.onAccent,
              disabledBackgroundColor:
                  JsColors.accent.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: JsPalette.onAccent),
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
