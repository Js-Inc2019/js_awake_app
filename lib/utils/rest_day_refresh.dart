// ============================================================
// lib/utils/rest_day_refresh.dart - 休みと振替休日の「読み直しの知らせ」（便F13）
//
// ★なぜ1本にするか:
//   休みと振替休日の状態は、いくつもの道で変わる（1件の画面での同意・取り下げ・取り消し・
//   休む日の変更、本日休み・打刻の催促の窓の本日休み・代休・振替の登録、本日休みの取り消し）。
//   →再（2026-09-30・便F13続）: 変わる道の名簿は下の「★鳴らす所」の1か所（ここに言い換えを二重に持たない）。
//   一方で、その状態を映している所も3つある（ホームの本日休みの状態、シェルの要対応の件数、
//   カレンダーの月）。道ごとに「戻ったら読み直す」を書き足すと、道が1本増えるたびに
//   どこかの読み直しが漏れ、古い数や古い輪が残る（振替の画面を開く道は、ホームの枠・
//   要対応の一覧・カレンダーの箱・お知らせ・スマホの通知・断りの窓と6つある）。
//   →再（2026-09-30・便F13続）: 振替の画面を開く道の名簿は lib/screens/substitute_detail_screen.dart の
//   冒頭（数と名簿はあちらの1か所に置き、ここには持たない）。
//   そこで「変わった」を鳴らす所と聞く所を、この1本だけでつなぐ。
//
// ★鳴らす所（ring を呼ぶ所）:
//   ★どこも「状態を変える通信が通ったとき」に、画面や窓が閉じたか（mounted）を見る前に1回だけ鳴らす
//     （便F13続）。閉じたかを見てから鳴らすと、通った後に閉じていた回に鳴らず、ホームとカレンダーが
//     次のきっかけまで古いまま残る。
//   ・lib/screens/substitute_detail_screen.dart の _run が通ったとき（同意・取り下げ・取り消し）
//     （元）と、_openChange が done == true を受けたとき
//     →再（2026-09-30・便F13続）: _openChange では鳴らさない（下の変更の画面が鳴らす＝2回鳴らさない）。
//   ・lib/screens/substitute_change_screen.dart の _confirm で休む日の変更の申し出が通ったとき（便F13続）
//   ・lib/screens/rest_day_screen.dart の _submit が通ったとき（新規も変更も）と _cancelRest が通ったとき
//   ・lib/widgets/punch_remind_dialog.dart の _restDay が通ったとき
//   ・lib/widgets/comp_off_dialog.dart の showCompOffFlow で代休を取れたとき
//   ・lib/screens/substitute_register_screen.dart で振替を登録できたとき（_register と、
//     _askPriorAgreement の「取り決めていた」で出し直して通ったとき）
//   ・lib/screens/punch_screen.dart の日報の入口で本日休みを取り消せたとき
// ★聞く所（changes に listener を付ける所）:
//   ・lib/screens/punch_screen.dart（本日休みの状態を読み直す）
//   ・lib/screens/home_screen.dart のシェル（要対応の件数を読み直す）と CalendarTab（_loadMonth）
//
// ★値は数を +1 するだけ（中身に意味を持たせない）。ValueNotifier は同じ値では鳴らないので、
//   必ず違う値になるよう数を進める。
// ============================================================

import 'package:flutter/foundation.dart';

/// 休みと振替休日の読み直しの知らせ（便F13）。
class RestDayRefresh {
  RestDayRefresh._();

  /// 聞く所はここに listener を付け、dispose で外す。
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// 鳴らす。★状態が変わったと BE が答えた（通った）ときだけ呼ぶ。
  static void ring() => changes.value++;
}
