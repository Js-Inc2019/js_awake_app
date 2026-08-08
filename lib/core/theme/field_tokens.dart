// ============================================================
// lib/core/theme/field_tokens.dart - FIELD 意味名カラートークン（Asphalt Dawn / 暗）
//
// T5工程1で新設。旧 js_colors.dart の3クラス構成を置き換える唯一の色の入口。
// OFFICE 側 core/theme/office_tokens.dart と同型（単一クラス・意味名のみ）。
//
// ★命名原則: 名前は「何色か」ではなく「何に使うか」で付ける。
//   旧構成は「定数名は1つも変えない」制約下で値だけを差し替えたため、
//   gold の実体が #6FD6B4（エメラルド）、black の実体が #14161A（濃紺グレー）、
//   silver の実体が補助文字色…という name と value の乖離を後方互換エイリアスとして
//   抱えていた。T5でその制約が解除されたので、本ファイルはその嘘を持たない。
//
// ★値は旧構成の実値をそのまま採用しており、1つも変えていない。
//   T5工程1は「名前の付け替えと参照の一本化」だけで、見た目は 1px も変わらない。
//
// 使い分けの原則:
//   ・面   = bgBase（画面地） / surfaceCard（カード地） / surfaceRaised（入力欄・ナビ地）
//   ・境界 = outline（枠線・区切り） / outlineStrong（枠線強・選択中チップの面）
//   ・文字 = textBody（本文・値） / textSupport（ラベル・補助） /
//            textFaint（弱い補助・非活性） / textHint（placeholder 専用）
//   ・強調 = accent 系。押せるもの＝accent、見せるだけの顔＝brand と役割を分ける。
//   ・状態 = statusSuccess / statusWarning / statusError（＋塗り用の面と前景）
//   ・外部 = externalBlue（他社・外部）。自社＝accent との対比でのみ使う。
//   ・別系統 = wbgt*（環境省指針）／worker*・boss*（人物の役割）／toolBrand（他アプリの顔）。
//             意匠を変えてもこれらは動かさない。
// ============================================================

import 'package:flutter/material.dart';

class FieldTokens {
  FieldTokens._();

  // ─── 面（奥 → 手前）──────────────────────────────────────
  /// 画面地。Scaffold / AppBar の backgroundColor
  static const Color bgBase = Color(0xFF14161A);

  /// カード・ダイアログ・BottomSheet・SnackBar の面
  static const Color surfaceCard = Color(0xFF1C1F24);

  /// 入力欄・BottomNav・Drawer の面（surfaceCard より一段手前）
  static const Color surfaceRaised = Color(0xFF23272D);

  // ─── 境界 ────────────────────────────────────────────────
  /// 枠線・区切り線・未選択チップの枠
  static const Color outline = Color(0xFF2E333A);

  /// 枠線（強）。選択中チップの面にも使う。
  /// ★選択中チップを accent 面にしていないのは実測理由がある: この面の上の文字は
  ///   textBody(#EAE3D0) 固定で、面を accent(#6FD6B4) にすると 1.37:1 で読めない。
  ///   本トークン(#3A4048)なら 8.17:1 で判別できる。
  static const Color outlineStrong = Color(0xFF3A4048);

  // ─── 文字 ────────────────────────────────────────────────
  /// 本文・見出し・重要数値（生成り）。生成り抜きボタンの枠1.5px＋文字にも使う
  static const Color textBody = Color(0xFFEAE3D0);

  /// ラベル・補助テキスト・非強調アイコン（温グレー）
  static const Color textSupport = Color(0xFF7B7567);

  /// さらに弱い補助（GPS・注記）・非選択・無効時の枠と文字（温グレー弱）
  static const Color textFaint = Color(0xFF635F55);

  /// hint / placeholder 専用。入力面（surfaceRaised）に対し 3.14:1
  static const Color textHint = Color(0xFF787264);

  // ─── アクセント（押せるもの）──────────────────────────────
  /// 主要アクション・押せるもの・選択中・済バッジ・つまみ
  static const Color accent = Color(0xFF6FD6B4);

  /// accent 塗りの面に載る文字・アイコン。accent に対し 8.75:1
  static const Color onAccent = Color(0xFF0A2A21);

  /// 見出し・左線など副次的な強調（accent より暗い同系）
  static const Color accentDeep = Color(0xFF2A9A7C);

  // ─── ブランド ────────────────────────────────────────────
  /// ブランド色（淡い金）。タイトル・顔に使う。押せるものには使わない
  static const Color brand = Color(0xFFD9C08A);

  /// TOOL（ARC FLASH）ブランド色。TOOL の顔にのみ使う
  /// （home_screen.dart の AppBar にある TOOL 起動アイコン1箇所）
  static const Color toolBrand = Color(0xFF00E5CC);

  // ─── 外部・他社の識別 ────────────────────────────────────
  /// 他社・外部の識別色（自社＝accent との対比）。
  /// 天気の寒色（週間予報の最低気温・降水確率≥50%）も同値で扱う。
  /// ★T5工程2で externalBlue として独立。値は移行前の #4FC3F7 を温存
  static const Color externalBlue = Color(0xFF4FC3F7);

  // ─── カレンダー専用 ──────────────────────────────────────
  // 「その日の性質」を表す文字色。会社の休業日設定とは無関係に固定で、
  // セル塗り（会社休業日）とは意味が別（両方同時に出てよい）。
  // 文字色の優先順は 日曜(statusError) ＞ 祝日(holidayText) ＞ 土曜(saturday) ＞ 平日(textBody)。
  /// 祝日の文字色（朱）。OFFICE と同値
  static const Color holidayText = Color(0xFFD9705F);

