// ============================================================
// lib/screens/substitute_detail_screen.dart - 振替休日（1件）
//
// 承認済みモック field_substitute_flow_mock_v4.html の C1・D1・D4・D5・D6・E1 の
// 【表示だけ】。一覧・通知・カレンダーの「振替休日を開く」から来る。
//   →再（2026-09-28・便F12）: 「表示だけ」は元の姿（操作は下の★のとおり 2026-09-20 に足した）。
//   来る道は4つ＝振替休日の一覧の行（substitute_list_screen.dart）・お知らせの一覧の
//   「振替休日を開く」（notification_list_screen.dart）・カレンダーの箱の「振替休日を開く」
//   （home_screen.dart の CalendarTab）・スマホの通知を押したとき（fcm_service.dart の
//   handleNotificationTap・便F12 から）。
//   →再（2026-09-29・便F13）: 道は4つ足した＝ホームの同意待ちの枠（punch_screen.dart）・
//   同意待ちの振替の休む日で断られた窓の［振替休日を開く］（rest_day_screen.dart・
//   lib/widgets/comp_off_dialog.dart・substitute_register_screen.dart）・打刻の催促の窓の枠
//   （lib/widgets/punch_remind_dialog.dart）・振替の登録の画面の休む日の断り（substitute_register_screen.dart）。
//   どの道で開いても、この画面で状態が変わったら読み直しの知らせ（lib/utils/rest_day_refresh.dart）を鳴らし、
//   ホームとカレンダーはその1本で読み直す。
//   →再（2026-09-30・便F13続）: 上の「4つ」と「4つ足した」は数と名簿が合っていなかった（足した道は
//   ファイルで数えて5つ）。開く道の名簿はここ1か所に置く（lib/utils/rest_day_refresh.dart と下の service の
//   説明は、ここを指すだけ）。呼ぶ所は、lib で「SubstituteDetailScreen」のすぐ後ろに丸括弧が続く行
//   （grep -n で数える）から定義の行を除いた9か所で、1ファイルに1か所ずつ:
//     1. substitute_list_screen.dart … 振替休日の一覧の行（一覧が受けた service をそのまま渡す）
//     2. notification_list_screen.dart … お知らせの一覧の「振替休日を開く」（restDayId だけ）
//     3. home_screen.dart … カレンダー（CalendarTab）の箱の［振替休日を開く］（restDayId だけ）
//     4. lib/services/fcm_service.dart … スマホの通知を押したとき（handleNotificationTap・restDayId だけ）
//     5. punch_screen.dart … ホームの同意待ちの枠（自分が受けた差し替え口 reports をそのまま渡す）
//     6. rest_day_screen.dart … 本日休みの断りの窓の［振替休日を開く］（自分が受けた service をそのまま渡す）
//     7. lib/widgets/comp_off_dialog.dart … 代休の断りの窓の［振替休日を開く］（restDayId だけ）
//     8. substitute_register_screen.dart … 振替の登録の画面の休む日の断りと、登録の断りの窓の
//        ［振替休日を開く］（2つの押す所が同じ1つの呼ぶ所 _openPendingSubstitute・自分が受けた service を渡す）
//     9. lib/widgets/punch_remind_dialog.dart … 打刻の催促の窓の枠の［振替休日を開く］（restDayId だけ）
//   この画面で状態が変わったら鳴らすのは、この画面（_run の同意・取り下げ・取り消し）と、ここから開く
//   休む日の変更の画面（substitute_change_screen.dart の _confirm の申し出）。鳴らす所の名簿は
//   lib/utils/rest_day_refresh.dart の冒頭。
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
import '../utils/rest_day_refresh.dart';
import '../widgets/deny_reason_line.dart';
import 'substitute_change_screen.dart';
import 'substitute_list_screen.dart'
    show jpMonthDay, jpMonthDayOfIso, kSubstituteWaitColor;

