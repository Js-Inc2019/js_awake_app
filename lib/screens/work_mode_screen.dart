// ============================================================
// lib/screens/work_mode_screen.dart
// 実勤務用 出勤ボタン画面
// ============================================================
import 'package:flutter/material.dart';
import '../services/work_mode_service.dart';

class WorkModeScreen extends StatefulWidget {
  const WorkModeScreen({
    super.key,
    required this.onCheckedIn,
    required this.screenTitle,
    required this.isBossMode,
  });
  final VoidCallback onCheckedIn;
  final String screenTitle;
  final bool isBossMode;

  @override
  State<WorkModeScreen> createState() => _WorkModeScreenState();
}

class _WorkModeScreenState extends State<WorkModeScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  Future<void> _checkIn() async {
    if (_loading) return;
    setState(() => _loading = true);
    await WorkModeService.instance.checkIn();
    if (mounted) widget.onCheckedIn();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: const Color(0xFFD4AF37),
        title: Text(widget.screenTitle,
            style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  width: 180, height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.08 + _pulse.value * 0.08),
                  ),
                  child: Center(
                    child: Container(
                      width: 140, height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.15 + _pulse.value * 0.1),
                      ),
                      child: const Center(
                        child: Icon(Icons.login, color: Color(0xFFD4AF37), size: 64),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              const Text('出勤しますか？',
                  style: TextStyle(color: Color(0xFFF5F5F0), fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('ボタンを押した時刻で出勤打刻されます',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14)),
              const SizedBox(height: 48),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: SizedBox(
                  width: double.infinity, height: 64,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _checkIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    child: _loading
                        ? const SizedBox(width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                        : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.login, size: 24),
                            SizedBox(width: 10),
                            Text('出勤する'),
                          ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
