// ============================================================
// lib/screens/day_request_screen.dart - 出勤の修正依頼・日報漏れの申告の画面
//   （便F8・見本 field_substitute_past_mock_v5 の B2・D2・ボス裁定【Q89】）
//
// ★1枚の画面で2つの種類を出す。種類で替わるのは、題・固定の文・例の字・ボタンの字・※の2行だけ
//   （画面を2枚作らない＝並び・形・送り方が2通りに割れない）。
//   ・出勤の修正依頼（B2）… 振替の登録の3択の画面（substitute_past_day_screen.dart）から来る。
//   ・日報漏れの申告（D2）… カレンダーの箱の入口（lib/widgets/day_request_entry.dart）から来る。
// ★出せるかどうかは、来る前に尋ねる口で確かめてある（この画面は聞き直さない）。
//   それでも送った時に断られたら、BE の文をそのまま閉じるまで消えない窓で出す。
// ★対象の日の字（「M月D日（曜）」）と、依頼の※の期限の字は呼び手が渡す
//   （曜日・週・締め期間を端末で数えない。このファイルの中では時計を読まない）。
// ★この画面から読み直しの知らせ（RestDayRefresh）は鳴らさない。休み・振替・日報の数は変わらない
//   （変わるのは尋ねる口の答えだけで、箱と3択は開くたびに聞き直す）。
//
// 色は FieldTokens のみ（直書き禁止・新しい色を作らない）。
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../main.dart' show showJsSnackbar;
import '../services/api_result.dart';
import '../services/reports_service.dart';
import 'substitute_detail_screen.dart' show showSubstituteDeny;
import 'substitute_past_day_screen.dart'
    show PastDayDateRow, kPastDayNote, pastDayFilledButton;

/// 依頼・申告の種類。
enum DayRequestKind {
  /// 出勤の修正依頼（B2）。
  attendanceFix,

  /// 日報漏れの申告（D2）。
  reportMissing,
}

/// 種類ごとに替わる字（この画面の字はこのファイルの中だけに置く）。
class _Words {
  const _Words({
    required this.title,
    required this.fixedText,
    required this.hint,
    required this.button,
    required this.done,
    required this.already,
    required this.denyTitle,
  });
  final String title;
  final String fixedText;
  final String hint;
  final String button;
  final String done;     // 201（新しく積めた）の知らせ
  final String already;  // 200（もう積まれている）の知らせ
  final String denyTitle;
}

const _Words _kFixWords = _Words(
  title: '出勤の修正依頼',
  fixedText: 'この日に出勤していましたが、日報を出していませんでした。'
      '振替休日の出勤する日にするため、この日の日報を出す許可をお願いします。',
  hint: '例：現場の片付けで出勤。日報を出し忘れた',
  button: '依頼を送る',
  done: '出勤の修正を依頼しました。事務が確認します。',
  already: 'すでに依頼済みです。',
  denyTitle: '依頼できませんでした',
);

const _Words _kMissingWords = _Words(
  title: '日報漏れの申告',
  fixedText: 'この日に出勤していましたが、日報を出していませんでした。'
      'この日の日報を出す許可をお願いします。',
  hint: '例：現場で電池が切れて日報を出せなかった',
  button: '申告を送る',
  done: '日報漏れを申告しました。事務が確認します。',
  already: 'すでに申告済みです。',
  denyTitle: '申告できませんでした',
);

class DayRequestScreen extends StatefulWidget {
  const DayRequestScreen({
    super.key,
    required this.kind,
    required this.workDate,
    required this.dateText,
    this.permitUntilText,
    this.service,
  });

  final DayRequestKind kind;

  /// 対象の日（'YYYY-MM-DD'）。口へ送る日。
  final String workDate;

  /// 対象の日の「M月D日（曜）」（呼び手が字で渡す）。
  final String dateText;

  /// 出勤の修正依頼の※の期限「M月D日（曜）」（その週の土曜＝候補の口の days[] の最後の日・
  ///   呼び手が字で渡す）。日報漏れの申告では使わない。
  final String? permitUntilText;

  /// 口の差し替え（検査だけが渡す）。既定は null＝ReportsService()。
  final ReportsService? service;

  @override
  State<DayRequestScreen> createState() => _DayRequestScreenState();
}

class _DayRequestScreenState extends State<DayRequestScreen> {
  late final ReportsService _api = widget.service ?? ReportsService();
  final TextEditingController _reason = TextEditingController();
  bool _sending = false;

  bool get _isFix => widget.kind == DayRequestKind.attendanceFix;
  _Words get _w => _isFix ? _kFixWords : _kMissingWords;

