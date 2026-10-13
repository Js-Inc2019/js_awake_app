// ============================================================
// lib/widgets/day_request_entry.dart - 日報漏れの申告の入口（カレンダーの箱の中）と、
//   尋ねる口の答えの読み方（便F8・見本 field_substitute_past_mock_v5 の D1・D3・ボス裁定【Q89】）
//
// ★このファイルが持つもの:
//   ・readDayRequestEligibility … 尋ねる口の答えを3つ（出せる日／出せない日／聞けなかった時）に分ける
//     ただ1か所。3択の画面（substitute_past_day_screen.dart）と、この箱の入口が同じ物を呼ぶ（写しを作らない）。
//   ・DayRequestTrouble … 聞けなかった時の出し方（理由の行＋「もう一度」）。これも両方が同じ物を使う。
//   ・shouldOfferDayRequestEntry … 箱に入口を出す日か（出すなら尋ねる口に聞く・出さないなら聞かない）。
//   ・ownLiveReportCount … その日の生きている日報のうち、自分の物の数。
//   ・dayRequestEntryOrNull … 上の条件が真なら入口の部品を、偽なら null を返す（箱を開く所はこれを1回呼ぶだけ）。
//   ・DayRequestEntry … 箱の中の入口（開いたら1回だけ聞き、答えで出し方を変える）。
//   →再（2026-10-11・便F8b-2）: 答えの分かれに4つ目「許可が出ている日」（permitted）を足した。
//     その日は、箱の入口と3択の画面に「この日の日報を出す」を出し、後から出す日報の画面
//     （lib/screens/late_report_screen.dart の LateReportScreen）を開く。出せるかはサーバに聞いて決める（端末で数えない）。
//
// ★端末は「聞くかどうか」だけを決め、出せるかどうかはサーバが決める。
//   週・締め期間・曜日を端末で数えない（今日より前かだけは、呼び手が渡す今日の字と比べる）。
//   ★このファイルの中では時計を読まない（今日は箱を開く所が1回だけ読んで渡す＝検査が今日を字で渡せる）。
// ★サーバの文（reason・error）は言い換えない・切らない。例外の字や本文の頭の字は画面に出さない。
//
// 色は FieldTokens のみ（直書き禁止・新しい色を作らない）。
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../screens/day_request_screen.dart' show DayRequestKind, DayRequestScreen;
import '../screens/late_report_screen.dart' show LateReportResult, LateReportScreen;
import '../screens/substitute_past_day_screen.dart'
    show PastDayFrame, kPastDayFrameBody, kPastDayNote, pastDayOutlinedButton;
import '../services/api_result.dart';
import '../services/reports_service.dart';

// ── 答えの読み方（3択の画面と箱の入口で同じ1つの決まり）────────────────

/// 尋ねる口の答えの3つの分かれ。
enum DayRequestEligibilityKind {
  /// 出せる日（答えが届いて can_declare が true）。
  allowed,

  /// 出せない日（答えが届いて can_declare が false で reason が空でない／
  ///   サーバが符号つきで断った＝400〜499 で errorCode も errorMessage も空でない）。
  denied,

  /// 許可が出ている日（便F8b-2）＝答えが届いて can_declare が false・code が 'ALREADY_PERMITTED'・
  ///   reason と request_id と permit_until がそろっている。まだ日報を出していない（出した後は REPORT_EXISTS）。
  ///   text は BE の reason、answer の request_id・confirm_type・permit_until を後から出す日報の画面へ渡す。
  ///   ★そろっていない時は「聞けなかった時」（unknown）にする（足りない値で画面を開かない）。
  permitted,

  /// 聞けなかった時（それ以外の全部）。★黙って「出せる日」にしない・黙って消さない。
  unknown,
}

/// 尋ねる口の答えを読んだ結果。
class DayRequestEligibility {
  const DayRequestEligibility(this.kind, {this.text, this.answer});

  final DayRequestEligibilityKind kind;

  /// 画面に出す文。
  ///   ・出せない日 … BE の reason か errorMessage をそのまま（null にならない）。
  ///   ・聞けなかった時 … サーバが符号つきで返した文（errorCode が空でない時の errorMessage）。
  ///     それ以外（サーバまで届かなかった・符号の無い答え・答えの形が読めない）は null
  ///     ＝画面ごとに決めた字を出す（例外の字や本文の頭の字を出さない）。
  ///   ・出せる日 … null。
  final String? text;

