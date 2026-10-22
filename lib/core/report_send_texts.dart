// lib/core/report_send_texts.dart
// 日報を送る所の、失敗の時の字を1か所に集めた表（便BJ・見本 claude/field_report_fix_mock_v1.html の ② と ③）。
//
// ★なぜ1つに集めるか: 同じ失敗を出す所が5つある（今日の日報の確認の画面・出し直しの画面・残業の窓・
//   休憩の短縮のシート・後から出す日報の確認の画面）。画面ごとに字を書くと、片方だけ直した時に割れる。

/// 送る途中で失敗した時の枠の見出し（今日の日報の確認の画面）。
const String kSendFailedHeading = '送信できません';

/// 送る途中で失敗した時の字（端末に日報が残っていない＝もう一度押せる）。
const String kSendFailedText = '送れませんでした。もう一度お試しください。';

/// 送る前に、写真が読めなかった時の字（今日の日報・後から出す日報）。
const String kPhotoUnreadableText = '写真を読み込めませんでした。戻って撮り直してください';

/// 送り直しで、読めなかった写真を除いて送った時の知らせ（ホーム）。
String droppedPhotosText(int count) => '写真 $count枚を送れませんでした';

/// 送った後の画面：送り先が受け付けなかった時の字（見本 claude/field_report_fix_mock_v2.html の ⑬・ボスの裁定【Q142】）。
///   かっこの中は送り先の答えの字のまま。「提出できません」は後から出す日報の枠の見出しと同じ字。
String refusedReportText(String reason) => '提出できません（$reason）';

/// 送った後の画面：送り先が受け付けなかった時の※（同じ見本の ⑬）。
const String kRefusedReportNote = '※会社のご担当者にご確認ください。';

// ── 便BK（見本 claude/field_report_fix_mock_v3.html の ⑮⑯⑰・ボスの裁定【Q143】【Q144】【Q145】＝１）──

/// 日報のフォーム：送った印を読めなかった時の※（見本 v3 の ⑰②・「今日の報告」の見出しの下）。
const String kDoneMarkReadFailedNote =
    '※今日の送信記録を読み込めませんでした。送信済みかは、管理・履歴で確かめてください。';

/// 送った後の画面：未送信の日報を読めなかった時の※（見本 v3 の ⑰②・頭の下）。
const String kPendingReadFailedNote = '※送信状況を読み込めませんでした。';

/// 送った後の画面：ほかの日の未送信と読み込めない日報の見出し（見本 v3 の ⑮⑯・字の形は「続けて報告」と同じ）。
const String kPendingSectionLabel = '未送信日報';

/// 「未送信日報」の件数の字（数と単位に分けた形）。number＝null の時は数が無い（unit が字の全部＝「件数不明」）。
///   便BM（見本 claude/field_close_date_remove_mock_v1.html の「決めた所」）: ホームの要対応の行は、数（大きい字）と単位（小さい字）を
///   分けて出す＝決まりは pendingCountLabel の1本（送った後の画面の見出しの字は、これをつないだ物＝pendingSectionCountLabel）。
class PendingCountLabel {
  const PendingCountLabel(this.number, this.unit);
  final String? number;
  final String unit;

  /// つないだ字（「2件」「2件以上」「件数不明」）。
  String get text => number == null ? unit : '$number$unit';
}

/// 「未送信日報」の件数の決まり。unknown＝読めない箱の元の字が在る（中の件数が分からない）・readFailed＝未送信の箱を読めなかった
///   （前に読めた時の数は今の数と違いうる）。分かった件数が在れば「N件以上」・無ければ「件数不明」・読めなかった時は「件数不明」
///   （分からない数を少なく見せない）。
PendingCountLabel pendingCountLabel(int known, {required bool unknown, bool readFailed = false}) {
  if (readFailed) return const PendingCountLabel(null, '件数不明');
  if (!unknown) return PendingCountLabel('$known', '件');
  return known > 0 ? PendingCountLabel('$known', '件以上') : const PendingCountLabel(null, '件数不明');
}

/// 「未送信日報」の見出しの件数（送った後の画面）。決まりは pendingCountLabel の1本。
String pendingSectionCountLabel(int known, {required bool unknown, bool readFailed = false}) =>
    pendingCountLabel(known, unknown: unknown, readFailed: readFailed).text;

/// 未送信の行の題「☀日勤 M/D分」「🌙夜勤 M/D分」（M/D は業務日＝送る report_date）。
String pendingRowTitle(String shiftType, String businessDate) =>
    '${shiftType == 'night' ? '🌙夜勤' : '☀日勤'} ${monthDayOfBusinessDate(businessDate)}分';

/// 業務日（'YYYY-MM-DD'）の「M/D」。形が違えば字のまま。
String monthDayOfBusinessDate(String businessDate) {
  final p = businessDate.split('-');
  if (p.length != 3) return businessDate;
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  return (m == null || d == null) ? businessDate : '$m/$d';
}

/// 未送信の行の下の字（通信で送れていない時）。
const String kPendingNetworkText = '通信状況により未送信です';

