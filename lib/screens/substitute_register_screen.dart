// ============================================================
// lib/screens/substitute_register_screen.dart - 振替休日を登録する（出勤する日を選ぶ）
//
// 承認済みモック field_substitute_flow_mock_v4.html の B3。
// 本日休みの画面の「振替で休む」と、カレンダーの箱の「振替で休む」から来る。
// どちらも手前で注意書き（B2）を読んでから入る。
//
// ★出どころは GET /rest-days/substitute/candidates?rest_date=… ただ1本。
//   返り＝{ rest_date, rest_date_is_workday, holiday_def_configured, days[] }
//   days[] の1つ＝{ date, dow, selectable, reason_code, reason }
//   ★選べる／選べないの判定も、選べない理由の文も【BE が返したものをそのまま】。
//     端末で曜日や休日から組み立て直さない。組み立てた瞬間、同じ判定が
//     BE と端末の2箇所に並び、片方だけ直せる二重真実になる。
//   ★並びも BE が返した順のまま（日曜〜土曜の7日）。端末で並べ替えない。
//
// ★端末で先回りして弾かない:
//   ・rest_date_is_workday が false（休む日そのものが会社の休みの日）でも、
//     この画面は登録の道を閉じない。断るのは口の仕事で、BE は
//     SUBSTITUTE_REST_DATE_NOT_WORKDAY で理由つきで断る。端末が先に閉じると、
//     同じ判定が2箇所に並ぶうえ、断りの文も端末が書くことになる。
//   ・holiday_def_configured が false の回だけは候補を出さない。全部選べない候補を
//     並べても選びようが無いので、BE が返した断りの文だけを出す（袋小路にしない）。
//
// ★登録は POST /rest-days/substitute ただ1本。断られたら BE の error をそのまま出し、
//   閉じるまで消えない形にする（流れて消えるものにしない）。
//
// 色は FieldTokens のみ（直書き禁止・新しい色を作らない）。
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../services/api_result.dart';
import '../services/reports_service.dart';
import 'substitute_detail_screen.dart' show showSubstituteDeny;
import 'substitute_list_screen.dart' show jpMonthDay;

class SubstituteRegisterScreen extends StatefulWidget {
  const SubstituteRegisterScreen({
    super.key,
    required this.restDate,
    this.service,
    this.onPickAnotherDate,
  });

  /// 休む日（'YYYY-MM-DD'）。呼び手が決めて渡す。
  final String restDate;

  /// 口の差し替え（検査だけが渡す）。既定は null＝今までどおり ReportsService()。
  ///   ★形も理由も substitute_list_screen.dart の同じ引数の★と同じ【Q70】。
  final ReportsService? service;

  /// 「変える」を押したときの道。★日を選ぶ仕掛けは呼び手が持っている
  ///   （本日休みの画面は自分の日付ピッカー、カレンダーは箱を開き直す）ので、
  ///   この画面には作らない。渡されなければ「変える」を出さない。
  final VoidCallback? onPickAnotherDate;

  @override
  State<SubstituteRegisterScreen> createState() =>
      _SubstituteRegisterScreenState();
}

