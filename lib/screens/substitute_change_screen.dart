// ============================================================
// lib/screens/substitute_change_screen.dart - 休む日を選び直す
//
// 承認済みモック field_substitute_flow_mock_v4.html の D2（候補を選ぶ）と
// D3（二度目の確認）。1件の画面の「休む日を変える」から来る。
//
// ★出どころは GET /rest-days/:id/change-candidates ただ1本。
//   返り＝{ rest_day_id, current_rest_date, paired_work_date,
//           holiday_def_configured, days[] }
//   days[] の1つ＝{ date, dow, selectable, reason_code, reason, deadline }
//   ★選べる／選べないの判定も、選べない理由の文も【BE が返したものをそのまま】。
//     端末で曜日や期限から組み立て直さない。組み立てた瞬間、同じ判定が
//     BE と端末の2箇所に並び、片方だけ直せる二重真実になる。
//   ★並びも BE が返した順のまま（日曜〜土曜の7日）。端末で並べ替えない。
//
// ★申し出は POST /rest-days/:id/change-request ただ1本。断られたら BE の error を
//   そのまま出し、閉じるまで消えない形にする（流れて消えるものにしない）。
//
// 色は FieldTokens のみ（直書き禁止・新しい色を作らない）。
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../services/api_result.dart';
import '../services/reports_service.dart';
import 'substitute_detail_screen.dart' show showSubstituteDeny;
import 'substitute_list_screen.dart' show jpMonthDay;

class SubstituteChangeScreen extends StatefulWidget {
  const SubstituteChangeScreen({
    super.key,
    required this.restDayId,
    this.service,
  });

  final String restDayId;

  /// 口の差し替え（検査だけが渡す）。既定は null＝今までどおり ReportsService()。
  ///   ★形も理由も substitute_list_screen.dart の同じ引数の★と同じ【Q70】。
  final ReportsService? service;

  @override
  State<SubstituteChangeScreen> createState() => _SubstituteChangeScreenState();
}