/// 読み込めない日報の行の題。count＝読めない行の数・unknown＝読めない箱の元の字が在る。
String unreadableRowTitle(int count, {required bool unknown}) {
  if (unknown) return '読み込めない日報（件数不明）';
  return count >= 2 ? '読み込めない日報 $count件' : '読み込めない日報';
}

/// 読み込めない日報の行の下の字。
const String kUnreadableRowText = '内容を読み込めないため、送信されません';

/// 行の「外す」。
const String kRemovePendingLabel = '外す';

/// 外せる行が在る時の※。
///   元: 「※外した日報は、管理・履歴のカレンダーから出し直せます。」＝出し直す道が無い日にも出た（見つけた事 (44)）。
///   →再（2026-10-19・便BM・【Q153】＝１・見本 claude/field_close_date_remove_mock_v1.html の (44) 案１）: いつも事実になる字。
const String kRemovedReportNote =
    '※外した日報は送信されません。管理・履歴のカレンダーに「日報漏れを申告する」が出ている日は、そこから出し直しを申告できます。';

/// 読み込めない日報が在る時の※（字は窓の2文目 kRemoveUnreadableLine2 と同じ＝そこから組む・検分 a260 の N3）。
const String kUnreadableReportNote = '※$kRemoveUnreadableLine2';

/// 外す時の窓の題（未送信の行）。
String removePendingTitle(String businessDate) =>
    '${monthDayOfBusinessDate(businessDate)}分の日報を外しますか？';

/// 外す時の窓の題（読み込めない日報）。
const String kRemoveUnreadableTitle = '読み込めない日報を外しますか？';

/// 外す時の窓の1文目（写真が在れば「写真N枚も消えます。」を足す）。
String removePendingLine1(int photoCount) =>
    '端末から外し、送信しません。${photoCount > 0 ? '写真$photoCount枚も消えます。' : ''}';

/// 外す時の窓の2文目（未送信の行）。
///   元: 「出し直しは、管理・履歴のカレンダーのM/Dから「日報漏れを申告する」で行えます。」＝出し直す道が無い日にも出た（見つけた事 (44)）。
///   →再（2026-10-19・便BM・【Q153】＝１・同じ見本の (44) 案１）: いつも事実になる字（出せるかは、カレンダーのその日で確かめられる）。
String removePendingLine2(String businessDate) =>
    '管理・履歴のカレンダーの${monthDayOfBusinessDate(businessDate)}に「日報漏れを申告する」が出ていれば、そこから出し直しを申告できます。';

/// 外す時の窓の2文目（読み込めない日報）。
const String kRemoveUnreadableLine2 = '日報の無い日は、管理・履歴のカレンダーで確かめられます。';

/// 送っている途中の日報を外そうとした時の知らせ。
const String kRemoveInFlightText = '送信中のため外せません。少し待ってから、もう一度お試しください。';

/// 送った後の画面の［今日はここまで］の「退勤して締める」で、ホームの打刻の画面が打刻か読み直しの最中だった時の知らせ
///   （便BN・見つけた事 (50)・【Q156】＝１・見本 claude/field_close_busy_mock_v1.html・出し方は kRemoveInFlightText と同じ＝isWarning・2秒）。
const String kCloseBusyText = '処理中のため退勤できません。少し待ってから、もう一度お試しください。';

/// 外せなかった時（端末の箱に書けない）の知らせ。
const String kRemoveFailedText = '外せませんでした。もう一度お試しください。';

// ── 便BM（見本 claude/field_refused_today_mock_v1.html の ②③・claude/field_close_date_remove_mock_v1.html の (41)・
//    ボスの裁定【Q150】【Q151】＝１）──

/// 今日の分に未送信の日報が在る時の、2件目の窓と本日休みの窓の題（見本 ③）。全部届いている時は今の題「本日は報告済みです」。
const String kTodayPendingTitle = '本日の日報に未送信があります';

/// 今日の分に未送信の日報が在る時の、2件目の窓の本文（見本 ③）。
const String kSecondReportPendingBody = '未送信の日報は、届くまで送り直しを続けます。2件目を作成しますか？';

/// 今日の分に未送信の日報が在る時の、本日休みの窓の本文（見本 ③）。
const String kRestDayPendingBody = '未送信の日報は、届くまで送り直しを続けます。休みとして登録しますか？';

/// みなしの締めの窓の本文の1行目（見本 (41)）。businessDate＝締める業務日（'YYYY-MM-DD'）・shiftType＝締める勤務の種類。
///   元: 「締めると、この日は「次の現場へ移動」と「勤務区分の切替」ができなくなります。」＝どちらも今の作りと違った（見つけた事 (41)）。
String closeTodayLine1(String shiftType, String businessDate) =>
    '締めると、${monthDayOfBusinessDate(businessDate)}の${shiftType == 'night' ? '夜勤' : '日勤'}の2件目の日報は作れなくなります。';

/// 「未送信日報」の画面で、行が1つも無い時の字（見本の「決めた所」・前例＝差し戻しの画面の「差し戻しはありません」）。
const String kPendingEmptyText = '未送信日報はありません';
