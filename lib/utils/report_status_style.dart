// lib/utils/report_status_style.dart
// 日報の4状態を「画面に出す色と語」へ変える唯一の対応表。
//
// ★なぜ1ファイルに集めるか（実際に起きていた食い違いの形）:
//   状態→色・語の switch が画面ごとに手書きされていて、同じ状態が
//   画面によって違う色で出ていた。実測した食い違いは2つ:
//     ・未承認 … 月間履歴の絞り込みチップと日付グループ行は statusWarning（橙）、
//                 日報1行と日報の詳細は textSupport（温グレー）。同じ「未承認」が
//                 画面によって橙と灰の2色あった。
//     ・取消済 … 全箇所 textSupport で、上の未承認（灰）と同じ色だった。
//                 色では見分けられず、語を読むまで区別できなかった。
//   同じ式が何箇所にも手書きされていたことが原因なので、式そのものをここへ1本にする。
//   （前例: lib/utils/report_cancel_gate.dart。判定を各画面に手書きした結果
//     「どこかだけ直し忘れる」形が構造的に残った、という同じ趣旨で作られている。
//     あちらが「どの状態か」を1本にし、こちらが「その状態をどう描くか」を1本にする。）
//
// ★なぜ lib/utils に置くか（家風を読んだ結果）:
//   ・この表は日報の4状態という業務の語彙を持つ。lib/core/theme/ に置くと
//     色の入口（field_tokens.dart）と ThemeData（app_theme.dart）しか無い層へ
//     日報の業務知識を持ち込むことになる。逆向きの依存は作らない。
//   ・lib/utils/ には既に field_role_gate.dart が居て、これは
//     package:flutter/material.dart と ../core/theme/field_tokens.dart の両方を
//     import している（field_role_gate.dart の import 行）。
//     ＝「utils の門番が色と UI を知っている」形はこのアプリに前例がある。
//   ・判定の report_cancel_gate.dart とは分けたままにする。あちらは
//     「通信も画面も持たない。純粋な関数だけを置く」と自分で宣言しており、
//     Color を持ち込むとその宣言を壊す。判定（どの状態か）と
//     見た目（どう描くか）は別の関心なので、ファイルも分ける。
//
// ★語は1文字も新しくしていない。ここに並ぶ4語は
//   monthly_history_screen.dart の JsReportTile と JsReportDetailSheet が
//   持っていた switch の文字列をそのまま写したもの。

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import 'report_cancel_gate.dart';

/// 1つの状態を画面に出すための色と語。
///
/// ★色と語を1つの型で返す理由: 別々の関数にすると片方だけ差し替えた画面が
///   生まれる（それが今回直している食い違いの作られ方そのもの）。
@immutable
class ReportStatusStyle {
  const ReportStatusStyle({required this.color, required this.label});

  /// バッジの文字・枠・縦帯に使う色。面はこの色の透過で作る。
  final Color color;

  /// バッジに出す語。画面ごとに言い換えない。
  final String label;

  @override
  bool operator ==(Object other) =>
      other is ReportStatusStyle &&
      other.color == color &&
      other.label == label;

  @override
  int get hashCode => Object.hash(color, label);
}

/// 状態の文字列 → 色と語。キーは reportStatusOf が返す4値だけ。
///
/// ★色の割り当ての根拠:
///   ・取消済 … statusCancelled（藤）。専用色を持つ理由は field_tokens.dart の
///     statusCancelled のコメントに書いてある。
///   ・承認済 … statusSuccess。従来どおりで変えていない。
///   ・差戻し … statusError。月間履歴の既存の割り当てと絞り込みチップ
///     （JsStatChip('差戻', …, FieldTokens.statusError)）に揃えた。
///   ・未承認 … statusWarning。2色あったうち橙側へ寄せた。理由は
///     絞り込みチップが既に橙で数えており、日付グループ行も橙だったから
///     ＝多数派ではなく「数を出している口」に合わせる。灰側へ寄せると
///     チップの色と行の色が食い違ったままになる。
const Map<String, ReportStatusStyle> kReportStatusStyles =
    <String, ReportStatusStyle>{
  kReportStatusCancelled: ReportStatusStyle(
      color: FieldTokens.statusCancelled, label: '取消済'),
  'approved': ReportStatusStyle(
      color: FieldTokens.statusSuccess, label: '承認済'),
  'rejected': ReportStatusStyle(
      color: FieldTokens.statusError, label: '差戻し'),
  'pending': ReportStatusStyle(
      color: FieldTokens.statusWarning, label: '未承認'),
};

/// 状態の文字列から色と語を引く。
///
/// ★知らない値は未承認へ倒す。report_cancel_gate.dart の reportStatusOf は
///   4値しか返さないので通常ここには来ないが、生の行の status（'open' など）を
///   誤って渡した画面があっても落ちない方に倒す。取消済へ倒すと、生きている
///   日報が取り消されたように見える嘘になる（判定側と同じ倒し方に揃えてある）。
ReportStatusStyle reportStatusStyleForState(String status) =>
    kReportStatusStyles[status] ?? kReportStatusStyles['pending']!;

/// 日報の行から直接、色と語を引く。
///
/// ★画面はこれ1本を呼ぶ。行の 'status' を自分で読まない。
///   判定は report_cancel_gate.dart の reportStatusOf に任せる（取消済を
///   最初に見る順序をここで書き直さない＝順序の写しを増やさない）。
ReportStatusStyle reportStatusStyleOf(Map<String, dynamic> report) =>
    reportStatusStyleForState(reportStatusOf(report));
