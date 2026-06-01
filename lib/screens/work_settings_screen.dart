// lib/screens/work_settings_screen.dart - 職長・事務用 勤務設定画面
import 'package:flutter/material.dart';
import '../main.dart' show JsColors, showJsSnackbar;
import '../services/work_settings_service.dart';

class WorkSettingsScreen extends StatefulWidget {
  const WorkSettingsScreen({super.key});
  @override
  State<WorkSettingsScreen> createState() => _WorkSettingsScreenState();
}

class _WorkSettingsScreenState extends State<WorkSettingsScreen> {
  List<Map<String, dynamic>> _workers = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await WorkSettingsService.instance.getAllSettings();
    if (mounted) setState(() { _workers = settings; _loading = false; });
  }

  Future<void> _editSetting(Map<String, dynamic> worker) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _SettingDialog(worker: worker),
    );
    if (result == null) return;
    final ok = await WorkSettingsService.instance.updateSetting(
      targetUserId: worker['worker_id'] as String,
      workMode:     result['work_mode'] as String,
      deemedStart:  result['deemed_start'] as String,
      deemedEnd:    result['deemed_end'] as String,
      breakMinutes: result['break_minutes'] as int,
    );
    if (mounted) {
      showJsSnackbar(context,
          ok ? '${worker['worker_name']}の設定を更新しました' : '更新に失敗しました',
          isError: !ok);
      if (ok) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('勤務設定管理'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
          : _workers.isEmpty
              ? const Center(
                  child: Text('職人が登録されていません',
                      style: TextStyle(color: JsColors.silver)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _workers.length,
                  itemBuilder: (_, i) {
                    final w        = _workers[i];
                    final mode     = w['work_mode'] as String? ?? 'deemed';
                    final start    = (w['deemed_start'] as String? ?? '08:00:00').substring(0, 5);
                    final end      = (w['deemed_end']   as String? ?? '17:00:00').substring(0, 5);
                    final breakMin = w['break_minutes'] as int? ?? 60;
                    final isDeemed = mode == 'deemed';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isDeemed
                              ? JsColors.gold.withValues(alpha: 0.2)
                              : JsColors.success.withValues(alpha: 0.2),
                          child: Icon(
                            isDeemed ? Icons.schedule : Icons.timer,
                            color: isDeemed ? JsColors.gold : JsColors.success,
                            size: 20,
                          ),
                        ),
                        title: Text(w['worker_name'] as String? ?? '',
                            style: const TextStyle(
                                color: JsColors.offWhite,
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          isDeemed
                              ? 'みなし: $start〜$end 休憩$breakMin分'
                              : '実勤務 休憩$breakMin分',
                          style: const TextStyle(
                              color: JsColors.silver, fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: JsColors.gold),
                          onPressed: () => _editSetting(w),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// 設定編集ダイアログ
class _SettingDialog extends StatefulWidget {
  const _SettingDialog({required this.worker});
  final Map<String, dynamic> worker;
  @override
  State<_SettingDialog> createState() => _SettingDialogState();
}

class _SettingDialogState extends State<_SettingDialog> {
  late String _mode;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late int _breakMin;

  @override
  void initState() {
    super.initState();
    _mode     = widget.worker['work_mode']     as String? ?? 'deemed';
    final s   = (widget.worker['deemed_start'] as String? ?? '08:00:00').substring(0, 5);
    final e   = (widget.worker['deemed_end']   as String? ?? '17:00:00').substring(0, 5);
    _start    = TimeOfDay(hour: int.parse(s.split(':')[0]), minute: int.parse(s.split(':')[1]));
    _end      = TimeOfDay(hour: int.parse(e.split(':')[0]), minute: int.parse(e.split(':')[1]));
    _breakMin = widget.worker['break_minutes'] as int? ?? 60;
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: JsColors.gold)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => isStart ? _start = picked : _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: JsColors.gunmetal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.worker['worker_name'] as String? ?? '',
          style: const TextStyle(color: JsColors.gold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 勤務モード切り替え
            const Text('勤務モード',
                style: TextStyle(color: JsColors.silver, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _mode = 'deemed'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _mode == 'deemed'
                          ? JsColors.gold.withValues(alpha: 0.2)
                          : JsColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _mode == 'deemed' ? JsColors.gold : JsColors.divider),
                    ),
                    child: Center(child: Text('みなし',
                        style: TextStyle(
                            color: _mode == 'deemed' ? JsColors.gold : JsColors.silver,
                            fontWeight: FontWeight.bold))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _mode = 'actual'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _mode == 'actual'
                          ? JsColors.success.withValues(alpha: 0.2)
                          : JsColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _mode == 'actual' ? JsColors.success : JsColors.divider),
                    ),
                    child: Center(child: Text('実勤務',
                        style: TextStyle(
                            color: _mode == 'actual' ? JsColors.success : JsColors.silver,
                            fontWeight: FontWeight.bold))),
                  ),
                ),
              ),
            ]),

            if (_mode == 'deemed') ...[
              const SizedBox(height: 16),
              const Text('開始時刻',
                  style: TextStyle(color: JsColors.silver, fontSize: 12)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _pickTime(true),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: JsColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: JsColors.divider),
                  ),
                  child: Row(children: [
                    const Icon(Icons.access_time, color: JsColors.gold, size: 18),
                    const SizedBox(width: 8),
                    Text(_fmtTime(_start),
                        style: const TextStyle(
                            color: JsColors.offWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              const Text('終了時刻',
                  style: TextStyle(color: JsColors.silver, fontSize: 12)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _pickTime(false),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: JsColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: JsColors.divider),
                  ),
                  child: Row(children: [
                    const Icon(Icons.access_time, color: JsColors.gold, size: 18),
                    const SizedBox(width: 8),
                    Text(_fmtTime(_end),
                        style: const TextStyle(
                            color: JsColors.offWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Text('休憩時間（分）',
                style: TextStyle(color: JsColors.silver, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              for (final min in [30, 45, 60, 90])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _breakMin = min),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _breakMin == min
                            ? JsColors.gold.withValues(alpha: 0.2)
                            : JsColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _breakMin == min ? JsColors.gold : JsColors.divider),
                      ),
                      child: Text('$min分',
                          style: TextStyle(
                              color: _breakMin == min ? JsColors.gold : JsColors.silver,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル',
              style: TextStyle(color: JsColors.silver)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {
            'work_mode':     _mode,
            'deemed_start':  _fmtTime(_start),
            'deemed_end':    _fmtTime(_end),
            'break_minutes': _breakMin,
          }),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