  // ★理由が空（前後の空白を除いて）の間は押せない（押せてしまうとサーバが断るだけになる）。
  //   ★送っている間も押せない（二度押しで2回送らない）。
  bool get _canSend => _reason.text.trim().isNotEmpty && !_sending;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final text = _reason.text;
    setState(() => _sending = true);
    final res = _isFix
        ? await _api.requestAttendanceFix(widget.workDate, text)
        : await _api.declareReportMissing(widget.workDate, text);
    if (!mounted) return;
    if (res.ok) {
      // 201=新しく積めた / 200=もう積まれている。どちらも通った答えとして閉じる
      //   （打刻漏れの申告＝lib/widgets/punch_remind_dialog.dart の _declare と同じ分け方と出し方）。
      //   ★知らせは ScaffoldMessenger に載るので、この画面を閉じた後も下の画面に残る。
      showJsSnackbar(context, res.statusCode == 200 ? _w.already : _w.done);
      Navigator.of(context).pop(true);
      return;
    }
    // ★送っている印を戻す（直して、または電波の戻った後に、もう一度押せる）。入力は消さない・画面は閉じない。
    setState(() => _sending = false);
    await showSubstituteDeny(context, _w.denyTitle, _denyShown(res));
  }

  /// 窓に出す答え。文は3通り:
  ///   ・サーバが符号つきで断った（errorCode が空でない）… BE の文をそのまま
  ///   ・サーバまで届かなかった（statusCode が 0）… 「通信エラーが発生しました」
  ///   ・それ以外 … 窓の今ある決まりの文（空の文を渡す＝「できませんでした。時間をおいて、…」）
  ///   ★例外の字や本文の頭の字を窓に出さない。
  ApiResult<Object?> _denyShown(ApiResult<Map<String, dynamic>> res) {
    if ((res.errorCode ?? '').isNotEmpty) return res;
    return apiFailure<Object?>(
      statusCode: res.statusCode,
      errorMessage: res.statusCode == 0 ? '通信エラーが発生しました' : '',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: FieldTokens.bgBase,
        // ★器は事前の取り決めの画面（substitute_past_day_screen.dart）と同じ。
        appBar: AppBar(
          backgroundColor: FieldTokens.surfaceCard,
          foregroundColor: FieldTokens.textBody,
          elevation: 0,
          title: Text(_w.title),
        ),
        // ★縦に動かせる（キーボードが出ても、ボタンと※へ届く）。
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              PastDayDateRow(label: '対象の日', value: widget.dateText),
              const SizedBox(height: 12),
              _DashedFrame(
                child: Text(_w.fixedText,
                    style: const TextStyle(
                        color: FieldTokens.textBody, fontSize: 13, height: 1.6)),
              ),
              const SizedBox(height: 12),
              const Text('理由（必須）',
                  style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
              const SizedBox(height: 6),
              // ★出し直しの画面（revision_edit_screen.dart の _fieldDeco）の入力の欄と同じ形。
              //   あの部品はあの画面の私有なので、同じ値をここに書いた。
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: null,
                style: const TextStyle(color: FieldTokens.textBody, fontSize: 14),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: FieldTokens.surfaceCard,
                  hintText: _w.hint,
                  hintStyle: const TextStyle(color: FieldTokens.textSupport),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: FieldTokens.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: FieldTokens.accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              pastDayFilledButton(_w.button, onPressed: _canSend ? _send : null),
              const SizedBox(height: 12),
              ..._notes(),
            ],
          ),
        ),
      );

  // ※の2行（字の形は事前の取り決めの画面の※と同じ kPastDayNote）。
  List<Widget> _notes() {
    if (_isFix) {
      return [
        Text.rich(
          TextSpan(
            style: kPastDayNote,
            children: [
              const TextSpan(text: '※事務が許可すると、この日の日報を '),
              // ★期限の日付だけ太字・本文色（呼び手が渡した字をそのまま）。
              TextSpan(
                text: widget.permitUntilText ?? '',
                style: const TextStyle(
                    color: FieldTokens.textBody, fontWeight: FontWeight.bold),
              ),
              const TextSpan(text: 'まで出せるようになります。'),
            ],
          ),
        ),
        const Text('※日報が事務に承認されるまで、この日を出勤する日には選べません。',
            style: kPastDayNote),
      ];
    }
    return const [
      Text('※事務が許可すると、この日の日報をこの締め期間の最終日まで出せるようになります。',
          style: kPastDayNote),
      Text('※出した日報は、事務の承認で確定します。', style: kPastDayNote),
    ];
  }
}

/// 点線の枠（線は outline・角丸8・中の余白は左右12と上下10）。
///   ★点線の四角を描く部品はこのアプリに無かった（在るのはカレンダーの輪を描く私有の部品だけ）ので、
///     この画面の中に1つだけ作る。パッケージは足さない。
class _DashedFrame extends StatelessWidget {
  const _DashedFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: const _DashedRRectPainter(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: child,
        ),
      );
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter();

  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FieldTokens.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // 線の太さの半分だけ内へ寄せて、枠の外へはみ出さないように描く。
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      const Radius.circular(8),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final next = (d + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, next), paint);
        d = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) => false;
}