class _SubstituteChangeScreenState extends State<SubstituteChangeScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};
  List<Map<String, dynamic>> _days = const [];
  bool _busy = false;

  late final ReportsService _api = widget.service ?? ReportsService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final ApiResult<Map<String, dynamic>> res =
        await _api.getChangeCandidates(widget.restDayId);
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

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: FieldTokens.bgBase,
        appBar: AppBar(title: const Text('休む日を変える')),
        body: _buildBody(),
      );

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final err = _error;
    if (err != null) return _Trouble(text: err, onRetry: _load);

    // ★会社の休みの日が1日も設定されていない回。
    //   候補を並べても全部選べないので、BE が返した断りの文だけを出す。
    //   ★文は BE のもの（days[] の reason）。端末で書かない＝袋小路にしない。
    if (_data['holiday_def_configured'] != true) {
      final reason = _days
          .map((d) => '${d['reason'] ?? ''}')
          .firstWhere((t) => t.isNotEmpty, orElse: () => '');
      return _Trouble(
        text: reason.isEmpty ? '選べる日がありません' : reason,
        onRetry: _load,
      );
    }

    final workDate = '${_data['paired_work_date'] ?? ''}';
    final current = '${_data['current_rest_date'] ?? ''}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 出勤する日（変えられない）──────────────────────────
        //   ★灰色で出す＝この画面で動かせるのは休む日だけであることを、
        //     押せない見た目そのもので言う。
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FieldTokens.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Text('出勤する日（変えられません）',
                  style: TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12)),
              const Spacer(),
              Text(jpMonthDay(workDate),
                  style: const TextStyle(
                      color: FieldTokens.textSupport,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        const Text('新しい休む日を選んでください',
            style: TextStyle(
                color: FieldTokens.textSupport,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        // ── 候補（BE が返した7日をその順のまま）──────────────────
        for (final d in _days)
          _CandidateRow(
            day: d,
            busy: _busy,
            onTap: () => _confirm(d, current, workDate),
          ),

        const SizedBox(height: 16),
        // ── ※（モック D2 の3行・原文のまま）────────────────────
        //   ★1行目の週の両端は【BE が返した days[] の最初と最後の date】から出す。
        //     端末で「日曜から土曜」を数え直さない。数え直すと、BE が週の数え方を
        //     変えた日に、この文だけが古い週を名乗る（同じ問いの答えが2箇所になる）。
        //   ★日付の書き方は同じ画面の候補の行と同じ jpMonthDay に揃える
        //     （1つの画面に2通りの日付の書き方を作らない）。
        Text('※休む日を動かせるのは同じ週（$_weekFirst〜$_weekLast）の中だけです。',
            style: _note),
        const Text('※確認の期限は、いまの休む日と新しい休む日の、早い方の前日です。'
            '前の日に変えるほど期限も早まります。',
            style: _note),
        const Text('※選べるのは申し出の翌日からです。', style: _note),
      ],
    );
  }

  /// 週の最初の日／最後の日。★BE が返した days[] の両端そのもの。
  ///   ★days が空の回は日付を作らない（'—'）。無い物を有るように見せない。
  String get _weekFirst =>
      _days.isEmpty ? '—' : jpMonthDay('${_days.first['date'] ?? ''}');
  String get _weekLast =>
      _days.isEmpty ? '—' : jpMonthDay('${_days.last['date'] ?? ''}');

  /// 二度目の確認（D3）→ 通れば申し出る。
  Future<void> _confirm(
      Map<String, dynamic> day, String current, String workDate) async {
    if (_busy) return;
    final newDate = '${day['date'] ?? ''}';
    if (newDate.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _SecondConfirmDialog(
        current: current,
        newDate: newDate,
        workDate: workDate,
        deadline: '${day['deadline'] ?? ''}',
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final res = await _api.requestSubstituteChange(widget.restDayId, newDate);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      await showSubstituteDeny(context, '申し出られませんでした', res);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true); // 1件の画面へ戻り、あちらが読み直す
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

/// 候補の1行。★selectable が false なら押せない見た目にして、横に BE の reason を出す。
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.day,
    required this.busy,
    required this.onTap,
  });
  final Map<String, dynamic> day;
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
    final deadline = day['deadline'];

    return Opacity(
      // ★選べない日は薄く出す。消さないのは「その日がなぜ選べないか」を
      //   読めるようにするため（消すと理由ごと消える）。
      opacity: selectable ? 1.0 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap: (selectable && !busy) ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
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
                      // ★選べる日には確認の期限を出す（いつまでに決まるかを先に言う）。
                      ? Text(
                          deadline == null
                              ? ''
                              : '確認の期限 ${jpMonthDay('$deadline')}',
                          style: const TextStyle(
                              color: FieldTokens.textSupport, fontSize: 12))
                      // ★選べない理由は BE の文をそのまま。端末で言い換えない。
                      : Text(reason,
                          style: const TextStyle(
                              color: FieldTokens.textFaint, fontSize: 12)),
                ),
                if (selectable)
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

/// 二度目の確認（モック D3）。
///   ★2つともチェックしないと「申請する」を押せない。変更は一度きりで、
///     成立すると以後の変更ができないため、押し間違いで進める形にしない。
class _SecondConfirmDialog extends StatefulWidget {
  const _SecondConfirmDialog({
    required this.current,
    required this.newDate,
    required this.workDate,
    required this.deadline,
  });
  final String current;
  final String newDate;
  final String workDate;
  final String deadline;

  @override
  State<_SecondConfirmDialog> createState() => _SecondConfirmDialogState();
}

class _SecondConfirmDialogState extends State<_SecondConfirmDialog> {
  bool _once = false;   // 変更は一度きりであることを確認しました
  bool _own = false;    // この変更を自分の意思で申し出ます

  @override
  Widget build(BuildContext context) {
    final ready = _once && _own;
    return AlertDialog(
      backgroundColor: FieldTokens.surfaceCard,
      title: const Text('変更は一度きりです',
          style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '休む日を ${jpMonthDay(widget.current)} から '
                '${jpMonthDay(widget.newDate)} に変更することを申し出ます。'
                '変更が成立すると、以後の変更はできません。',
                style: const TextStyle(
                    color: FieldTokens.textBody, height: 1.6)),
            const SizedBox(height: 10),
            Text(
                '事務が確認したとき、または ${jpMonthDay(widget.deadline)} までに'
                '事務の確認がないときに成立します。'
                '出勤する日（${jpMonthDay(widget.workDate)}）は変わりません。',
                style: const TextStyle(
                    color: FieldTokens.textSupport,
                    fontSize: 12,
                    height: 1.6)),
            const SizedBox(height: 8),
            _Check(
              value: _once,
              label: '変更は一度きりであることを確認しました',
              onChanged: (v) => setState(() => _once = v),
            ),
            _Check(
              value: _own,
              label: 'この変更を自分の意思で申し出ます',
              onChanged: (v) => setState(() => _own = v),
            ),
            const SizedBox(height: 8),
            const Text('※申請を取り下げた場合は記録に残らず、回数も減りません。',
                style: _note),
            const Text('※実際の取り扱いは、雇用契約書および就業規則の定めによります。',
                style: _note),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('戻る',
              style: TextStyle(color: FieldTokens.textSupport)),
        ),
        TextButton(
          // ★2つ揃うまで null＝押せない。見た目だけ灰色にして押せる形にしない。
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          child: Text('申請する',
              style: TextStyle(
                  color: ready ? FieldTokens.accent : FieldTokens.textFaint)),
        ),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.value,
    required this.label,
    required this.onChanged,
  });
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                onChanged: (v) => onChanged(v == true),
                activeColor: FieldTokens.accent,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(label,
                      style: const TextStyle(
                          color: FieldTokens.textBody, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      );
}
