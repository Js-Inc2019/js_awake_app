// lib/utils/field_role_gate.dart
// FIELD アプリに入れる役職の唯一の名簿と、入れなかったときの案内ダイアログ。
//
// ★なぜ1ファイルに集めるか（実際に起きた事故の再発防止）:
//   アプリの棲み分け（FIELD=worker+boss / OFFICE=admin_office+admin_exec）は
//   BE には無く FE だけが持っているルールで、判定が経路ごとに手書きされていた。
//   その結果、複数所属の経路と招待有効化の経路は弾くのに、
//   単一所属の経路（verify-pin / verify-device / F5サイレント復帰）と
//   機種変更の経路（recover-by-code）は role を一度も見ずに保存まで進んでいた。
//   名簿が1箇所に無いと「どこかだけ直し忘れる」形が構造的に残るため、
//   役職の名簿・判定・案内の3つをここに置き、各画面はこれを呼ぶだけにする。
//
// ★ダイアログはここに1つだけ置く（画面ごとに作らない）。
//   文言・見た目は移設前の login_screen.dart の _showOfficeOnlyDialog と同一。

import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';

/// FIELD アプリで扱う役職の全数。ここが唯一の名簿。
///
/// ★BE 側にこの区別は無い（POST /auth/verify-pin は role で絞り込まない）。
///   よってこの名簿はサーバ真実の複製ではなく、FE が持つ独自のルールである。
const Set<String> kFieldRoles = {'worker', 'boss'};

/// サーバが返した role が FIELD で扱えるものか。
/// null・空・未知の値はすべて false（fail-close＝知らない役職は入れない）。
bool isFieldRole(String? role) => role != null && kFieldRoles.contains(role);

/// verify 応答の memberships[] を FIELD で扱えるものだけに絞る。
///
/// ★複数所属の分岐（0件＝案内 / 1件＝自動select / 2件以上＝選択画面）を持つ画面が
///   2つ（login_screen / recovery_screen）あり、両方が同じ絞り込みを必要とする。
///   絞り込みの式を各画面に書くと isFieldRole の名簿が増えたときに片方だけ
///   直し忘れる形になるため、絞り込みもここに1つだけ置く。
///   ※0/1/2+ の分岐そのものは画面ごとに「次に何を呼ぶか」が違う（保存処理も
///     戻る先も別）ので共通化しない。共通化できるのは判定と絞り込みまで。
///
/// rawList が List でない（キー欠落・型違い）場合は空リストを返す（fail-close）。
List<Map<String, dynamic>> filterFieldMemberships(dynamic rawList) {
  if (rawList is! List) return const [];
  return rawList
      .whereType<Map>()
      .where((m) => isFieldRole(m['role'] as String?))
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}

/// FIELD で扱えない役職だったときの案内。閉じたら呼び出し元の画面に留まる。
///
/// ★このダイアログは「行き止まり」ではない。閉じると呼び出し元は
///   ログイン手段のある画面（ランディング／PIN入力／機種変更）へ戻るため、
///   別のIDで入り直すことができる。
Future<void> showOfficeOnlyDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: FieldTokens.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('ご案内',
          style: TextStyle(color: FieldTokens.accent, fontSize: 16)),
      content: const Text('この端末の役割はOFFICEアプリをご利用ください',
          style: TextStyle(color: FieldTokens.textBody, height: 1.7)),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(
            backgroundColor: FieldTokens.accent,
            foregroundColor: FieldTokens.onAccent,
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
