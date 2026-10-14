// lib/widgets/reports_truncated_bar.dart
// 月の日報が上限で切れた時だけ出す帯（便BJ・見本 claude/field_report_fix_mock_v1.html の ⑪）。
//
// ★何か：月の日報を取る口（ReportsService.getReportsByMonth）の答えの truncated（サーバの上限で切れた事実）が
//   true の時だけ、画面の上に出す1行。字は事務アプリの帯（js_office_admin_app の lib/widgets/reports_truncated_band.dart）と
//   同じ（同じ事実を同じ言葉で言う）。
// ★形はカレンダーの取得失敗の帯（home_screen.dart の _CalendarTabState._buildFailureBar）と同じ
//   （幅いっぱい・地 surfaceCard・左右 12・印 16 と字 12 は statusWarning・高さは 44 以上）。
//   ［再試行］は付けない（取り直しても同じ上限で切れる）。印は ⓘ（info_outline）。
// ★使う所：カレンダー（CalendarTab）・承認のタブ（ReviewTab）・月の履歴（MonthlyHistoryBody）。
import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';

/// 帯の字（事務アプリと同じ字）。
const String kReportsTruncatedLine = '件数が多いため、古い日の日報の一部を取得できませんでした';

class ReportsTruncatedBar extends StatelessWidget {
  const ReportsTruncatedBar({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: FieldTokens.surfaceCard,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        constraints: const BoxConstraints(minHeight: 44),
        child: const Row(children: [
          Icon(Icons.info_outline, color: FieldTokens.statusWarning, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(kReportsTruncatedLine,
                style: TextStyle(color: FieldTokens.statusWarning, fontSize: 12)),
          ),
        ]),
      );
}
