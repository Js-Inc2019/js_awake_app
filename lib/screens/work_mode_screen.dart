// lib/screens/work_mode_screen.dart
import 'package:flutter/material.dart';
import '../models/work_mode.dart';
import '../services/work_mode_service.dart';
import '../main.dart' show JsColors, showJsSnackbar, showConfirmDialog;

class WorkModeScreen extends StatefulWidget {
  const WorkModeScreen({super.key});
  @override
  State<WorkModeScreen> createState() => _WorkModeScreenState();
}

class _WorkModeScreenState extends State<WorkModeScreen> {
  WorkSession? _todaySession;
  String?      _activeId;
  bool         _loading    = true;
  bool         _processing = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final session  = await WorkModeService.instance.loadToday();
    final activeId = await WorkModeService.instance.getActiveId();
    if (mounted) setState(() {
      _todaySession = session;
      _activeId     = activeId;
      _loading      = false;
    });
  }

  Future<void> _startDeemed() async {
    if (_todaySession != null) {
      final ok = await showConfirmDialog(context,
        title: '上書き確認', message: '本日の勤務記録があります。\nみなし勤務で上書きしますか？',
        confirmText: '上書きする', isDanger: true);
      if (!ok) return;
    }
    setState(() => _processing = true);
    final s = await WorkModeService.instance.startDeemed();
    if (mounted) {
      setState(() { _todaySession = s; _activeId = null; _processing = false; });
      showJsSnackbar(context, 'みなし勤務を記録しました（8:00〜17:00）');
    }
  }

  Future<void> _clockIn() async {
    if (_todaySession != null) {
      final ok = await showConfirmDialog(context,
        title: '上書き確認', message: '本日の勤務記録があります。\n実勤務で上書きしますか？',
        confirmText: '上書きする', isDanger: true);
      if (!ok) return;
    }
    setState(() => _processing = true);
    final s = await WorkModeService.instance.clockIn();
    if (mounted) {
      setState(() { _todaySession = s; _activeId = s.id; _processing = false; });
      showJsSnackbar(context, '出勤しました（${s.clockInLabel}）');
    }
  }

  Future<void> _clockOut() async {
    final ok = await showConfirmDialog(context,
      title: '退勤確認', message: '退勤しますか？', confirmText: '退勤する');
    if (!ok) return;
    setState(() => _processing = true);
    final s = await WorkModeService.instance.clockOut();
    if (mounted) {
      setState(() { _todaySession = s; _activeId = null; _processing = false; });
      if (s != null) showJsSnackbar(context, '退勤しました（${s.clockOutLabel}） ${s.durationLabel}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('勤務モード'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JsColors.gold))
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TodayStatusCard(session: _todaySession, activeId: _activeId),
                    const SizedBox(height: 32),
                    const Text('本日の勤務タイプを選択',
                        style: TextStyle(color: JsColors.silver, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _ModeCard(
                      icon: Icons.schedule, title: 'みなし勤務',
                      subtitle: '8:00〜17:00 固定（タップ1回で完了）',
                      color: JsColors.gold,
                      isActive:   _todaySession?.mode == WorkModeType.deemed,
                      isDisabled: _processing || _activeId != null,
                      onTap: _startDeemed,
                    ),
                    const SizedBox(height: 12),
                    if (_activeId == null)
                      _ModeCard(
                        icon: Icons.login, title: '実勤務 - 出勤',
                        subtitle: '現在時刻で出勤打刻',
                        color: JsColors.success,
                        isActive: false, isDisabled: _processing,
                        onTap: _clockIn,
                      ),
                    if (_activeId != null)
                      _ModeCard(
                        icon: Icons.logout, title: '実勤務 - 退勤',
                        subtitle: '現在時刻で退勤打刻',
                        color: JsColors.error,
                        isActive: true, isDisabled: _processing,
                        onTap: _clockOut,
                      ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: JsColors.gunmetal, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: JsColors.divider),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline, color: JsColors.silver, size: 16),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          'みなし勤務は8:00〜17:00で自動記録。\n実勤務は出勤・退勤ボタンで実際の時刻を記録します。',
                          style: TextStyle(color: JsColors.silver, fontSize: 12, height: 1.5),
                        )),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _TodayStatusCard extends StatelessWidget {
  const _TodayStatusCard({required this.session, required this.activeId});
  final WorkSession? session;
  final String?      activeId;

  String _weekday(int w) => ['月','火','水','木','金','土','日'][(w-1)%7];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = '${now.year}年${now.month}月${now.day}日（${_weekday(now.weekday)}）';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: JsColors.gunmetal, borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: activeId != null ? JsColors.success : JsColors.divider,
          width: activeId != null ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(dateStr, style: const TextStyle(color: JsColors.silver, fontSize: 12)),
        const SizedBox(height: 8),
        if (session == null) ...[
          const Text('未記録', style: TextStyle(color: JsColors.offWhite, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('下のボタンから勤務タイプを選択してください', style: TextStyle(color: JsColors.silver, fontSize: 12)),
        ] else ...[
          Row(children: [
            Icon(session!.mode == WorkModeType.deemed ? Icons.schedule : Icons.timer,
                color: JsColors.gold, size: 20),
            const SizedBox(width: 8),
            Text(session!.mode == WorkModeType.deemed ? 'みなし勤務' : '実勤務',
                style: const TextStyle(color: JsColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (activeId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: JsColors.success, borderRadius: BorderRadius.circular(20)),
                child: const Text('勤務中', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            if (session!.isComplete && activeId == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: JsColors.divider, borderRadius: BorderRadius.circular(20)),
                child: const Text('完了', style: TextStyle(color: JsColors.silver, fontSize: 11)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _TimeChip(label: '出勤', time: session!.clockInLabel),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, color: JsColors.silver, size: 16),
            const SizedBox(width: 8),
            _TimeChip(label: '退勤', time: session!.clockOutLabel ?? '--:--', dim: session!.clockOutLabel == null),
            const Spacer(),
            Text(session!.durationLabel,
                style: const TextStyle(color: JsColors.gold, fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ],
      ]),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.time, this.dim = false});
  final String label; final String time; final bool dim;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: JsColors.silver, fontSize: 10)),
      Text(time, style: TextStyle(
        color: dim ? JsColors.silver : JsColors.offWhite,
        fontSize: 16, fontWeight: FontWeight.bold)),
    ],
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon, required this.title, required this.subtitle,
    required this.color, required this.isActive, required this.isDisabled, required this.onTap,
  });
  final IconData icon; final String title; final String subtitle;
  final Color color; final bool isActive; final bool isDisabled; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: isDisabled ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.15) : JsColors.gunmetal,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isActive ? color : JsColors.divider, width: isActive ? 2 : 1),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDisabled ? 0.1 : 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: isDisabled ? JsColors.silver : color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(
            color: isDisabled ? JsColors.silver : JsColors.offWhite,
            fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: JsColors.silver, fontSize: 12)),
        ])),
        Icon(Icons.chevron_right, color: isDisabled ? JsColors.divider : color),
      ]),
    ),
  );
}
