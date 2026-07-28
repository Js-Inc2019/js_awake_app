// lib/screens/management_history_screen.dart
// 「管理・履歴」タブ（ボトム index1）の器。
//
// ★この画面は「既存Widgetを呼ぶだけ」の器であり、独自のロジック・独自の配色を一切持たない。
//   各セグメントの中身は既存実体をそのまま呼ぶ（中身は1行も変更していない）:
//     カレンダー = CalendarTab            (home_screen.dart:5237)
//     履歴       = MonthlyHistoryBody     (monthly_history_screen.dart:17)
//     承認       = ReviewTab              (home_screen.dart:4292・職長のみ)
//     管理       = ForemanManagementBody  (home_screen.dart:4255・職長のみ)
//
// TabBar の見た目（Container(color: JsColors.gunmetal) + 既定 TabBar）は
// home_screen.dart:4264-4273（_ForemanManagementBody）および :4341-4350（_ReviewTab）と同一。
// 新しい色・余白・フォントは一切導入していない。
import 'package:flutter/material.dart';

import '../core/theme/js_colors.dart';
import 'home_screen.dart' show CalendarTab, ReviewTab, ForemanManagementBody;
import 'monthly_history_screen.dart' show MonthlyHistoryBody;

class ManagementHistoryScreen extends StatelessWidget {
  const ManagementHistoryScreen({super.key, required this.isForeman});

  /// 職長かどうか。JsMainShell.isForeman(home_screen.dart:359) をそのまま下ろす。
  final bool isForeman;

  @override
  Widget build(BuildContext context) {
    // 職人: カレンダー / 履歴
    // 職長: カレンダー / 履歴 / 承認 / 管理
    final tabs = <Tab>[
      const Tab(text: 'カレンダー'),
      const Tab(text: '履歴'),
      if (isForeman) ...[
        const Tab(text: '承認'),
        const Tab(text: '管理'),
      ],
    ];

    final views = <Widget>[
      const CalendarTab(),
      const MonthlyHistoryBody(),
      if (isForeman) ...[
        const ReviewTab(),
        const ForemanManagementBody(),
      ],
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Container(
            color: JsColors.gunmetal,
            child: TabBar(
              isScrollable: false,
              tabs: tabs,
            ),
          ),
          Expanded(
            child: TabBarView(children: views),
          ),
        ],
      ),
    );
  }
}