/// 振替休日に同意できない理由の行の頭の語（便F14・ボス裁定【Q113】＝1・見本 claude/substitute_cannot_agree_mock_v1.html）。
///   ★置き場はここ1か所。1件の画面（C1・このファイル）・ホームの同意待ちの枠（P1・punch_screen.dart）・
///     カレンダーの箱（K2・K3・home_screen.dart）が同じこの1つを使う（同じ頭の語を3つのファイルに書き写さない）。
///     前例は home_screen.dart の kCannotApproveHead（承認の理由の行の頭の語を1つに置く）と、
///     SubstituteOpenButton をこのファイルに置いて3か所（ホームの枠・打刻の催促の窓・振替の登録の画面）で
///     使う形。行の文は lib/widgets/deny_reason_line.dart の denyReasonText で「{この語}：{理由}」に組む。
///   ★理由は BE の cannot_agree_reason をそのまま（端末で日付や日報を比べて作り直さない）。
const String kCannotAgreeHead = '同意できません';

/// その行（BE の rest_day・GET /rest-days/my の行・GET /rest-days/my/substitutes の行）に、ご本人が同意できるか。
///   ★BE の can_agree をそのまま読む（便B18）。鍵が無い答え（便B18 より前の BE）と null は【押せる扱い】
///     ＝`!= false`（今までどおりの姿・前例は home_screen.dart の canApproveReport）。
bool canAgreeSubstitute(Map<String, dynamic>? row) => row?['can_agree'] != false;

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
  ///     →再（2026-09-28・便F12）: 呼び出し側は4つ。notification_list_screen.dart・
  ///     home_screen.dart・fcm_service.dart（便F12 から）は restDayId だけを渡す。
  ///     substitute_list_screen.dart は、一覧が受けた service をそのまま下ろして渡す。
  ///     →再（2026-09-29・便F13）: 呼び出し側は増えた（上のファイル冒頭の→再）。punch_screen.dart・
  ///     rest_day_screen.dart・substitute_register_screen.dart は自分が受けた差し替え口をそのまま渡し、
  ///     lib/widgets/comp_off_dialog.dart・lib/widgets/punch_remind_dialog.dart は restDayId だけを渡す。
  ///     →再（2026-09-30・便F13続）: 呼び出し側の名簿（どこが service を渡し、どこが restDayId だけか）は
  ///     このファイル冒頭の名簿1か所に置く（ここに二重に持たない）。
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

  /// ★（便F13）同意待ちと事務の確認待ち（振替の「待ち」）は、substitute_list_screen.dart の
  ///   kSubstituteWaitColor ただ1本（値は今までと同じ statusWarning＝見た目は変わらない）。
  Color get _stateColor {
    if (_cancelled) return FieldTokens.textSupport;
    if (_restDay['pending_agreement'] == true) return kSubstituteWaitColor;
    if (_restDay['change_blocked'] == true) return FieldTokens.statusError;
    if (_restDay['change_requested_rest_date'] != null) {
      return kSubstituteWaitColor;
    }
    return FieldTokens.statusSuccess;
  }

  // ══════════════ 操作 ══════════════════════════════════════
  // ★どれを出すかは【BE の印だけ】で決める。日付や期限から端末で組み立てない。
  //   状態の見分け方は上の _stateLabel と【同じ順・同じ条件】。2つの置き場を作らない。
  //   →再（2026-10-04・便F14続）: 同意待ちの枝だけは、_stateLabel に無い BE の can_agree も見る
  //   （同意できない行の操作を選ぶため）。
  //     ・取消済み       … 操作なし（無い理由を言い切る）
  //     ・同意待ち       … 同意する ／ まだ決めない            （モック C1）
  //       →再（2026-10-04・便F14続）: 同意待ちで can_agree が false の行は、押せない［この振替に同意する］＋
  //       理由の行（DenyReasonLine）＋※の行（［まだ決めない］は出さない・見本 substitute_cannot_agree_mock_v1 の C1）。
  //     ・成立できない   … 申し出を取り下げる                  （E1）
  //     ・事務の確認待ち … 申し出を取り下げる                  （D4）
  //     ・変更済み       … この振替を取り消す だけ            （D6）
  //       ★「休む日を変える」を出さない理由: 変更は一度きりで、BE も
  //         SUBSTITUTE_CHANGE_ALREADY_SETTLED で断る。押せるのに必ず断られる
  //         ボタンを置くと「押すまで分からない」を作る。
  //     ・成立           … 休む日を変える ／ この振替を取り消す（D1）
  bool _busy = false;

  // ★（元）断られたら断りの窓を出して戻るだけ（読み直さない）。
  //   →再（2026-10-01・便F14）: reloadOnDeny を立てた回（今は同意＝_agree だけ）は、BE が符号を返した断り
  //   （errorCode がある回・今の8つの符号も便B18 の3つも）なら、窓を閉じた後に mounted を確かめてから
  //   _load で読み直す。画面を開いたまま日付が変わって押せた回も、読み直すと BE の can_agree が false に
  //   なって灰色になる（鍵と口は同じ今日のときだけ一致する＝BE の judgeAgreeSubstitute の★）。
  //   通信の失敗（符号が無い回）は今のまま読み直さない（読み直しても同じく引けない）。
  //   取り下げ・取り消しの道は今のまま（立てない）。
  Future<void> _run(
    String denyTitle,
    Future<ApiResult<Map<String, dynamic>>> Function() call, {
    bool popOnSuccess = false,
    bool reloadOnDeny = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await call();
    // ★通った（同意・取り下げ・取り消し）＝休みと振替の状態が変わった。ホームとカレンダーへ
    //   知らせる（lib/utils/rest_day_refresh.dart・便F13）。どの道でこの画面を開いても、
    //   読み直しはこの1本で届く（道ごとに「戻ったら読み直す」を書き足さない）。
    //   （元）mounted を見て戻った後に鳴らしていた（通った後にこの画面が閉じていると鳴らない）。
    //   →再（2026-09-30・便F13続）: 通ったら、この画面が閉じたかを見る前に1回だけ鳴らす。
    if (res.ok) RestDayRefresh.ring();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      await showSubstituteDeny(context, denyTitle, res);
      if (reloadOnDeny && res.errorCode != null && mounted) await _load();
      return;
    }
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
    await _run('同意できませんでした', () => _api.agreeSubstitute(widget.restDayId),
        reloadOnDeny: true);
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
    if (done == true) {
      // ★（元）休む日の変更を申し出た（変更の画面は触らない＝受けた done で知らせる・便F13）。
      //   →再（2026-09-30・便F13続）: 鳴らすのは変更の画面（substitute_change_screen.dart の _confirm）が、
      //   申し出が通った直後に閉じたかを見る前に鳴らす。ここでは鳴らさない（同じ出来事で2回鳴らさない・
      //   受けた done で鳴らすと、戻る前にこの画面が閉じた回に鳴らない）。この画面の読み直しはそのまま。
      await _load();
    }
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
  ///   →再（2026-10-04・便F14続）: 同意待ちの枝だけは、_stateLabel に無い BE の can_agree も見る
  ///   （同意できない行の操作を選ぶため）。
  ///   ★（2026-10-01・便F14・見本 substitute_cannot_agree_mock_v1 の C1）同意待ちで、BE の can_agree が
  ///     false の行（ご本人がこの振替に同意できない。BE の can_agree は同意の口の判定そのもの＝便B18 の
  ///     judgeAgreeSubstitute（同意の口の今の8つの断りと過去の日の決まり①②③）から作るので、①②③のほかに
  ///     例えば所属の顔が違う行（MEMBERSHIP_MISMATCH）でも false になる。理由の文は BE の
  ///     cannot_agree_reason をそのまま出す）は、
  ///     ［この振替に同意する］を押せない灰色で残し（消さない・【Q98】の決まり）、すぐ下に理由の1行
  ///     （DenyReasonLine・頭の語は kCannotAgreeHead・理由は BE の cannot_agree_reason をそのまま）と
  ///     ※の1行を出す。［まだ決めない］は出さない（決めることが無いため）。
  ///     理由の行と※の行に外側の余白は足さない（ボタンの下の余白 10 と、操作の後の SizedBox 20 のままで
  ///     見本の間になる）。can_agree が true・null・鍵なしのときは今のまま（canAgreeSubstitute）。
  List<Widget> get _actions {
    if (_cancelled) return const [];
    if (_restDay['pending_agreement'] == true &&
        !canAgreeSubstitute(_restDay)) {
      return [
        _ActionButton(
            label: 'この振替に同意する',
            tone: _Tone.accent,
            busy: _busy,
            enabled: false,
            onTap: _agree),
        DenyReasonLine(
            denyReasonText(kCannotAgreeHead, _restDay['cannot_agree_reason'])),
        const Text('※事務へご連絡ください。事務がこの振替を取り消します。',
            style: _noticeNote),
      ];
    }
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
///   ★（元）受けるのは中身が Map の ApiResult だけ・押す物は［閉じる］（accent）の1つだけ。
///     →再（2026-09-29・便F13）: 断りの窓を1本にするため、次の2つを足した（今の呼び手の見た目と動きは変えない）:
///     ・ApiResult の中身の型を問わない（読むのは errorMessage と errorDetails だけ）。本日休み
///       （RestDayMutation）・代休（CompOffTaken）の断りも同じこの窓に出す。
///     ・onOpenSubstitute を渡した回だけ［振替休日を開く］を足す。その回の［閉じる］は textSupport、
///       ［振替休日を開く］は accent の太字（見本 v1 の P2）。押すと窓を閉じてから onOpenSubstitute を呼ぶ。
///       使うのは、その日が同意待ちの振替の休む日で断られた回（SUBSTITUTE_PENDING_ON_DATE・便B17）。
Future<void> showSubstituteDeny(
  BuildContext context,
  String title,
  ApiResult<Object?> res, {
  VoidCallback? onOpenSubstitute,
}) async {
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
        if (onOpenSubstitute == null)
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる',
                style: TextStyle(color: FieldTokens.accent)),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onOpenSubstitute();
            },
            child: const Text('振替休日を開く',
                style: TextStyle(
                    color: FieldTokens.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    ),
  );
}

