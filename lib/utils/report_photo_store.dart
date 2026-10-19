// lib/utils/report_photo_store.dart
// 日報の写真の置き場（便BJ・見本 claude/field_report_fix_mock_v1.html の ③）。
//
// ★何か：撮った写真を、アプリの置き場（getApplicationSupportDirectory の下の report_photos）へ写す・消す・掃除する。
// ★なぜ：カメラが返す写真は OS の一時の置き場に在り、送り直しを待つ間に消える事がある
//   （消えると、送る時に写真が黙って抜けていた）。アプリの置き場は、アプリが消すまで残る。
// ★消すのは、この置き場の中の写真だけ（ほかの道は触らない）。
// ★呼ぶ所：写すのは写真の帯（lib/widgets/photo_strip_field.dart の撮る所）だけ。消すのは ReportStore
//   （lib/main.dart・送れた日報の写真）だけ。掃除は ReportStore.sweepPhotos（起動の時・ログアウトの掃除の後）だけ。
//   →再（2026-10-14・便BK）: 消すのは、ReportStore（送れた日報の写真・送った後の画面で外した日報の写真＝見本 v3 の ⑮⑯）と、
//   写真の帯の ✕（外した写真を、箱のどの日報も指していない時だけ＝見つけた事 (30)）。数えるのは ReportStore
//   （外す前の窓の「写真N枚も消えます。」）。
// ★写真の見分けは名前（reportPhotoKey）。置き場の場所は使うたびにシステムに聞く（Apple の技術資料 TN2406
//   「標準の置き場の場所は、いつもシステムに聞く」）。箱や下書きが覚えた道は、聞いた時の場所の字なので、
//   場所そのものが替わった後も、名前で今の置き場の写真に当てる（読む・消す・掃除の3つとも同じ決まり）。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'device_error_log.dart';

/// 置き場の名前（アプリの置き場の下）。
const String kReportPhotoDirName = 'report_photos';

/// 置き場を返す（無ければ作る）。★検査は差し替える（検査には端末の置き場が無い）。
Future<Directory> Function() reportPhotoDirOf = _defaultReportPhotoDir;

Future<Directory> _defaultReportPhotoDir() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/$kReportPhotoDirName');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

int _seq = 0;

/// 写真の見分けの鍵。置き場（report_photos）の直下の写真は名前だけ・ほかの道（置き場へ写せなかった写真）は道のまま。
///   ★「.」「..」と空の名前は置き場の外として扱う（道のまま＝消す・掃除の的にならない）。
String reportPhotoKey(String path) {
  final parts = path.split('/');
  if (parts.length >= 2 && parts[parts.length - 2] == kReportPhotoDirName) {
    final name = parts.last;
    if (name.isNotEmpty && name != '.' && name != '..') return name;
  }
  return path;
}

/// 覚えた道を、今の置き場の道に読み替える（置き場の中の写真だった道だけ・名前で当てる）。★投げない。
///   覚えた道に写真が在れば、その道のまま返す。当てる先にも無ければ、覚えた道のまま返す（読めない＝呼び手が数える）。
Future<String> resolveReportPhotoPath(String path) async {
  try {
    if (await File(path).exists()) return path;
    final key = reportPhotoKey(path);
    if (key == path) return path;
    final dir = await reportPhotoDirOf();
    final now = '${dir.path}/$key';
    if (await File(now).exists()) return now;
  } catch (e) {
    debugPrint('写真の道を読み替えられませんでした: $e');
    await recordDeviceError('photo_path');   // 便BK（見本 v3 の ⑰④）
  }
  return path;
}

/// 撮った写真を置き場へ写し、写した道を返す。★投げない。
///   写せなかった時は元の道を返す（今までと同じ道＝送る前の確かめ（読めなければ止める）と、送り直しの知らせ
///   （「写真 N枚を送れませんでした」）で、抜けた事は必ず出る）。元の写真は消さない（置き場の外は触らない）。
Future<String> keepReportPhoto(String sourcePath) async {
  try {
    final dir = await reportPhotoDirOf();
    final dot = sourcePath.lastIndexOf('.');
    final slash = sourcePath.lastIndexOf('/');
    final ext = (dot > slash && sourcePath.length - dot <= 6)
        ? sourcePath.substring(dot)
        : '.jpg';
    final name = '${DateTime.now().microsecondsSinceEpoch}_${_seq++}$ext';
    final copied = await File(sourcePath).copy('${dir.path}/$name');
    return copied.path;
  } catch (e) {
    debugPrint('写真を置き場へ写せませんでした（元の道のまま）: $e');
    await recordDeviceError('photo_keep');   // 便BK（見本 v3 の ⑰④）
    return sourcePath;
  }
}

