// lib/core/permitted_report_labels.dart
// 許可を得て出た日報の「印」の語を1か所に集めた表（便 F7）。
//
// ★なぜ1つに集めるか: 同じ印を出す場所が2つある。
//     ・承認待ちのカード（home_screen.dart の PendingApprovalCard）
//     ・承認の日の画面の人の行（approval_day_screen.dart の _row）
//   画面ごとに語を書くと、片方だけ直したときに同じ日報の印が画面で割れる。
//
// ★語は事務アプリ（js_office_admin_app の lib/core/permitted_report_labels.dart）と
//   1文字も同じ。同じ日報に、職長と事務とで別の名前を付けない。
//
// ★鍵は BE の日報の行の confirm_type（js-office-api routes/reports.js の CONFIRM_TYPE_COL。
//   GET /reports・/reports/today・/reports/:report_id の3つの口が載せる）。
//   通常の日報は null。
// ★表に無い値・null は null を返す＝印を出さない。通常の日報に印を付けないため。

/// confirm_type → 印の語。
const Map<String, String> kPermittedReportMark = {
  'attendance_fix': '振替の出勤日の日報（許可あり）',
  'report_missing': '日報漏れの日報（許可あり）',
};

/// 印の語を引く。通常の日報（null）・表に無い値は null。
String? permittedReportMarkOrNull(Object? confirmType) {
  if (confirmType is! String || confirmType.isEmpty) return null;
  return kPermittedReportMark[confirmType];
}