  /// 尋ねる口の答え（8つのキー）を Map のまま。答えが届かなかった時は null。
  ///   元: ★次の便 F8b が request_id・confirm_type・permit_until を読む（この便の画面は読まない）。
  ///   →再（2026-10-11・便F8b-2）: 許可が出ている日に、箱の入口と3択の画面がこの3つを読み、
  ///   後から出す日報の画面へ渡す。
  final Map<String, dynamic>? answer;
}

/// 尋ねる口の答え（getDayRequestEligibility の返り）を3つに分ける。★分ける所はここ1か所。
DayRequestEligibility readDayRequestEligibility(
    ApiResult<Map<String, dynamic>> res) {
  if (res.ok) {
    final data = res.data;
    final canDeclare = data?['can_declare'];
    // ★== true / == false で見る。字や null（答えの形が読めない）を真偽へ丸めない。
    if (canDeclare == true) {
      return DayRequestEligibility(DayRequestEligibilityKind.allowed,
          answer: data);
    }
    // ★許可が出ている日（便F8b-2）。出せない日の判定より先に見る（code が ALREADY_PERMITTED でも
    //   reason は在る＝先に見ないと出せない日になる）。値がそろわなければ聞けなかった時。
    if (canDeclare == false && data?['code'] == 'ALREADY_PERMITTED') {
      final reason = data?['reason'];
      final requestId = data?['request_id'];
      final permitUntil = data?['permit_until'];
      if (reason is String &&
          reason.isNotEmpty &&
          requestId != null &&
          '$requestId'.isNotEmpty &&
          permitUntil is String &&
          permitUntil.isNotEmpty) {
        return DayRequestEligibility(DayRequestEligibilityKind.permitted,
            text: reason, answer: data);
      }
      return DayRequestEligibility(DayRequestEligibilityKind.unknown,
          answer: data);
    }
    if (canDeclare == false) {
      final reason = data?['reason'];
      if (reason is String && reason.isNotEmpty) {
        return DayRequestEligibility(DayRequestEligibilityKind.denied,
            text: reason, answer: data);
      }
    }
    // false なのに reason が空・can_declare が true でも false でもない＝答えの形が読めない。
    return DayRequestEligibility(DayRequestEligibilityKind.unknown,
        answer: data);
  }
  final code = res.errorCode ?? '';
  final message = res.errorMessage ?? '';
  final coded = code.isNotEmpty && message.isNotEmpty;
  // サーバが符号つきで断った（例 403 ATTENDANCE_EMPLOYEE_ONLY）＝出せない日の形で文を出す。
  if (coded && res.statusCode >= 400 && res.statusCode <= 499) {
    return DayRequestEligibility(DayRequestEligibilityKind.denied,
        text: message);
  }
  // 聞けなかった時。文はサーバが符号つきで返した時だけ（例 500 の「サーバーエラー」）。
  //   ★符号の無い答え（statusCode 0 の「サーバーに接続できません: 例外」・HTML の本文の頭）は出さない。
  return DayRequestEligibility(DayRequestEligibilityKind.unknown,
      text: coded ? message : null);
}

/// 聞けなかった時の出し方（理由の行＋「もう一度」）。★3択の画面と箱の入口が同じこれを使う。
///   理由の行は※と同じ字の形（textSupport 12・行の高さ1.6・左寄せ）。その下に 8 の間をあけて、
///   OutlinedButton「もう一度」（テーマの既定の形＝今の「もう一度」と同じ・幅いっぱい）。
class DayRequestTrouble extends StatelessWidget {
  const DayRequestTrouble({super.key, required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.left, style: kPastDayNote),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: onRetry, child: const Text('もう一度')),
          ),
        ],
      );
}

// ── 箱に入口を出す日か ───────────────────────────────────────────

