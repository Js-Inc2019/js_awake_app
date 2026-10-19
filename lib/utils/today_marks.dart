// lib/utils/today_marks.dart
// 今日の印（送った・締めた印と、勤務の種類）に、書いた人の印を付けて読み書きする
// （便BJ・見本 claude/field_report_fix_mock_v2.html の ⑫・ボスの裁定【Q141】）。
//
// ★何か：今日の印は3つ＝送った・締めた印（report_done_day・report_done_night）と、勤務の種類（shift_type と
//   shift_business_date の組）。書く時に、書いた人（端末の保存の 'user_id'）の印を付ける。読む時は、印の人が
//   今ログインしている人と同じ時だけ使う。別の人の印は、シェル（home_screen.dart の _restoreTodayState）が開く時に消す
//   （clearOtherOwnersTodayMarks・勤務の種類は _restoreShiftType が消す＝見本 v2 の ⑫「別の人の時は使わずに消す」）。
// ★なぜ：元は、ログアウトの掃除がこの3つを消し、見本 v1 の ⑧ で締め出し・期限切れも同じ掃除にした。消すと、
//   同じ人がログインし直した時に、送った後の画面が消えて日報のフォームが開く（送った日報を2枚目として送る恐れ）・
//   夜勤の人が日勤に戻る・締めた日が締めていない形に戻る。→ 掃除では消さずに、人の印で見分ける（【Q141】＝１）。
// ★形：report_done_<種類> = '<業務日>|<status>|<user_id>'・shift_business_date = '<業務日>|<user_id>'
//   （shift_type は 'day'|'night' のまま＝人の印は shift_business_date の方に付ける）。
//   便BJ より前の形（人の印が無い＝'<業務日>|<status>'・'<業務日>'）は、今ログインしている人の物として読む
//   （ログインしたまま更新した人の印を消さないため）。人の印が無い印は、掃除で消す（clearUnownedTodayMarks＝次の人に渡さない）。
// ★書く人が分からない時（'user_id' が無い時）は書かない（人の印の無い印を作らない）。
// →再（2026-10-14・便BK・見つけた事 (28)）: 前の形の印を「今ログインしている人の物」として読むので、ログインした人が
//   替わった時（書く前の 'user_id' が空か、別の人）に、人の印の無い前の形の印を消す。'user_id' を書く所は
//   saveLoginUserId の1本（ログイン画面の2か所・機種変更の画面・登録の画面が呼ぶ）。
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_error_log.dart';

/// 勤務の種類の鍵（'day'|'night'）。
const String kShiftTypeKey = 'shift_type';

/// 勤務の種類を選んだ業務日の鍵（'<業務日>|<user_id>'）。
const String kShiftBusinessDateKey = 'shift_business_date';

/// 送った・締めた印の鍵（勤務の種類ごと）。
String reportDoneKeyOf(String shiftType) => 'report_done_$shiftType';

/// 送った・締めた印の字（書く形）。
String reportDoneValue(String bizDate, String status, String owner) =>
    '$bizDate|$status|$owner';

/// 送った・締めた印を読む。業務日が bizDate と同じで、印の人が me（または人の印が無い前の形）の時だけ status を返す。
///   ほか（無い・形が違う・業務日が違う・別の人）は null（＝今日の印は無い）。
String? reportDoneStatusOf(String? raw,
    {required String bizDate, required String me}) {
  if (raw == null) return null;
  final parts = raw.split('|');
  if (parts.length != 2 && parts.length != 3) return null;
  if (parts.length == 3 && (me.isEmpty || parts[2] != me)) return null;
  if (parts[0] != bizDate) return null;
  return parts[1];
}

/// 勤務の種類を選んだ業務日の字（書く形）。
String shiftDateValue(String bizDate, String owner) => '$bizDate|$owner';

/// 勤務の種類を選んだ業務日を読む。印の人が me（または人の印が無い前の形）の時だけ業務日を返す。ほかは null。
String? shiftDateOf(String? raw, {required String me}) {
  if (raw == null) return null;
  final parts = raw.split('|');
  if (parts.length == 1) return parts[0];
  if (parts.length == 2 && me.isNotEmpty && parts[1] == me) return parts[0];
  return null;
}

/// 今ログインしている人の 'user_id'（無ければ ''）。
String todayMarkOwnerOf(SharedPreferences prefs) =>
    prefs.getString('user_id') ?? '';

/// シェルが開く時（home_screen.dart の _restoreTodayState）に呼ぶ：送った・締めた印のうち、書いた人が今の人でない物を消す
///   （別の人の印は使わずに消す＝見本 v2 の ⑫・検分 a253 の S3）。今の人が分からない時と、人の印の無い前の形は触らない。★投げる。
Future<void> clearOtherOwnersTodayMarks(SharedPreferences prefs) async {
  final me = todayMarkOwnerOf(prefs);
  if (me.isEmpty) return;
  for (final k in <String>[reportDoneKeyOf('day'), reportDoneKeyOf('night')]) {
    final parts = prefs.getString(k)?.split('|');
    if (parts != null && parts.length == 3 && parts[2] != me) await prefs.remove(k);
  }
}

/// 掃除（utils/personal_data_cleanup.dart の clearPersonalData）から呼ぶ：人の印の無い今日の印を消す。
///   人の印の付いた印は残す（同じ人がログインし直した時だけ使う）。勤務の種類は2つの鍵の組で見る
///   （業務日の方に人の印が無ければ、2つとも消す）。★投げる（呼び手が受ける）。
Future<void> clearUnownedTodayMarks(SharedPreferences prefs) async {
  for (final k in const <String>['report_done_day', 'report_done_night']) {
    final raw = prefs.getString(k);
    if (raw != null && raw.split('|').length != 3) await prefs.remove(k);
  }
  final date = prefs.getString(kShiftBusinessDateKey);
  if (date == null || date.split('|').length != 2) {
    await prefs.remove(kShiftTypeKey);
    await prefs.remove(kShiftBusinessDateKey);
  }
}

/// ログインした人の 'user_id' を書く（便BK・見つけた事 (28)）。★'user_id' を書く所はこの1本だけ
///   （login_screen.dart の2か所・recovery_screen.dart・register_screen.dart）。
///   書く前の 'user_id' が空か、userId と違えば、人の印の無い前の形の今日の印を消してから書く（clearUnownedTodayMarks＝
///   前の人の前の形の印を、次の人の物として読まない）。ログインしたまま更新した人（同じ人）の前の形の印は消さない。
///   消せなかった時は、端末の失敗の控えに残し、書くのは止めない（ログインを止めない）。★書く方の失敗は投げる（今までと同じ）。
///   →再（2026-10-14・便BK・検分 a261 の任意 8）: 書く前の 'user_id' を読めない時（字でない値）は、空として扱う
///   （読めないままログインを止めない・前の形の印は消してから書く）。
Future<void> saveLoginUserId(SharedPreferences prefs, String userId) async {
  String before;
  try {
    before = todayMarkOwnerOf(prefs);
  } catch (e) {
    debugPrint('書く前のログインした人を読めませんでした（空として続行）: $e');
    before = '';
  }
  if (before.isEmpty || before != userId) {
    try {
      await clearUnownedTodayMarks(prefs);
    } catch (e) {
      debugPrint('前の形の今日の印を消せませんでした（続行）: $e');
      await recordDeviceError('unowned_marks_clear');
    }
  }
  await prefs.setString('user_id', userId);
}
