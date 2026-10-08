// ============================================================
// test/f8b1_calendar_wiring_test.dart
//   便F8b-1＝カレンダーの箱を開く所（lib/screens/home_screen.dart の _openDaySheet）が、
//   日報漏れの申告の入口を組む関数（dayRequestEntryOrNull）へ渡す7つの値を、機械で固定する。
//
// ★なぜ要るか（2026-10-08 の「日の試し」で見つけた守りの穴）:
//   箱へ渡す「今日」を、わざと遠い先の日（'2999-12-31'）と遠い前の日（'2000-01-01'）に替えて、
//   検査の全部を走らせたら、どちらも全部緑だった。
//   ＝今ある検査は、走らせる日に寄って赤くならない（良い事）。
//     けれど同じ理由で、ここの繋ぎを壊しても（今日を決まった字にしても）、気づく検査が1つも無かった。
//   その穴を、この本でふさぐ（入口を組む関数の答えを箱へ渡す事と、自分の日報の数を ownLiveReportCount で
//   数えて渡す形は、test/f8_day_request_test.dart の (x-1)(x-2) が見ている。その日・今日・休み・同意待ち・
//   日付の字・口と、数え方の2つ目の引数は、この本だけが見る。ここは7つの全部を、並びごと見る）。
//
// ★掟: ソースの字で見る（CalendarTab は時計を差し替える口を持たない＝画面を立てて確かめると、
//   走らせる日に寄る検査になる）。説明文だけの行（空白の後が // で始まる行）は除いて見る。
//   期待の字はこの本の中に直に書く。改行と字下げの違いでは落ちない（空白を1つに畳んで比べる）。
// ★検査の名前の頭の番号（(g-1)）は、ログの赤い行からどの検査かを機械で読むための物。
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 説明文だけの行（空白の後が // で始まる行）を除いたソースの字。
String _codeOnly(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 名前で始まる呼び出しの中身（最初の「名前(」から、対になる「)」まで）。
String _callOf(String src, String name) {
  final start = src.indexOf('$name(');
  if (start < 0) return '';
  var depth = 0;
  for (var i = start + name.length; i < src.length; i++) {
    final c = src[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  return '';
}

/// 空白を1つに畳む（改行と字下げの違いで落ちないように）。
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('(g) カレンダーの箱を開く所の繋ぎ', () {
    test('(g-1) 入口を組む関数へ、その日・今日（日本の今日）・自分の日報の数・自分の休み・同意待ち・日付の字・口を渡している',
        () {
      final src = _codeOnly('lib/screens/home_screen.dart');
      // 入口を組む関数を呼ぶ所は1つだけ（二者比較：0 でも 2 でもない）。
      expect('dayRequestEntryOrNull('.allMatches(src).length, 1,
          reason: 'dayRequestEntryOrNull を呼ぶ所が1つでない');
      // 渡す7つを、並びごと見る。
      //   今日＝箱を開く時に、日本の今日（jstDateString(DateTime.now())）を読んで渡す（決まった字にしない）。
      expect(
          _flat(_callOf(src, 'dayRequestEntryOrNull')),
          'dayRequestEntryOrNull( '
          'workDate: ds, '
          'today: jstDateString(DateTime.now()), '
          'ownReportCount: ownLiveReportCount(info.liveReports, _myUserId), '
          'hasOwnRest: info.restPortion != null, '
          'substitutePendingRest: info.substitutePendingRest, '
          'dateText: info.dateText, '
          'service: ReportsService(), )',
          reason: '入口を組む関数へ渡す物（7つ）が違う');
      // 箱へ渡す日の中身（info）と、入口へ渡す値の元（info）は、押した日（ds）の同じ物。
      expect(
          _flat(src).contains('Future<void> _openDaySheet(String ds) async { '
              'final info = _dayInfoOf(ds); '
              'await showCalendarDaySheet( context, info: info, '
              'maxHeight: _sheetMaxHeight(), myCompanyId: _myCompanyId, '
              'dayRequestEntry: dayRequestEntryOrNull( workDate: ds, '),
          isTrue,
          reason: '箱を開く所が、押した日の中身（_dayInfoOf(ds)）を箱と入口の両方へ渡していない');
    });
  });
}
