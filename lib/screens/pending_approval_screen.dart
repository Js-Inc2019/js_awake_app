// lib/screens/pending_approval_screen.dart
import 'package:flutter/material.dart';
 import '../core/theme/js_colors.dart';
import 'home_screen.dart';

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JsColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('⏳', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 24),
                const Text(
                  '承認待ちです',
                  style: TextStyle(
                    color: JsColors.textStrong,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '管理者が承認すると\nフル機能が使えます',
                  style: TextStyle(
                    color: JsColors.textMid,
                    fontSize: 15,
                    height: 1.8,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  '現在は日報送信のみ\nご利用いただけます',
                  style: TextStyle(
                    color: JsColors.textMid,
                    fontSize: 15,
                    height: 1.8,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 52),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: JsColors.surface,
                      foregroundColor: JsColors.textStrong,
                      side: const BorderSide(color: JsColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '日報を送信する',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
