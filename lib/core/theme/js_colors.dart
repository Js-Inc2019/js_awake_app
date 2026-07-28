// lib/core/theme/js_colors.dart
// J's FIELD — カラーパレット

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// 新配色パレット（確定13値）— 意味名のみ・値の単一出所
//
// ★別クラスにした理由（推測でなく事実）:
//   意味名として必要な background / surface / border / accent / error /
//   warning / success / textPrimary は、すべて既存 JsColors に同名の定数が
//   実在する（:100 以降）。リネーム禁止のため JsColors へ追記すると
//   名前衝突で追加できない。また JsFormTokens は :188 のコメントどおり
//   「FIELD日報フォームv2 専用」にスコープされており、アプリ全体の
//   パレットを置く場所ではない。
//   本ファイルは既に「衝突を避けるためクラスで名前空間を分ける」方式を
//   採用済み（:186-190 の JsFormTokens 分離）なので、その前例に従った。
//
//   以降、JsColors / JsFormTokens の各定数は「値」をこのクラスへ向け直す。
//   定数名は1つも変えていない（リネーム・削除なし）。
// ─────────────────────────────────────────────────────────────
class JsPalette {
  JsPalette._();

  // ─── 面（奥 → 手前）──────────────────────────────────────
  static const Color bgBase        = Color(0xFF14161A); // 背景
  static const Color surfaceCard   = Color(0xFF1C1F24); // カード
  static const Color surfaceRaised = Color(0xFF23272D); // カード副

  // ─── 境界 ────────────────────────────────────────────────
  static const Color outline       = Color(0xFF2E333A); // 枠線
  static const Color outlineStrong = Color(0xFF3A4048); // 枠線(強)

  // ─── 文字 ────────────────────────────────────────────────
  static const Color textBody      = Color(0xFFEAE3D0); // 本文（生成り）
  static const Color textSupport   = Color(0xFF7B7567); // 補助文字（温グレー）
  static const Color textFaint     = Color(0xFF635F55); // 弱い補助（温グレー弱）
  static const Color textHint      = Color(0xFF787264); // hint/placeholder専用・対入力面3.14:1

  // ─── アクセント ──────────────────────────────────────────
  static const Color accent        = Color(0xFF6FD6B4); // 主要アクション・押せるもの
  // ★アクセント塗りの上に乗る文字色。これが無いと accent 面上の文字が読めない。
  static const Color onAccent      = Color(0xFF0A2A21);
  static const Color accentDeep    = Color(0xFF2A9A7C); // 見出し・左線・副次的な強調

  // ─── ブランド ────────────────────────────────────────────
  // ★冒頭の「確定13値」外の追加トークン（onAccent と同じ扱い）。
  //   accent(エメラルド) と役割を分けるために新設した。
  static const Color brand         = Color(0xFFD9C08A); // ブランド色(淡い金): タイトル・顔。押せるものには使わない

  // ─── カレンダー専用 ──────────────────────────────────────
  // 「その日の性質」を表す文字色。休日設定（会社の休業日）とは無関係に固定で、
  // セル塗り（会社休業日）とは意味が別（両方同時に出てよい）。
  // 文字色の優先順は 日曜(statusError) ＞ 祝日(holidayText) ＞ 土曜(saturday) ＞ 平日(textBody)。
  static const Color holidayText   = Color(0xFFD9705F); // 祝日の文字色（朱）。OFFICE と同値
  static const Color saturday      = Color(0xFF6FA8D9); // 土曜の文字色（水色）

  // ─── 状態 ────────────────────────────────────────────────
  static const Color statusSuccess = Color(0xFF6FD6B4); // 成功/済（accent と同値）
  static const Color statusWarning = Color(0xFFE0603A); // 未提出/警告
  static const Color statusError   = Color(0xFFE05252); // エラー
}

class JsColors {
  JsColors._();

  // ─── ブランドカラー ─────────────────────────────────────
  static const Color background    = JsPalette.bgBase;        // 背景メイン
  static const Color surfaceAlt    = JsPalette.surfaceRaised;  // 背景サブ（入力欄/BottomNav/Drawer の面）
  static const Color surface       = JsPalette.surfaceCard;    // カード背景
  static const Color border        = JsPalette.outline;        // ボーダー・区切り線
  static const Color divider       = JsPalette.outline;        // 区切り線エイリアス
  static const Color accent        = JsPalette.accent;         // アクセント
  static const Color textStrong    = JsPalette.textBody;       // タイトル・強テキスト
  static const Color textWhite     = JsPalette.textBody;       // 名前・重要数値
  static const Color textMid       = JsPalette.textSupport;    // ラベル
  static const Color textWeak      = JsPalette.textFaint;      // 非選択・サブ・hint
  static const Color hint          = JsPalette.textHint;       // hint/placeholder専用

