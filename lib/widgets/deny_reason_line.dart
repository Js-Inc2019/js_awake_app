// ============================================================
// lib/widgets/deny_reason_line.dart - 押せない理由の1行（公開・共通部品）と、その文の組み方【1本ずつ】
//   ・DenyReasonLine … 印 Icons.info_outline（textSupport・14）・間 6・字 textSupport 12・行の高さ 1.6 の1行
//   ・denyReasonText … 「{頭の語}：{理由}」／理由が文字でないか空白だけなら頭の語だけ
//
// ★なぜ1本にするか（2026-10-01・便F14）: 押せないボタンを消さずに灰色で残し、下に理由を1行で言う形
//   （ボス裁定【Q98】）が、日報の承認と修正依頼（home_screen.dart の ApprovalDenyLines）に続いて、
//   振替休日の同意（substitute_detail_screen.dart の1件の画面・punch_screen.dart のホームの枠・
//   home_screen.dart のカレンダーの箱）にも要るようになった。同じ行を置き場ごとに書き写すと、
//   片方だけ変わる。事務アプリの lib/widgets/deny_reason_line.dart と同じ考え。
// ★外側の余白（SizedBox・Padding）は置き場ごとに違うので、呼び手に残す（ここでは持たない）。
// ★理由の文は BE の cannot_*_reason をそのまま渡す（端末で言い換えない・組み立てない）。
//
// 色は FieldTokens のみ（直書き禁止・新しい色を作らない）。
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';

/// 押せない理由の1行。★形は home_screen.dart の ApprovalDenyLines の1行だったものを、
///   1つも変えずにここへ移した。
class DenyReasonLine extends StatelessWidget {
  const DenyReasonLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              color: FieldTokens.textSupport, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: FieldTokens.textSupport,
                    fontSize: 12,
                    height: 1.6)),
          ),
        ],
      );
}

/// 押せない理由の1行の文。「{頭の語}：{理由}」／理由が文字でないか空白だけなら頭の語だけ。
///   ★中身は home_screen.dart の approvalDenyLine だったものと同じ（あちらはこれを呼ぶ）。
String denyReasonText(String head, Object? reason) {
  final t = reason is String ? reason.trim() : '';
  return t.isEmpty ? head : '$head：$t';
}