/// 箱に「日報漏れの申告」の入口を出す日か。★関数の中で時計を読まない（今日は呼び手が字で渡す）。
///   出すのは: 今日（JST）より前の日で、自分の生きている日報が0枚で、自分の休みが無い日
///   （休みが無い＝今の「代休で休む」を出す条件と同じ＝restPortion が null・同意待ちの振替の休む日でない）。
///   今日・先の日・自分の日報の在る日・休みの在る日には何も足さない（尋ねる口も呼ばない）。
///   ★日付は 'YYYY-MM-DD' の字のまま比べる（同じ桁の字なので、字の順が日の順）。
bool shouldOfferDayRequestEntry({
  required String workDate,
  required String today,
  required int ownReportCount,
  required bool hasOwnRest,
  required bool substitutePendingRest,
}) =>
    workDate.compareTo(today) < 0 &&
    ownReportCount == 0 &&
    !hasOwnRest &&
    !substitutePendingRest;

/// その日の生きている日報の行のうち、自分の物（行の user_id が自分の id と同じ）の数。
///   ★比べ方は今の本人の見分けの前例（approval_day_screen.dart の _revisionCardIn・
///     revision_inbox_screen.dart）と同じ＝値が同じか。
///   ★自分の id が分からない時（null か空の字）は、行の全部を自分の物として数える
///     ＝日報が1枚でも在る日には入口を出さない側に倒す（黙って出す側に倒さない）。
///   ★なぜ数え分けるか: 職長などの役では、カレンダーの日報は会社ぶんが返る（GET /reports）。
///     ほかの人の日報だけが在る日にも、自分の日報が無ければ入口を出す。逆に、締め期間より前の日に
///     自分の日報が在るのに理由（OUT_OF_CLOSING_PERIOD の文）が出る、という食い違いも作らない
///     （自分の日報が在る日は聞かない）。職人（worker）は自分の日報だけが返るので、今の数と同じ答え。
int ownLiveReportCount(
    List<Map<String, dynamic>> liveReports, String? myUserId) {
  if (myUserId == null || myUserId.isEmpty) return liveReports.length;
  return liveReports.where((r) => r['user_id'] == myUserId).length;
}

/// 箱の入口を組み立てる。shouldOfferDayRequestEntry が真なら入口の部品を、偽なら null。
///   ★箱を開く所（home_screen.dart の _CalendarTabState）は、これを1か所で呼び、答えをそのまま箱へ渡すだけ。
///
/// [dateText] 対象の日の「M月D日（曜）」（祝日の名前は付けない・CalendarDayInfo の日付だけの字）。
/// [service] 口（検査は差し替えを渡す）。
/// [onReportsChanged] 後から出す日報の画面から出せた（submitted）か閉じた（closed）時に呼ぶ（便F8b-2）。
Widget? dayRequestEntryOrNull({
  required String workDate,
  required String today,
  required int ownReportCount,
  required bool hasOwnRest,
  required bool substitutePendingRest,
  required String dateText,
  required ReportsService service,
  VoidCallback? onReportsChanged,
}) {
  final offer = shouldOfferDayRequestEntry(
    workDate: workDate,
    today: today,
    ownReportCount: ownReportCount,
    hasOwnRest: hasOwnRest,
    substitutePendingRest: substitutePendingRest,
  );
  if (!offer) return null;
  return DayRequestEntry(
      workDate: workDate,
      dateText: dateText,
      service: service,
      onReportsChanged: onReportsChanged);
}

// ── 箱の中の入口（D1・D3）────────────────────────────────────────

/// カレンダーの箱の中の入口。開いたら尋ねる口に type=report_missing とその日で1回だけ聞く。
///   ・聞いている間 … 小さいくるくる
///   ・出せる日 … 「日報漏れを申告する」＋※（押すと先に箱を閉じてから申告の画面へ）
///   ・出せない日 … 枠「申告できません」に BE の文（ボタンは出さない）
///   ・聞けなかった時 … 理由＋「もう一度」（DayRequestTrouble）
///   ・許可が出ている日（便F8b-2・見本 G1） … 見出しの無い accent の線の枠に BE の文＋「この日の日報を出す」
///     （押すと先に箱を閉じてから後から出す日報の画面へ）
///   ★どの姿も上に 8 の間（今の箱のボタンと同じ間）。
class DayRequestEntry extends StatefulWidget {
  const DayRequestEntry({
    super.key,
    required this.workDate,
    required this.dateText,
    required this.service,
    this.onReportsChanged,
  });

