// lib/theme/role_colors.dart - experience_months ベース動的カラー
import 'package:flutter/material.dart';

class RoleColors {
  static const Color _goldBase   = Color(0xFFD4AF37);
  static const Color _greenBase  = Color(0xFF2E7D5E);
  static const Color _blueBase   = Color(0xFF1565C0);
  static const Color _purpleBase = Color(0xFF6A1B9A);
  static const Color _redBase    = Color(0xFFB71C1C);

  // experience_months から職人の段位カラーを返す
  // 0-11月: 見習い（ゴールド）
  // 12-35月: 一人前（グリーン）
  // 36-71月: 中堅（ブルー）
  // 72-119月: ベテラン（パープル）
  // 120月+: 名人（レッドゴールド）
  static Color workerColor(int experienceMonths) {
    if (experienceMonths < 12)  return _goldBase;
    if (experienceMonths < 36)  return _greenBase;
    if (experienceMonths < 72)  return _blueBase;
    if (experienceMonths < 120) return _purpleBase;
    return _redBase;
  }

  // 段位ラベル
  static String workerRank(int experienceMonths) {
    if (experienceMonths < 12)  return '見習い';
    if (experienceMonths < 36)  return '一人前';
    if (experienceMonths < 72)  return '中堅';
    if (experienceMonths < 120) return 'ベテラン';
    return '名人';
  }

  // foreman_years から職長の段位カラーを返す
  static Color bossColor(int foremanYears) {
    if (foremanYears < 2)  return _goldBase;
    if (foremanYears < 5)  return _greenBase;
    if (foremanYears < 10) return _blueBase;
    if (foremanYears < 20) return _purpleBase;
    return _redBase;
  }

  // SharedPreferences から読み込んでカラーを返すユーティリティ
  static Color fromPrefs({
    required String role,
    required int experienceMonths,
    int foremanYears = 0,
  }) {
    if (role == 'boss') return bossColor(foremanYears);
    return workerColor(experienceMonths);
  }

  // バッジ用ウィジェット
  static Widget rankBadge(int experienceMonths, {double fontSize = 10}) {
    final color = workerColor(experienceMonths);
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
}
