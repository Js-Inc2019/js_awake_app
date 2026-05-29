// lib/screens/clock_in_screen.dart - 出勤ボタン画面（実勤務用）
import 'package:flutter/material.dart';
import '../main.dart' show JsColors, showJsSnackbar;
import '../services/work_mode_service.dart';

class ClockInScreen extends StatefulWidget {
  const ClockInScreen({super.key, required this.userName});
  final String userName;
  @override
  State<ClockInScreen> createState() => _ClockInScreenState();
}

class _ClockInScreenState extends State<ClockInScreen> {
  bool _processing = false;

  Future<void> _clockIn() async {
    setState(() => _processing = true);
    await WorkModeService.instance.checkIn();
    if (mounted) {
      showJsSnackbar(context, '出勤しました！');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now     = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';

    return Scaffold(
      backgroundColor: JsColors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.work, color: JsColors.gold, size: 80),
                const SizedBox(height: 24),
                Text(widget.userName,
                    style: const TextStyle(color: JsColors.offWhite,
                        fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(timeStr,
                    style: const TextStyle(color: JsColors.gold,
                        fontSize: 48, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('現在時刻',
                    style: TextStyle(color: JsColors.silver, fontSize: 14)),
                const SizedBox(height: 60),

                GestureDetector(
                  onTap: _processing ? null : _clockIn,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _processing
                          ? JsColors.success.withValues(alpha: 0.3)
                          : JsColors.success,
                      boxShadow: [BoxShadow(
                        color: JsColors.success.withValues(alpha: 0.4),
                        blurRadius: 30, spreadRadius: 5,
                      )],
                    ),
                    child: _processing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login, color: Colors.white, size: 48),
                              SizedBox(height: 8),
                              Text('出勤', style: TextStyle(color: Colors.white,
                                  fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text('ボタンを押した時刻で出勤打刻されます',
                    style: TextStyle(color: JsColors.silver, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
