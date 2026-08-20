// lib/screens/management_history_screen.dart
// 「管理・履歴」タブ（ボトム index1）の器。
//
// ★この画面は「既存Widgetを呼ぶだけ」の器であり、独自のロジック・独自の配色を一切持たない。
//   各セグメントの中身は既存実体をそのまま呼ぶ（中身は1行も変更していない）:
//     カレンダー = CalendarTab            (home_screen.dart)
//     履歴       = MonthlyHistoryBody     (monthly_history_screen.dart)
//     集計       = MonthlyStatsBody       (monthly_stats_screen.dart・全員)
//     承認       = ReviewTab              (home_screen.dart・職長のみ)
//     管理       = ForemanManagementBody  (home_screen.dart・職長のみ)
//   ★上4行の行番号は「集計」追加に合わせて実ファイルで数え直した値（旧値は陳腐化していた）。
//
// TabBar の見た目（Container(color: FieldTokens.surfaceCard) + 既定 TabBar）は
// home_screen.dart の _ForemanManagementBody および _ReviewTab と同一。
// 新しい色・余白・フォントは一切導入していない。
import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import 'home_screen.dart' show CalendarTab, ReviewTab, ForemanManagementBody;
import 'monthly_history_screen.dart' show MonthlyHistoryBody;
import 'monthly_stats_screen.dart' show MonthlyStatsBody;

class ManagementHistoryScreen extends StatefulWidget {
  const ManagementHistoryScreen({
    super.key,
    required this.isForeman,
    this.initialSegment,
    this.segmentRequestId = 0,
  });

  /// 職長かどうか。JsMainShell.isForeman(home_screen.dart) をそのまま下ろす。
  final bool isForeman;

  /// 開きたいセグメントを「ラベル」で指定する（'カレンダー'|'履歴'|'承認'|'管理'）。
  /// 未指定・および存在しないラベルのときは先頭＝カレンダー（従来と同じ）。
  ///
  /// ★index の直指定にしない理由（実コード上の事実）: セグメントの枚数と並びが
  ///   職人＝2枚（カレンダー/履歴）・職長＝4枚（+承認/管理）で異なる（本ファイルのタブ枚数の分岐）。
  ///   index を直に渡すと職人側で意図しないタブが開く。ラベルで引き当て、
  ///   引き当たらなければ 0 へフォールバックする＝安全側に倒す。
  final String? initialSegment;

  /// 「今もう一度 initialSegment を開いてほしい」という要求の通し番号。
  ///
  /// ★この画面は IndexedStack(home_screen.dart) の子として生かされ続けるため、
  ///   同じ initialSegment を渡し直しても State は作り直されず切り替わらない。
  ///   呼び出し側が要求のたびに +1 することで2回目以降のタップにも追従させる。
  ///   既定 0 のまま渡さなければ、この画面は従来どおり一切自動切替をしない。
  final int segmentRequestId;

  @override
  State<ManagementHistoryScreen> createState() => _ManagementHistoryScreenState();
}

class _ManagementHistoryScreenState extends State<ManagementHistoryScreen>
    with SingleTickerProviderStateMixin {
  /// セグメントのラベル（＝並びの単一の出所）。tabs も views もこの並びに従う。
  late final List<String> _labels;
  late final TabController _ctrl;

  @override
  void initState() {
    super.initState();
    // 職人: カレンダー / 履歴 / 集計
    // 職長: カレンダー / 履歴 / 集計 / 承認 / 管理
    // ★「集計」は職長にも出す。職長は「管理→社員」で他人の月次しか見られず、
    //   自分の月次を見る導線が無い不整合があったため（本人開放は BE 側で対応済み）。
    _labels = <String>[
      'カレンダー',
      '履歴',
      '集計',
      if (widget.isForeman) ...['承認', '管理'],
    ];
    _ctrl = TabController(
      length: _labels.length,
      vsync: this,
      initialIndex: _resolve(widget.initialSegment),
    );
  }

  /// ラベル → index。未指定、または並びに存在しないラベル（職人が'承認'を
  /// 要求した等）は 0（カレンダー）を返す。範囲外の index は決して返さない。
  int _resolve(String? label) {
    if (label == null) return 0;
    final i = _labels.indexOf(label);
    return i >= 0 ? i : 0;
  }

  @override
  void didUpdateWidget(covariant ManagementHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 要求番号が進んだときだけ追従する（通常の再描画では現在のタブを動かさない）。
    if (widget.segmentRequestId != oldWidget.segmentRequestId) {
      final i = _resolve(widget.initialSegment);
      if (i != _ctrl.index) _ctrl.index = i;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 見た目は従来どおり（Container(surfaceCard) + 既定 TabBar / TabBarView）。
    // DefaultTabController を明示の TabController へ置き換えただけで、
    // 各セグメントの中身は1行も変更していない。
    final tabs = _labels.map((t) => Tab(text: t)).toList();

    // ★_labels と同じ並び・同じ条件で並べる（片方だけ足すと index がずれる）。
    final views = <Widget>[
      const CalendarTab(),
      const MonthlyHistoryBody(),
      const MonthlyStatsBody(),
      if (widget.isForeman) ...[
        const ReviewTab(),
        const ForemanManagementBody(),
      ],
    ];

    return Column(
      children: [
        Container(
          color: FieldTokens.surfaceCard,
          child: TabBar(
            controller: _ctrl,
            isScrollable: false,
            tabs: tabs,
          ),
        ),
        Expanded(
          child: TabBarView(controller: _ctrl, children: views),
        ),
      ],
    );
  }
}
