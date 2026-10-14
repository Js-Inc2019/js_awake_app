// lib/utils/saved_shift_type.dart
// 端末に保存した、今の勤務の種類（'day'|'night'）を読む（便BJ・見本 claude/field_report_fix_mock_v1.html の B）。
//
// ★何か：シェル（home_screen.dart の _saveShiftType）が書く 'shift_type' と 'shift_business_date' を読み、
//   保存した業務日と、今その種類で数えた業務日が同じ時だけ、その種類を返す（別の業務日へ夜勤を引きずらない）。
//   決まりは shiftTypeIfSameBusinessDate の1本（シェルの _restoreShiftType も同じ1本で見る）。
//   →再（2026-10-14・便BJ・見本 v2 の ⑫・【Q141】）: 'shift_business_date' は '<業務日>|<書いた人>' になった。
//   書いた人が今の人でない時は、保存が無い物として読む（utils/today_marks.dart の shiftDateOf）。
// ★なぜ：夜勤の人の朝（JST 0〜11時）は、まだ前の日の勤務の中に居る。日報漏れの申告の入口と、尋ねる口・申告の口は、
//   その業務日を「今日」として扱う（サーバは送られた shift_type で今日を決める＝便BI）。
import 'package:shared_preferences/shared_preferences.dart';

import 'business_date.dart';
import 'today_marks.dart';

/// 保存した勤務の種類を、今も使えるか見る。使えればその種類・使えなければ null。
///   使える＝種類が 'day' か 'night' で、保存した業務日が、今その種類で数えた業務日と同じ。
String? shiftTypeIfSameBusinessDate(
    String? savedType, String? savedDate, DateTime now) {
  if (savedType != 'day' && savedType != 'night') return null;
  if (savedDate == null || savedDate != businessDateForShift(savedType!, now)) {
    return null;
  }
  return savedType;
}

/// 今の勤務の種類（使える保存が無ければ 'day'）。★投げない（読めなければ 'day'）。
Future<String> savedShiftTypeForNow() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return shiftTypeIfSameBusinessDate(
            prefs.getString(kShiftTypeKey),
            shiftDateOf(prefs.getString(kShiftBusinessDateKey),
                me: todayMarkOwnerOf(prefs)),
            DateTime.now()) ??
        'day';
  } catch (_) {
    return 'day';
  }
}
