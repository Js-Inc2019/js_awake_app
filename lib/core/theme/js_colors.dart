// lib/core/theme/js_colors.dart
// J's FIELD — Asphalt Dawn カラーパレット

import 'package:flutter/material.dart';

class JsColors {
  JsColors._();

  // ─── Asphalt Dawn ブランドカラー ────────────────────────────
  static const Color background    = Color(0xFF080806); // 背景メイン
  static const Color surfaceAlt    = Color(0xFF101008); // 背景サブ
  static const Color surface       = Color(0xFF181810); // カード背景
  static const Color border        = Color(0xFF242418); // ボーダー・区切り線
  static const Color divider       = Color(0xFF242418); // 区切り線エイリアス
  static const Color accent        = Color(0xFFA89868); // ゴールド砂埃（アクセント）
  static const Color textStrong    = Color(0xFFEDE8DC); // タイトル・強テキスト
  static const Color textWhite     = Color(0xFFFFFFFF); // 名前・重要数値
  static const Color textMid       = Color(0xFF686040); // ラベル
  static const Color textWeak      = Color(0xFF484830); // 非選択・サブ

  // ─── 後方互換エイリアス ──────────────────────────────────────
  static const Color black         = Color(0xFF080806);
  static const Color gunmetal      = Color(0xFF181810);
  static const Color gold          = Color(0xFFA89868);
  static const Color silver        = Color(0xFF484830);
  static const Color offWhite      = Color(0xFFEDE8DC);
  static const Color textPrimary   = Color(0xFFEDE8DC);
  static const Color textSecondary = Color(0xFF686040);

  // ─── セマンティックカラー ────────────────────────────────────
  static const Color error         = Color(0xFFFF4444);
  static const Color warning       = Color(0xFFFFB800);
  static const Color success       = Color(0xFF2E7D5E);

  // ─── 役割カラー（経験年数別）────────────────────────────────
  static const Color worker0 = Color(0xFFFF4444);
  static const Color worker1 = Color(0xFFFF8C00);
  static const Color worker2 = Color(0xFFFFB800);
  static const Color worker3 = Color(0xFF00C853);
  static const Color worker4 = Color(0xFF2979FF);
  static const Color worker5 = Color(0xFF00B4CC);
  static const Color worker6 = Color(0xFF7C4DFF);
  static const Color worker7 = Color(0xFFA89868);

  // ─── 職種カラー ─────────────────────────────────────────────
  static const Color foremanBase  = Color(0xFF7C4DFF);
  static const Color officeBase   = Color(0xFF00B4CC);
  static const Color bossGold     = Color(0xFFA89868);
  static const Color bossPlatinum = Color(0xFFE8E8E8);
  static const Color bossCrimson  = Color(0xFFC62828);

  // ─── 経験年数 → アクセントカラー ────────────────────────────
  static Color getWorkerAccent(int years) {
    if (years < 1) return worker0;
    if (years < 3) return worker2;
    if (years < 5) return worker3;
    if (years < 10) return worker4;
    if (years < 15) return worker5;
    if (years < 20) return worker6;
    return worker7;
  }

  static Color getForemanAccent(int foremanYears, int workerYears) {
    if (foremanYears >= 10) return foremanBase;
    if (foremanYears >= 5) {
      return Color.lerp(getWorkerAccent(workerYears), foremanBase, 0.6)!;
    }
    return Color.lerp(getWorkerAccent(workerYears), foremanBase, 0.3)!;
  }
}
