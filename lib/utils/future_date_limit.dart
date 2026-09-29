// lib/utils/future_date_limit.dart
// 先の日の上限（今日からどこまで先を選べるか・見られるか）の唯一の定義。
//
// ★なぜ1ファイルに集めるか（2026-09-28・便F12）:
//   本日休みの画面の「別の日」の日付の窓2つ（代休の _pickCompOffDate と振替の
//   _pickSubstituteDate）は、同じ式 DateTime(now.year + 1, now.month, now.day) を
//   それぞれ手書きしていた。一方、管理・履歴のカレンダー（home_screen.dart の CalendarTab）は
//   今月より先へ送れず、日付の窓では選べる来月の日の箱（代休で休む・振替で休む・
//   振替休日を開く）を開けなかった。
//   カレンダーを先へ送れるようにするとき、上限をもう1か所に手書きすると
//   「窓では選べるのにカレンダーでは開けない」（またはその逆）が、どちらか1つを
//   直したときに黙って生まれる（二重真実）。よって上限の式をここへ1本にし、
//   日付の窓2つとカレンダーの月送りが同じ関数を呼ぶ。
//   （前例: lib/utils/report_cancel_gate.dart。判定を各画面に手書きした結果
//     「どこかだけ直し忘れる」形が構造的に残った、という同じ趣旨。）
//
// ★このファイルは通信も画面も持たない。純粋な関数だけを置く。
//   「今日」は引数で受ける（DateTime.now() をここで呼ばない＝検査で日を固定できる）。

/// 今日から選べる最後の日。
///   ★式は移す前の rest_day_screen.dart の2つの lastDate と1文字も変えていない
///     （1年先の同じ月・同じ日。時刻は持たない）。
///   ★うるう日（2月29日）の今日は、1年先に2月29日が無いので DateTime の繰り上がりで
///     3月1日になる（移す前の式と同じ値＝値を変えない）。
DateTime lastSelectableDate(DateTime today) =>
    DateTime(today.year + 1, today.month, today.day);

/// カレンダーで、表示中の月から次の月へ送れるか。
///   ★見るのは表示中の月の【年と月だけ】（日は見ない。表示中の月を月の途中の日で
///     持っていても、1日で持っていても同じ答えになる）。
///   ★送った先の月が、[lastSelectableDate] を含む月を越えなければ送れる
///     ＝日付の窓で選べる最後の日の箱まで、カレンダーでも開ける。
bool canGoToNextMonth({required DateTime shownMonth, required DateTime today}) {
  final last = lastSelectableDate(today);
  final next = DateTime(shownMonth.year, shownMonth.month + 1);
  return next.year * 12 + next.month <= last.year * 12 + last.month;
}