  /// 土曜の文字色（水色）
  static const Color saturday = Color(0xFF6FA8D9);

  // ─── 状態 ────────────────────────────────────────────────
  /// 成功・済。★accent と同値だが意味が別なので定数を分けている
  /// （明るい面なので、塗り面として使う箇所の前景は onAccent にすること）
  static const Color statusSuccess = Color(0xFF6FD6B4);

  /// 未提出・警告。未入力バッジ（枠線＋文字）にも使う
  static const Color statusWarning = Color(0xFFE0603A);

  /// statusWarning 塗りの面に載る文字・アイコン（onAccent の warning 版）。
  /// 差戻し／修正依頼など「橙塗りのボタン」の前景
  static const Color onStatusWarning = Color(0xFF3D1E00);

  /// エラー。カレンダーの日曜文字色にも使う
  static const Color statusError = Color(0xFFE05252);

  /// 危険を「面」で示すときの地（暗赤）。改ざん検知行の行地など。
  /// 文字色の statusError とは役割が別で、surfaceCard の代わりに敷く
  static const Color statusErrorSurface = Color(0xFF3D1515);

  // ─── スクリム（半透明黒・面トークンでは表現できない重ね色）──────
  /// 写真の上に置く操作ボタンの下敷き（黒54%）
  static const Color scrimStrong = Color(0x8A000000);

  /// 画像読込失敗プレースホルダの地（黒26%）
  static const Color scrimWeak = Color(0x42000000);

  // ─── WBGT 熱中症危険度（環境省指針・外部由来）─────────────────
  // ★意匠トークン（面/文字/強調/状態）とは別系統。値の意味がアプリ外で
  //   決まっているため、テーマを変えてもこの5色は独立して扱う。
  //   OFFICE 側 core/theme/app_colors.dart の wbgtSafe〜wbgtDanger と同じ命名。
  //   区分は home_screen.dart の _wbgtColor()/_wbgtLabel() が使う 21/25/28/31。
  //   ★T5工程2で独立。それ以前は Safe が textSupport、Danger が statusError を
  //     流用しており「文字色トークンを段階色に使う」状態だった。値は温存＝見た目不変。
  /// ほぼ安全（wbgt < 21）
  static const Color wbgtSafe = Color(0xFF7B7567);
  /// 注意（21 ≤ wbgt < 25）
  static const Color wbgtCaution = Color(0xFF43A047);
  /// 警戒（25 ≤ wbgt < 28）
  static const Color wbgtWarning = Color(0xFFF9A825);
  /// 厳重警戒（28 ≤ wbgt < 31）
  static const Color wbgtSevere = Color(0xFFE65100);
  /// 危険（31 ≤ wbgt）
  static const Color wbgtDanger = Color(0xFFE05252);

  // ─── 経験カラー（経験年数別・ラベルと同じ4段階）──────────────
  // ★ラベル（profile_screen.dart:35-42 experienceTier）の境界 1/3/10/20 に
  //   色の境界を一致させた4本。移行前は8本（worker0〜worker7）で色の境界が
  //   1/3/5/10/15/20 だったため、同じラベルの中で色が変わる区分が2つあった
  //   （3-4年と5-9年＝共に「中堅」／10-14年と15-19年＝共に「ベテラン」）。
  // ★旧色は statusError(#FF4444) / statusWarning(#FFB800) と同値を流用していて
  //   状態色と混線していた。新色は状態色のどれとも重複しない値にしてある。
  /// 経験1〜2年（新人）。新芽
  static const Color workerNew = Color(0xFF8FBF6F);
  /// 経験3〜9年（中堅）。水色
  static const Color workerMid = Color(0xFF4FA3C4);
  /// 経験10〜19年（ベテラン）。藤
  static const Color workerVeteran = Color(0xFF7B6FD4);
  /// 経験20年〜（マスター）。鉄鼠
  static const Color workerMaster = Color(0xFF7D8A94);

  // ─── 職種カラー ─────────────────────────────────────────────
  /// 職長。membership_select_screen.dart:62 が boss ロールの識別色に使い、
  /// profile_screen.dart の役割バッジ・プレビューバッジも boss のとき本色を使う。
  /// ★値は #7C4DFF（旧 worker6 と同値の紫）から朱丹へ差し替えた。経験色に紫系
  ///   （workerVeteran #7B6FD4）が入るため、役割色と経験色が近似しないようにする。
  static const Color foremanBase = Color(0xFFD4664A);
  /// 事務。現状参照なし
  static const Color officeBase = Color(0xFF00B4CC);
  /// 社長（金）。現状参照なし
  static const Color bossGold = Color(0xFFA89868);
  /// 社長（白金）。現状参照なし
  static const Color bossPlatinum = Color(0xFFE8E8E8);
  /// 社長（深紅）。現状参照なし
  static const Color bossCrimson = Color(0xFFC62828);

  // ─── 経験年数 → 経験カラー ──────────────────────────────────
  /// 経験年数から経験カラーを引く。分岐の境界は experienceTier
  /// （profile_screen.dart:35-42）と同一で、同じラベルの中で色は変わらない。
  /// 参照元は profile_screen.dart:33 の experienceColor()。
  /// ★0年（years < 1）はラベルが空文字になる区分なので、色でも意味を主張しない
  ///   textSupport（ラベル・補助の温グレー :58）を返す。
  ///   ※本トークン群に textMid は無く、補助文字色の意味名は textSupport。
  static Color getWorkerAccent(int years) {
    if (years < 1)  return textSupport;
    if (years < 3)  return workerNew;
    if (years < 10) return workerMid;
    if (years < 20) return workerVeteran;
    return workerMaster;
  }
}
