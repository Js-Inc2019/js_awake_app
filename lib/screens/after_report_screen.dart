import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../utils/business_date.dart';

// 報告完了ビュー（日報タブ index1 を占有）。
// S5b: 縦詰まり・見切れ・スクロール不能・スライド/タップ混在を解消するため全面改修。
//  ・全体を SingleChildScrollView 化（小画面でも必ず最後まで届く）
//  ・操作は全てタップ式カードに統一（旧 _SlideBtn / 円形 GestureDetector は廃止）
// ※ 旧・全画面版 AfterReportScreen は S5b で削除（呼び手ゼロの死蔵クラスだった）。
//
// N4（完了ビュー縮小）:
//  ・「🚗 次の現場へ移動」カードを全モードで撤去（showMoveToNextSite / onMoveToNextSite ごと削除）
//  ・「☀/🌙 シフト切替」カードも撤去（showShiftContinue / onShiftContinue ごと削除）
//  ・残るアクションは「⏰ 追加の申告」と主ボタン「今日はここまで」の2つだけ
//  ★2件目の作成に入る導線はホーム(punch_screen)へ一本化した（N5）。完了ビューは
//    「締める」か「追加で申告する」かの2択に絞る＝入口を2箇所に分けない。
//    リセット処理そのものは home_screen 側に _resetForNextReport として温存してある。
//
// A案作り直し（カード撤去）:
//  ・丸バッジ(_Badge)を廃止＝頭はテキストのみ。事実は文字で言う
//  ・「今日はここまで」を主ボタンへ昇格し、見出し直下＝最上部エリアに置く
//    （旧・末尾の案内文『今日はここまでなら、そのまま閉じてOK』はこれに置換）
//  ・塗り面（α0.08）を全廃。枠は暗枠1px のみ。区切りは1px線＋余白
//  ・色は意味だけ: 未送信の警告 = FieldTokens.statusWarning。続行3行は単色（textBody/textSupport）
//    ＝ FieldTokens.foremanBase(紫) / FieldTokens.accent の装飾用途は撤去した
class AfterReportBody extends StatefulWidget {
  const AfterReportBody({
    super.key,
    required this.workerName,
    required this.sent,
    required this.shiftType,
    required this.onOvertime,
    this.onRetry,
    this.onClose,
  });
  // N4: アクションは「⏰追加の申告」と「今日はここまで」の2つだけ＝出し分けの引数を持たない。
  //   （旧 showMoveToNextSite / showShiftContinue / onMoveToNextSite / onShiftContinue は撤去）
  final String workerName;
  final bool sent;                       // 送信APIの成否（正直ゲート用）
  final String shiftType;                // 'day'|'night'（ヘッダのサブ行 _headerSubtitle に使う）
  final Future<void> Function() onOvertime;
  final VoidCallback? onRetry;           // sent==false時の「今すぐ再送」
  final VoidCallback? onClose;           // 主ボタン「今日はここまで」＝この画面を閉じる

  @override
  State<AfterReportBody> createState() => _AfterReportBodyState();
}

class _AfterReportBodyState extends State<AfterReportBody> {
  bool get _isNight => widget.shiftType == 'night';