class _SubstituteRegisterScreenState extends State<SubstituteRegisterScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};
  List<Map<String, dynamic>> _days = const [];
  String? _picked;          // 選んだ出勤する日（null = まだ選んでいない）
  bool _busy = false;

  late final ReportsService _api = widget.service ?? ReportsService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _picked = null; });
    final ApiResult<Map<String, dynamic>> res =
        await _api.getSubstituteWorkDateCandidates(widget.restDate);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!res.ok) {
        // ★0件に倒さない。取れなかったことを取れなかったと言う。
        _error = res.errorMessage ?? '選べる日を取得できませんでした';
        _data = const {};
        _days = const [];
        return;
      }
      _data = res.data ?? const <String, dynamic>{};
      _days = ((_data['days'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  /// 週の最初の日／最後の日。★BE が返した days[] の両端そのもの。
  ///   ★端末で「日曜から土曜」を数え直さない（数え直すと週の数え方が2箇所になる）。
  String get _weekFirst =>
      _days.isEmpty ? '—' : jpMonthDay('${_days.first['date'] ?? ''}');
  String get _weekLast =>
      _days.isEmpty ? '—' : jpMonthDay('${_days.last['date'] ?? ''}');

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: FieldTokens.bgBase,
        appBar: AppBar(title: const Text('振替で休む')),
        body: _buildBody(),
      );

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final err = _error;
    if (err != null) return _Trouble(text: err, onRetry: _load);

    // ★会社の休みの日が1日も設定されていない回。候補を並べても選びようが無いので、
    //   BE が返した断りの文だけを出す。文は BE のもの（端末で書かない）。
    if (_data['holiday_def_configured'] != true) {
      final reason = _days
          .map((d) => '${d['reason'] ?? ''}')
          .firstWhere((t) => t.isNotEmpty, orElse: () => '');
      return _Trouble(
        text: reason.isEmpty ? '選べる日がありません' : reason,
        onRetry: _load,
      );
    }

    return ListView(
      // ★上下を 16 → 12 に詰める。左右 16 はそのまま（1画面に収めるため）。
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        // ── 休む日（上）──────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: FieldTokens.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Text('休む日',
                  style: TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12)),
              const SizedBox(width: 12),
              Text(jpMonthDay(widget.restDate),
                  style: const TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              if (widget.onPickAnotherDate != null)
                TextButton(
                  onPressed: _busy ? null : widget.onPickAnotherDate,
                  child: const Text('変える',
                      style: TextStyle(color: FieldTokens.accent)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── 区切りの帯 ───────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: FieldTokens.surfaceCard,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('同じ週の中で入れ替え',
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
        ),
        const SizedBox(height: 12),

        const Text('代わりに出勤する日',
            style: TextStyle(
                color: FieldTokens.textSupport,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),

        // ── 候補（BE が返した7日をその順のまま）──────────────────
        for (final d in _days)
          _WorkDateRow(
            day: d,
            picked: _picked != null && _picked == '${d['date']}',
            busy: _busy,
            onTap: () => setState(() => _picked = '${d['date']}'),
          ),

        const SizedBox(height: 12),
        // ── ※（モック B3 の2行）──────────────────────────────
        //   ★週の両端は BE が返した days[] の最初と最後から出す。
        //   ★1行目は同じ意味のまま短くした（1画面に収めるため）。
        Text('※同じ週（$_weekFirst〜$_weekLast）の会社休みの日から選びます。',
            style: _note),
        const Text('※出勤する日を決めないと登録できません。', style: _note),

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            // ★選ぶまで押せない。見た目だけ灰色にして押せる形にしない
            //   （押せてしまうと、何を送るか決まっていないまま口を叩くことになる）。
            onPressed: (_picked == null || _busy) ? null : _register,
            style: OutlinedButton.styleFrom(
              foregroundColor: FieldTokens.accent,
              side: const BorderSide(color: FieldTokens.accent, width: 1),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('この内容で登録する',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Future<void> _register() async {
    final work = _picked;
    if (work == null || _busy) return;
    setState(() => _busy = true);
    final res = await _api.registerSubstitute(widget.restDate, work);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      await showSubstituteDeny(context, '登録できませんでした', res);
      return;
    }
    if (!mounted) return;
    // ★通ったら呼び手へ true を返す。数（要対応・カレンダー・一覧）の読み直しは
    //   呼び手が持っている（この画面はどこから来たかを知らない）。
    Navigator.of(context).pop(true);
  }
}

const TextStyle _note =
    TextStyle(color: FieldTokens.textSupport, fontSize: 12, height: 1.6);

/// 取れなかった・選べない回の受け皿。★黙って空にしない。
class _Trouble extends StatelessWidget {
  const _Trouble({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FieldTokens.textSupport)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('もう一度')),
            ],
          ),
        ),
      );
}

/// 出勤する日の候補1行。
///   ★selectable が false なら押せない見た目にして、横に BE の reason を出す。
///     消さないのは「その日がなぜ選べないか」を読めるようにするため。
class _WorkDateRow extends StatelessWidget {
  const _WorkDateRow({
    required this.day,
    required this.picked,
    required this.busy,
    required this.onTap,
  });
  final Map<String, dynamic> day;
  final bool picked;
  final bool busy;
  final VoidCallback onTap;

  static const List<String> _dow = ['日', '月', '火', '水', '木', '金', '土'];

  @override
  Widget build(BuildContext context) {
    final selectable = day['selectable'] == true;
    final date = '${day['date'] ?? ''}';
    final dowIdx = day['dow'];
    final dowText = (dowIdx is int && dowIdx >= 0 && dowIdx < 7)
        ? '（${_dow[dowIdx]}）'
        : '';
    final reason = '${day['reason'] ?? ''}';

    return Opacity(
      opacity: selectable ? 1.0 : 0.55,
      child: Container(
        // ★行の間だけ詰める（8 → 4）。行そのものの高さは下の padding で保つ。
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: picked
              ? Border.all(color: FieldTokens.accent, width: 2)
              : null,
        ),
        child: InkWell(
          onTap: (selectable && !busy) ? onTap : null,
          child: Padding(
            // ★押せる高さは 44pt 以上を保つ。行の高さは日付1行（15pt）が決める。
            //   実測: 21〜22 + 12 * 2 = 45（検査の書体）／46（実機）。
            //   ここを縮めると 44 を割るため詰めない。
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  // ★104 では日付が2行に折れて、行の高さが 44 ではなく 67 になっていた
                  //   （7日ぶんで 161pt ぶん余計に伸び、これが「1画面に収まらない」
                  //     一番の原因だった）。
                  //   実測（iPhone 16 / iOS 26.5 のシミュレータ）:
                  //     '12月31日（水）' 15pt太字 = 112.3pt ＞ 104 → 折れる
                  //     列を 144 にすると行の高さは 46pt（1行のまま）
                  //   ★144 は検査で使う書体（'12月31日（水）' = 137.3pt）でも折れない幅。
                  width: 144,
                  child: Text('${jpMonthDay(date)}$dowText',
                      style: TextStyle(
                          color: selectable
                              ? FieldTokens.textBody
                              : FieldTokens.textFaint,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: selectable
                      ? const SizedBox.shrink()
                      // ★選べない理由は BE の文をそのまま。端末で言い換えない。
                      : Text(reason,
                          style: const TextStyle(
                              color: FieldTokens.textFaint, fontSize: 12)),
                ),
                if (picked)
                  const Icon(Icons.check,
                      color: FieldTokens.accent, size: 20)
                else if (selectable)
                  const Icon(Icons.chevron_right,
                      color: FieldTokens.textFaint, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