/// ［振替休日を開く］の形（見本 v1 の P1・便F13）。★この形の置き場はここ1か所。
///   読む所: ホームの同意待ちの枠（punch_screen.dart）・打刻の催促の窓の枠
///   （lib/widgets/punch_remind_dialog.dart）・振替の登録の画面の休む日の断り
///   （substitute_register_screen.dart）。写しを作らない。
///   ★テーマの OutlinedButton の既定（字 accent・幅いっぱい・高さ52・角丸10・字16 の太字）を
///     ここで上書きする: 高さ44・左右の余白14・角丸8・枠の線は本文色 1.5・字13 の太さ600・
///     字は本文色・地は透明・幅は字の幅。左に寄せるのは置く側（Align）。
///   ★押せる高さは 44（押せる物の決まり＝44以上）。tapTargetSize を shrinkWrap にして、
///     見た目の44と押せる44を同じにする（padded のままだと 48 の見えない余白が付く）。
class SubstituteOpenButton extends StatelessWidget {
  const SubstituteOpenButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: FieldTokens.textBody,
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: const BorderSide(color: FieldTokens.textBody, width: 1.5),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: const Text('振替休日を開く'),
      );
}

/// 操作ボタンの色の役割。★意味の色だけ（新しい色を作らない）。
enum _Tone { accent, danger, quiet }

/// 画面の下に並べる操作ボタン1つ。
///   ★処理中は押せなくする（二度押しで同じ口を2回叩かない）。
///   ★（元）押せなくなるのは busy の間だけで、押せないときの色の指定は無かった（線は _color のまま）。
///     →再（2026-10-01・便F14）: enabled（押せるか・既定は押せる）を足した。enabled が false のときは
///     押せない灰色＝線 outlineStrong・字 textFaint（前例 home_screen.dart の日報の承認と修正依頼の押せない
///     ボタンと同じ組・【Q98】）。高さと形は今のまま。busy の間の見た目は今のまま（線の色を変えない）。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.tone,
    required this.busy,
    required this.onTap,
    this.enabled = true,
  });
  final String label;
  final _Tone tone;
  final bool busy;
  final VoidCallback onTap;
  final bool enabled;

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
            onPressed: (busy || !enabled) ? null : onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: _color,
              disabledForegroundColor: enabled ? null : FieldTokens.textFaint,
              side: BorderSide(
                  color: enabled ? _color : FieldTokens.outlineStrong, width: 1),
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
