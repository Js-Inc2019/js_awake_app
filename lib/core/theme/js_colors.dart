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

  // ─── アクション（次の行動を促す・危険ではない）────────────────
  // TOOL Arc Flash 由来のミュートシアン。移動・切替など「前へ進む」操作に使う。
  static const Color actionCyan    = Color(0xFF5ABEAA);

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

// ─────────────────────────────────────────────────────────────
// FIELD日報フォームv2の意味名トークン。将来OFFICE等へ同名で展開予定。
//
// ★別クラスにした理由（推測でなく事実）: 意味名 textPrimary が既存の
//   JsColors.textPrimary(#EDE8DC・後方互換エイリアス) と衝突する。
//   「既存定数は削除も改変もしない」を満たしつつ8つの意味名を揃って持つには
//   名前空間を分けるしかないため JsFormTokens として分離した。
//   JsColors 側は1行も触っていない＝他画面への影響ゼロ。
// ─────────────────────────────────────────────────────────────
class JsFormTokens {
  JsFormTokens._();

  static const Color bgBase       = Color(0xFF2C2C2C); // 地（ガンメタ）
  static const Color surfaceCard  = Color(0xFF242424); // カード（枠線なし・明度差のみ）
  static const Color textPrimary  = Color(0xFFF5F5F0); // オフホワイト（本文・見出し）
  static const Color textSub      = Color(0xFF8A9BA8); // シルバー（ラベル・補助）
  static const Color textMuted    = Color(0xFF7D8891); // さらに弱い補助（GPS・注記）
  static const Color chipSelected = Color(0xFF41474C); // 鋼（選択中チップの面）
  static const Color chipBorder   = Color(0xFF3D3D3D); // 未選択チップの枠
  static const Color accentAlert  = Color(0xFFE8A33D); // 琥珀（未入力バッジのみ・枠線+文字）
}
