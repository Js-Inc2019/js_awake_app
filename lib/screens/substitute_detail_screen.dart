// ============================================================
// lib/screens/substitute_detail_screen.dart - 振替休日（1件）
//
// 承認済みモック field_substitute_flow_mock_v4.html の C1・D1・D4・D5・D6・E1 の
// 【表示だけ】。一覧・通知・カレンダーの「振替休日を開く」から来る。
//
// ★2026-09-20 に【操作】を足した（同意する・休む日を変える・申し出を取り下げる・
//   この振替を取り消す）。どれを出すかは BE の印だけで決める（下の _actions の★）。
//   ★断りは BE の error をそのまま出し、閉じるまで消えない形にする
//     （流れて消えるものにしない＝押した人がもう一度読める）。
//
// ★出どころは GET /rest-days/:id ただ1本（rest_day と events）。
//   ★events の text は BE の文をそのまま出す。端末で書き換えない・言い換えない。
//     並びも BE が返した順（古い順）のまま。端末で並べ替えない・畳まない。
//
// 色は FieldTokens のみ（直書き禁止・新しい色を作らない）。
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../services/api_result.dart';
import '../services/reports_service.dart';
import 'substitute_change_screen.dart';
import 'substitute_list_screen.dart' show jpMonthDay, jpMonthDayOfIso;

class SubstituteDetailScreen extends StatefulWidget {
  const SubstituteDetailScreen({
    super.key,
    required this.restDayId,
    this.service,
  });

  final String restDayId;

  /// 口の差し替え（検査だけが渡す）。既定は null＝今までどおり ReportsService()。
  ///   ★なぜ要るか【Q70】と形は substitute_list_screen.dart の同じ引数の★と同じ。
  ///   ★呼び出し側（notification_list_screen.dart / home_screen.dart）は
  ///     restDayId だけを渡しており、1文字も変わらない。
  final ReportsService? service;

  @override
  State<SubstituteDetailScreen> createState() => _SubstituteDetailScreenState();
}

