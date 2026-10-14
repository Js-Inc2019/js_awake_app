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
