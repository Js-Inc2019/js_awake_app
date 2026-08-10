// lib/screens/monthly_stats_screen.dart — 「集計」セグメント（管理・履歴タブ）
//
// ★自分の月次集計だけを見る画面。他人の集計は扱わない（person_id は常に自分）。
//
// ★数字の出所は BE の GET /attendance/monthly-summary ただ一つ。
//   クライアント側で合計・平均・判定を作らない（＝二重真実を作らない）。
//   表示する4項目・単位・計算は home_screen.dart の _StaffMonthlySheet(:5952-5987) と同一:
//     出勤日数 = days_worked                          （日）
//     実働     = total_net_minutes / 60 を小数1桁      （h）
//     残業     = overtime.total_min                    （分）
//     休日出勤 = holiday_work_days                     （日）
//   色も同じ割り当て（statusSuccess / accent / statusWarning / statusError）。
//
// ★36協定アラート（GET /attendance/compliance-alerts）は呼ばない。
//   法令判断は会社の責任であり、職人に法令判断をさせないため（法務設計と整合）。
//
// ★数字部品は既存の JsStatChip(monthly_history_screen.dart:255) を再利用する。新部品は作らない。
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/field_tokens.dart';
import '../services/work_mode_service.dart';
import 'monthly_history_screen.dart' show JsStatChip;

// ─────────────────────────────────────────────
// MonthlyStatsBody — Scaffold なし（管理・履歴タブの TabBarView で使用）
// ─────────────────────────────────────────────
class MonthlyStatsBody extends StatefulWidget {
  const MonthlyStatsBody({super.key});
  @override
  State<MonthlyStatsBody> createState() => _MonthlyStatsBodyState();
}

class _MonthlyStatsBodyState extends State<MonthlyStatsBody> {
  DateTime _selectedMonth = DateTime.now();

  // ★状態は3つだけ。互いに排他であることを _load() が保証する:
  //   loading           … _loading == true
  //   error             … _loading == false && _error != null （このとき _summary は必ず null）
  //   データ             … _loading == false && _error == null && _summary != null
  //   ★「取得失敗」と「0件」を混ぜない。失敗時は数字を1つも描かない（嘘の 0 を出さない）。
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _summary;

