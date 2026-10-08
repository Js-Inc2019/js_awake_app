// ============================================================
// test/f8b1_report_wire_test.dart
//   便F8b-1＝今日の日報の「サーバへ送る字」を機械で固定する。
//
// ★この本は、lib を直す前の実装（HEAD eec17e3）でも、直した後の実装でも、1字も変えずに緑になる。
//   ＝本文と写真を組む所を関数（reportBodyFor・reportPhotosFor）へ出しても、送る字が1バイトも
//     変わっていない事の証し（直す前の実装で緑を確かめてから、lib を直した）。
//
// ★何を守るか（届いた本文の「生の字」をそのまま比べる＝鍵の並び・値の形まで）:
//   (w-1) 日勤・値が全部在る形
//   (w-2) 夜勤・値が空の多い形（null の並び・条件つきの鍵が無い）
//   (w-3) 写真つき（作業が先・駐車場が後・読めない写真は、作業のも駐車場のも飛ばす）
//   (w-4) 届かなかった時は保留の箱に残り、送り直すと同じ字がもう一度届く
//   (w-5) 送り先（POST・道の終わりは /reports・1件の日報で1回）
//   (w-6) 業務日（日勤の日本の午前はその日・夜勤の日本の午前は前の日。UTC の日付とも違う時刻で見る）
//
// ★掟: 期待の字はこの本の中に直に書く（実装の定数は import しない）。時計を読まない
//   （日報の入れ物には id と timestamp を必ず渡す。timestamp は UTC で作る＝どの端末で走らせても同じ字）。
//   ※打刻の時刻（clock_in_time）は、実物では端末の土地の時刻で刻まれる。この本は UTC の時刻を渡すので、
//     「土地の時刻で刻む」事そのものは固定していない（どの端末で走らせても同じ字にするための割り切り）。
//   通信は package:http の runWithClient＋MockClient で偽物にする（実 HTTP へ行かせない）。
//   端末の保存は SharedPreferences の偽物。作った一時のファイルは、その検査が終わりに消す。
// ★検査の名前の頭の番号（(w-1) ほか）は、ログの赤い行からどの検査かを機械で読むための物。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/main.dart'
    show ReportStore, TransportType, WorkerReportItem;

// ── 日報の入れ物（検査が字で決める・時計を読まない）──────────────────────

/// 日勤・値が全部在る形。2026-09-20 09:05 UTC（日本の時刻で 18:05）。
WorkerReportItem _fullItem({
  List<String>? workPhotoPaths,
  List<String>? parkingPhotoPaths,
}) =>
    WorkerReportItem(
      id: 'w1',
      name: '検査 太郎',
      transport: TransportType.car,
      transportTypes: ['car'],
      parkingFee: '500',
      workContent: '【移動】バイクで駅まで 1階の配線',
      gpsAddress: 'テスト県テスト市1-2-3',
      gpsLat: 34.5,
      gpsLon: 135.25,
      originType: 'office',
      siteId: 'site-1',
      shiftType: 'day',
      transportDistanceKm: 12.4,
      transportFuelCost: 141,
      transportToll: 300,
      transportBreakdown: [
        {'mode': 'car', 'distance_km': 12.4, 'fuel_cost': 141, 'toll': 300},
      ],
      workPhotoPaths: workPhotoPaths,
      parkingPhotoPaths: parkingPhotoPaths,
      timestamp: DateTime.utc(2026, 9, 20, 9, 5),
    );

/// 夜勤・値が空の多い形。2026-09-20 16:30 UTC（日本の時刻で 9月21日 01:30＝夜勤の午前なので、業務日は前の日の 9月20日。
///   ただし、この時刻は UTC の日付も 9月20日。業務日の決まりそのものは (w-6) が、3つの日付が互いに違う時刻で見る）。
WorkerReportItem _sparseItem() => WorkerReportItem(
      id: 'w2',
      name: '検査 太郎',
      transport: TransportType.train,
      transportTypes: ['train', 'bus'],
      shiftType: 'night',
      carpoolCompany: '相乗り商事',
      carpoolName: '相乗 次郎',
      timestamp: DateTime.utc(2026, 9, 20, 16, 30),
    );