class _SubstituteDetailScreenState extends State<SubstituteDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _restDay = const {};
  List<Map<String, dynamic>> _events = const [];

  /// 実際に叩く口。★本番は今までどおり ReportsService()。
  late final ReportsService _api = widget.service ?? ReportsService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final ApiResult<Map<String, dynamic>> res =
        await _api.getRestDay(widget.restDayId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!res.ok) {
        _error = res.errorMessage ?? 'この振替休日を開けませんでした';
        _restDay = const {};
        _events = const [];
        return;
      }
      final d = res.data ?? const <String, dynamic>{};
      _restDay = (d['rest_day'] is Map)
          ? Map<String, dynamic>.from(d['rest_day'] as Map)
          : const <String, dynamic>{};
      _events = ((d['events'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  /// 取り消し済みか。★BE が返す cancelled_at ただ1本で決める。
  ///   ★2026-09-20 に events から読む形をやめた。それまでは記録（events）に
  ///     'cancelled' の行が在るかどうかで導いていたが、events は
  ///     【人に読ませる記録】であって状態の印ではない。BE が印を持っているのに
  ///     端末で組み立て直す形になっていた（change_blocked を直したのと同じ穴）。
  ///     BE が GET /rest-days/:id の rest_day に cancelled_at を載せたので、それを読む。
  ///   ★キーが無い回の分岐は作らない。端末はサーバーより後に焼かれる
  ///     （サーバーが先に新しくなる）ので、古いサーバー向けの道は実際には通らない。
  ///     無い回は null＝取消済みを出さない＝change_blocked と同じ扱いで揃える。
  ///   ★真偽に潰さず時刻のまま受け取り、ここでは「在るか」だけを見る。
  bool get _cancelled => _restDay['cancelled_at'] != null;

  /// 上に出す状態。★BE が返した印と列だけで決める（日付の比較はしない）。
  ///   ・取消済み       … cancelled_at が入っている
  ///   ・同意待ち       … pending_agreement
  ///   ・成立できません … change_blocked（1件の口が返す真偽）
  ///   ・事務の確認待ち … 申し出の列が入っている（change_requested_rest_date）
  ///   ・変更済み       … 成立の列が入っている（change_settled_at）
  ///   ・成立           … 残り
  ///
  /// ★change_blocked を1件の口から読む形に直した（2026-09-20）。それまでは
  ///   一覧から【引数で持ち込む】形だったため、通知やカレンダーから直に開いた回は
  ///   印が渡らず「成立できません」が出なかった＝同じ1件が入口によって違って見えた。
  ///   BE が一覧の口と1件の口の両方で同じ式から同じ真偽を返すようになったので、
  ///   どちらの入口から来ても、この画面は自分で読んだ印だけで同じ状態を出す。
  /// ★change_blocked を返さない回（古いサーバー）はキーが無く null＝false になり、
  ///   「成立できません」を出さない。端末で期限と今日を比べて作り直さない。
  String get _stateLabel {
    if (_cancelled) return '取消済み';
    if (_restDay['pending_agreement'] == true) return '同意待ち';
    if (_restDay['change_blocked'] == true) return '成立できません';
    if (_restDay['change_requested_rest_date'] != null) return '事務の確認待ち';
    if (_restDay['change_settled_at'] != null) return '変更済み';
    return '成立';
  }

  Color get _stateColor {
    if (_cancelled) return FieldTokens.textSupport;
    if (_restDay['pending_agreement'] == true) return FieldTokens.statusWarning;
    if (_restDay['change_blocked'] == true) return FieldTokens.statusError;
    if (_restDay['change_requested_rest_date'] != null) {
      return FieldTokens.statusWarning;
    }
    return FieldTokens.statusSuccess;
  }

  // ══════════════ 操作 ══════════════════════════════════════
  // ★どれを出すかは【BE の印だけ】で決める。日付や期限から端末で組み立てない。
  //   状態の見分け方は上の _stateLabel と【同じ順・同じ条件】。2つの置き場を作らない。
  //     ・取消済み       … 操作なし（無い理由を言い切る）
  //     ・同意待ち       … 同意する ／ まだ決めない            （モック C1）
  //     ・成立できない   … 申し出を取り下げる                  （E1）
  //     ・事務の確認待ち … 申し出を取り下げる                  （D4）
  //     ・変更済み       … この振替を取り消す だけ            （D6）
  //       ★「休む日を変える」を出さない理由: 変更は一度きりで、BE も
  //         SUBSTITUTE_CHANGE_ALREADY_SETTLED で断る。押せるのに必ず断られる
  //         ボタンを置くと「押すまで分からない」を作る。
  //     ・成立           … 休む日を変える ／ この振替を取り消す（D1）
  bool _busy = false;

  Future<void> _run(
    String denyTitle,
    Future<ApiResult<Map<String, dynamic>>> Function() call, {
    bool popOnSuccess = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      await showSubstituteDeny(context, denyTitle, res);
      return;
    }
    if (!mounted) return;
    if (popOnSuccess) {
      // ★取り消したあとはこの画面に用が無い。一覧へ戻す（一覧は戻ったら読み直す）。
      Navigator.of(context).pop(true);
      return;
    }
    await _load(); // BE の真実へ追随
  }

  Future<void> _agree() async {
    if (!await showSubstituteNotice(context)) return;
    if (!mounted) return;
    await _run('同意できませんでした', () => _api.agreeSubstitute(widget.restDayId));
  }

  Future<void> _openChange() async {
    if (!await showSubstituteNotice(context)) return;
    if (!mounted) return;
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SubstituteChangeScreen(
        restDayId: widget.restDayId,
        service: widget.service,
      ),
    ));
    if (!mounted) return;
    if (done == true) await _load();
  }

  Future<void> _withdraw() => _run(
        '取り下げられませんでした',
        () => _api.withdrawSubstituteChange(widget.restDayId),
      );

  Future<void> _cancel() async {
    final restDate = '${_restDay['rest_date'] ?? ''}';
    final workDate = '${_restDay['paired_work_date'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        title: const Text('この振替を取り消しますか？',
            style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '休む日 ${jpMonthDay(restDate)}と、'
                '出勤する日 ${jpMonthDay(workDate)}の入れ替えを取り消します。',
                style: const TextStyle(color: FieldTokens.textBody)),
            const SizedBox(height: 10),
            Text('取り消すと、${jpMonthDay(workDate)}は会社の休みの日の扱いに戻ります。',
                style: const TextStyle(
                    color: FieldTokens.textSupport, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('戻る',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('取り消す',
                style: TextStyle(color: FieldTokens.statusWarning)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      '取り消せませんでした',
      () => _api.cancelRestDayById(widget.restDayId),
      popOnSuccess: true,
    );
  }

  /// その状態に要る操作だけ。★条件は _stateLabel と同じ順・同じ印。
  List<Widget> get _actions {
    if (_cancelled) return const [];
    if (_restDay['pending_agreement'] == true) {
      return [
        _ActionButton(
            label: 'この振替に同意する',
            tone: _Tone.accent,
            busy: _busy,
            onTap: _agree),
        _ActionButton(
            label: 'まだ決めない',
            tone: _Tone.quiet,
            busy: _busy,
            // ★「まだ決めない」は何も送らずに閉じるだけ。押した人を元の場所へ返す。
            onTap: () => Navigator.of(context).pop()),
      ];
    }
    if (_restDay['change_blocked'] == true ||
        _restDay['change_requested_rest_date'] != null) {
      return [
        _ActionButton(
            label: '申し出を取り下げる',
            tone: _Tone.accent,
            busy: _busy,
            onTap: _withdraw),
      ];
    }
    if (_restDay['change_settled_at'] != null) {
      return [
        _ActionButton(
            label: 'この振替を取り消す',
            tone: _Tone.danger,
            busy: _busy,
            onTap: _cancel),
      ];
    }
    return [
      _ActionButton(
          label: '休む日を変える',
          tone: _Tone.accent,
          busy: _busy,
          onTap: _openChange),
      _ActionButton(
          label: 'この振替を取り消す',
          tone: _Tone.danger,
          busy: _busy,
          onTap: _cancel),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(title: const Text('振替休日')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final err = _error;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(err,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FieldTokens.textSupport)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('もう一度')),
            ],
          ),
        ),
      );
    }

    final requested = _restDay['change_requested_rest_date'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 状態 ─────────────────────────────────────────────
        Text(_stateLabel,
            style: TextStyle(
                color: _stateColor,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        // ── はじめにご確認ください（同意待ちのときだけ）─────────────
        //   ★出すのは【同意待ちの状態のときだけ】。まだ頷いていない人に、
        //     何に頷くのかを先に言うための注意書きなので、成立した後や
        //     事務の確認待ちの回に出すと「もう決まった話」を蒸し返す形になる。
        //   ★文はモック B2 の原文をそのまま写した（1文字も変えていない）。
        //     端末で言い換えない＝同じ事実に2通りの言い方を作らない。
        if (_restDay['pending_agreement'] == true) ...[
          const _AgreementNotice(),
          const SizedBox(height: 20),
        ],

        // ── 日付 ─────────────────────────────────────────────
        //   ★申し出中は「いまの休む日」と「変えたい休む日」を上下に出す
        //     （どちらが効いているのかを取り違えないため）。
        _Line('出勤する日', jpMonthDay('${_restDay['paired_work_date'] ?? ''}')),
        if (requested == null)
          _Line('休む日', jpMonthDay('${_restDay['rest_date'] ?? ''}'))
        else ...[
          _Line('いまの休む日', jpMonthDay('${_restDay['rest_date'] ?? ''}')),
          _Line('変えたい休む日', jpMonthDay('$requested')),
          if (_restDay['change_deadline'] != null)
            _Line('確認の期限', jpMonthDay('${_restDay['change_deadline']}')),
        ],
        if (_restDay['change_from_date'] != null)
          _Line('変更前の休む日', jpMonthDay('${_restDay['change_from_date']}')),

        const SizedBox(height: 20),

        // ── 操作（その状態に要るものだけ）──────────────────────
        //   ★出し分けは _actions ただ1箇所（条件をここへもう一度書かない）。
        ..._actions,
        // ★操作が0個のときは、無いことと理由を言い切る（沈黙にしない）。
        if (_actions.isEmpty)
          const Text('この振替は取り消し済みです。行える操作はありません。',
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
        const SizedBox(height: 20),

        // ── 記録 ─────────────────────────────────────────────
        //   ★BE が並べた順のまま。text は BE の文をそのまま出す。
        const Text('記録',
            style: TextStyle(
                color: FieldTokens.textSupport,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_events.isEmpty)
          const Text('記録はありません',
              style: TextStyle(color: FieldTokens.textFaint, fontSize: 13)),
        for (final e in _events)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(jpMonthDayOfIso('${e['at'] ?? ''}'),
                      style: const TextStyle(
                          color: FieldTokens.textFaint, fontSize: 12)),
                ),
                Expanded(
                  child: Text('${e['text'] ?? ''}',
                      style: const TextStyle(
                          color: FieldTokens.textBody, fontSize: 14)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 注意書き B2 の文（モック field_substitute_flow_mock_v4）
//
// ★本文1 は【画面の枠】（同意待ちのときに出しっぱなしにする方）と
//   【押す手前のダイアログ】の両方に出る、まったく同じ1文。写しを2つ持つと、
//   片方だけ直した日に同じ注意書きが2通りになる。だから1箇所に置いて共有する。
// ★太字は読み違えるとその人の賃金の受け取り方が変わる語だけ:
//   「前もって入れ替える」「休日の割増賃金は発生しません」、本文2 では「後」。
// ══════════════════════════════════════════════════════════════

const TextStyle _noticeBody = TextStyle(
    color: FieldTokens.textBody, fontSize: 14, height: 1.6);
const TextStyle _noticeStrong = TextStyle(
    color: FieldTokens.textBody,
    fontSize: 14,
    height: 1.6,
    fontWeight: FontWeight.bold);
const TextStyle _noticeNote = TextStyle(
    color: FieldTokens.textSupport, fontSize: 12, height: 1.6);

/// B2 の本文1。★ここが唯一の置き場（枠もダイアログもこれを使う）。
const Widget kNoticeBody1 = Text.rich(
  TextSpan(children: [
    TextSpan(text: '振替休日は、出勤する日と休む日を', style: _noticeBody),
    TextSpan(text: '前もって入れ替える', style: _noticeStrong),
    TextSpan(text: 'しくみです。入れ替えた出勤日は通常の労働日となり、', style: _noticeBody),
    TextSpan(text: '休日の割増賃金は発生しません', style: _noticeStrong),
    TextSpan(text: '。', style: _noticeBody),
  ]),
);

/// B2 の本文2。★太字は「後」ただ1文字（代休との違いが「働いた後か前か」なので）。
const Widget kNoticeBody2 = Text.rich(
  TextSpan(children: [
    TextSpan(text: '休日に働いた', style: _noticeBody),
    TextSpan(text: '後', style: _noticeStrong),
    TextSpan(text: 'に休む代休とは、賃金の扱いが異なります。', style: _noticeBody),
  ]),
);

const String kNoticeHead = 'はじめにご確認ください';

/// 注意書きの枠（見出し＋本文）。★※は枠の【外】なので、ここには入れない。
class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: const Border(
              left: BorderSide(color: FieldTokens.statusWarning, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(kNoticeHead,
                style: TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );
}

/// 画面に出しっぱなしにする方の注意書き（同意待ちのときだけ・前の便で入れた）。
///   ★※の2行は【枠の外】に置く。枠の中は本文だけ＝「何のしくみか」と
///     「いま何が要るか・最終的に何が決めるか」を同じ重さで並べない。
class _AgreementNotice extends StatelessWidget {
  const _AgreementNotice();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NoticeBox(children: [kNoticeBody1]),
          SizedBox(height: 8),
          // ★文は原文のまま。頭の「※」だけが印で、本文には1文字も足していない。
          Text('※同意するまで、この振替は成立しません。', style: _noticeNote),
          Text('※実際の取り扱いは、雇用契約書および就業規則の定めによります。',
              style: _noticeNote),
        ],
      );
}

/// 押す手前に毎回出す注意書き（B2）。true＝「確認しました」。
///   ★【同意するとき】と【休む日を変えるとき】の手前で毎回出す。
///     「一度出したから2回目は省く」にしない。賃金の扱いが変わる操作は、
///     押すたびに同じ言葉を読んでから進む（覚えているはず、で飛ばさない）。
Future<bool> showSubstituteNotice(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: FieldTokens.surfaceCard,
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NoticeBox(children: [
              kNoticeBody1,
              SizedBox(height: 10),
              kNoticeBody2,
            ]),
            SizedBox(height: 8),
            // ★※は枠の外。
            Text('※実際の取り扱いは、雇用契約書および就業規則の定めによります。'
                'ご不明な点は事務までご確認ください。',
                style: _noticeNote),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('やめる',
              style: TextStyle(color: FieldTokens.textSupport)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('確認しました',
              style: TextStyle(color: FieldTokens.accent)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 断りを出す。★BE の文をそのまま・閉じるまで消えない形（流れて消えない）。
///   ★英字の code は出さない（読む人の言葉ではない）。
///   ★deadline が返っている回で、BE の文にその日付がまだ入っていないときだけ
///     期限を別の行で添える。入っているのに足すと同じ日付を2回言うことになる。
Future<void> showSubstituteDeny(
  BuildContext context,
  String title,
  ApiResult<Map<String, dynamic>> res,
) async {
  final beText = res.errorMessage ?? '';
  final deadline = res.errorDetails?['deadline'];
  final extra = (deadline != null && !beText.contains(jpMonthDay('$deadline')))
      ? '\n\n確認の期限は ${jpMonthDay('$deadline')} でした。'
      : '';
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: FieldTokens.surfaceCard,
      title: Text(title,
          style: const TextStyle(color: FieldTokens.textBody, fontSize: 16)),
      content: Text(
        beText.isEmpty ? 'できませんでした。時間をおいて、もう一度お試しください。' : '$beText$extra',
        style: const TextStyle(color: FieldTokens.textBody),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('閉じる',
              style: TextStyle(color: FieldTokens.accent)),
        ),
      ],
    ),
  );
}

/// 操作ボタンの色の役割。★意味の色だけ（新しい色を作らない）。
enum _Tone { accent, danger, quiet }

/// 画面の下に並べる操作ボタン1つ。
///   ★処理中は押せなくする（二度押しで同じ口を2回叩かない）。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.tone,
    required this.busy,
    required this.onTap,
  });
  final String label;
  final _Tone tone;
  final bool busy;
  final VoidCallback onTap;

  Color get _color => switch (tone) {
        _Tone.accent => FieldTokens.accent,
        _Tone.danger => FieldTokens.statusWarning,
        _Tone.quiet => FieldTokens.textSupport,
      };

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: _color,
              side: BorderSide(color: _color, width: 1),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(label,
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: FieldTokens.textBody, fontSize: 16)),
            ),
          ],
        ),
      );
}
