// ============================================================
// lib/screens/substitute_register_screen.dart - 振替休日を登録する（出勤する日を選ぶ）
//
// 承認済みモック field_substitute_flow_mock_v4.html の B3。
// 本日休みの画面の「振替で休む」と、カレンダーの箱の「振替で休む」から来る。
// どちらも手前で注意書き（B2）を読んでから入る。
//
// ★出どころは GET /rest-days/substitute/candidates?rest_date=… ただ1本。
//   返り＝{ rest_date, rest_date_is_workday, rest_date_reason_code,
//           rest_date_reason, holiday_def_configured, days[] }
//   →再（2026-09-29・便F13）: 頭に rest_date_pending_substitute_id も載る（便B17）。休む日を
//   同意待ちの振替が塞いでいる回（rest_date_reason_code が rest_date_pending_substitute）の、
//   その振替の id。この画面は休む日の断りの下に［振替休日を開く］を出すのに使う。
//   days[] の1つ＝{ date, dow, selectable, reason_code, reason }
//   ★選べる／選べないの判定も、選べない理由の文も【BE が返したものをそのまま】。
//     端末で曜日や休日から組み立て直さない。組み立てた瞬間、同じ判定が
//     BE と端末の2箇所に並び、片方だけ直せる二重真実になる。
//   ★並びも BE が返した順のまま（日曜〜土曜の7日）。端末で並べ替えない。
//   （元）days[] の reason_code は読んでいなかった（選べるかは selectable だけ・理由は reason の文だけ）。
//   →再（2026-10-07・便F8・見本 field_substitute_past_mock_v5 の A3・B1）: reason_code を1つだけ読む＝
//   no_report（「この日の日報がありません」）の行は、選べないが押せる行にして、押すと3択の画面
//   （substitute_past_day_screen.dart の showWorkDateNoReport）を開く。どの行が no_report かは BE が決める
//   （端末で過去の日か・会社の休みの日かを数えない）。ほかの reason_code は今までどおり読まない。
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
import '../utils/rest_day_refresh.dart';
import '../widgets/comp_off_dialog.dart' show showCompOffFlow;
import 'substitute_detail_screen.dart'
    show showSubstituteDeny, SubstituteDetailScreen, SubstituteOpenButton;