// ── 期待の字（届く本文の生の字・1行）────────────────────────────────

const String _kFullHead = '{"worker_name":"検査 太郎","worker_company":"",'
    '"report_date":"2026-09-20","shift_type":"day","clock_in_time":"09:05:00",'
    '"transport_type":"car","transport_types_json":["car"],"parking_fee":500.0,'
    '"gps_address":"テスト県テスト市1-2-3","origin_type":"office",'
    '"work_content":"【移動】バイクで駅まで 1階の配線",'
    '"transport_distance_km":12.4,"transport_fuel_cost":141,"transport_fare":null,'
    '"transport_toll":300,'
    '"transport_breakdown":[{"mode":"car","distance_km":12.4,"fuel_cost":141,"toll":300}],'
    '"carpool_company":null,"carpool_name":null,'
    '"site_id":"site-1","gps_lat":34.5,"gps_lon":135.25';

/// (w-1) 写真なし＝上の字を閉じただけ。
const String _kFullBody = '$_kFullHead}';

const String _kSparseBody = '{"worker_name":"検査 太郎","worker_company":"",'
    '"report_date":"2026-09-20","shift_type":"night","clock_in_time":"16:30:00",'
    '"transport_type":"train","transport_types_json":["train","bus"],"parking_fee":null,'
    '"gps_address":"","origin_type":"home","work_content":"",'
    '"transport_distance_km":null,"transport_fuel_cost":null,"transport_fare":null,'
    '"transport_toll":null,"transport_breakdown":null,'
    '"carpool_company":"相乗り商事","carpool_name":"相乗 次郎"}';

// ── 偽物の通信 ────────────────────────────────────────────────

