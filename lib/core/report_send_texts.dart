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

/// 「未送信日報」の見出しの件数。unknown＝読めない箱の元の字が在る（中の件数が分からない）。
///   分かった件数が在れば「N件以上」・無ければ「件数不明」（分からない数を少なく見せない）。
String pendingSectionCountLabel(int known, {required bool unknown}) {
  if (!unknown) return '$known件';
  return known > 0 ? '$known件以上' : '件数不明';
}

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
const String kRemovedReportNote = '※外した日報は、管理・履歴のカレンダーから出し直せます。';

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
String removePendingLine2(String businessDate) =>
    '出し直しは、管理・履歴のカレンダーの${monthDayOfBusinessDate(businessDate)}から「日報漏れを申告する」で行えます。';

/// 外す時の窓の2文目（読み込めない日報）。
const String kRemoveUnreadableLine2 = '日報の無い日は、管理・履歴のカレンダーで確かめられます。';

/// 送っている途中の日報を外そうとした時の知らせ。
const String kRemoveInFlightText = '送信中のため外せません。少し待ってから、もう一度お試しください。';

/// 外せなかった時（端末の箱に書けない）の知らせ。
const String kRemoveFailedText = '外せませんでした。もう一度お試しください。';
