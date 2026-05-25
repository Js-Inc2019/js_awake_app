import 'dart:io';
// lib/screens/after_report_screen.dart - 報告後画面（残業追加版）
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JsColors, fetchGpsAddress, showJsSnackbar;

const String _API_URL = 'https://js-office-api-prod-9ae070ebc5ba.herokuapp.com/api/v1';

class AfterReportScreen extends StatefulWidget {
  const AfterReportScreen({
    super.key,
    required this.workerName,
    required this.reportTime,
    this.gpsAddress = '',
    this.transport = '',
    this.workContent = '',
    this.reportType = 'daily',
    this.parkingPhotoPath,
    this.workPhotoPath,
  });
  final String workerName;
  final String reportTime;
  final String gpsAddress;
  final String transport;
  final String workContent;
  final String reportType;
  final String? parkingPhotoPath;
  final String? workPhotoPath;

  @override
  State<AfterReportScreen> createState() => _AfterReportScreenState();
}

class _AfterReportScreenState extends State<AfterReportScreen> {
  bool _processing = false;

  Future<void> _onMove() async {
    setState(() => _processing = true);
    final newAddress = await fetchGpsAddress();
    if (mounted) Navigator.pop(context, {'action': 'move', 'newAddress': newAddress});
  }

  void _onNightShift() {
    Navigator.pop(context, {'action': 'night_shift'});
  }

  bool _overtimeDone = false;