import 'substitute_list_screen.dart' show jpMonthDay;
// ★過去の日が入っていたときに事前の取り決めを尋ねる画面（A1・A2）。
//   曜日の文字の並び（kWeekdayJa）もあちらが唯一の持ち主で、下の候補の行が使う。
//   →再（2026-10-07・便F8）: 出勤する日の候補で no_report の行を押した時の3択の画面（B1・
//   showWorkDateNoReport）も、あちらに在る。
import 'substitute_past_day_screen.dart'
    show
        showSubstitutePastDay,
        SubstitutePastDayChoice,
        kWeekdayJa,
        showWorkDateNoReport,
        WorkDateNoReportChoice;

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

  // 「休む日」の箱（上に出す1行）。★候補を出す回と、休む日そのものが断られて
  //   候補を出さない回の【両方】が使う。写しを作らないために関数へ出した
  //   （中身は写す前と1バイトも同じ。「変える」を出す条件も同じ）。
  Widget _restDateBox() => Container(
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
      );

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final err = _error;
    if (err != null) return _Trouble(text: err, onRetry: _load);

    // ★休む日そのものが断られている回（2026-09-21 の裁定）。
    //   BE が応答の頭に rest_date_reason_code / rest_date_reason を載せてくる。
    //   ・候補の7日も「この内容で登録する」も出さない ─ どの日を選んでも登録は
    //     休む日の側で断られるので、選ばせるのは嘘になる。
    //   ・出すのは【休む日の行】（「変える」も今までと同じ条件）と、その下に
    //     BE の文をそのまま。端末で言い換えない・組み立てない。
    //   ★holiday_def_configured の見張りより【先】に見る。休む日そのものが
    //     断られているなら、候補の話をする前にそれを言う。
    final restReasonCode = _data['rest_date_reason_code'];
    if (restReasonCode != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        children: [
          _restDateBox(),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FieldTokens.surfaceCard,
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                  left: BorderSide(color: FieldTokens.statusWarning, width: 4)),
            ),
            child: Text('${_data['rest_date_reason'] ?? ''}',
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 13, height: 1.6)),
          ),
          // ★休む日を同意待ちの振替が塞いでいる回（rest_date_pending_substitute・便B17）だけ、
          //   上の断りの形（枠と BE の文）の下に［振替休日を開く］（便F13）。id は候補の口の
          //   rest_date_pending_substitute_id。戻ったら候補を引き直す（同意すると、この休む日の
          //   断りが事実でなくなるため）。
          if (restReasonCode == 'rest_date_pending_substitute' &&
              '${_data['rest_date_pending_substitute_id'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SubstituteOpenButton(
                onPressed: _busy
                    ? null
                    : () => _openPendingSubstitute(
                        '${_data['rest_date_pending_substitute_id']}',
                        reload: true),
              ),
            ),
          ],
        ],
      );
    }

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
        _restDateBox(),
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
            // ★便F8: BE が reason_code に no_report を付けた行だけ、押すと3択の画面（B1）を開く。
            onNoReportTap: () => _openNoReport(d),
          ),

        const SizedBox(height: 12),
        // ── ※（モック B3 の2行・→再 便F8 で3行）──────────────────
        //   ★週の両端は BE が返した days[] の最初と最後から出す。
        //   ★1行目は同じ意味のまま短くした（1画面に収めるため）。
        //   →再（2026-10-07・便F8）: 3行（見本 field_substitute_past_mock_v5 の A3 の1行を、週の※の
        //   すぐ下に足した）。字の形は今の※と同じ。
        Text('※同じ週（$_weekFirst〜$_weekLast）の会社休みの日から選びます。',
            style: _note),
        const Text('※過去の日を選べるのは、今日が入っている週の中だけです。',
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

  /// 候補の口が返した days[] から「日付 → 曜日の添字」を作る。
  ///   ★端末で曜日を数えない（BE の dow をそのまま写すだけ）。
  ///     2つの日は必ずこの週の7日に入っているので、ここから引ける。
  Map<String, int> _dowOf() {
    final out = <String, int>{};
    for (final d in _days) {
      final date = '${d['date'] ?? ''}';
      final dow = d['dow'];
      if (date.isNotEmpty && dow is int) out[date] = dow;
    }
    return out;
  }

  Future<void> _register() async {
    final work = _picked;
    if (work == null || _busy) return;
    setState(() => _busy = true);
    final res = await _api.registerSubstitute(widget.restDate, work);
    // ★振替を登録できた＝休みと振替が変わった。ホームとカレンダーへ知らせる（便F13）。
    //   （元）mounted を見て戻った後に鳴らしていた（通った後にこの画面が閉じていると鳴らない）。
    //   →再（2026-09-30・便F13続）: 通ったら、この画面が閉じたかを見る前に1回だけ鳴らす。
    if (res.ok) RestDayRefresh.ring();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      // ★過去の日が入っていた回だけ、事前の取り決めを尋ねる画面（A1）へ進む。
      //   ほかの断りは今までどおり showSubstituteDeny（1つも変えていない）。
      //   ★どの日が過去かは BE の past_dates をそのまま渡す（端末で数えない）。
      if (res.errorCode == 'SUBSTITUTE_PRIOR_AGREEMENT_REQUIRED') {
        await _askPriorAgreement(work, res.errorDetails?['past_dates']);
        return;
      }
      await showSubstituteDeny(context, '登録できませんでした', res,
          onOpenSubstitute: _pendingOpenerOf(res));
      return;
    }
    // ★（元）通ったら呼び手へ true を返す。数（要対応・カレンダー・一覧）の読み直しは
    //   呼び手が持っている（この画面はどこから来たかを知らない）。
    //   →再（2026-09-29・便F13）: true は今も返す。ホームの要対応の件数とカレンダーの読み直しは、
    //   上で鳴らした読み直しの知らせ（lib/utils/rest_day_refresh.dart）が届ける。
    Navigator.of(context).pop(true);
  }

  // 同意待ちの振替の休む日で断られた回（SUBSTITUTE_PENDING_ON_DATE・便B17）だけ、断りの窓に
  //   ［振替休日を開く］を足す（便F13）。id は断りの本文の rest_day_id。ほかの断りは null＝今の窓のまま。
  //   （元）戻っても候補を引き直さなかった。→再（2026-09-30・便F13続）: 休む日の断りの［振替休日を開く］と
  //   同じく、戻ったら候補を引き直す（reload: true・同意するとこの休む日の断りと候補が事実でなくなるため）。
  VoidCallback? _pendingOpenerOf(ApiResult<Object?> res) {
    if (res.errorCode != 'SUBSTITUTE_PENDING_ON_DATE') return null;
    final id = '${res.errorDetails?['rest_day_id'] ?? ''}';
    if (id.isEmpty) return null;
    return () => _openPendingSubstitute(id, reload: true);
  }

  // その1件の画面を開く（便F13）。★差し替え口はそのまま下ろす。
  //   （元）reload が true（休む日の断りの［振替休日を開く］）なら、戻ったら候補を引き直す。
  //   →再（2026-09-30・便F13続）: reload が true なのは、休む日の断りと断りの窓（_pendingOpenerOf）の
  //   ［振替休日を開く］の両方＝今の呼び手はどちらも引き直す。引き直すと選んだ出勤する日は消える（_load）。
  Future<void> _openPendingSubstitute(String id, {bool reload = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          SubstituteDetailScreen(restDayId: id, service: widget.service),
    ));
    if (reload && mounted) await _load();
  }

  /// 事前の取り決めを尋ねて、答えで道を分ける（A1・A2 の返りを受ける側）。
  ///   ・取り決めていた … 同じ2つの日に prior_agreement: true を付けて出し直す。
  ///   ・代休で取る     … 代休の受け皿（showCompOffFlow）を開く。取れたら閉じる。
  ///                      →再（2026-10-07・便F8）: 中身は _goCompOff へ出した（3択の画面と同じ1つの道）。
  ///   ・日を選び直す   … 選んだ日を消してこの画面に残る。
  ///   ・戻る（null）   … 何もせずこの画面に残る。
  Future<void> _askPriorAgreement(String work, dynamic rawPastDates) async {
    // past_dates は BE の配列をそのまま文字列にするだけ（中身を作らない）。
    final pastDates = (rawPastDates is List)
        ? rawPastDates.map((x) => '$x').toList()
        : <String>[];
    final choice = await showSubstitutePastDay(
      context,
      restDate: widget.restDate,
      pairedWorkDate: work,
      pastDates: pastDates,
      dowOf: _dowOf(),
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case SubstitutePastDayChoice.agreed:
        setState(() => _busy = true);
        final again = await _api.registerSubstitute(widget.restDate, work,
            priorAgreement: true);
        // ★登録できた（便F13・上の _register と同じ）。→再（2026-09-30・便F13続）: 閉じたかを見る前に1回だけ鳴らす。
        if (again.ok) RestDayRefresh.ring();
        if (!mounted) return;
        setState(() => _busy = false);
        if (!again.ok) {
          // ★2回目の断りは今までどおりの箱（ここでもう一度 A1 を出さない＝
          //   同じ問いを繰り返しても答えは変わらない）。
          await showSubstituteDeny(context, '登録できませんでした', again,
              onOpenSubstitute: _pendingOpenerOf(again));
          return;
        }
        Navigator.of(context).pop(true);
      case SubstitutePastDayChoice.compOff:
        await _goCompOff();
      case SubstitutePastDayChoice.pickAnother:
        // 選んだ日を消してこの画面に残る（候補はそのまま・引き直さない）。
        setState(() => _picked = null);
    }
  }

  /// 「代休で取る」の道（事前の取り決めの画面 A2 と、3択の画面 B1 の両方から来る）。
  ///   （元）_askPriorAgreement の中に直に書いていた。
  ///   →再（2026-10-07・便F8）: 3択の「代休で取る」も同じ1つの道へ寄せるため、中身を変えずにここへ出した
  ///   （代休の受け皿 showCompOffFlow を呼ぶ所は、この画面に1か所のまま＝呼ぶ所を増やさない）。
  Future<void> _goCompOff() async {
    // ★休む日は【この画面が持っている値】をそのまま渡す（入口の★と同じ）。
    final took = await showCompOffFlow(context, restDate: widget.restDate);
    if (!mounted || !took) return; // 取らなければこの画面に残る
    Navigator.of(context).pop(true);
  }

  /// 候補で no_report の行（「この日の日報がありません」）を押した時（便F8・見本 v5 の A3 → B1）。
  ///   ・出勤の修正依頼を送れた … 候補を引き直す（引き直すと選んでいた日は消える＝_load の動き）
  ///   ・代休で取る … 事前の取り決めの「代休で取る」と同じ道（_goCompOff）
  ///   ・日を選び直す … 選んだ日を消してこの画面に残る
  ///   ・戻る（null） … 何もせずこの画面に残る（選んだ日は残る）
  ///   ★曜日・依頼の※の期限は候補の口の days[] から字で渡す（端末で数えない）。期限＝その週の土曜＝
  ///     days[] の最後の日（_weekLast と同じ端）。
  Future<void> _openNoReport(Map<String, dynamic> d) async {
    final choice = await showWorkDateNoReport(
      context,
      workDate: '${d['date'] ?? ''}',
      dateText: _dayText(d),
      permitUntilText: _days.isEmpty ? '—' : _dayText(_days.last),
      service: widget.service,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case WorkDateNoReportChoice.requested:
        await _load();
      case WorkDateNoReportChoice.compOff:
        await _goCompOff();
      case WorkDateNoReportChoice.pickAnother:
        setState(() => _picked = null);
    }
  }
}