/// 届いた求めを順に控え、statuses の順に答える（足りなくなったら最後の値を使い続ける）。
Future<T> _withServer<T>(
  List<http.Request> seen,
  List<int> statuses,
  Future<T> Function() run,
) {
  var n = 0;
  return http.runWithClient(
    run,
    () => MockClient((req) async {
      seen.add(req);
      final status = statuses[n < statuses.length ? n : statuses.length - 1];
      n++;
      final body = status == 201
          ? jsonEncode({'report_id': 'r-$n'})
          : jsonEncode({'error': 'サーバーエラー'});
      return http.Response(body, status,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'T'}));

  group('(w) 今日の日報の、サーバへ送る字', () {
    test('(w-1) 日勤・値が全部在る形の本文は、鍵の並びも値の形も決まった字のまま', () async {
      final seen = <http.Request>[];
      final ok = await _withServer(seen, [201],
          () => ReportStore.instance.addReport(_fullItem()));
      expect(ok, isTrue);
      expect(seen.length, 1);
      expect(seen.single.body, _kFullBody);
    });

    test('(w-2) 夜勤・値が空の多い形の本文は、null の並びも、条件つきの鍵が無い事も、決まった字のまま',
        () async {
      final seen = <http.Request>[];
      final ok = await _withServer(seen, [201],
          () => ReportStore.instance.addReport(_sparseItem()));
      expect(ok, isTrue);
      expect(seen.length, 1);
      // 生の字の全文を比べる＝条件つきの鍵（現場・座標・写真）が無い事も、この1行で見ている
      //   （値が在る形の (w-1) の期待の字には、現場と座標の3つが在る＝2つの期待の字の違いが二者比較）。
      expect(seen.single.body, _kSparseBody);
    });

    test('(w-3) 写真は、作業が先・駐車場が後。読めない写真は、作業のも駐車場のも飛ばす（ほかの鍵と値は同じ）', () async {
      final dir = Directory.systemTemp.createTempSync('f8b1_wire_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final work = File('${dir.path}/work.jpg')..writeAsBytesSync([1, 2, 3]);
      final parking = File('${dir.path}/parking.jpg')
        ..writeAsBytesSync([9, 8, 7, 6]);
      final missing = '${dir.path}/none.jpg';

      final seen = <http.Request>[];
      final ok = await _withServer(
          seen,
          [201],
          () => ReportStore.instance.addReport(_fullItem(
                workPhotoPaths: [work.path, missing],
                parkingPhotoPaths: [missing, parking.path],
              )));
      expect(ok, isTrue, reason: '読めない写真が在るだけで、送れなくなった');
      expect(seen.length, 1);
      // 置いたファイルの中身（1,2,3 と 9,8,7,6）の base64 を、字で直に書く。
      expect(
          seen.single.body,
          '$_kFullHead,"photos":['
          '{"photo_type":"site","base64":"AQID"},'
          '{"photo_type":"parking","base64":"CQgHBg=="}]}');
    });

    test('(w-4) 届かなかった時は保留の箱に1件残り、送り直すと同じ字がもう一度届いて箱が空になる', () async {
      final seen = <http.Request>[];
      await _withServer(seen, [500, 201], () async {
        final ok = await ReportStore.instance.addReport(_fullItem());
        expect(ok, isFalse, reason: '500 なのに送れた事になっている');
        expect(await ReportStore.instance.pendingCount(), 1);
        await ReportStore.instance.retryPending();
        expect(await ReportStore.instance.pendingCount(), 0);
      });
      expect(seen.length, 2);
      expect(seen[0].body, _kFullBody);
      expect(seen[1].body, _kFullBody, reason: '送り直しの本文が1回目と違う');
    });

    test('(w-5) 送り先は POST で、道の終わりは /reports。1件の日報で届くのは1回', () async {
      final seen = <http.Request>[];
      await _withServer(seen, [201],
          () => ReportStore.instance.addReport(_sparseItem()));
      expect(seen.length, 1);
      expect(seen.single.method, 'POST');
      expect(seen.single.url.path.endsWith('/reports'), isTrue,
          reason: seen.single.url.path);
      expect(seen.single.headers['Content-Type'], 'application/json');
    });

    test('(w-6) 業務日：日勤の日本の午前はその日・夜勤の日本の午前は前の日（UTC の日付とも違う時刻で見る）',
        () async {
      final seen = <http.Request>[];
      await _withServer(seen, [201], () async {
        // 2026-09-20 16:30 UTC＝日本の 9月21日 01:30。日勤＝その日（21日）。UTC の日付（20日）とは違う。
        await ReportStore.instance.addReport(WorkerReportItem(
          id: 'w6a',
          name: '検査 太郎',
          transport: TransportType.train,
          shiftType: 'day',
          timestamp: DateTime.utc(2026, 9, 20, 16, 30),
        ));
        // 2026-09-21 01:30 UTC＝日本の 9月21日 10:30。夜勤の午前＝前の日（20日）。UTC の日付（21日）とは違う。
        await ReportStore.instance.addReport(WorkerReportItem(
          id: 'w6b',
          name: '検査 太郎',
          transport: TransportType.train,
          shiftType: 'night',
          timestamp: DateTime.utc(2026, 9, 21, 1, 30),
        ));
        // 2026-09-21 03:00 UTC＝日本の 9月21日 12:00。夜勤でも、昼からはその日（21日）。
        await ReportStore.instance.addReport(WorkerReportItem(
          id: 'w6c',
          name: '検査 太郎',
          transport: TransportType.train,
          shiftType: 'night',
          timestamp: DateTime.utc(2026, 9, 21, 3, 0),
        ));
      });
      expect(seen.length, 3);
      expect(
          seen[0].body.contains('"report_date":"2026-09-21","shift_type":"day",'
              '"clock_in_time":"16:30:00"'),
          isTrue,
          reason: seen[0].body);
      expect(
          seen[1].body.contains('"report_date":"2026-09-20","shift_type":"night",'
              '"clock_in_time":"01:30:00"'),
          isTrue,
          reason: seen[1].body);
      expect(
          seen[2].body.contains('"report_date":"2026-09-21","shift_type":"night",'
              '"clock_in_time":"03:00:00"'),
          isTrue,
          reason: seen[2].body);
    });
  });
}