  String get _monthStr =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _load();
  }

  // ★当月で止める。式は既存5箇所と同一（代表: home_screen.dart:6341-6353）。
  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year &&
        _selectedMonth.month == now.month) {
      return;
    }
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _load();
  }

  // ── 取得 ───────────────────────────────────────────────────────
  // ★必ず「_summary を入れる」か「_error を入れる」のどちらか一方で終わる。
  //   握り潰して無言で空表示にする経路を作らない。
  //   ★debugPrint には token / Authorization / headers を一切渡さない（秘匿値の漏洩防止）。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error   = null;
      _summary = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      // ★自分の person_id。login_screen.dart:926 が BE の user_id をこのキーへ保存しており、
      //   その user_id は routes/auth.js:726/844/1239 のとおり person.person_id そのもの。
      //   home_screen.dart:5726 が職人カードから取り出す worker['user_id'] と同じ意味の値。
      final personId = prefs.getString('user_id') ?? '';
      if (personId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error   = 'ログイン情報を取得できませんでした。\n再ログインしてください。';
        });
        return;
      }

      final res = await WorkModeService()
          .fetchMonthlySummary(personId: personId, month: _monthStr);

      if (!mounted) return;

      // ★「必ず _summary か _error のどちらか一方で終わる」掟を守るため、
      //   ok でも本文が空（data == null）なら成功にしない。移設前は
      //   jsonDecode('') が投げて catch 側のネットワークエラーになっていた経路。
      final summary = res.data;
      if (res.ok && summary != null) {
        setState(() {
          _summary = summary;
          _loading = false;
        });
        return;
      }

      // 通信不成立（statusCode:0）＋ 200系だが本文が読めなかった場合＝移設前の catch 相当。
      if (res.statusCode == 0 || res.ok) {
        setState(() {
          _loading = false;
          _error   = 'ネットワークエラー。\n通信状況を確認して再試行してください。';
        });
        return;
      }

      // ★非200を握り潰さない。状態コードを本文に出して原因を隠さない。
      //   （応答本文・token は出さない。ApiResult 側でも同じ規約で可視化済み）
      setState(() {
        _loading = false;
        _error = res.statusCode == 401
            ? '認証の有効期限が切れました。\n再ログインしてください。'
            : res.statusCode == 403
                ? '集計を表示する権限がありません。'
                : 'データの取得に失敗しました（HTTP ${res.statusCode}）。\nしばらく経ってから再試行してください。';
      });
    } catch (e) {
      debugPrint('monthly-summary 取得失敗: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = 'ネットワークエラー。\n通信状況を確認して再試行してください。';
      });
    }
  }

  // ── 表示値（BE の値をそのまま使う。ここで再計算・再判定はしない）──────
  int _intOf(String key) => (_summary?[key] as num?)?.toInt() ?? 0;

  String get _netHours {
    final mins = (_summary?['total_net_minutes'] as num?)?.toDouble() ?? 0;
    return '${(mins / 60).toStringAsFixed(1)}h';
  }

  int get _overtimeMin =>
      ((_summary?['overtime'] as Map<String, dynamic>?)?['total_min'] as num?)
          ?.toInt() ??
      0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth =
        _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    return Column(
      children: [
        // ① 月ナビ（既存の流儀そのまま: surfaceCard 帯 + 前月/当月/翌月 + 再読込）
        Container(
          color: FieldTokens.surfaceCard,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: FieldTokens.brand),
                onPressed: _prevMonth,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_selectedMonth.year}年${_selectedMonth.month}月',
                    style: const TextStyle(
                        color: FieldTokens.brand,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth ? FieldTokens.textSupport : FieldTokens.brand),
                onPressed: isCurrentMonth ? null : _nextMonth,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.refresh,
                    color: FieldTokens.textSupport, size: 18),
                onPressed: _load,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        // ② 本体（3分岐。どの分岐も必ず何かを描く＝無言で終わらない）
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: FieldTokens.accent));
    }
    if (_error != null) {
      return _errorView(_error!);
    }
    final s = _summary;
    if (s == null) {
      // 到達しない想定（_load は必ず _summary か _error を入れる）。
      // それでも無言の空画面を作らないため、再試行できる形で必ず知らせる。
      return _errorView('データを取得できませんでした。');
    }
    return _dataView(s);
  }

  // ── 失敗表示（数字は1つも描かない＝0を嘘として見せない）────────────
  Widget _errorView(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: FieldTokens.statusWarning, size: 32),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: FieldTokens.statusWarning, fontSize: 13),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('再試行'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FieldTokens.textBody,
                  side: const BorderSide(
                      color: FieldTokens.textBody, width: 1.5),
                ),
              ),
            ],
          ),
        ),
      );

  // ── データ表示 ──────────────────────────────────────────────────
  Widget _dataView(Map<String, dynamic> s) {
    final daysWorked = _intOf('days_worked');
    // note は BE が必ず載せる注意書き（法務の盾）。欠けても文言が消えないよう既定値を持つ。
    final note = s['note'] as String? ??
        '参考値です。労働時間・賃金の最終確定は貴社の責任で行ってください';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Row(
          children: [
            JsStatChip('出勤日数', daysWorked, FieldTokens.statusSuccess),
            const SizedBox(width: 4),
            // 実働だけは単位付き（h）。int に落とすと _StaffMonthlySheet と単位が食い違うため
            // JsStatChip の valueText を使う（count は同値の分ではなく参考の丸め値を入れない）。
            JsStatChip('実働', 0, FieldTokens.accent, valueText: _netHours),
            const SizedBox(width: 4),
            JsStatChip('残業', _overtimeMin, FieldTokens.statusWarning),
            const SizedBox(width: 4),
            JsStatChip('休日出勤', _intOf('holiday_work_days'), FieldTokens.statusError),
          ],
        ),
        const SizedBox(height: 12),
        // 単位を明示（チップの数字だけでは「残業=分」が読み取れないため）
        const Text(
          '出勤日数・休日出勤は日数／残業は分',
          style: TextStyle(color: FieldTokens.textSupport, fontSize: 11),
        ),
        // ★「0件」は失敗ではない。取得できたうえでの事実として言葉でも伝える。
        if (daysWorked == 0) ...[
          const SizedBox(height: 16),
          const Text(
            'この月の出勤記録はありません',
            textAlign: TextAlign.center,
            style: TextStyle(color: FieldTokens.textBody, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          note,
          style: TextStyle(
              color: FieldTokens.accent.withValues(alpha: 0.85), fontSize: 11),
        ),
      ],
    );
  }
}