/// 候補の1日の「M月D日（曜）」。曜日は BE の dow をそのまま（分からなければ付けない）。
///   ★便F8 で関数へ出した（候補の行の字と、3択・依頼の画面へ渡す字を同じ1本で作る）。
///     中身は今の候補の行が組んでいた字と1字も同じ。
String _dayText(Map<String, dynamic> day) {
  final date = '${day['date'] ?? ''}';
  final dowIdx = day['dow'];
  final dowText = (dowIdx is int && dowIdx >= 0 && dowIdx < 7)
      // ★曜日の文字の並びは substitute_past_day_screen.dart の kWeekdayJa ただ1本
      //   （事前の取り決めの画面と同じものを使う＝写しを作らない）。
      ? '（${kWeekdayJa[dowIdx]}）'
      : '';
  return '${jpMonthDay(date)}$dowText';
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
///   →再（2026-10-07・便F8・見本 field_substitute_past_mock_v5 の A3）: reason_code が no_report の行
///     （「この日の日報がありません」）だけは、選べないが押せる行にする。薄くしない（不透明度も日付の字の色も
///     選べる行と同じ）・枠の線を brand の1・右の字（BE の reason）を brand・その右に chevron（brand）。
///     押すと onNoReportTap（3択の画面 B1）。登録を送っている間は押せない（今の行と同じ）。
///     ★過去の日か・会社の休みの日かを端末で数えない（BE が no_report を付けた行だけ）。
///     ほかの選べない行（report_unapproved を含む）と選べる行は今のまま。
class _WorkDateRow extends StatelessWidget {
  const _WorkDateRow({
    required this.day,
    required this.picked,
    required this.busy,
    required this.onTap,
    required this.onNoReportTap,
  });
  final Map<String, dynamic> day;
  final bool picked;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onNoReportTap;

  @override
  Widget build(BuildContext context) {
    final selectable = day['selectable'] == true;
    // ★選べない行のうち、BE が no_report を付けた行だけ（便F8）。
    final noReport = !selectable && day['reason_code'] == 'no_report';
    // 見た目を選べる行と同じにするか（不透明度と日付の字の色）。
    final lively = selectable || noReport;
    final reason = '${day['reason'] ?? ''}';

    return Opacity(
      opacity: lively ? 1.0 : 0.55,
      child: Container(
        // ★行の間だけ詰める（8 → 4）。行そのものの高さは下の padding で保つ。
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: picked
              ? Border.all(color: FieldTokens.accent, width: 2)
              : noReport
                  ? Border.all(color: FieldTokens.brand, width: 1)
                  : null,
        ),
        child: InkWell(
          onTap: busy
              ? null
              : selectable
                  ? onTap
                  : noReport
                      ? onNoReportTap
                      : null,
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
                  child: Text(_dayText(day),
                      style: TextStyle(
                          color: lively
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
                          style: TextStyle(
                              color: noReport
                                  ? FieldTokens.brand
                                  : FieldTokens.textFaint,
                              fontSize: 12)),
                ),
                if (picked)
                  const Icon(Icons.check,
                      color: FieldTokens.accent, size: 20)
                else if (selectable)
                  const Icon(Icons.chevron_right,
                      color: FieldTokens.textFaint, size: 20)
                else if (noReport)
                  const Icon(Icons.chevron_right,
                      color: FieldTokens.brand, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
