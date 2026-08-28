// lib/core/closing_period_labels.dart
// 給与の締め日で「期間が2つある月」を人に見せるときの語と整形（画面を持たない純ヘルパー）。
//
// ★ここに置く理由: この語は共有部品（widgets/closing_period_dialog.dart）と
//   検査の両方が使う。語を部品の中に書くと、検査が部品の私有文字列を写して
//   二重真実になる。lib/core は画面を持たない層（今あるのは theme だけ）で、
//   どの画面からも同じ向きで読める。
//
// ★言い方は BE に合わせる。js-office-api の services/closingPeriodRequest.js が
//   400 の本文へ載せる文言は
//     「この月は締め日の変更により期間が2つあります。どちらの期間かを指定してください」
//   ＝同じ事情が BE の応答と画面で2つの名前を持たないようにする。
//   ★違うのは末尾だけ＝画面は「指定してください」ではなく「選んでください」と言う。
//     画面には選ぶ道（候補の一覧）が実際にあるため。
//
// ★数え方の根拠: 期間の呼び名は「その期間の最後の日が属する月」。
//   BE の services/closingPeriod.js が start / end / closingDate を同時に組み立てる
//   ときにそう決めており、20日締めなら 8/21〜9/20 は「9月分」。ここもそれに従う。

/// 選んだ締め日を BE へ送るときのクエリ。未指定なら1文字も足さない。
///   ★ここに置く理由: `closing_dates` という【鍵の名前】も語のひとつで、
///     2つのサービス（reports_service / work_mode_service）が同じ名前で送る。
///     綴りを2箇所に書くと、片方だけ直る事故が起きる。名前はここ1つ。
///   ★送り方は複数形ただ1つ。BE は単数の closing_date も受けるが、こちらが
///     2つの送り方を持つと「1つの月なら単数・複数月なら複数」という分岐が生える。
///   ★戻りは先頭に & を付けた形（既存のクエリの後ろへ足す前提）。
String closingDatesQuery(List<String> closingDates) => closingDates.isEmpty
    ? ''
    : '&closing_dates=${Uri.encodeQueryComponent(closingDates.join(','))}';

/// 候補から1つ選ばせるダイアログの見出し。
const String kClosingAmbiguousTitle = '期間を選ぶ';

/// 「まだ選べていない」画面が出すボタンの語。
const String kClosingChooseAction = '期間を選ぶ';

/// 候補が応答に載っていない等で選ばせようがないときの理由
/// （BE が文言を返していないときだけ使う）。
const String kClosingUnresolvedFallback =
    '締め日の変更で期間が決められませんでした。会社にご確認ください';

/// 'YYYY-MM' を「YYYY年M月分」にする。読めない値は「対象の月」。
String closingMonthText(String? month) {
  if (month == null || month.length < 7) return '対象の月';
  final y = int.tryParse(month.substring(0, 4));
  final m = int.tryParse(month.substring(5, 7));
  if (y == null || m == null) return '対象の月';
  return '$y年$m月分';
}

/// 'YYYY-MM-DD' を「M/D」にする（期間の幅の表示用）。
String closingMdText(String? ymd) {
  if (ymd == null || ymd.length < 10) return '-';
  final m = int.tryParse(ymd.substring(5, 7));
  final d = int.tryParse(ymd.substring(8, 10));
  if (m == null || d == null) return ymd;
  return '$m/$d';
}

/// 'YYYY-MM-DD' を「YYYY年M月D日」にする（締め日そのものの表示用）。
String closingJpDateText(String? ymd) {
  if (ymd == null || ymd.length < 10) return '-';
  final y = int.tryParse(ymd.substring(0, 4));
  final m = int.tryParse(ymd.substring(5, 7));
  final d = int.tryParse(ymd.substring(8, 10));
  if (y == null || m == null || d == null) return ymd;
  return '$y年$m月$d日';
}

/// 候補1件の幅を「M/D〜M/D」で言う。
///   ★終端は closingDate（＝閉区間の最後の日）を使う。BE の end は「含まない」
///     ので、そのまま出すと1日ずれる。
String closingPeriodRangeText(Map<String, dynamic>? period) {
  if (period == null) return '-';
  return '${closingMdText(period['start'] as String?)}'
      '〜${closingMdText(period['closingDate'] as String?)}';
}

/// 候補1件の締め日を「締め日 YYYY年M月D日」で言う（2つの候補を取り違えないため）。
String closingPeriodClosingText(Map<String, dynamic>? period) =>
    '締め日 ${closingJpDateText(period?['closingDate'] as String?)}';

/// 未解決の月と候補の数から、画面に出す理由を1文にする。
///   ★月名を必ず出す（どの月が決まっていないのか分からないまま押させない）。
///   ★数は数えた値を書く。候補が2つのときは BE の文言と同じ「期間が2つあります」になる。
String closingAmbiguousNotice(List<String> monthTexts, int periodCount) {
  final who = monthTexts.isEmpty ? '対象の月' : monthTexts.join(' / ');
  return '$whoは締め日の変更で期間が$periodCountつあります。どちらの期間かを選んでください';
}
