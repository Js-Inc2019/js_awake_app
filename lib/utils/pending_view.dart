// lib/utils/pending_view.dart
// 送った後の画面に出す、未送信の日報の姿（便BK・見本 claude/field_report_fix_mock_v3.html の ⑮⑯・
// ボスの裁定【Q143】【Q144】＝１）。
//
// ★何か：ReportStore（lib/main.dart）が未送信の箱を読んだ時の姿（今の人の日報の並び・読めない行の数・読めない箱の数・
//   読めなかったか）と、それを「今日の分」と「ほかの日」に分ける決まり（pendingTodayRows・pendingOtherRows・
//   決まりの式は _isTodayRow の1本）。
//   送った後の画面（lib/screens/after_report_screen.dart）と、その呼び手（lib/screens/home_screen.dart）が読む。
//   →再（2026-10-19・便BM）: ホームの要対応の「未送信日報」の行（下の homePendingCountOf）と、その行から開く「未送信日報」の画面
//   （lib/screens/pending_reports_screen.dart）も読む。
// ★なぜ：元は、頭の字を「今の人の未送信の数が 0 か」で決めていた（見本 v1 の ①案A）。送り先が受け付けなかった日報は、
//   送り直しても同じ答えで箱に残り続けるので、次の日からの日報が送れても、頭が「未送信（再送待ち）」になった
//   （見つけた事 (25)）。読めない行は、数えず・画面にも出なかった（見つけた事 (27)）。
// ★今日の分＝勤務の種類が画面の勤務の種類と同じで、業務日（送る report_date と同じ物差し＝businessDateForShift）が
//   今の業務日と同じ日報。
// ★通信しない・端末の保存を読まない（読むのは ReportStore）。
import '../core/report_send_texts.dart' show PendingCountLabel, pendingCountLabel;
import 'business_date.dart';

/// 今の人の未送信の日報の1件（送った後の画面に出す分だけ）。
class PendingReportRow {
  const PendingReportRow({
    required this.id,
    required this.shiftType,
    required this.businessDate,
    this.refusedMessage,
  });

  /// 箱の日報の id（WorkerReportItem.id）。外す時に渡す。
  final String id;

  /// 'day'|'night'。
  final String shiftType;

  /// 業務日 'YYYY-MM-DD'（送る report_date と同じ＝businessDateForShift(shiftType, 日報の時刻)）。
  final String businessDate;

  /// 送り先が受け付けなかった時の、送り先の答えの字（null＝受け付けなかった答えは来ていない）。
  final String? refusedMessage;
}

/// 未送信の箱を読んだ時の姿。★作り直すのは ReportStore.refreshPendingCount だけ。
class PendingView {
  const PendingView({
    this.own = const <PendingReportRow>[],
    this.unreadableRows = 0,
    this.unreadableBoxes = 0,
    this.readFailed = false,
  });

  /// 今の人の箱の日報（箱の並び）。今の人が分からない時は、持ち主の分からない日報。
  final List<PendingReportRow> own;

  /// 箱の中の、このアプリが読めない行の数（持ち主は分からない）。
  final int unreadableRows;

  /// 箱そのものが読めなかった時に写した元の字の数（中の件数は分からない）。
  final int unreadableBoxes;

  /// 最後に読もうとした時に読めなかったか（true の間、上の値は前に読めた時のまま）。
  final bool readFailed;

  /// 読めない日報が在るか。
  bool get hasUnreadable => unreadableRows > 0 || unreadableBoxes > 0;

  PendingView copyWith({bool? readFailed}) => PendingView(
        own: own,
        unreadableRows: unreadableRows,
        unreadableBoxes: unreadableBoxes,
        readFailed: readFailed ?? this.readFailed,
      );
}

/// 外した結果（便BK・見本 v3 の ⑮⑯）。
enum PendingRemoveResult {
  /// 外した。
  removed,

  /// 送っている途中なので外さなかった。
  inFlight,

  /// もう箱に無かった（送れた・ほかで外した）。
  gone,

  /// 箱に書けなかった（外していない＝手元の写しも元のまま）。
  failed,
}

// 今日の分か（決まりはここ1つ）。today＝businessDateForShift(shiftType, 今)。
bool _isTodayRow(PendingReportRow r, String shiftType, String today) =>
    r.shiftType == shiftType && r.businessDate == today;

/// 今の人の未送信の日報のうち、今日の分（並びは箱の並びのまま）。
///   今日の分＝row.shiftType が shiftType と同じで、row.businessDate が businessDateForShift(shiftType, now) と同じ物。
///   →再（2026-10-21・便BN・下調べの (D3)）: bizDate を渡した時は、その業務日を「今日の分」の日にする（送った後の画面が
///   出している印の日で分ける・呼び手は送った後の画面）。渡さない時は今のとおり。
List<PendingReportRow> pendingTodayRows(PendingView v,
    {required String shiftType, required DateTime now, String? bizDate}) {
  final today = bizDate ?? businessDateForShift(shiftType, now);
  return [
    for (final r in v.own)
      if (_isTodayRow(r, shiftType, today)) r,
  ];
}

/// 今日の分でない、今の人の未送信の日報（並びは箱の並びのまま）。
///   bizDate は pendingTodayRows と同じ（同じ日を渡す＝2つの関数で分け方が食い違わない）。
List<PendingReportRow> pendingOtherRows(PendingView v,
    {required String shiftType, required DateTime now, String? bizDate}) {
  final today = bizDate ?? businessDateForShift(shiftType, now);
  return [
    for (final r in v.own)
      if (!_isTodayRow(r, shiftType, today)) r,
  ];
}

/// 行の並びの中で、最初の受け付けなかった字（無ければ null）。
String? firstRefusedMessageOf(List<PendingReportRow> rows) {
  for (final r in rows) {
    if (r.refusedMessage != null) return r.refusedMessage;
  }
  return null;
}

/// ホームの要対応の「未送信日報」の行の数（便BM・見本 claude/field_refused_today_mock_v1.html の ②・
///   claude/field_close_date_remove_mock_v1.html の「決めた所」）。行を出さない時は null。
///   出すのは、今の人の日報か読み込めない日報が在る時と、未送信の箱を読めなかった時（読めない事を黙らない）。
///   数＝今の人の日報（今日の分も・ほかの日の分も）と読み込めない行の数・決まりは pendingCountLabel の1本。
PendingCountLabel? homePendingCountOf(PendingView v) {
  if (v.own.isEmpty && !v.hasUnreadable && !v.readFailed) return null;
  return pendingCountLabel(v.own.length + v.unreadableRows,
      unknown: v.unreadableBoxes > 0, readFailed: v.readFailed);
}
