// lib/utils/app_route_observer.dart
// 画面の重なりの見張り（便BN・下調べの (D6)）。MaterialApp の navigatorObservers に差す（lib/main.dart）。
//   ★型は ModalRoute（窓とシートは PopupRoute＝PageRoute だけの型だと、その上の物が閉じた時の知らせが届かない）。
//   聞く所＝シェル（lib/screens/home_screen.dart の _JsMainShellState・RouteAware）と、日報のフォームの全画面の見張り
//   （同じ本の _ReportFormRouteWatcher）＝上の物が閉じた時（didPopNext）に、夜勤のまま業務日が替わった時の日勤への戻しを見る。
import 'package:flutter/widgets.dart';

/// アプリの画面の重なりの見張り（1つだけ）。
final RouteObserver<ModalRoute<void>> appRouteObserver = RouteObserver<ModalRoute<void>>();
