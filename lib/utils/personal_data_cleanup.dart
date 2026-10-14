// lib/utils/personal_data_cleanup.dart
// 人に付く物を端末から消す（便BJ・見本 claude/field_report_fix_mock_v1.html の ⑧・ボスの裁定【Q140】）。
//
// ★何か：ログアウトの時に消す鍵の名簿と、それを消す関数。名簿はここ1つ（画面に写しを作らない）。
// ★呼ぶ所は4つ：ログアウト（profile_screen.dart の _confirmLogout）・締め出し（session_lockout.dart の
//   _discardCredentials）・ログイン画面の断り（login_screen.dart の 401/403）・月の履歴の 401
//   （monthly_history_screen.dart）。元は締め出しと 401 の3つの道が auth_token だけを消していた
//   （前の人の下書き・場所・名前が次の人の端末に残った）。
// ★消さない物：
//   ・端末に付く物＝notification_hours（通知の時刻）・is_registered（端末の登録の印）・device_id（端末の番号）・
//     logged_out（ログアウトの印＝呼び手が立てる）。
//   ・未送信の日報の箱（pending_reports）＝持ち主の印つきで残し、同じ人がログインし直した時だけ送る（【Q140】・
//     lib/main.dart の ReportStore.retryPending）。読めなかった箱の元の字（pending_reports_unreadable）も同じく残す
//     （日報を黙って消さない・検分 a251 の N3）。
//   ・締め出しの理由（session_lockout_reason）＝ログイン画面の赤い帯に出すため。ログアウトは clearLockoutReason で別に消す。
//   ・今日の印（送った・締めた印 report_done_day・report_done_night と、勤務の種類 shift_type・shift_business_date）のうち、
//     書いた人の印が付いた物＝同じ人がログインし直した時だけ使う（見本 v2 の ⑫・ボスの裁定【Q141】・utils/today_marks.dart）。
//     人の印が無い物（便BJ より前の形）は消す（clearUnownedTodayMarks）。
// ★次の人の初めの画面：出発地は「自宅」（default_origin が無い）・天気は測り終わるまで空（控えが無い）・
//   規約は同意し直す（同意の印が無い）。
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'today_marks.dart';

/// 消す鍵の名簿（63）。★今日の印の4つは、この名簿でなく clearUnownedTodayMarks（人の印の無い物だけを消す）で見る。
const List<String> kPersonalDataKeys = <String>[
  // ── 便BJ より前のログアウトが消していた物（45 から pending_reports を除いた 44 のうち、今日の印の4つを除いた 40）──
  // 資格と人
  'auth_token', 'user_id', 'user_name', 'user_role', 'role', 'company_id', 'work_mode',
  // 勤務設定（みなし）・打刻の状態
  'deemed_start', 'deemed_end', 'break_minutes', 'work_checked_in', 'work_check_in_time',
  // 勤務の種類（shift_type・shift_business_date）と、勤務の状態（report_done_day・report_done_night）は、
  //   →再（2026-10-14・便BJ・見本 v2 の ⑫・【Q141】）: 名簿から外した（clearUnownedTodayMarks が人の印の無い物だけを消す）。
  // 勤務の状態の前の形の3つ（読み捨て済みの残り）
  'today_date', 'today_work_status', 'report_done_shift',
  // 日報の下書き
  'today_transport', 'today_work_content', 'today_parking_fee',
  'today_overtime_hours', 'today_overtime_minutes',
  // 前回の現場・移動手段（home_screen.dart）
  'last_site_id', 'last_site_name', 'last_transports', 'last_car_type',
  // 目安の覚え書き・最後に開いたタブ（home_screen.dart）
  'route_cache_key', 'route_cache_json',
  'last_tab_index_worker', 'last_tab_index_foreman',
  'last_tab_index_v2_worker', 'last_tab_index_v2_foreman',
  // 日報の控え（lib/main.dart の ReportStore の履歴）
  'worker_reports_history',
  // 個人の情報（profile_screen.dart）
  'emergency_contact_name', 'emergency_contact_phone', 'profile_phone', 'profile_blood_type',
  'home_address', 'work_address', 'health_check_date_iso', 'experience_years', 'worker_id',
  // ── 便BJ で足した物（23）──
  // 相乗りの下書き（home_screen.dart の _saveDraft）
  'today_carpool_company', 'today_carpool_name',
  // 出発地の選び（home_screen.dart）
  'default_origin',
  // 会社の住所と会社名（home_screen.dart）
  'company_address', 'company_name',
  // 最後に測った場所（home_screen.dart・punch_screen.dart）
  'gps_address', 'gps_lat', 'gps_lon',
  // 天気の控え（home_screen.dart）
  'cache_weather_v2_alert_level', 'cache_weather_v2_alert_message', 'cache_weather_v2_desc',
  'cache_weather_v2_humidity', 'cache_weather_v2_icon', 'cache_weather_v2_precip',
  'cache_weather_v2_temp', 'cache_weather_v2_wbgt_level', 'cache_weather_v2_wbgt_value',
  'cache_weather_v2_wind',
  // 未対応の件数の控え（home_screen.dart）
  'cache_revision_count',
  // 氏名の名簿（便BJ で作りごと撤去した・前の端末に残った鍵を消す）
  'registered_worker_names',
  // 規約の同意の印（login_screen.dart・次の人が同意し直す）
  'consent_agreed', 'consent_agreed_at', 'consent_version',
];

/// 掃除の後に呼ぶ口。★main() が ReportStore の afterPersonalDataCleared（写真の置き場の掃除と、
///   未送信の数の読み直し）を差す（utils から main.dart を読み込むと依存が逆流するため、参照だけを受け取る）。
Future<void> Function() afterPersonalDataCleared = _nothing;

Future<void> _nothing() async {}

/// 人に付く物を消す。★投げない（掃除の失敗で、ログアウト・締め出し・ログイン画面への道を止めない）。
Future<void> clearPersonalData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final k in kPersonalDataKeys) {
      await prefs.remove(k);
    }
    await clearUnownedTodayMarks(prefs);
  } catch (e) {
    debugPrint('[personal_data_cleanup] 鍵の掃除に失敗（続行）: $e');
  }
  try {
    await afterPersonalDataCleared();
  } catch (e) {
    debugPrint('[personal_data_cleanup] 写真の掃除に失敗（続行）: $e');
  }
}
