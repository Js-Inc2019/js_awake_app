// lib/utils/business_day_tick.dart
// 業務日の切り替わりの知らせと時計（便BN・見つけた事 (47)・下調べの (D5)）。
//
// ★なぜ要るか：画面や窓は、開いた時（または描いた時）の今で決めた「今日」を持ち続ける。アプリを閉じずに業務日が替わると、
//   前の業務日の「送った・締めた」の印・ボタン・窓の字が残った（見つけた事 (47)）。切り替わりの時刻に1回鳴らし、聞く所が
//   今の業務日で決め直す。
// ★時計（BusinessDayClock）：次の切り替わりの時刻（nextBusinessBoundary＝日本の時刻の次の 0 時と次の 12 時の早い方）に1回鳴る。
//   鳴ったら掛け直す。アプリへ戻った時は、前の時計を止めて今から掛け直す（restart・裏や端末が眠る間の時計の進み方に頼らない）。
//   掛けるのはシェル（lib/screens/home_screen.dart の _JsMainShellState の initState）・止めるのは dispose。
// ★知らせ（BusinessDayTick.changes）：鳴らすのはシェルだけ（時計が鳴った時と、アプリへ戻った時）。前例＝lib/utils/rest_day_refresh.dart。
//   聞く所＝「未送信日報」の画面（lib/screens/pending_reports_screen.dart・今日の分を分け直す）と、今日を前に置く字の窓
//   （lib/widgets/business_day_dialog_guard.dart の CloseOnBusinessDayChange）。ホームの打刻の画面は、シェルの番号
//   （PunchScreen.businessDayTick）で読み直す。
// ★値は数を +1 するだけ（中身に意味を持たせない）。
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'business_date.dart';

/// 業務日の切り替わりの知らせ（便BN）。
class BusinessDayTick {
  BusinessDayTick._();

  /// 聞く所はここに listener を付け、dispose で外す。
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// 鳴らす（シェルの時計が鳴った時と、アプリへ戻った時だけ）。
  static void ring() => changes.value++;
}

/// 次の業務日の切り替わりの時刻（now より後）。日本の時刻（+9時間・business_date.dart と同じ物差し）で、次の 0 時と次の 12 時の
///   早い方（日勤と暦の日は 0 時・夜勤は 12 時で業務日が替わる＝どの勤務の種類でも、この時刻をまたぐ時だけ業務日の字が替わりうる）。
DateTime nextBusinessBoundary(DateTime now) {
  final jst = now.toUtc().add(const Duration(hours: 9));
  final midnight = DateTime.utc(jst.year, jst.month, jst.day);
  final noon = midnight.add(const Duration(hours: 12));
  final next = jst.isBefore(noon) ? noon : midnight.add(const Duration(days: 1));
  return next.subtract(const Duration(hours: 9));
}

/// 次の切り替わりの時刻に1回鳴る時計（鳴ったら次の切り替わりへ掛け直す）。
class BusinessDayClock {
  BusinessDayClock(this.onTick);

  /// 鳴った時に呼ぶ。
  final VoidCallback onTick;
  Timer? _timer;
  DateTime? _target;

  /// 今から次の切り替わりへ掛け直す（前の時計は止める）。
  void restart() => _arm(businessNow());

  /// 止める（dispose）。
  void stop() {
    _timer?.cancel();
    _timer = null;
    _target = null;
  }

  /// 掛けている切り替わりの時刻（検査が見る・止めている時は null）。
  @visibleForTesting
  DateTime? get target => _target;

  void _arm(DateTime from) {
    _timer?.cancel();
    final target = nextBusinessBoundary(from);
    _target = target;
    final now = businessNow();
    final wait = target.isAfter(now) ? target.difference(now) : Duration.zero;
    _timer = Timer(wait, () {
      // 早く鳴った時（端末の時計が戻った・時計の進み方がずれた）は、鳴らさずに、今から次の切り替わりへ掛け直す
      //   （ふつうは同じ切り替わり・端末の時計が12時間より多く戻った時は、それより前の切り替わり＝今の時計で次に来る物・検分 a430b〜a433c）
      //   （切り替わりの前に鳴らない＝前の業務日のまま描き直して、本当の切り替わりを飛ばす形を作らない・検分 a430）。
      final n = businessNow();
      if (n.isBefore(target)) {
        _arm(n);   // 早く鳴った時（鳴らさない）
        return;
      }
      _arm(n);
      onTick();
    });
  }
}