  final String workDate;
  final String dateText;
  final ReportsService service;

  /// 後から出す日報の画面から submitted か closed で戻った時に呼ぶ（便F8b-2）。
  ///   ★どちらも、その日の日報が増えている事がある（closed は、ほかの端末で出していた時も）。
  final VoidCallback? onReportsChanged;

  @override
  State<DayRequestEntry> createState() => _DayRequestEntryState();
}

class _DayRequestEntryState extends State<DayRequestEntry> {
  bool _loading = true;
  DayRequestEligibility? _answer;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  // 尋ねる口に1回聞く（「もう一度」も同じこの1本）。
  Future<void> _ask() async {
    setState(() => _loading = true);
    final res = await widget.service
        .getDayRequestEligibility('report_missing', widget.workDate);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _answer = readDayRequestEligibility(res);
    });
  }

  // 今の箱の道と同じく、先に箱を閉じてから次の画面へ進む。
  //   ★箱を閉じるとこの部品の context は消えるので、先に Navigator を掴んでおく
  //     （箱も申告の画面も同じ Navigator に積まれる）。
  void _openDeclare() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push<bool>(MaterialPageRoute(
      builder: (_) => DayRequestScreen(
        kind: DayRequestKind.reportMissing,
        workDate: widget.workDate,
        dateText: widget.dateText,
        service: widget.service,
      ),
    ));
  }

  // 「この日の日報を出す」（便F8b-2）。今の _openDeclare と同じく、先に箱を閉じてから次の画面へ進む。
  //   ★箱を閉じるとこの部品は消える（widget も読めなくなる）ので、Navigator と知らせの関数と
  //     画面へ渡す値を、箱を閉じる前に手元へ写しておく。
  Future<void> _openLateReport() async {
    final nav = Navigator.of(context);
    final onReportsChanged = widget.onReportsChanged;
    final answer = _answer?.answer;
    final confirmType = answer?['confirm_type'];
    final screen = LateReportScreen(
      workDate: widget.workDate,
      dateText: widget.dateText,
      confirmationId: '${answer?['request_id']}',
      confirmType: confirmType is String ? confirmType : null,
      permitUntil: '${answer?['permit_until']}',
      reportsService: widget.service,
    );
    nav.pop();
    final result = await nav.push<LateReportResult>(
        MaterialPageRoute(builder: (_) => screen));
    if (result == LateReportResult.submitted ||
        result == LateReportResult.closed) {
      onReportsChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _answer;
    final Widget body;
    if (_loading) {
      body = const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (a == null || a.kind == DayRequestEligibilityKind.unknown) {
      body = DayRequestTrouble(
        text: a?.text ?? '申告できるかを確かめられませんでした',
        onRetry: _ask,
      );
    } else if (a.kind == DayRequestEligibilityKind.permitted) {
      // ★見本 G1: 見出しの無い accent の線の枠に BE の文 → 8 → 「この日の日報を出す」（幅いっぱい）。※は置かない。
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PastDayFrame(
            lineColor: FieldTokens.accent,
            body: Text(a.text ?? '', style: kPastDayFrameBody),
          ),
          const SizedBox(height: 8),
          pastDayOutlinedButton('この日の日報を出す', onPressed: _openLateReport),
        ],
      );
    } else if (a.kind == DayRequestEligibilityKind.denied) {
      // ★枠は3択の画面と同じ部品・同じ線の色。
      body = PastDayFrame(
        lineColor: FieldTokens.brand,
        heading: '申告できません',
        headingColor: FieldTokens.brand,
        body: Text(a.text ?? '', style: kPastDayFrameBody),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ★今の箱のボタンと同じ形（OutlinedButton.icon・幅いっぱい・本文色 1.5・印 16）。
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openDeclare,
              icon: const Icon(Icons.assignment_late_outlined, size: 16),
              label: const Text('日報漏れを申告する'),
              style: OutlinedButton.styleFrom(
                foregroundColor: FieldTokens.textBody,
                side: const BorderSide(color: FieldTokens.textBody, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text('※この日の日報を後から出すには、事務の許可が要ります。',
              style: kPastDayNote),
        ],
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 8), child: body);
  }
}