/// 道の並びのうち、置き場の中の写真を消す（名前で今の置き場の写真に当てる・ほかの道は触らない）。★投げない。
Future<void> deleteReportPhotos(Iterable<String> paths) async {
  final list = paths.toList();
  if (list.isEmpty) return;
  try {
    final dir = await reportPhotoDirOf();
    for (final p in list) {
      final key = reportPhotoKey(p);
      if (key == p) continue;
      try {
        final f = File('${dir.path}/$key');
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('写真を消せませんでした: $e');
        await recordDeviceError('photo_delete');   // 便BK（見本 v3 の ⑰④）
      }
    }
  } catch (e) {
    debugPrint('写真の置き場を開けませんでした: $e');
    await recordDeviceError('photo_delete');   // 便BK（見本 v3 の ⑰④）
  }
}

/// 字の中の、置き場（kReportPhotoDirName）の直下の写真の名前（便BK・見本 v3 の ⑯）。
///   読めない箱・読めない行の字から拾う（日報として読めなくても、指している写真は外すまで消さない）。
///   「置き場の名前/」（JSON の「\/」も）の後ろの、「/」「\」「"」と空白までの字。「.」「..」は拾わない。
Set<String> reportPhotoNamesIn(String text) {
  final re = RegExp('${RegExp.escape(kReportPhotoDirName)}' r'(?:\\)?/([^/\\"\s]+)');
  return <String>{
    for (final m in re.allMatches(text))
      if (m.group(1) != '.' && m.group(1) != '..') m.group(1)!,
  };
}

/// 置き場の直下に在る写真のうち、names（名前）の数（外す前の窓の「写真N枚も消えます。」・便BK）。★投げない。
///   数えるのは、在ると確かめられた写真だけ（便BK・検分 a259 の N2）＝確かめられない写真（1枚の読みが投げた・置き場を
///   開けない）は、消す時（deleteReportPhotos）にも消せないので数えない（窓の数と、実際に消える数を食い違わせない）。
Future<int> countReportPhotos(Iterable<String> names) async {
  final Directory dir;
  try {
    dir = await reportPhotoDirOf();
  } catch (e) {
    debugPrint('写真の置き場を開けませんでした（数えない）: $e');
    return 0;
  }
  var n = 0;
  for (final name in names.toSet()) {
    if (name.isEmpty || name.contains('/') || name == '.' || name == '..') continue;
    try {
      if (await File('${dir.path}/$name').exists()) n++;
    } catch (e) {
      debugPrint('写真を確かめられませんでした（数えない）: $e');
    }
  }
  return n;
}

/// 置き場の中で、keep の道（名前で当てる）に無い写真を消す。before が在れば、それより前に書かれた写真だけ。
///   返り＝消した数。★投げない。
Future<int> sweepReportPhotos({required Set<String> keep, DateTime? before}) async {
  var removed = 0;
  try {
    final dir = await reportPhotoDirOf();
    if (!await dir.exists()) return 0;
    final keepKeys = keep.map(reportPhotoKey).toSet();
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      if (keepKeys.contains(reportPhotoKey(e.path))) continue;
      try {
        if (before != null && !(await e.lastModified()).isBefore(before)) continue;
        await e.delete();
        removed++;
      } catch (err) {
        debugPrint('写真を消せませんでした: $err');
        await recordDeviceError('photo_sweep');   // 便BK（見本 v3 の ⑰④）
      }
    }
  } catch (e) {
    debugPrint('写真の置き場の掃除に失敗: $e');
    await recordDeviceError('photo_sweep');   // 便BK（見本 v3 の ⑰④）
  }
  return removed;
}
