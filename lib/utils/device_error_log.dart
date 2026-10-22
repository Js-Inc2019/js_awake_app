// lib/utils/device_error_log.dart
// 端末の中の失敗の控え（便BK・見本 claude/field_report_fix_mock_v3.html の ⑰④・ボスの裁定【Q145】＝１）。
//
// ★何か：裏で止まった失敗（止めずに進んだ所＝便BJ で足した開発の記録 debugPrint の所）を、決まった種類の鍵と
//   時刻だけで端末に残す。設定の「端末｜エラー記録」と、その先の一覧（lib/screens/device_error_log_screen.dart）で見る。
// ★なぜ：失敗が開発の記録（debugPrint）にだけ出て、画面にも端末にも残らなかった（見つけた事 (31)＝沈黙障害）。
//   不具合の問い合わせの時に「何が・いつ・代わりに何をしたか」を、端末の画面で確かめられるようにする。
// ★残す物：種類の鍵と時刻だけ。例外の字・個人の情報・資格・住所・写真の道は残さない（字は下の名簿の決まった字だけ）。
// ★新しい順に kDeviceErrorLogMax（50）件まで。送信しない（端末の中だけ）。
//   ログアウトの掃除（utils/personal_data_cleanup.dart）では消さない（人に付く物でない・次の人の問い合わせにも要る）。
// ★投げない（控えの失敗で、元の動きを止めない）。
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 端末の保存の鍵（字の並び・1件＝「<世界標準時のミリ秒>|<種類の鍵>」・新しい順）。
const String kDeviceErrorLogKey = 'device_error_log';

/// 残す件数の上限（古い物から捨てる）。
const int kDeviceErrorLogMax = 50;

/// 種類の鍵 → 一覧の題と「代わりにした事」。★画面の字はここだけ（写しを作らない）。
const Map<String, ({String title, String fallback})> kDeviceErrorKinds = {
  'photo_keep': (title: '写真の保存', fallback: '元の写真のまま送信'),
  'photo_path': (title: '写真の読み込み', fallback: '覚えた道のまま読む'),
  'photo_delete': (title: '写真の削除', fallback: '写真を残した'),
  'photo_sweep': (title: '写真の掃除', fallback: '写真を残した'),
  'net_watch': (title: '電波の監視', fallback: 'アプリを開いた時に再送'),
  'cleanup_keys': (title: '端末の掃除', fallback: '次に開いた時にもう一度'),
  'shift_restore': (title: '勤務区分の読み込み', fallback: '日勤で表示'),
  'shift_save': (title: '勤務区分の保存', fallback: '選んだ区分で表示'),
  'done_mark_read': (title: '送信記録の読み込み', fallback: '日報のフォームを表示'),
  // 便BN（見つけた事 (53)・見本 claude/field_unread_unwritten_mock_v1.html・【Q160】＝１）: 今日の印（送った・締めた ほか）を
  //   端末に書けなかった時（home_screen.dart の _saveWorkStatus）。続けて書けない間は1件だけ。
  'today_mark_save': (title: '送信記録の保存', fallback: '印を残さずに続行'),
  'today_marks_clear': (title: '別の人の印の掃除', fallback: '使わずに続行'),
  'unowned_marks_clear': (title: '前の形の印の掃除', fallback: '残したまま続行'),
  'pending_read': (title: '送信状況の読み込み', fallback: '前の表示のまま'),
  'pending_unreadable': (title: '読み込めない日報', fallback: '端末に残した'),
  'pending_unreadable_keep': (title: '読み込めない日報の控え', fallback: '控えずに続行'),
  'box_undo': (title: '未送信の箱の戻し', fallback: '「送信できません」と表示'),
  'box_remove_after_send': (title: '送れた日報の片付け', fallback: '送れた事として続行'),
  'note_answer': (title: '送り先の答えの控え', fallback: '前の表示のまま'),
  'retry_failed': (title: '送り直し', fallback: '次の機会に再送'),
  'remove_undo': (title: '外す時の箱の戻し', fallback: '「外せませんでした」と表示'),
  'lockout_token_read': (title: '資格の読み込み', fallback: '締め出しを続行'),
};

/// 名簿に無い鍵の時の字（前の版の端末に残った鍵など＝黙って消さずに出す）。
const ({String title, String fallback}) kDeviceErrorUnknownKind =
    (title: '不明な記録', fallback: '—');

/// 控えの1件。
class DeviceErrorEntry {
  const DeviceErrorEntry(this.at, this.kind);

  /// 起きた時刻（端末の時刻・世界標準時で持ち、出す時に端末の時刻へ直す）。
  final DateTime at;

  /// 種類の鍵（kDeviceErrorKinds の鍵）。
  final String kind;

  String get title => (kDeviceErrorKinds[kind] ?? kDeviceErrorUnknownKind).title;
  String get fallback =>
      (kDeviceErrorKinds[kind] ?? kDeviceErrorUnknownKind).fallback;
}

/// 控えの数が替わった時に知らせる（設定の行の件数・検査）。★値は件数。
final ValueNotifier<int> deviceErrorCount = ValueNotifier<int>(0);

/// 時計（検査は差し替える）。
@visibleForTesting
DateTime Function() deviceErrorClock = DateTime.now;

/// 失敗を1件残す。★投げない。kind は kDeviceErrorKinds の鍵（名簿に無い鍵も残す＝一覧で「不明な記録」）。
///   →再（2026-10-14・便BK・検分 a261 の任意 9）: 鍵に字の並びでない値が入っていて読めない時は、その鍵をこの1件で
///   書き直す（読めないまま上書きもしないと、その端末では二度と控えを残せない）。読めない値は控えの形でないので、控えではない。
Future<void> recordDeviceError(String kind) async {
  final now = deviceErrorClock().toUtc().millisecondsSinceEpoch;
  try {
    final prefs = await SharedPreferences.getInstance();
    List<String> before;
    try {
      before = prefs.getStringList(kDeviceErrorLogKey) ?? const <String>[];
    } catch (e) {
      debugPrint('失敗の控えの鍵を読めませんでした（この1件で書き直す）: $e');
      before = const <String>[];
    }
    final list = <String>['$now|$kind', ...before];
    final kept = list.length > kDeviceErrorLogMax
        ? list.sublist(0, kDeviceErrorLogMax)
        : list;
    await prefs.setStringList(kDeviceErrorLogKey, kept);
    deviceErrorCount.value = kept.length;
  } catch (e) {
    debugPrint('失敗の控えを残せませんでした: $e');
  }
}

/// 控えを新しい順に読む。読めない行は飛ばさずに「不明な記録」（時刻が読めなければ 0 時）として出す。★投げない。
///   →再（2026-10-14・便BK・検分 a260 の N9）: 控えそのものを読めない時は null（「エラー記録はありません」と事実と違う字を
///   出さない＝画面が読めなかった事を出す）。その時、件数の知らせ（deviceErrorCount）は前の値のまま。
Future<List<DeviceErrorEntry>?> readDeviceErrors() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kDeviceErrorLogKey) ?? const <String>[];
    final out = <DeviceErrorEntry>[];
    for (final line in raw) {
      final bar = line.indexOf('|');
      final ms = bar < 0 ? null : int.tryParse(line.substring(0, bar));
      final kind = bar < 0 ? '' : line.substring(bar + 1);
      out.add(DeviceErrorEntry(
          DateTime.fromMillisecondsSinceEpoch(ms ?? 0, isUtc: true), kind));
    }
    deviceErrorCount.value = out.length;
    return out;
  } catch (e) {
    debugPrint('失敗の控えを読めませんでした: $e');
    return null;
  }
}
