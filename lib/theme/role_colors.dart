// lib/theme/role_colors.dart - 役割別カラーシステム（仕様準拠版）
import 'package:flutter/material.dart';

class RoleColors {
  // worker: 経験月数ベース 8段階 (0-6m:#FF4444 〜 20y+:#D4AF37)
  static Color forWorker(int experienceMonths) {
    if (experienceMonths < 6)   return const Color(0xFFFF4444);
    if (experienceMonths < 12)  return const Color(0xFFFF8C00);
    if (experienceMonths < 36)  return const Color(0xFFFFB800);
    if (experienceMonths < 60)  return const Color(0xFF00C853);
    if (experienceMonths < 120) return const Color(0xFF2979FF);
    if (experienceMonths < 180) return const Color(0xFF00B4CC);
    if (experienceMonths < 240) return const Color(0xFF7C4DFF);
    return const Color(0xFFD4AF37);
  }

  // boss: 職長年数ベース 5段階 (0-1y:#9C27B0 〜 10y+:#AA00FF)
  static Color forBoss(int foremanYears) {
    if (foremanYears < 1)  return const Color(0xFF9C27B0);
    if (foremanYears < 3)  return const Color(0xFF7B1FA2);
    if (foremanYears < 5)  return const Color(0xFF6A1B9A);
    if (foremanYears < 10) return const Color(0xFF4A148C);
    return const Color(0xFFAA00FF);
  }

  // admin_office: 固定
  static const Color adminOffice = Color(0xFF00B4CC);

  // デフォルト（未ログイン時）
  static const Color defaultColor = Color(0xFFD4AF37);

  // ─── ランク表示用ユーティリティ ───────────────────────────

  static String workerRank(int experienceMonths) {
    if (experienceMonths < 6)   return '見習い';
    if (experienceMonths < 12)  return '半人前';
    if (experienceMonths < 36)  return '一人前';
    if (experienceMonths < 60)  return '中堅';
    if (experienceMonths < 120) return 'ベテラン';
    if (experienceMonths < 180) return 'エキスパート';
    if (experienceMonths < 240) return '匠';
    return '名人';
  }

  static Widget rankBadge(int experienceMonths, {double fontSize = 10}) {
    final color = forWorker(experienceMonths);
    final rank  = workerRank(experienceMonths);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(rank,
          style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold)),
    );
  }

  // SharedPreferences 値からカラーを返すユーティリティ
  static Color fromPrefs({
    required String role,
    required int experienceMonths,
    int foremanYears = 0,
  }) {
    switch (role) {
      case 'boss':         return forBoss(foremanYears);
      case 'admin_office': return adminOffice;
      default:             return forWorker(experienceMonths);
    }
  }
}