  // ヘッダのサブ行「🌙夜勤 7/22分を送信しました」。
  // 業務日は送信時と同じ物差し（businessDateForShift）で出す＝黙って日付を変えない。
  String get _headerSubtitle {
    final biz = businessDateForShift(widget.shiftType, DateTime.now());
    final p = biz.split('-');
    final md = p.length == 3 ? '${int.parse(p[1])}/${int.parse(p[2])}' : biz;
    return '${_isNight ? '🌙夜勤' : '☀日勤'} $md分を送信しました';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 頭の表示は送信成否(sent)で正直に出し分け ──
            //    分岐条件・文言はA案でも1文字も変えていない。丸バッジだけを外した。
            if (widget.sent) ...[
              const Text('報告完了',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: FieldTokens.textBody, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(_headerSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
            ] else ...[
              const Text('未送信（再送待ち）',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: FieldTokens.textBody, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('${widget.workerName}さんの報告は保存されました',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
              const SizedBox(height: 10),
              const Text(
                '通信状況により未送信です。電波の良い場所で自動再送されます。',
                textAlign: TextAlign.center,
                style: TextStyle(color: FieldTokens.statusWarning, fontSize: 12),
              ),
              const SizedBox(height: 12),
              // 再送は続行3行と同じ新様式。ただし文字/アイコンは warning のまま
              //（＝「まだ送れていない」という意味を色で持つ唯一の行）。機能は現行のまま。
              _ActionCard(
                icon: Icons.refresh,
                title: '今すぐ再送する',
                subtitle: '保存済みの報告をもう一度送信',
                accent: FieldTokens.statusWarning,
                onTap: () => widget.onRetry?.call(),
              ),
            ],

            const SizedBox(height: 24),

            // ── 主ボタン「今日はここまで」（見出しブロック直下＝最上部エリア）──
            //    旧UIでは末尾の小さな案内文でしかなく、閉じる導線がAppBarの戻る矢印しか
            //    無かった。最も多い行動を最上部の主ボタンへ昇格する。
            _PrimaryOutlineButton(
              label: '今日はここまで',
              onTap: () => widget.onClose?.call(),
            ),

            const SizedBox(height: 24),
            // 区切りは1px線＋余白のみ（カード・塗り面は使わない）
            const Divider(height: 1, thickness: 1, color: FieldTokens.outline),
            const SizedBox(height: 20),

            const Text('続けて報告',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
            const SizedBox(height: 12),

            // ⏰ 追加の申告（残業／休憩の短縮。ラッチなし＝何度でも申告できる）
            //    絵文字・アイコン・onTap（既存 onOvertime）は据え置き。呼び先の
            //    home_screen 側で種別を選ばせる1段を挟むだけ＝ここは入口の名前だけを変える。
            //    サブ行は既存3行で唯一2行に渡るため subtitleMaxLines: 2 を渡す
            //    （既定は 1 のまま＝下の2行の描画は1ピクセルも変わらない）。
            _ActionCard(
              icon: Icons.more_time,
              title: '⏰  追加の申告',
              subtitle: '※残業や休憩の短縮を、あとから申告できます',
              subtitleMaxLines: 2,
              onTap: () => widget.onOvertime(),
            ),
            // N4: 「🚗 次の現場へ移動」「☀/🌙 シフト切替」の2カードは撤去した。
            //   2件目の作成に入る導線はホーム(punch_screen)へ一本化（N5）。
          ],
        ),
      ),
    );
  }
}

// 主ボタン「今日はここまで」。生成り枠1.5px＋同色文字・塗りなし・高さ56・角丸10。
// 色は FieldTokens.textBody(#EAE3D0)。field_tokens.dart の同トークンの doc が
// 「生成り抜きボタンの枠1.5px＋文字にも使う」と明記しており、
// home_screen.dart が同じ width:1.5 で使っている既存様式に揃えた。
class _PrimaryOutlineButton extends StatelessWidget {
  const _PrimaryOutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: FieldTokens.textBody, width: 1.5),
            ),
            child: Center(
              child: Text(label,
                  style: const TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      );
}

// 次の行動の1行。A案で塗り面（旧: 背景α0.08 + 枠α0.4 + 行ごとの色）を撤去した。
//   ・面は透明。枠は暗枠1px = FieldTokens.outline(= FieldTokens.outline #2E333A)
//     ＝ home_screen.dart の二次様式 _StepBackButton と同一トークン
//   ・アイコン/サブ/シェブロンは単色 FieldTokens.textSupport、タイトルのみ FieldTokens.textBody
//   ・accent は「未送信の再送行」だけが渡す意味色。null のときは単色に落ちる。
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent,
    this.subtitleMaxLines = 1,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? accent;
  // サブ行の行数。既定 1 ＝従来の描画そのまま（現場移動・シフト切替・再送の3行は不変）。
  // 「追加の申告」行だけが 2 を渡す＝長い注記が見切れるのを防ぐ。
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    // 単色統一。accent が来た行だけ意味色（warning）で塗り分ける。
    final sub   = accent ?? FieldTokens.textSupport;
    final head  = accent ?? FieldTokens.textBody;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,                                   // 行全面がタップ領域
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            // 塗り面なし（透明）。枠のみで領域を示す。
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: FieldTokens.outline),
          ),
          child: Row(
            children: [
              Icon(icon, color: sub, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: head,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: subtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: sub, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: sub, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
