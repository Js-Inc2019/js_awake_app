// lib/utils/business_date.dart
// 業務日（JST基準の YYYY-MM-DD）を返す単一の真実源。
// BE の js-office-api/utils/businessDate.js と同一ルール（Asia/Tokyo・DSTなし=固定+9h）。
// 端末のタイムゾーン設定に依存しないため、海外TZ端末でも日付がBEとズレない。

/// 任意の時刻を JST(UTC+9) の 'YYYY-MM-DD' 文字列にする。
String jstDateString(DateTime d) {
  final jst = d.toUtc().add(const Duration(hours: 9));
  final mm = jst.month.toString().padLeft(2, '0');
  final dd = jst.day.toString().padLeft(2, '0');
  return '${jst.year}-$mm-$dd';
}

/// 夜勤対応の業務日。shiftType=='night' かつ JST時刻が 00:00〜11:59 のとき
/// （夜勤の退勤側＝深夜〜午前）は「始業日＝前日」を返す。
/// それ以外（日勤・夜勤の12時以降＝開始側）は jstDateString(d) と同値。
String businessDateForShift(String shiftType, DateTime d) {
  if (shiftType != 'night') return jstDateString(d);
  final jst = d.toUtc().add(const Duration(hours: 9));
  if (jst.hour >= 12) return jstDateString(d); // 昼以降の夜勤開始側は当日が始業日
  return jstDateString(d.subtract(const Duration(days: 1)));
}
