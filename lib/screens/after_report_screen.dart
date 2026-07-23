import 'package:flutter/material.dart';

import '../core/theme/js_colors.dart';
import '../utils/business_date.dart';

// 報告完了ビュー（日報タブ index1 を占有）。
// S5b: 縦詰まり・見切れ・スクロール不能・スライド/タップ混在を解消するため全面改修。
//  ・全体を SingleChildScrollView 化（小画面でも必ず最後まで届く）
//  ・操作は全てタップ式カードに統一（旧 _SlideBtn / 円形 GestureDetector は廃止）
//  ・アクションは3択（残業 / 現場移動 / シフト切替）
// ※ 旧・全画面版 AfterReportScreen は S5b で削除（呼び手ゼロの死蔵クラスだった）。
class AfterReportBody extends StatefulWidget {
  const AfterReportBody({
    super.key,
    required this.workerName,
    required this.sent,
    required this.shiftType,
    required this.onMoveToNextSite,
    required this.onShiftContinue,
    required this.onOvertime,
    this.onRetry,
  });
  final String workerName;
  final bool sent;                       // 送信APIの成否（正直ゲート用）
  final String shiftType;                // 'day'|'night'（切替カードのラベルを反転表示するため）
  final VoidCallback onMoveToNextSite;
  final VoidCallback onShiftContinue;    // 現シフトの逆へ切替（day→night / night→day）
  final Future<void> Function() onOvertime;
  final VoidCallback? onRetry;           // sent==false時の「今すぐ再送」

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
            if (widget.sent) ...[
              const _Badge(icon: Icons.check, color: JsColors.success),
              const SizedBox(height: 16),
              const Text('報告完了',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: JsColors.textStrong, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(_headerSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: JsColors.textMid, fontSize: 12)),
            ] else ...[
              const _Badge(icon: Icons.schedule, color: JsColors.warning),
              const SizedBox(height: 16),
              const Text('未送信（再送待ち）',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: JsColors.textStrong, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('${widget.workerName}さんの報告は保存されました',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: JsColors.textMid, fontSize: 12)),
              const SizedBox(height: 10),
              const Text(
                '通信状況により未送信です。電波の良い場所で自動再送されます。',
                textAlign: TextAlign.center,
                style: TextStyle(color: JsColors.warning, fontSize: 12),
              ),
              const SizedBox(height: 12),
              // 再送はカード群と調和させたタップ式カードに（機能は現行のまま）
              _ActionCard(
                icon: Icons.refresh,
                title: '今すぐ再送する',
                subtitle: '保存済みの報告をもう一度送信',
                color: JsColors.warning,
                onTap: () => widget.onRetry?.call(),
              ),
            ],

            const SizedBox(height: 28),
            const Text('このあとは？',
                style: TextStyle(color: JsColors.textMid, fontSize: 12)),
            const SizedBox(height: 12),

            // ⏰ 残業（ラッチなし＝何度でも報告できる）
            _ActionCard(
              icon: Icons.more_time,
              title: '⏰  残業を報告する',
              subtitle: '残業した時間を追加で記録',
              color: JsColors.warning,
              onTap: () => widget.onOvertime(),
            ),
            const SizedBox(height: 10),

            // 🚗 現場移動
            _ActionCard(
              icon: Icons.directions_car,
              title: '🚗  次の現場へ移動',
              subtitle: '現場と位置を取り直して報告',
              color: JsColors.actionCyan,
              onTap: widget.onMoveToNextSite,
            ),
            const SizedBox(height: 10),

            // ☀/🌙 シフト切替（現在の勤務区分の逆へ）
            _ActionCard(
              icon: _isNight ? Icons.wb_sunny_outlined : Icons.nightlight_round,
              title: _isNight ? '☀  日勤に切り替えて続ける' : '🌙  夜勤に切り替えて続ける',
              subtitle: '勤務区分を変えて次の報告へ',
              color: JsColors.foremanBase,
              onTap: widget.onShiftContinue,
            ),

            const SizedBox(height: 20),
            const Text('今日はここまでなら、そのまま閉じてOK',
                textAlign: TextAlign.center,
                style: TextStyle(color: JsColors.textMid, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// 完了/未送信を示す丸バッジ
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 42),
        ),
      );
}

// 次の行動カード（3枚とも同一パターン: 枠α0.4 + 背景α0.08 + アイコンに各色）。
// タイトルは視認性優先で textStrong 固定。危険色(error)は使わない。
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,                                   // カード全面がタップ領域
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: JsColors.textStrong,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: JsColors.textMid, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: color.withValues(alpha: 0.7), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