  Future<void> _onOvertime() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _OvertimeDialog(workerName: widget.workerName),
    );
    // 送信完了したら非表示
    if (mounted && result == true) setState(() => _overtimeDone = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: JsColors.success.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: JsColors.success, width: 2),
                ),
                child: const Icon(Icons.check_circle, color: JsColors.success, size: 56),
              ),
              const SizedBox(height: 24),
              const Text('報告完了！',
                  style: TextStyle(color: JsColors.offWhite, fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${widget.workerName} - ${widget.reportTime}',
                  style: const TextStyle(color: JsColors.silver, fontSize: 14)),
              const SizedBox(height: 48),
              // 送信詳細
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: JsColors.gunmetal,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: JsColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('送信内容',
                        style: TextStyle(color: JsColors.silver, fontSize: 11)),
                    const SizedBox(height: 8),
                    if (widget.gpsAddress.isNotEmpty)
                      Row(children: [
                        const Icon(Icons.location_on, color: JsColors.gold, size: 14),
                        const SizedBox(width: 4),
                        Expanded(child: Text(widget.gpsAddress,
                            style: const TextStyle(color: JsColors.offWhite, fontSize: 12),
                            maxLines: 2)),
                      ]),
                    if (widget.transport.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.directions, color: JsColors.silver, size: 14),
                        const SizedBox(width: 4),
                        Text(widget.transport,
                            style: const TextStyle(color: JsColors.offWhite, fontSize: 12)),
                      ]),
                    ],
                    if (widget.workContent.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.construction, color: JsColors.silver, size: 14),
                        const SizedBox(width: 4),
                        Expanded(child: Text(widget.workContent,
                            style: const TextStyle(color: JsColors.offWhite, fontSize: 12),
                            maxLines: 3)),
                      ]),
                    ],
                  ],
                ),
              ),
              // 写真枚数表示
              Builder(builder: (context) {
                final photoCount = (widget.parkingPhotoPath != null ? 1 : 0)
                                 + (widget.workPhotoPath    != null ? 1 : 0);
                if (photoCount == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    const Icon(Icons.photo_camera, color: JsColors.gold, size: 14),
                    const SizedBox(width: 4),
                    Text('写真 $photoCount枚添付',
                        style: const TextStyle(color: JsColors.gold, fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ]),
                );
              }),
              const SizedBox(height: 20),
              const Text('次の行動を選択',
                  style: TextStyle(color: JsColors.silver, fontSize: 14)),
              const SizedBox(height: 20),

              // 残業ボタン（最上段・丸ボタン）
              if (!_overtimeDone)
                GestureDetector(
                  onTap: _processing ? null : _onOvertime,
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: JsColors.warning,
                      boxShadow: [BoxShadow(
                        color: JsColors.warning.withValues(alpha: 0.4),
                        blurRadius: 16, spreadRadius: 2,
                      )],
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.more_time, color: Colors.white, size: 32),
                        SizedBox(height: 4),
                        Text('残業',
                            style: TextStyle(color: Colors.white,
                                fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _SlideButton(
                icon: Icons.directions_car, label: '現場移動',
                subLabel: 'GPS再取得して新しい報告へ',
                color: JsColors.gold,
                onSlide: _processing ? null : _onMove,
              ),
              const SizedBox(height: 12),
              _SlideButton(
                icon: Icons.nights_stay, label: '夜勤継続',
                subLabel: 'そのまま勤務を継続する',
                color: const Color(0xFF5C6BC0),
                onSlide: _processing ? null : _onNightShift,
              ),

              if (_processing) ...[
                const SizedBox(height: 32),
                const CircularProgressIndicator(color: JsColors.gold),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// 残業入力ダイアログ
class _OvertimeDialog extends StatefulWidget {
  const _OvertimeDialog({required this.workerName});
  final String workerName;
  @override
  State<_OvertimeDialog> createState() => _OvertimeDialogState();
}

class _OvertimeDialogState extends State<_OvertimeDialog> {
  TimeOfDay _start   = TimeOfDay.now();
  TimeOfDay _end     = TimeOfDay(
      hour: (TimeOfDay.now().hour + 2) % 24, minute: TimeOfDay.now().minute);
  final _contentCtrl = TextEditingController();
  bool _submitting   = false;

  @override
  void dispose() { _contentCtrl.dispose(); super.dispose(); }

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

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final now   = DateTime.now();
      await http.post(
        Uri.parse('$_API_URL/reports'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'worker_name':   widget.workerName,
          'report_date':   now.toIso8601String().substring(0, 10),
          'clock_in_time': '${_fmtTime(_start)}:00',
          'clock_out_time': '${_fmtTime(_end)}:00',
          'work_content':  '[残業] ${_contentCtrl.text.trim()}',
          'transport_type': 'other',
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: JsColors.gunmetal,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('⏰ 残業報告',
        style: TextStyle(color: JsColors.warning, fontWeight: FontWeight.bold)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _pickTime(true),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: JsColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JsColors.divider),
                ),
                child: Column(children: [
                  const Text('開始', style: TextStyle(color: JsColors.silver, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(_fmtTime(_start),
                      style: const TextStyle(color: JsColors.offWhite,
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, color: JsColors.silver),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _pickTime(false),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: JsColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JsColors.divider),
                ),
                child: Column(children: [
                  const Text('終了', style: TextStyle(color: JsColors.silver, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(_fmtTime(_end),
                      style: const TextStyle(color: JsColors.offWhite,
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _contentCtrl,
          maxLines: 3,
          style: const TextStyle(color: JsColors.offWhite),
          decoration: const InputDecoration(
            labelText: '残業内容',
            hintText: '例：配線工事の残り作業',
            prefixIcon: Icon(Icons.construction, color: JsColors.silver),
            alignLabelWithHint: true,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル', style: TextStyle(color: JsColors.silver)),
      ),
      ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
            backgroundColor: JsColors.warning, foregroundColor: Colors.white),
        child: _submitting
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('送信'),
      ),
    ],
  );
}

// スライドボタン
class _SlideButton extends StatefulWidget {
  const _SlideButton({
    super.key,
    required this.icon, required this.label, required this.subLabel,
    required this.color, required this.onSlide,
  });
  final IconData icon; final String label; final String subLabel;
  final Color color; final VoidCallback? onSlide;
  @override
  State<_SlideButton> createState() => _SlideButtonState();
}

class _SlideButtonState extends State<_SlideButton> {
  double _dragX  = 0;
  bool   _slid   = false;
  final  double _maxDrag = 220;

  void _onDragUpdate(DragUpdateDetails d) {
    if (widget.onSlide == null) return;
    setState(() {
      _dragX = (_dragX + d.delta.dx).clamp(0, _maxDrag);
      if (_dragX >= _maxDrag * 0.95 && !_slid) {
        _slid = true;
        widget.onSlide?.call();
      }
    });
  }

  void _onDragEnd(DragEndDetails d) {
    // 完了してなければ戻す
    if (!_slid) setState(() => _dragX = 0);
    // 残業など非同期処理後もリセット
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _dragX = 0; _slid = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = _dragX / _maxDrag;
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: JsColors.gunmetal,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: widget.color.withValues(alpha: 0.5)),
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            width: 72 + (_maxDrag * progress),
            height: 72,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(36),
            ),
          ),
          Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label, style: TextStyle(color: widget.color,
                  fontSize: 16, fontWeight: FontWeight.bold)),
              Text(widget.subLabel,
                  style: const TextStyle(color: JsColors.silver, fontSize: 11)),
            ],
          )),
          Positioned(
            left: _dragX,
            child: GestureDetector(
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd:    _onDragEnd,
              child: Container(
                width: 64, height: 64,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: widget.color, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: widget.color.withValues(alpha: 0.4),
                    blurRadius: 8, spreadRadius: 2,
                  )],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 28),
              ),
            ),
          ),
          Positioned(
            right: 20,
            child: Icon(Icons.chevron_right,
                color: widget.color.withValues(alpha: 0.5), size: 24),
          ),
        ],
      ),
    );
  }
}
