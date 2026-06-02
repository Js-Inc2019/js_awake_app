// lib/core/theme/js_colors.dart
// 株式会社J's 全アプリ共通カラー定義

import 'package:flutter/material.dart';

class JsColors {
  JsColors._();

  // ─── ベースカラー（全アプリ共通）───────────────────────────
  static const Color background   = Color(0xFF111111); // ガンメタ（背景）
  static const Color surface      = Color(0xFF1E1E1E); // カード背景
  static const Color surfaceAlt   = Color(0xFF2A2A2A); // gunmetal相当
  static const Color textPrimary  = Color(0xFFF5F5F5); // オフホワイト
  static const Color textSecondary= Color(0xFF9E9E9E); // グレー
  static const Color border       = Color(0xFF2E2E2E); // ボーダー
  static const Color divider      = Color(0xFF3A3A3A); // 区切り線
  static const Color error        = Color(0xFFFF4444); // エラー
  static const Color warning      = Color(0xFFFFB800); // 警告
  static const Color success      = Color(0xFF2E7D5E); // 成功

  // ─── 後方互換エイリアス（既存コード移行期間用）────────────
  static const Color black        = Color(0xFF111111);
  static const Color gunmetal     = Color(0xFF2A2A2A);
  static const Color gold         = Color(0xFFD4AF37);
  static const Color silver       = Color(0xFF9E9E9E);
  static const Color offWhite     = Color(0xFFF5F5F0);

  // ─── 役割カラー（経験年数別）──────────────────────────────
  /// 〜6ヶ月
  static const Color worker0 = Color(0xFFFF4444);
  /// 6ヶ月〜1年
  static const Color worker1 = Color(0xFFFF8C00);
  /// 1〜3年
  static const Color worker2 = Color(0xFFFFB800);
  /// 3〜5年
  static const Color worker3 = Color(0xFF00C853);
  /// 5〜10年
  static const Color worker4 = Color(0xFF2979FF);
  /// 10〜15年
  static const Color worker5 = Color(0xFF00B4CC);
  /// 15〜20年
  static const Color worker6 = Color(0xFF7C4DFF);
  /// 20年以上
  static const Color worker7 = Color(0xFFD4AF37);

  // ─── 職種カラー ───────────────────────────────────────────
  /// 職長ベースカラー
  static const Color foremanBase  = Color(0xFF7C4DFF);
  /// 事務固定カラー
  static const Color officeBase   = Color(0xFF00B4CC);
  /// 社長ゴールド
  static const Color bossGold     = Color(0xFFD4AF37);
  /// 社長プラチナ
  static const Color bossPlatinum = Color(0xFFE8E8E8);
  /// 社長クリムゾン
  static const Color bossCrimson  = Color(0xFFC62828);

  // ─── 経験年数 → アクセントカラー ────────────────────────
  /// 職人の経験年数からアクセントカラーを返す
  static Color getWorkerAccent(int years) {
    if (years < 1) return worker0;          // 〜6ヶ月（年単位なので0）
    if (years < 3) return worker2;          // 1〜3年
    if (years < 5) return worker3;          // 3〜5年
    if (years < 10) return worker4;         // 5〜10年
    if (years < 15) return worker5;         // 10〜15年
    if (years < 20) return worker6;         // 15〜20年
    return worker7;                         // 20年以上
  }

  /// 職長の職長年数・職人年数からアクセントカラーを返す
  static Color getForemanAccent(int foremanYears, int workerYears) {
    // 職長年数が長いほど foremanBase に近づく
    if (foremanYears >= 10) return foremanBase;
    if (foremanYears >= 5) {
      return Color.lerp(getWorkerAccent(workerYears), foremanBase, 0.6)!;
    }
    return Color.lerp(getWorkerAccent(workerYears), foremanBase, 0.3)!;
  }
}