  // ─── 後方互換エイリアス ──────────────────────────────────
  // 名前は色名のまま（リネーム禁止）。値は「実際の用途」に合わせて割り当てた。
  static const Color black         = JsPalette.bgBase;      // 実体は背景色（Scaffold/AppBar の backgroundColor 専用）
  static const Color gunmetal      = JsPalette.surfaceCard; // 実体はカード面
  static const Color gold          = JsPalette.accent;      // 実体はアクセント
  static const Color silver        = JsPalette.textSupport; // 実体は補助文字（TextStyle 64件 / Icon 30件）
  static const Color offWhite      = JsPalette.textBody;    // 実体は本文
  static const Color textPrimary   = JsPalette.textBody;
  static const Color textSecondary = JsPalette.textSupport;

  // ─── セマンティックカラー ────────────────────────────────
  static const Color error         = JsPalette.statusError;
  static const Color warning       = JsPalette.statusWarning;
  // ★success は新配色 statusSuccess(#6FD6B4) へ差し替え済み。
  //   #6FD6B4 は明るい面なので、塗り面として使う箇所の前景を白のままにすると
  //   1.76:1 で読めなくなる。そのため下記6箇所の前景を JsPalette.onAccent
  //   (#0A2A21 / 8.75:1) へ同時に修正した。
  //     lib/screens/site_quick_register_screen.dart:183（＋:178 のスピナー）
  //     lib/screens/home_screen.dart:3025
  //     lib/screens/home_screen.dart:4553
  //     lib/screens/home_screen.dart:2612（_badgeDot・success のときのみ）
  //     lib/screens/home_screen.dart:4527-4538（承認SnackBar・ok のときのみ）
  //     lib/main.dart:782-788（showJsSnackbar・success のときのみ）
  //   文字/アイコン色としての用途（13箇所）は 3.0〜3.3:1 → 5.7〜10.3:1 へ改善する。
  static const Color success       = JsPalette.statusSuccess;

  // ─── アクション（次の行動を促す・危険ではない）────────────────
  // 「移動・切替など前へ進む操作」＝新配色の「アクセント（押せるもの）」に対応。
  static const Color actionCyan    = JsPalette.accent;

  // ─── 役割カラー（経験年数別）────────────────────────────────
  // ★新配色13値に役割色の指定が無いため値は未変更。次工程で要指定。
  static const Color worker0 = Color(0xFFFF4444);
  static const Color worker1 = Color(0xFFFF8C00);
  static const Color worker2 = Color(0xFFFFB800);
  static const Color worker3 = Color(0xFF00C853);
  static const Color worker4 = Color(0xFF2979FF);
  static const Color worker5 = Color(0xFF00B4CC);
  static const Color worker6 = Color(0xFF7C4DFF);
  static const Color worker7 = Color(0xFFA89868);

  // ─── 職種カラー ─────────────────────────────────────────────
  // ★同上・新配色に指定が無いため未変更。
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
//   JsColors.textPrimary(後方互換エイリアス) と衝突する。
//   「既存定数は削除も改変もしない」を満たしつつ8つの意味名を揃って持つには
//   名前空間を分けるしかないため JsFormTokens として分離した。
//   JsColors 側は1行も触っていない＝他画面への影響ゼロ。
// ─────────────────────────────────────────────────────────────
class JsFormTokens {
  JsFormTokens._();

  static const Color bgBase       = JsPalette.bgBase;        // 地
  static const Color surfaceCard  = JsPalette.surfaceCard;   // カード（枠線なし・明度差のみ）
  static const Color textPrimary  = JsPalette.textBody;      // 本文・見出し
  static const Color textSub      = JsPalette.textSupport;   // ラベル・補助
  static const Color textMuted    = JsPalette.textFaint;     // さらに弱い補助（GPS・注記）
  // ★選択中チップの面。アクセント色にはしていない。
  //   理由（実測）: この面の上の文字は home_screen.dart:2019 / 2055 / 3638 /
  //   3707 / 3824 で JsFormTokens.textPrimary(#EAE3D0) 固定。
  //   面を accent(#6FD6B4) にすると 1.37:1 で読めなくなる。
  //   枠線(強) #3A4048 なら 8.17:1 で、
  //   画面ファイルを一切変えずに選択状態が判別できる。
  static const Color chipSelected = JsPalette.outlineStrong;
  static const Color chipBorder   = JsPalette.outline;       // 未選択チップの枠
  static const Color accentAlert  = JsPalette.statusWarning; // 未入力バッジのみ（枠線+文字）

  // ─── 生成り抜きボタン（画面内の主ボタン）────────────────────
  // 新原則「枠＝生成り（押せるもの）／ポイント＝エメラルド（選択中・済・
  // バッジ・つまみ）／顔＝金」に基づく。画面内の主ボタンは accent 塗りを
  // やめ、面は透明・枠1.5px・文字を下記トークンで描く。
  //   ・ダイアログ内の主ボタンは対象外（accent 塗りのまま＝app_theme.dart:58-66
  //     の elevatedButtonTheme を継承する）。そのためテーマ側は変更していない。
  //   ・値は既存の JsColors.textStrong / textWeak を指すだけで新規hexは無い。
  static const Color outlineButtonBorder   = JsColors.textStrong; // 枠1.5px＋文字
  static const Color outlineButtonDisabled = JsColors.textWeak;   // 無効時の枠＋文字
}
