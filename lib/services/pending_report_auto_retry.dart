// lib/services/pending_report_auto_retry.dart
// 未送信の日報を、電波が戻った時に送り直す（便BJ・見本 claude/field_report_fix_mock_v1.html の ①案A）。
//
// ★何か：端末の電波の知らせ（connectivity_plus の onConnectivityChanged）を聞き、つながっている知らせ
//   （ConnectivityResult.none でない物）が届いたら、渡された送り直し（ReportStore.retryPending）を呼ぶ。
// ★なぜ：送った後の画面の字「電波の良い場所で自動再送されます。」のとおりに動かす。元は、送り直すのが
//   アプリを開いた2秒後・次に送る時・「今すぐ再送する」の3つだけで、電波の部品は入っていたが使われていなかった。
// ★アプリへ戻った時の送り直しは、ここではなくシェル（home_screen.dart の didChangeAppLifecycleState）が呼ぶ。
// ★送り直しが重なっても、同じ日報を2回送らない（ReportStore が、送っている途中の日報を拾わない）。
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../utils/device_error_log.dart';

/// 電波の知らせが「つながっている」か（none だけの知らせのほかは、つながっている）。
bool isConnectivityOnline(List<ConnectivityResult> results) =>
    results.isNotEmpty && !results.contains(ConnectivityResult.none);

class PendingReportAutoRetry {
  /// [changes] 電波の知らせの流れ（検査は偽の流れを渡す・既定は connectivity_plus）。
  /// [retry] 送り直し（シェルは ReportStore.instance.retryPending を渡す）。
  PendingReportAutoRetry({
    required this.retry,
    Stream<List<ConnectivityResult>>? changes,
  }) : _changes = changes;

  final Future<void> Function() retry;
  final Stream<List<ConnectivityResult>>? _changes;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// 聞き始める（2回目からは何もしない）。★投げない（知らせの流れが壊れても、アプリは止めない）。
  void start() {
    if (_sub != null) return;
    try {
      _sub = (_changes ?? Connectivity().onConnectivityChanged).listen(
        (results) {
          if (isConnectivityOnline(results)) unawaited(retry());
        },
        onError: (Object e) {
          debugPrint('電波の知らせを読めませんでした: $e');
          unawaited(recordDeviceError('net_watch'));   // 便BK（見本 v3 の ⑰④・知らせを読めなかった時）
        },
      );
    } catch (e) {
      debugPrint('電波の知らせを聞けませんでした: $e');
      unawaited(recordDeviceError('net_watch'));   // 便BK（見本 v3 の ⑰④・聞けなかった時）
    }
  }

  /// 聞くのをやめる。
  Future<void> stop() async {
    final s = _sub;
    _sub = null;
    await s?.cancel();
  }
}
