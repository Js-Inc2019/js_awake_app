// ============================================================
// test/f8b1_report_form_test.dart
//   便F8b-1＝今日の日報のフォームを、見た目も動きも変えずに「動かした部品」「段の部品」「値の関数」へ
//   取り出した事を、機械で固定する（今日の日報のフォームを立てる検査は、この便まで1本も無かった）。
//
// ★何を守るか（すべて二者比較。「出ない」だけで合格にしない）:
//   (a) 動かした部品（lib/widgets/report_form_parts.dart）の字・大きさ・色・押した時・選んである印
//   (b) 段の部品（lib/widgets/report_form_steps.dart）の並び・空き・条件つきの4つ・押し口と写真の帯の繋ぎ
//   (c) 確認の画面（行の名と形・相乗りの行・送る・差の見張り・二度押し・戻る・鍵）
//   (d) 値の関数（移動手段の選び・作業内容の頭の字・駐車料金・相乗り・確認の画面の材料・目安と経費）
//   (e) 送る本文と写真の関数（lib/main.dart）
//   (f) ソースの字（シェルが、今の欄と今の関数を、部品と関数へ正しく繋いでいる・押した時の中身・段の出し分け・
//       名前だけ替えた呼び出しの中身＝現場のシート・音声の窓・休憩の短縮のシート）
//
// ★掟: 期待値（語・色・数）はこのファイル内で組み立てる。実装の定数は import しない。
//   字は一字一句・色は16進の生の値。時計を読まない（日付の字は検査が渡す）。
// ★今日の日報のシェル（ホームの画面）そのものは、端末の機能（位置・音声・通知）に寄るので立てない。
//   シェルの繋ぎは (f) のソースの字で見る（説明文だけの行を除いた字で数える）。
// ★音声の窓（ReportVoiceInputDialog）は、端末の音声の機能が要るので立てない
//   （名前を替えた事と、作り口に任意の key を足した事のほかに違いが無い事は、便F8b-1 の道具が、HEAD の字と機械で比べて確かめた。
//   シェルが窓を呼ぶ所の中身は、(f-7) がソースの字で見る）。
// ★検査の名前の頭の番号（(a-1) ほか）は、ログの赤い行からどの検査かを機械で読むための物。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:js_awake_app/core/theme/app_theme.dart';
import 'package:js_awake_app/main.dart'
    show TransportType, WorkerReportItem, reportBodyFor, reportPhotosFor;
import 'package:js_awake_app/services/routes_service.dart'
    show CarRoute, SimpleRoute, TransitRoute;
import 'package:js_awake_app/widgets/photo_strip_field.dart'
    show PhotoStripField;
import 'package:js_awake_app/widgets/report_form_parts.dart';
import 'package:js_awake_app/widgets/report_form_steps.dart';
import 'package:js_awake_app/widgets/search_suggest_field.dart'
    show SearchSuggestField;

// ── 色（lib/core/theme/field_tokens.dart の値を16進の生の値で写した）──────
const int _kBrand = 0xFFD9C08A;
const int _kTextBody = 0xFFEAE3D0;
const int _kTextSupport = 0xFF7B7567;
const int _kTextFaint = 0xFF635F55;

// ── 画面の字（今日の日報のフォームに在る字を、一字一句写した）────────────
const String _kTransportNote = '※タップで選択　／　2つ以上使うときはダブルタップで追加';
const String _kMemoHint = '移動手段の補足（任意）例：バイクで駅まで → 電車 → 徒歩';
const String _kOwn = '社用車・自家用車';
const String _kCarpool = '相乗り';
const String _kCompanyHint = '相乗り相手の会社名（任意）';
const String _kNameHint = '相乗り相手の氏名（任意）';
const String _kCompanyNote = '※自社なら空欄のままでOK';
const String _kFeeHint = '駐車料金（円）';
const String _kParkingPhoto = '駐車場写真（看板・領収書）';
const String _kRouteLoading = 'ルート計算中...';
const String _kRouteFailed = '移動情報を取得できません（タップで再取得）';
const String _kRouteNoData = 'この手段の目安は取得できません';
const String _kRouteCached = '前回の目安';
const String _kWorkHint = '1階の配線、コンセント10箇所　など';
const String _kWorkNote = '※未記入のままでも報告できます';
const String _kPhotoNote = '※なくても報告できます';
const String _kCheck = '内容を確認する';
const String _kCheckNote = '※次の画面で見直してから送信します';
const String _kConfirmHead = 'この内容で送ります';
const String _kSend = '報告を送信';
const String _kBackToFix = '戻って直す';
const String _kChanged = '内容が変わりました。もう一度ご確認ください';
const String _kNoSite = '該当現場なし';

// ── 目安の入れ物（検査が値を決める）────────────────────────────────
CarRoute _car() => CarRoute(
      time: 28,
      distanceM: 12400,
      distanceText: '12.4km',
      tollNormal: 300,
      tollLight: 250,
      gasCost: 141,
      totalNormal: 441,
      totalLight: 391,
    );

TransitRoute _transit() => TransitRoute(
      time: 35,
      fareIc: 620,
      depStation: '神戸',
      arrStation: '三宮',
      routes: const [],
    );

// ── 立てる土台 ────────────────────────────────────────────────

/// 本物のテーマの下で、今日の日報のフォームと同じ器（横いっぱいの縦の並び・スクロール）に置く。
Future<void> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(400, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [child],
        ),
      ),
    ),
  ));
  await tester.pump();
}

TextStyle _style(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;
int? _colorOf(WidgetTester tester, String text) =>
    _style(tester, text).color?.toARGB32();
double _top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;
double _left(WidgetTester tester, Finder f) => tester.getTopLeft(f).dx;

Finder _fieldByHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

/// 段2（移動）を、押した時の記録つきで組む。持ち物（入力欄の中身）も外から見られる。
class _MoveRig {
  final log = <String>[];
  final memo = TextEditingController();
  final company = TextEditingController();
  final name = TextEditingController();
  final fee = TextEditingController();
  int companyCandidateCalls = 0;
  int nameCandidateCalls = 0;

  ReportStepMove build({
    Set<TransportType> transports = const {},
    String carType = 'own',
    String originType = 'home',
    TransportType? routeTransport,
    Map<String, dynamic> routeComparisons = const {},
    bool loadingRoutes = false,
    bool routeFailed = false,
    bool routeFromCache = false,
    List<String> companyCandidates = const [],
    List<String> nameCandidates = const [],
    List<String> parkingPhotoPaths = const [],
  }) =>
      ReportStepMove(
        originType: originType,
        onOriginChanged: (v) => log.add('origin:$v'),
        transports: transports,
        onTransportTap: (t) => log.add('tap:${t.name}'),
        onTransportDoubleTap: (t) => log.add('double:${t.name}'),
        transportMemoController: memo,
        carType: carType,
        onCarTypeOwn: () => log.add('own'),
        onCarTypeCarpool: () => log.add('carpool'),
        routeTransport: routeTransport ??
            (transports.isEmpty ? TransportType.none : transports.first),
        routeComparisons: routeComparisons,
        loadingRoutes: loadingRoutes,
        routeFailed: routeFailed,
        routeFromCache: routeFromCache,
        onRouteRetry: () async => log.add('retry'),
        carpoolCompanyController: company,
        carpoolCompanyCandidatesOf: () {
          companyCandidateCalls++;
          return companyCandidates;
        },
        onCarpoolCompanyChanged: (v) => log.add('company:$v'),
        carpoolNameController: name,
        carpoolNameCandidatesOf: () {
          nameCandidateCalls++;
          return nameCandidates;
        },
        onCarpoolNameChanged: (v) => log.add('name:$v'),
        parkingFeeController: fee,
        onParkingFeeChanged: (v) => log.add('fee:$v'),
        parkingPhotoPaths: parkingPhotoPaths,
        onParkingPhotosChanged: (v) => log.add('photos:${v.join('|')}'),
      );
}

/// 確認の画面の材料（検査が値を決める）。
ReportSnapshot _snap({
  String? siteId = 's1',
  String siteName = '○○ビル 新築工事',
  String transportKey = 'car',
  String workContent = '1階の配線',
  String parkingFeeRaw = '500',
  String carpoolCompany = '',
  String carpoolName = '',
  String dateLabel = '9月20日（日）',
  String shiftLabel = '☀日勤',
  String originLabel = '自宅',
  String transportLabel = '車',
  int workPhotoCount = 0,
  int parkingPhotoCount = 1,
  List<({String label, String? dist, String? cost})> routeRows = const [
    (label: '車', dist: '12.4km', cost: '⛽¥141'),
  ],
}) =>
    ReportSnapshot(
      dateLabel: dateLabel,
      shiftLabel: shiftLabel,
      siteId: siteId,
      siteName: siteName,
      originLabel: originLabel,
      transportKey: transportKey,
      transportLabel: transportLabel,
      routeRows: routeRows,
      parkingFeeRaw: parkingFeeRaw,
      carpoolCompany: carpoolCompany,
      carpoolName: carpoolName,
      workContent: workContent,
      workPhotoCount: workPhotoCount,
      parkingPhotoCount: parkingPhotoCount,
    );

/// 確認の画面を、前の画面の上に積んで立てる（閉じたかどうかを見るため）。
Future<void> _pumpConfirm(
  WidgetTester tester, {
  required ReportSnapshot initial,
  required ReportSnapshot Function() currentOf,
  required Future<void> Function() onSend,
  required bool Function() isDone,
}) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ReportConfirmScreen(
                  initial: initial,
                  currentOf: currentOf,
                  onSend: onSend,
                  isDone: isDone,
                ),
              ),
            ),
            child: const Text('確認を開く'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('確認を開く'));
  await tester.pumpAndSettle();
}

/// 説明文だけの行（空白の後が // で始まる行）を除いたソースの字。
String _codeOnly(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// シェルの本の中の、名前で始まる呼び出しの中身（最初の「名前(」から、対になる「)」まで）。
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
  // ══════════════════════════════════════════════════════════
  // (a) 動かした部品
  // ══════════════════════════════════════════════════════════
  group('(a) 動かした部品', () {
    testWidgets('(a-1) ReportSectionHeader と ReportFieldLabel：渡した字が出る・色と大きさが今の値',
        (tester) async {
      await _pump(
          tester,
          const Column(children: [
            ReportSectionHeader('見出しの字'),
            ReportFieldLabel('小ラベルの字'),
          ]));
      final head = _style(tester, '見出しの字');
      expect(head.color!.toARGB32(), _kTextSupport);
      expect(head.fontSize, 13);
      expect(head.fontWeight, FontWeight.bold);
      final label = _style(tester, '小ラベルの字');
      expect(label.color!.toARGB32(), _kTextSupport);
      expect(label.fontSize, 12);
      expect(label.fontWeight, isNot(FontWeight.bold));
    });

    testWidgets('(a-2) ReportFormInputShell：高さ 46・渡した印と中身が出る', (tester) async {
      await _pump(
          tester,
          const ReportFormInputShell(
              icon: Icons.local_parking, child: Text('欄の中身')));
      expect(tester.getSize(find.byType(ReportFormInputShell)).height, 46);
      expect(find.byIcon(Icons.local_parking), findsOneWidget);
      expect(find.text('欄の中身'), findsOneWidget);
    });

    testWidgets('(a-3) ReportOutlineActionButton：高さ 56・押すと1回呼ぶ／busy の間はくるくるで、押しても呼ばない',
        (tester) async {
      var taps = 0;
      await _pump(
          tester,
          ReportOutlineActionButton(
              label: '押すボタン', onTap: () async => taps++));
      expect(tester.getSize(find.byType(ReportOutlineActionButton)).height, 56);
      expect(find.text('押すボタン'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byType(ReportOutlineActionButton));
      await tester.pump();
      expect(taps, 1);

      await _pump(
          tester,
          ReportOutlineActionButton(
              label: '押すボタン', busy: true, onTap: () async => taps++));
      expect(find.text('押すボタン'), findsNothing, reason: 'busy の間は字が出ない');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(ReportOutlineActionButton));
      await tester.pump();
      expect(taps, 1, reason: 'busy の間に押して呼ばれた');
    });

    testWidgets('(a-4) ReportStepIndicator：1〜4 と 現場／移動／作業／確認・今の段だけ色と太さが違う',
        (tester) async {
      for (final current in [1, 3]) {
        await _pump(tester, ReportStepIndicator(current: current));
        const labels = ['現場', '移動', '作業', '確認'];
        for (var n = 1; n <= 4; n++) {
          final isCurrent = n == current;
          for (final text in ['$n', labels[n - 1]]) {
            final st = _style(tester, text);
            expect(st.color!.toARGB32(), isCurrent ? _kBrand : _kTextSupport,
                reason: '今の段=$current の「$text」の色');
            expect(st.fontWeight,
                isCurrent ? FontWeight.bold : FontWeight.normal,
                reason: '今の段=$current の「$text」の太さ');
          }
        }
        // 並び（左から 1・2・3・4）。
        expect(_left(tester, find.text('1')) < _left(tester, find.text('2')),
            isTrue);
        expect(_left(tester, find.text('3')) < _left(tester, find.text('4')),
            isTrue);
      }
    });

    testWidgets('(a-5) ReportStepBackButton：「戻る」・高さ 56・押すと1回呼ぶ', (tester) async {
      var taps = 0;
      await _pump(tester, ReportStepBackButton(onTap: () => taps++));
      expect(find.text('戻る'), findsOneWidget);
      expect(tester.getSize(find.byType(ReportStepBackButton)).height, 56);
      await tester.tap(find.text('戻る'));
      expect(taps, 1);
    });

    testWidgets('(a-6) ReportSiteSelectField：名前が null なら「該当現場なし」・在ればその字／「変更」／押すと1回呼ぶ',
        (tester) async {
      var taps = 0;
      await _pump(
          tester, ReportSiteSelectField(siteName: null, onTap: () => taps++));
      expect(find.text(_kNoSite), findsOneWidget);
      expect(_colorOf(tester, _kNoSite), _kTextSupport);
      expect(find.text('変更'), findsOneWidget);
      await tester.tap(find.text(_kNoSite));
      expect(taps, 1);

      await _pump(tester,
          ReportSiteSelectField(siteName: '○○ビル 新築工事', onTap: () => taps++));
      expect(find.text(_kNoSite), findsNothing);
      expect(find.text('○○ビル 新築工事'), findsOneWidget);
      expect(_colorOf(tester, '○○ビル 新築工事'), _kTextBody);
      expect(find.text('変更'), findsOneWidget);
    });

    group('(a-7) ReportSitePickerSheet（通信は偽物）', () {
      setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'T'}));

      /// シートを開いて、選んだ結果（id・名前）を picked に足す。
      Future<void> open(WidgetTester tester, List<List<String?>> picked,
          {String? selectedSiteId}) async {
        tester.view.physicalSize = const Size(400, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ReportSitePickerSheet(
                      selectedSiteId: selectedSiteId,
                      onSelected: (id, name) => picked.add([id, name]),
                    ),
                  ),
                  child: const Text('シートを開く'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('シートを開く'));
        await tester.pumpAndSettle();
      }

      http.Client sitesClient(int status, Object body, List<String> paths) =>
          MockClient((req) async {
            paths.add('${req.method} ${req.url.path}');
            return http.Response(jsonEncode(body), status,
                request: req,
                headers: {'content-type': 'application/json; charset=utf-8'});
          });

      const sites = {
        'sites': [
          {'site_id': 'a1', 'site_name': '○○ビル 新築工事', 'address': '神戸市1-1'},
          {'site_id': 'b2', 'site_name': '△△マンション 改修', 'address': ''},
        ],
      };

      testWidgets('(a-7) 読めた時：「該当現場なし」が先頭・現場の名前と住所／現場を押すと id と名前が渡って閉じる・選んである印は、選んである行にだけ（何も選んでいない時は「該当現場なし」の行）',
          (tester) async {
        final picked = <List<String?>>[];
        final paths = <String>[];
        await http.runWithClient(() async {
          await open(tester, picked);
          expect(find.text('作業現場を選択'), findsOneWidget);
          expect(paths.length, 1);
          expect(paths.single.startsWith('GET '), isTrue);
          expect(paths.single.endsWith('/sites'), isTrue, reason: paths.single);
          expect(find.text(_kNoSite), findsOneWidget);
          expect(find.text('該当現場がない・現場未登録'), findsOneWidget);
          expect(find.text('○○ビル 新築工事'), findsOneWidget);
          expect(find.text('神戸市1-1'), findsOneWidget);
          expect(find.text('△△マンション 改修'), findsOneWidget);
          expect(
              _top(tester, find.text(_kNoSite)) <
                  _top(tester, find.text('○○ビル 新築工事')),
              isTrue,
              reason: '「該当現場なし」が先頭でない');
          expect(
              _top(tester, find.text('○○ビル 新築工事')) <
                  _top(tester, find.text('△△マンション 改修')),
              isTrue);
          // 選んである印（✓）は、選んである行にだけ付く（何も選んでいない時＝「該当現場なし」の行）。
          expect(
              find.descendant(
                  of: find.widgetWithText(ListTile, _kNoSite),
                  matching: find.byIcon(Icons.check)),
              findsOneWidget,
              reason: '何も選んでいないのに、「該当現場なし」の行に印が無い');
          expect(
              find.descendant(
                  of: find.widgetWithText(ListTile, '○○ビル 新築工事'),
                  matching: find.byIcon(Icons.check)),
              findsNothing,
              reason: '選んでいない現場の行に印が在る');
          await tester.tap(find.text('△△マンション 改修'));
          await tester.pumpAndSettle();
        }, () => sitesClient(200, sites, paths));
        expect(picked, [
          ['b2', '△△マンション 改修']
        ]);
        expect(find.text('作業現場を選択'), findsNothing, reason: '選んだのにシートが閉じていない');
      });

      testWidgets('(a-7) 「該当現場なし」を押すと、id も名前も null が渡って閉じる・現場を選んである時は、その行にだけ印', (tester) async {
        final picked = <List<String?>>[];
        await http.runWithClient(() async {
          await open(tester, picked, selectedSiteId: 'a1');
          // 選んである現場（a1）の行にだけ、印（✓）が付く。
          expect(
              find.descendant(
                  of: find.widgetWithText(ListTile, '○○ビル 新築工事'),
                  matching: find.byIcon(Icons.check)),
              findsOneWidget,
              reason: '選んである現場の行に印が無い');
          expect(
              find.descendant(
                  of: find.widgetWithText(ListTile, _kNoSite),
                  matching: find.byIcon(Icons.check)),
              findsNothing,
              reason: '現場を選んであるのに、「該当現場なし」の行に印が在る');
          await tester.tap(find.text(_kNoSite));
          await tester.pumpAndSettle();
        }, () => sitesClient(200, sites, []));
        expect(picked, [
          [null, null]
        ]);
        expect(find.text('作業現場を選択'), findsNothing);
      });

      testWidgets('(a-7) 検索の欄で名前を絞れる・当たりが無い時は「該当する現場がありません」（「該当現場なし」は残る）',
          (tester) async {
        final picked = <List<String?>>[];
        await http.runWithClient(() async {
          await open(tester, picked);
          await tester.enterText(_fieldByHint('現場名で検索'), 'マンション');
          await tester.pumpAndSettle();
          expect(find.text('○○ビル 新築工事'), findsNothing);
          expect(find.widgetWithText(ListTile, '△△マンション 改修'), findsOneWidget);
          expect(find.text(_kNoSite), findsOneWidget);

          await tester.enterText(_fieldByHint('現場名で検索'), 'どこにも無い字');
          await tester.pumpAndSettle();
          expect(find.text('該当する現場がありません'), findsOneWidget);
          expect(find.text(_kNoSite), findsOneWidget, reason: '当たりが無い時に「該当現場なし」が消えた');
          expect(find.widgetWithText(ListTile, '△△マンション 改修'), findsNothing);
        }, () => sitesClient(200, sites, []));
        expect(picked, isEmpty);
      });

      testWidgets('(a-7) 読めなかった時：サーバの文と「再試行」が出て、「該当現場なし」は選べる', (tester) async {
        final picked = <List<String?>>[];
        final paths = <String>[];
        await http.runWithClient(() async {
          await open(tester, picked);
          expect(find.text('現場を読めませんでした'), findsOneWidget);
          expect(find.text('再試行'), findsOneWidget);
          expect(find.text('○○ビル 新築工事'), findsNothing);
          expect(paths.length, 1);
          await tester.tap(find.text('再試行'));
          await tester.pumpAndSettle();
          expect(paths.length, 2, reason: '「再試行」で読み直していない');
          await tester.tap(find.text(_kNoSite));
          await tester.pumpAndSettle();
        }, () => sitesClient(500, {'error': '現場を読めませんでした'}, paths));
        expect(picked, [
          [null, null]
        ]);
      });
    });

    testWidgets('(a-8) ReportOriginSelector：「自宅」「会社」／押すと home・office が渡る／選んだ方だけ太字',
        (tester) async {
      final got = <String>[];
      await _pump(
          tester, ReportOriginSelector(selected: 'home', onChanged: got.add));
      expect(_left(tester, find.text('自宅')) < _left(tester, find.text('会社')),
          isTrue);
      expect(_style(tester, '自宅').fontWeight, FontWeight.bold);
      expect(_style(tester, '会社').fontWeight, FontWeight.normal);
      expect(_colorOf(tester, '自宅'), _kTextBody);
      expect(_colorOf(tester, '会社'), _kTextSupport);
      await tester.tap(find.text('会社'));
      await tester.tap(find.text('自宅'));
      expect(got, ['office', 'home']);

      await _pump(tester,
          ReportOriginSelector(selected: 'office', onChanged: got.add));
      expect(_style(tester, '自宅').fontWeight, FontWeight.normal);
      expect(_style(tester, '会社').fontWeight, FontWeight.bold);
    });

    testWidgets('(a-9) ReportTransportRow：車・電車・バス・その他 の並び／1回押すと onTap・2度押すと onDoubleTap／高さ 58',
        (tester) async {
      final log = <String>[];
      await _pump(
          tester,
          ReportTransportRow(
            selectedSet: const {TransportType.train},
            onTap: (t) => log.add('tap:${t.name}'),
            onDoubleTap: (t) => log.add('double:${t.name}'),
          ));
      expect(tester.getSize(find.byType(ReportTransportRow)).height, 58);
      final xs = ['車', '電車', 'バス', 'その他']
          .map((t) => _left(tester, find.text(t)))
          .toList();
      expect(xs[0] < xs[1] && xs[1] < xs[2] && xs[2] < xs[3], isTrue,
          reason: '並びが 車・電車・バス・その他 でない $xs');
      expect(_style(tester, '電車').fontWeight, FontWeight.bold);
      expect(_style(tester, '車').fontWeight, FontWeight.normal);

      // 1回押す（2度押しを待つ間が明けてから呼ばれる）。
      await tester.tap(find.text('バス'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, ['tap:bus']);
      // 2度押す。
      await tester.tap(find.text('その他'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('その他'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, ['tap:bus', 'double:other']);
    });

    testWidgets('(a-10) ReportWorkContentSection：字・例の字・※／マイクのボタンは出す時だけ・聞いている間は印が替わる・押すと呼ぶ',
        (tester) async {
      var mic = 0;
      final ctrl = TextEditingController();
      await _pump(
          tester,
          ReportWorkContentSection(
              controller: ctrl,
              showMediaButtons: true,
              isListening: false,
              onMicTap: () => mic++));
      expect(find.text('作業内容'), findsOneWidget);
      expect(_fieldByHint(_kWorkHint), findsOneWidget);
      expect(find.text(_kWorkNote), findsOneWidget);
      expect(_colorOf(tester, _kWorkNote), _kTextFaint);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);
      await tester.tap(find.byIcon(Icons.mic_none));
      expect(mic, 1);

      await _pump(
          tester,
          ReportWorkContentSection(
              controller: ctrl,
              showMediaButtons: true,
              isListening: true,
              onMicTap: () => mic++));
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsNothing);

      await _pump(tester, ReportWorkContentSection(controller: ctrl));
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(find.byIcon(Icons.mic_none), findsNothing);
      expect(find.text('作業内容'), findsOneWidget);
    });

    testWidgets('(a-11) ReportRouteInfoBar：計算中／失敗（押すと取り直す）／この手段の値なし／値あり／前回の値',
        (tester) async {
      var retry = 0;
      ReportRouteInfoBar bar({
        bool loading = false,
        bool failed = false,
        bool fromCache = false,
        TransportType transport = TransportType.car,
        Map<String, dynamic> comparisons = const {},
      }) =>
          ReportRouteInfoBar(
            transport: transport,
            comparisons: comparisons,
            loading: loading,
            failed: failed,
            fromCache: fromCache,
            onRetry: () async => retry++,
          );

      await _pump(tester, bar(loading: true, comparisons: {'car': _car()}));
      expect(find.text(_kRouteLoading), findsOneWidget);
      expect(find.text('12.4km'), findsNothing);

      await _pump(tester, bar(failed: true));
      expect(find.text(_kRouteFailed), findsOneWidget);
      await tester.tap(find.text(_kRouteFailed));
      expect(retry, 1);

      await _pump(tester, bar());
      expect(find.text(_kRouteNoData), findsOneWidget);
      expect(_colorOf(tester, _kRouteNoData), _kTextFaint);

      await _pump(tester, bar(comparisons: {'car': _car()}));
      expect(find.text('12.4km'), findsOneWidget);
      expect(find.text('28分'), findsOneWidget);
      expect(find.text('⛽¥141'), findsOneWidget);
      expect(find.text(_kRouteCached), findsNothing);
      expect(find.text(_kRouteNoData), findsNothing);

      await _pump(tester, bar(comparisons: {'car': _car()}, fromCache: true));
      expect(find.text(_kRouteCached), findsOneWidget);
      expect(find.text('12.4km'), findsOneWidget);

      // 電車の値（運賃と、駅から駅）。車の値しか無い時に電車を渡すと「値なし」。
      await _pump(
          tester,
          bar(
              transport: TransportType.train,
              comparisons: {'transit': _transit()}));
      expect(find.text('35分'), findsOneWidget);
      expect(find.text('💴¥620'), findsOneWidget);
      expect(find.text('神戸→三宮'), findsOneWidget);
      await _pump(tester,
          bar(transport: TransportType.train, comparisons: {'car': _car()}));
      expect(find.text(_kRouteNoData), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (b) 段の部品
  // ══════════════════════════════════════════════════════════
  group('(b) 段の部品', () {
    testWidgets('(b-1) ReportStepSite：見出し「現場」が現場の欄より上／欄を押すと onTap', (tester) async {
      var taps = 0;
      await _pump(
          tester, ReportStepSite(siteName: null, onTap: () => taps++));
      expect(find.text('現場'), findsOneWidget);
      expect(
          _top(tester, find.text('現場')) < _top(tester, find.text(_kNoSite)),
          isTrue);
      await tester.tap(find.text(_kNoSite));
      expect(taps, 1);

      await _pump(tester,
          ReportStepSite(siteName: '○○ビル 新築工事', onTap: () => taps++));
      expect(find.text('○○ビル 新築工事'), findsOneWidget);
      expect(find.text(_kNoSite), findsNothing);
    });

    testWidgets('(b-2) ReportStepMove・何も選んでいない時：上からの並びと、条件つきの4つが出ない事', (tester) async {
      final rig = _MoveRig();
      await _pump(tester, rig.build());
      final order = [
        find.text('移動'),
        find.text('出発地'),
        find.text('自宅'),
        find.text('移動手段'),
        find.text('車'),
        find.text(_kTransportNote),
        find.text(_kRouteNoData),
      ].map((f) => _top(tester, f)).toList();
      for (var i = 1; i < order.length; i++) {
        expect(order[i - 1] < order[i], isTrue, reason: '上からの並びが違う（$i 番目） $order');
      }
      // 同じ行の物は、横の並びで見る。
      expect(_left(tester, find.text('自宅')) < _left(tester, find.text('会社')),
          isTrue);
      final xs = ['車', '電車', 'バス', 'その他']
          .map((t) => _left(tester, find.text(t)))
          .toList();
      expect(xs[0] < xs[1] && xs[1] < xs[2] && xs[2] < xs[3], isTrue);
      expect(_colorOf(tester, _kTransportNote), _kTextFaint);
      expect(_style(tester, _kTransportNote).fontSize, 11);
      // 条件つきの4つ。
      expect(_fieldByHint(_kMemoHint), findsNothing);
      expect(find.text(_kOwn), findsNothing);
      expect(find.text(_kCarpool), findsNothing);
      expect(find.byType(SearchSuggestField), findsNothing);
      expect(_fieldByHint(_kFeeHint), findsNothing);
      expect(find.byType(PhotoStripField), findsNothing);
    });

    testWidgets('(b-3) 補足の欄：車だけ → 出ない／「その他」だけ → 出る／車と電車 → 出る・印と、入れた字の行き先',
        (tester) async {
      final rig = _MoveRig();
      await _pump(tester, rig.build(transports: {TransportType.car}));
      expect(_fieldByHint(_kMemoHint), findsNothing);

      await _pump(tester, rig.build(transports: {TransportType.other}));
      expect(_fieldByHint(_kMemoHint), findsOneWidget);
      expect(find.byIcon(Icons.edit_note), findsOneWidget);

      await _pump(tester,
          rig.build(transports: {TransportType.car, TransportType.train}));
      expect(_fieldByHint(_kMemoHint), findsOneWidget);
      await tester.enterText(_fieldByHint(_kMemoHint), 'バイクで駅まで');
      expect(rig.memo.text, 'バイクで駅まで');
      expect(rig.fee.text, '', reason: '補足の字が、駐車料金の持ち物に入った');
      expect(rig.company.text, '');
      expect(rig.name.text, '');
    });

    testWidgets('(b-4) 車の種類の2択：車を選んだ時だけ出る／押した方の口だけを呼ぶ／carType に合う方だけ太字',
        (tester) async {
      final rig = _MoveRig();
      await _pump(tester, rig.build(transports: {TransportType.train}));
      expect(find.text(_kOwn), findsNothing);
      expect(find.text(_kCarpool), findsNothing);

      await _pump(tester, rig.build(transports: {TransportType.car}));
      expect(find.text(_kOwn), findsOneWidget);
      expect(find.text(_kCarpool), findsOneWidget);
      expect(_style(tester, _kOwn).fontWeight, FontWeight.bold);
      expect(_style(tester, _kCarpool).fontWeight, FontWeight.normal);
      expect(_colorOf(tester, _kOwn), _kTextBody);
      expect(_colorOf(tester, _kCarpool), _kTextSupport);
      await tester.tap(find.text(_kOwn));
      expect(rig.log, ['own'], reason: '「社用車・自家用車」を押して呼ばれた口');
      await tester.tap(find.text(_kCarpool));
      expect(rig.log, ['own', 'carpool'], reason: '「相乗り」を押して呼ばれた口');

      await _pump(tester,
          rig.build(transports: {TransportType.car}, carType: 'carpool'));
      expect(_style(tester, _kOwn).fontWeight, FontWeight.normal);
      expect(_style(tester, _kCarpool).fontWeight, FontWeight.bold);
    });

    testWidgets('(b-5) 相乗りの2欄：車で相乗りの時だけ出る／出ていない時は候補を計算しない／字と候補の行き先・絞り方',
        (tester) async {
      final rig = _MoveRig();
      // 出ない2通り（車で社用車・自家用車／電車で carType が相乗り）。
      await _pump(tester, rig.build(transports: {TransportType.car}));
      expect(find.byType(SearchSuggestField), findsNothing);
      await _pump(tester,
          rig.build(transports: {TransportType.train}, carType: 'carpool'));
      expect(find.byType(SearchSuggestField), findsNothing);
      expect(find.text(_kCompanyNote), findsNothing);
      expect(rig.companyCandidateCalls, 0, reason: '欄が出ていないのに、会社名の候補を計算した');
      expect(rig.nameCandidateCalls, 0, reason: '欄が出ていないのに、氏名の候補を計算した');

      // 出る（車で相乗り）。
      await _pump(
          tester,
          rig.build(
            transports: {TransportType.car},
            carType: 'carpool',
            companyCandidates: ['相乗り商事'],
            nameCandidates: ['山田 太郎'],
          ));
      expect(find.byType(SearchSuggestField), findsNWidgets(2));
      expect(_fieldByHint(_kCompanyHint), findsOneWidget);
      expect(_fieldByHint(_kNameHint), findsOneWidget);
      expect(find.text(_kCompanyNote), findsOneWidget);
      expect(
          _top(tester, _fieldByHint(_kCompanyHint)) <
              _top(tester, _fieldByHint(_kNameHint)),
          isTrue,
          reason: '会社名の欄が、氏名の欄より上でない');
      expect(rig.companyCandidateCalls > 0, isTrue);
      expect(rig.nameCandidateCalls > 0, isTrue);

      // 会社名の欄：候補はサーバが絞った物＝入れた字に合わなくても出る。押すと、同じ口が2回呼ばれる
      //   （欄の「変わった」と「候補を選んだ」の両方を、同じ口へ繋いである）。
      await tester.enterText(_fieldByHint(_kCompanyHint), 'ぜんぜん違う字');
      await tester.pump();
      expect(rig.log, ['company:ぜんぜん違う字']);
      expect(rig.company.text, 'ぜんぜん違う字');
      expect(rig.name.text, '', reason: '会社名の字が、氏名の持ち物に入った');
      expect(find.text('相乗り商事'), findsOneWidget, reason: '会社名の候補が、入れた字で絞られた');
      await tester.tap(find.text('相乗り商事'));
      await tester.pump();
      expect(rig.log,
          ['company:ぜんぜん違う字', 'company:相乗り商事', 'company:相乗り商事'],
          reason: '候補を選んだ時に、会社名の口が2回（変わった・選んだ）呼ばれていない');
      expect(rig.company.text, '相乗り商事');

      // 氏名の欄：候補は欄の側で絞る＝入れた字に合う時だけ出る。押すと、口は1回。
      rig.log.clear();
      await tester.enterText(_fieldByHint(_kNameHint), 'どこにも無い字');
      await tester.pump();
      expect(find.text('山田 太郎'), findsNothing, reason: '氏名の候補が、入れた字で絞られていない');
      await tester.enterText(_fieldByHint(_kNameHint), '山田');
      await tester.pump();
      expect(rig.log, ['name:どこにも無い字', 'name:山田']);
      expect(rig.name.text, '山田');
      expect(rig.company.text, '相乗り商事', reason: '氏名の字が、会社名の持ち物に入った');
      await tester.tap(find.byWidgetPredicate((w) =>
          w is RichText && w.text.toPlainText() == '山田 太郎'));
      await tester.pump();
      expect(rig.log, ['name:どこにも無い字', 'name:山田', 'name:山田 太郎'],
          reason: '氏名の候補を選んだ時の口の回数が違う');
    });

    testWidgets('(b-6) 駐車料金と写真：出る条件の6通り（うち1つは「1組だけ」の確かめ）・印と数字のキーボード・入れた字の行き先', (tester) async {
      final rig = _MoveRig();
      Future<void> expectShown(Set<TransportType> t, String carType,
          bool shown, String why) async {
        await _pump(tester, rig.build(transports: t, carType: carType));
        expect(_fieldByHint(_kFeeHint), shown ? findsOneWidget : findsNothing,
            reason: '駐車料金の欄（$why）');
        expect(find.text(_kParkingPhoto), shown ? findsOneWidget : findsNothing,
            reason: '駐車場の写真（$why）');
        expect(find.byType(PhotoStripField),
            shown ? findsOneWidget : findsNothing,
            reason: '写真の帯の数（$why）');
      }

      await expectShown({TransportType.car}, 'own', true, '車で社用車・自家用車');
      await expectShown({TransportType.car}, 'carpool', false, '車で相乗り');
      await expectShown({TransportType.other}, 'own', true, '「その他」だけ');
      await expectShown({TransportType.car, TransportType.other}, 'carpool',
          true, '車（相乗り）と「その他」');
      await expectShown({TransportType.car, TransportType.other}, 'own', true,
          '車（社用車・自家用車）と「その他」＝1組だけ');
      await expectShown({TransportType.train}, 'own', false, '電車');

      await _pump(tester, rig.build(transports: {TransportType.car}));
      expect(find.byIcon(Icons.local_parking), findsOneWidget);
      expect(
          tester.widget<TextField>(_fieldByHint(_kFeeHint)).keyboardType,
          TextInputType.number);
      await tester.enterText(_fieldByHint(_kFeeHint), '500');
      expect(rig.log, ['fee:500']);
      expect(rig.fee.text, '500');
      expect(rig.memo.text, '', reason: '駐車料金の字が、補足の持ち物に入った');
    });

    testWidgets('(b-7) 押し口と目安の帯の繋ぎ：出発地・移動手段・取り直し・計算中・前回の値・渡した手段の値・帯の位置',
        (tester) async {
      final rig = _MoveRig();
      await _pump(tester, rig.build());
      expect(_style(tester, '自宅').fontWeight, FontWeight.bold);
      await tester.tap(find.text('会社'));
      expect(rig.log, ['origin:office']);
      await tester.tap(find.text('電車'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(rig.log, ['origin:office', 'tap:train']);
      await tester.tap(find.text('バス'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('バス'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(rig.log, ['origin:office', 'tap:train', 'double:bus']);

      // 出発地と移動手段の「選んである物」が、渡した値のとおり。
      await _pump(
          tester,
          rig.build(
              originType: 'office', transports: {TransportType.train}));
      expect(_style(tester, '会社').fontWeight, FontWeight.bold);
      expect(_style(tester, '自宅').fontWeight, FontWeight.normal);
      expect(_style(tester, '電車').fontWeight, FontWeight.bold);
      expect(_style(tester, '車').fontWeight, FontWeight.normal);

      // 目安の帯：失敗 → 押すと取り直し／計算中／前回の値／渡した手段と値。
      rig.log.clear();
      await _pump(tester, rig.build(routeFailed: true));
      await tester.tap(find.text(_kRouteFailed));
      expect(rig.log, ['retry']);
      await _pump(tester, rig.build(loadingRoutes: true));
      expect(find.text(_kRouteLoading), findsOneWidget);
      expect(find.text(_kRouteCached), findsNothing);
      await _pump(
          tester,
          rig.build(
            transports: {TransportType.car},
            routeComparisons: {'car': _car(), 'transit': _transit()},
            routeFromCache: true,
          ));
      expect(find.text(_kRouteCached), findsOneWidget);
      expect(find.text(_kRouteLoading), findsNothing);
      expect(find.text('12.4km'), findsOneWidget);
      // 渡した手段（routeTransport）の値を出す＝選んだ集まりの中身ではなく、渡した手段で決まる。
      await _pump(
          tester,
          rig.build(
            transports: {TransportType.car},
            routeTransport: TransportType.train,
            routeComparisons: {'car': _car(), 'transit': _transit()},
          ));
      expect(find.text('神戸→三宮'), findsOneWidget);
      expect(find.text('12.4km'), findsNothing);

      // 帯の位置：車の種類の2択より下・相乗りの欄より上／駐車料金より上。
      await _pump(
          tester,
          rig.build(
            transports: {TransportType.car},
            carType: 'carpool',
            routeComparisons: {'car': _car()},
          ));
      expect(
          _top(tester, find.text(_kCarpool)) <
              _top(tester, find.text('12.4km')),
          isTrue);
      expect(
          _top(tester, find.text('12.4km')) <
              _top(tester, _fieldByHint(_kCompanyHint)),
          isTrue);
      await _pump(
          tester,
          rig.build(
            transports: {TransportType.car},
            routeComparisons: {'car': _car()},
          ));
      expect(
          _top(tester, find.text('12.4km')) <
              _top(tester, _fieldByHint(_kFeeHint)),
          isTrue);
    });

    testWidgets('(b-8) ReportStepWork：上からの並び・※の2つ・マイクを押すと onMicTap・渡した値が部品へ渡る', (tester) async {
      var mic = 0;
      final ctrl = TextEditingController();
      await _pump(
          tester,
          ReportStepWork(
            workController: ctrl,
            isListening: false,
            onMicTap: () => mic++,
            workPhotoPaths: const [],
            onWorkPhotosChanged: (_) {},
          ));
      final order = [
        find.text('作業'),
        find.text('作業内容'),
        find.text(_kWorkNote),
        find.text('写真'),
      ].map((f) => _top(tester, f)).toList();
      for (var i = 1; i < order.length; i++) {
        expect(order[i - 1] < order[i], isTrue, reason: '上からの並びが違う（$i 番目） $order');
      }
      expect(find.text(_kPhotoNote), findsOneWidget);
      expect(find.text('0/5'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.mic_none));
      expect(mic, 1);
      await tester.enterText(_fieldByHint(_kWorkHint), '1階の配線');
      expect(ctrl.text, '1階の配線');

      await _pump(
          tester,
          ReportStepWork(
            workController: ctrl,
            isListening: true,
            onMicTap: () => mic++,
            workPhotoPaths: const [],
            onWorkPhotosChanged: (_) {},
          ));
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsNothing);
    });

    testWidgets('(b-9) ReportStepButtons：段ごとの並びと行き先・busy の間は確認へ進まない・高さ 56・※は横の真ん中',
        (tester) async {
      final went = <int>[];
      var checks = 0;
      Future<void> pumpStep(int step, {bool busy = false}) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ReportStepButtons(
                step: step,
                onGoStep: went.add,
                checkBusy: busy,
                onCheck: () async => checks++,
              ),
            ),
          ),
        ));
        await tester.pump();
      }

      await pumpStep(1);
      expect(find.text('次へ'), findsOneWidget);
      expect(find.text('戻る'), findsNothing);
      expect(find.text(_kCheck), findsNothing);
      expect(find.text(_kCheckNote), findsNothing);
      expect(tester.getSize(find.byType(ReportOutlineActionButton)).height, 56);
      await tester.tap(find.text('次へ'));
      await tester.pump();
      expect(went, [2]);

      await pumpStep(2);
      expect(find.text('戻る'), findsOneWidget);
      expect(find.text('次へ'), findsOneWidget);
      expect(find.text(_kCheck), findsNothing);
      expect(_left(tester, find.text('戻る')) < _left(tester, find.text('次へ')),
          isTrue);
      final back = tester.getSize(find.byType(ReportStepBackButton));
      final next = tester.getSize(find.byType(ReportOutlineActionButton));
      expect(back.height, 56);
      expect(next.height, 56);
      expect(next.width, closeTo(back.width * 2, 0.5), reason: '幅が 1 対 2 でない');
      await tester.tap(find.text('戻る'));
      await tester.tap(find.text('次へ'));
      await tester.pump();
      expect(went, [2, 1, 3]);

      await pumpStep(3);
      expect(find.text('戻る'), findsOneWidget);
      expect(find.text('次へ'), findsNothing);
      expect(find.text(_kCheck), findsOneWidget);
      expect(find.text(_kCheckNote), findsOneWidget);
      expect(_colorOf(tester, _kCheckNote), _kTextFaint);
      expect(
          _top(tester, find.text(_kCheck)) < _top(tester, find.text(_kCheckNote)),
          isTrue);
      // ※の字は、横いっぱいに伸ばさず、字の幅のまま横の真ん中に置く
      //   （縦の並びに「横いっぱい」を付けると、箱の真ん中は同じでも、字は左に寄って見える＝箱の幅でも見る）。
      final noteBox = tester.getRect(find.text(_kCheckNote));
      expect(noteBox.center.dx, closeTo(200, 0.5), reason: '※の字が横の真ん中でない');
      expect(noteBox.width < 360, isTrue,
          reason: '※の字の箱が横いっぱいに伸びている（字が左に寄る） 幅=${noteBox.width}');
      expect(noteBox.left > 20, isTrue,
          reason: '※の字が左の端から始まっている 左=${noteBox.left}');
      await tester.tap(find.text('戻る'));
      await tester.tap(find.text(_kCheck));
      await tester.pump();
      expect(went, [2, 1, 3, 2]);
      expect(checks, 1);

      await pumpStep(3, busy: true);
      expect(find.text(_kCheck), findsNothing, reason: 'busy の間は字の代わりにくるくる');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(ReportOutlineActionButton));
      await tester.pump();
      expect(checks, 1, reason: 'busy の間に押して、確認へ進んだ');
    });

    testWidgets('(b-10) 写真の帯の繋ぎ：渡した並びの数が出る・✕で消すと、残りの並びが口へ渡る（駐車場・作業）',
        (tester) async {
      // 写真のファイルは無くてよい（帯は Image.file でサムネを読むが、無いファイルでも、この検査は落ちない＝箱で何度も走らせて確かめた）。
      //   見るのは、数の字と、消した後に口へ渡る並び。
      final rig = _MoveRig();
      await _pump(
          tester,
          rig.build(
            transports: {TransportType.car},
            parkingPhotoPaths: const ['/none/a.jpg', '/none/b.jpg'],
          ));
      expect(find.text('2/5'), findsOneWidget, reason: '渡した駐車場の写真の数が帯に出ていない');
      expect(find.text('0/5'), findsNothing);
      // 帯は新しい物を左に出す。左の ✕ を押すと最後の1枚（b）が消えて、残り（a）が口へ渡る。
      await tester.tap(find.byIcon(Icons.close).first);
      expect(rig.log, ['photos:/none/a.jpg'], reason: '駐車場の写真を消した後の並びが、口へ渡っていない');

      final got = <String>[];
      await _pump(
          tester,
          ReportStepWork(
            workController: TextEditingController(),
            isListening: false,
            onMicTap: () {},
            workPhotoPaths: const ['/none/w.jpg'],
            onWorkPhotosChanged: (v) => got.add('work:${v.join('|')}'),
          ));
      expect(find.text('1/5'), findsOneWidget, reason: '渡した作業の写真の数が帯に出ていない');
      expect(find.text('0/5'), findsNothing);
      await tester.tap(find.byIcon(Icons.close));
      expect(got, ['work:'], reason: '作業の写真を消した後の並び（空）が、口へ渡っていない');
    });

    testWidgets('(b-11) 段2の全部が出る形の、上からの並びと空き／段3と下のボタンの空き', (tester) async {
      double top(Finder f) => tester.getTopLeft(f).dy;
      double bottom(Finder f) => tester.getBottomLeft(f).dy;
      double gap(Finder above, Finder below) => top(below) - bottom(above);

      // 全部が出る形＝車（相乗り）と「その他」：補足の欄・車の種類の2択・目安の帯・相乗りの2欄・駐車料金と写真。
      final rig = _MoveRig();
      await _pump(
          tester,
          rig.build(
            transports: {TransportType.car, TransportType.other},
            carType: 'carpool',
            routeComparisons: {'car': _car()},
          ));
      final order = <Finder>[
        find.widgetWithText(ReportFieldLabel, '出発地'),
        find.byType(ReportOriginSelector),
        find.widgetWithText(ReportFieldLabel, '移動手段'),
        find.byType(ReportTransportRow),
        find.text(_kTransportNote),
        find.widgetWithIcon(ReportFormInputShell, Icons.edit_note),
        find.ancestor(of: find.text(_kOwn), matching: find.byType(Row)).first,
        find.byType(ReportRouteInfoBar),
        find.byType(SearchSuggestField).at(0),
        find.text(_kCompanyNote),
        find.byType(SearchSuggestField).at(1),
        find.widgetWithIcon(ReportFormInputShell, Icons.local_parking),
        find.byType(PhotoStripField),
      ];
      // 空き（上の物の下の端から、下の物の上の端まで）。取り出す前（HEAD eec17e3）のシェルの並びと同じ数。
      const gaps = <double>[8, 16, 8, 6, 10, 10, 12, 10, 6, 10, 10, 12];
      for (var i = 1; i < order.length; i++) {
        expect(gap(order[i - 1], order[i]), closeTo(gaps[i - 1], 0.01),
            reason: '段2の $i 番目と ${i + 1} 番目の間の空き（並びが違う時もここで落ちる）');
      }

      await _pump(
          tester,
          ReportStepWork(
            workController: TextEditingController(),
            isListening: false,
            onMicTap: () {},
            workPhotoPaths: const [],
            onWorkPhotosChanged: (_) {},
          ));
      expect(
          gap(find.byType(ReportWorkContentSection), find.byType(PhotoStripField)),
          closeTo(14, 0.01),
          reason: '段3の、作業内容と写真の間の空き');

      await _pump(
          tester,
          ReportStepButtons(
            step: 3,
            onGoStep: (_) {},
            checkBusy: false,
            onCheck: () async {},
          ));
      expect(gap(find.byType(ReportStepBackButton), find.text(_kCheckNote)),
          closeTo(7, 0.01),
          reason: '下のボタンと※の間の空き');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (c) 確認の画面
  // ══════════════════════════════════════════════════════════
  group('(c) 確認の画面', () {
    testWidgets('(c-1) 上の帯・見出し・行の名の並び・値の形・ボタンの字', (tester) async {
      await _pumpConfirm(tester,
          initial: _snap(),
          currentOf: () => _snap(),
          onSend: () async {},
          isDone: () => false);
      expect(find.widgetWithText(AppBar, '確認'), findsOneWidget);
      expect(find.text(_kConfirmHead), findsOneWidget);
      const rows = ['日付', '現場', '移動', '距離・時間', '交通費（駐車料金）', '作業内容', '写真'];
      final tops = rows.map((r) => _top(tester, find.text(r))).toList();
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i - 1] < tops[i], isTrue, reason: '行の並びが違う（${rows[i]}） $tops');
      }
      expect(find.text('9月20日（日）・☀日勤'), findsOneWidget);
      expect(find.text('○○ビル 新築工事'), findsOneWidget);
      expect(find.text('自宅から 車'), findsOneWidget);
      expect(find.text('車　12.4km　⛽¥141'), findsOneWidget);
      expect(find.text('¥500'), findsOneWidget);
      expect(find.text('1階の配線'), findsOneWidget);
      expect(find.text('作業 0枚 / 駐車 1枚'), findsOneWidget);
      expect(find.text(_kSend), findsOneWidget);
      expect(find.text(_kBackToFix), findsOneWidget);
      expect(_colorOf(tester, '日付'), _kTextSupport);
      expect(_colorOf(tester, '¥500'), _kTextBody);
    });

    testWidgets('(c-1) 値が無い所は「—」（目安の行が無い・駐車料金が空・作業内容が空・目安の値が欠けている）', (tester) async {
      await _pumpConfirm(tester,
          initial: _snap(routeRows: const [], parkingFeeRaw: '', workContent: ''),
          currentOf: () => _snap(),
          onSend: () async {},
          isDone: () => false);
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('¥'), findsNothing);

      await _pumpConfirm(tester,
          initial: _snap(routeRows: const [
            (label: '電車', dist: null, cost: '💴¥620'),
            (label: '徒歩', dist: '1.2km', cost: null),
          ]),
          currentOf: () => _snap(),
          onSend: () async {},
          isDone: () => false);
      expect(find.text('電車　—　💴¥620\n徒歩　1.2km　—'), findsOneWidget);
    });

    testWidgets('(c-2) 「相乗り」の行：会社名か氏名のどちらかが在る時だけ出る（両方は全角の空白でつなぐ）', (tester) async {
      await _pumpConfirm(tester,
          initial: _snap(),
          currentOf: () => _snap(),
          onSend: () async {},
          isDone: () => false);
      expect(find.text('相乗り'), findsNothing);

      await _pumpConfirm(tester,
          initial: _snap(carpoolCompany: '相乗り商事', carpoolName: '相乗 次郎'),
          currentOf: () => _snap(),
          onSend: () async {},
          isDone: () => false);
      expect(find.text('相乗り'), findsOneWidget);
      expect(find.text('相乗り商事　相乗 次郎'), findsOneWidget);
      expect(
          _top(tester, find.text('交通費（駐車料金）')) <
              _top(tester, find.text('相乗り')),
          isTrue);
      expect(
          _top(tester, find.text('相乗り')) < _top(tester, find.text('作業内容')),
          isTrue);

      await _pumpConfirm(tester,
          initial: _snap(carpoolName: '相乗 次郎'),
          currentOf: () => _snap(),
          onSend: () async {},
          isDone: () => false);
      expect(find.text('相乗り'), findsOneWidget);
      expect(find.text('相乗 次郎'), findsOneWidget);
    });

    testWidgets('(c-3) 「報告を送信」：変わっていなければ1回送る／送れた時だけ閉じる（二者比較）', (tester) async {
      var sent = 0;
      var done = false;
      await _pumpConfirm(tester,
          initial: _snap(),
          currentOf: () => _snap(),
          onSend: () async => sent++,
          isDone: () => done);
      await tester.tap(find.text(_kSend));
      await tester.pumpAndSettle();
      expect(sent, 1);
      expect(find.text(_kConfirmHead), findsOneWidget, reason: '送れていないのに閉じた');

      done = true;
      await tester.tap(find.text(_kSend));
      await tester.pumpAndSettle();
      expect(sent, 2);
      expect(find.text(_kConfirmHead), findsNothing, reason: '送れたのに閉じていない');
      expect(find.text('確認を開く'), findsOneWidget);
    });

    testWidgets('(c-4) 内容が変わっていた時：送らずに知らせて、画面の値を新しい物に替える／もう一度押すと送る', (tester) async {
      var sent = 0;
      var now = _snap();
      await _pumpConfirm(tester,
          initial: _snap(),
          currentOf: () => now,
          onSend: () async => sent++,
          isDone: () => false);
      now = _snap(workContent: '2階の配線');
      await tester.tap(find.text(_kSend));
      await tester.pump();
      expect(sent, 0, reason: '内容が変わっているのに送った');
      expect(find.text(_kChanged), findsOneWidget);
      expect(find.text('2階の配線'), findsOneWidget, reason: '画面の値が新しい物に替わっていない');
      expect(find.text('1階の配線'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_kSend));
      await tester.pumpAndSettle();
      expect(sent, 1, reason: '見直した後に押しても送らない');
    });

    testWidgets('(c-5) 送っている間に、もう一度押しても送るのは1回だけ', (tester) async {
      var sent = 0;
      final gate = Completer<void>();
      await _pumpConfirm(tester,
          initial: _snap(),
          currentOf: () => _snap(),
          onSend: () {
            sent++;
            return gate.future;
          },
          isDone: () => false);
      await tester.tap(find.text(_kSend));
      await tester.pump();
      expect(sent, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(ReportOutlineActionButton));
      await tester.pump();
      expect(sent, 1, reason: '送っている間に、もう一度送った');
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(_kSend), findsOneWidget);
    });

    testWidgets('(c-6) 「戻って直す」：押すと閉じる／送っている間は押しても閉じない', (tester) async {
      final gate = Completer<void>();
      await _pumpConfirm(tester,
          initial: _snap(),
          currentOf: () => _snap(),
          onSend: () => gate.future,
          isDone: () => false);
      await tester.tap(find.text(_kSend));
      await tester.pump();
      await tester.tap(find.text(_kBackToFix));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(_kConfirmHead), findsOneWidget, reason: '送っている間に閉じた');
      gate.complete();
      await tester.pumpAndSettle();

      await tester.tap(find.text(_kBackToFix));
      await tester.pumpAndSettle();
      expect(find.text(_kConfirmHead), findsNothing);
      expect(find.text('確認を開く'), findsOneWidget);
    });

    test('(c-7) 差の見張りの鍵（diffKey）：7つの値のどれでも変わる・ほかの値では変わらない・境い目・区切りは6つ', () {
      final base = _snap(carpoolCompany: 'c', carpoolName: 'n');
      // 鍵に入る7つ（1つずつ変える）。
      final changed = <String, ReportSnapshot>{
        '現場の id': _snap(siteId: 's2', carpoolCompany: 'c', carpoolName: 'n'),
        '移動手段の鍵':
            _snap(transportKey: 'train', carpoolCompany: 'c', carpoolName: 'n'),
        '作業内容':
            _snap(workContent: '2階の配線', carpoolCompany: 'c', carpoolName: 'n'),
        '目安の金額': _snap(carpoolCompany: 'c', carpoolName: 'n', routeRows: const [
          (label: '車', dist: '12.4km', cost: '⛽¥999'),
        ]),
        '駐車料金':
            _snap(parkingFeeRaw: '600', carpoolCompany: 'c', carpoolName: 'n'),
        '相乗りの会社名': _snap(carpoolCompany: 'c2', carpoolName: 'n'),
        '相乗りの氏名': _snap(carpoolCompany: 'c', carpoolName: 'n2'),
      };
      changed.forEach((what, s) {
        expect(s.diffKey, isNot(base.diffKey), reason: '$what を変えても鍵が同じ');
      });
      // 鍵に入らない値。
      final same = <String, ReportSnapshot>{
        '日付の字': _snap(dateLabel: '9月21日（月）', carpoolCompany: 'c', carpoolName: 'n'),
        '勤務の字': _snap(shiftLabel: '🌙夜勤', carpoolCompany: 'c', carpoolName: 'n'),
        '現場の名前': _snap(siteName: '別の名前', carpoolCompany: 'c', carpoolName: 'n'),
        '出発地の字': _snap(originLabel: '会社', carpoolCompany: 'c', carpoolName: 'n'),
        '移動手段の字':
            _snap(transportLabel: '電車', carpoolCompany: 'c', carpoolName: 'n'),
        '作業の写真の枚数':
            _snap(workPhotoCount: 3, carpoolCompany: 'c', carpoolName: 'n'),
        '駐車場の写真の枚数':
            _snap(parkingPhotoCount: 0, carpoolCompany: 'c', carpoolName: 'n'),
        '目安の距離の字': _snap(carpoolCompany: 'c', carpoolName: 'n', routeRows: const [
          (label: '車', dist: '99km', cost: '⛽¥141'),
        ]),
      };
      same.forEach((what, s) {
        expect(s.diffKey, base.diffKey, reason: '$what を変えたら鍵が変わった');
      });
      // 値の境い目をずらした2つは、別の鍵（区切りが在るから）。
      expect(_snap(siteId: 'a', transportKey: 'bc').diffKey,
          isNot(_snap(siteId: 'ab', transportKey: 'c').diffKey));
      // 区切りの字（符号 1）は6つ＝7つの値の間。中身も決まった並び。
      expect(base.diffKey.codeUnits.where((c) => c == 1).length, 6);
      expect(base.diffKey.split(String.fromCharCode(1)),
          ['s1', 'car', '1階の配線', '車:⛽¥141', '500', 'c', 'n']);
      // 現場が null の時は、空の字で入る。
      expect(_snap(siteId: null).diffKey.split(String.fromCharCode(1)).first, '');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (d) 値の関数
  // ══════════════════════════════════════════════════════════
  group('(d) 値の関数', () {
    test('(d-1) transportsAfterTap：1つだけ選ぶ・1つの時は外れない・2つ以上の時は外れる・渡した集まりは変わらない', () {
      expect(transportsAfterTap({}, TransportType.car), {TransportType.car});
      expect(transportsAfterTap({TransportType.car}, TransportType.train),
          {TransportType.train});
      expect(transportsAfterTap({TransportType.car}, TransportType.car),
          {TransportType.car},
          reason: '1つだけの時に押して、外れた');
      final two = {TransportType.car, TransportType.train};
      expect(transportsAfterTap(two, TransportType.car), {TransportType.train});
      expect(transportsAfterTap(two, TransportType.bus), {TransportType.bus});
      expect(two, {TransportType.car, TransportType.train},
          reason: '渡した集まりが書き換わった');
      // 並び（先頭の1つが目安の手段になる）＝残った物の順はそのまま。
      final three = {
        TransportType.train,
        TransportType.car,
        TransportType.other
      };
      expect(transportsAfterTap(three, TransportType.train).toList(),
          [TransportType.car, TransportType.other]);
    });

    test('(d-2) reportWorkContentPrefix：「その他」と補足の字・順・空白・選んでいない時', () {
      String p(Set<TransportType> t, String other, String memo) =>
          reportWorkContentPrefix(transports: t, otherText: other, memoText: memo);
      expect(p({TransportType.other}, 'トラック', ''), '[その他:トラック] ');
      expect(p({TransportType.car}, '', 'バイクで駅まで'), '【移動】バイクで駅まで ');
      expect(p({TransportType.other}, ' トラック ', ' バイクで駅まで '),
          '[その他:トラック] 【移動】バイクで駅まで ');
      // 全角の空白（U+3000）も、Dart の trim が除く（実測）＝空として扱う・前後からも除く。
      expect(p({TransportType.other}, '   ', '\u3000'), '',
          reason: '全角の空白だけの補足に、頭の字が付いた');
      expect(p({TransportType.car}, '', '\u3000バイクで\u3000駅まで\u3000'),
          '【移動】バイクで\u3000駅まで ',
          reason: '補足の前後の全角の空白が残った／間の空白が消えた');
      expect(p({TransportType.other}, '   ', '   '), '');
      expect(p({TransportType.car}, 'トラック', ''), '',
          reason: '「その他」を選んでいないのに、その他の字が付いた');
      expect(p({}, '', ''), '');
    });

    test('(d-3) reportParkingFeeValue：空・空白・0・負の数・数でない字・小数', () {
      expect(reportParkingFeeValue(''), isNull);
      expect(reportParkingFeeValue('   '), isNull);
      expect(reportParkingFeeValue(' 500 '), '500');
      expect(reportParkingFeeValue('0'), '0', reason: '0 が空にされた');
      expect(reportParkingFeeValue('-1'), isNull);
      expect(reportParkingFeeValue('abc'), isNull);
      expect(reportParkingFeeValue('12.5'), '12.5');
    });

    test('(d-4) reportCarpoolValue：車で相乗りの時だけ・空白を除く・空なら null', () {
      String? v(Set<TransportType> t, String carType, String text) =>
          reportCarpoolValue(transports: t, carType: carType, text: text);
      expect(v({TransportType.car}, 'carpool', ' 相乗り商事 '), '相乗り商事');
      expect(v({TransportType.car}, 'own', '相乗り商事'), isNull,
          reason: '社用車・自家用車なのに、相乗りの字が送られる');
      expect(v({TransportType.train}, 'carpool', '相乗り商事'), isNull,
          reason: '車を選んでいないのに、相乗りの字が送られる');
      expect(v({TransportType.car}, 'carpool', '   '), isNull);
      expect(v({TransportType.car, TransportType.train}, 'carpool', 'x'), 'x');
    });

    test('(d-5) reportSnapshotFrom：出発地・移動手段の鍵と字・現場なし・相乗り・空白・枚数', () {
      ReportSnapshot make({
        Set<TransportType> transports = const {},
        String carType = 'own',
        String originType = 'home',
        String? siteId,
        String? siteName,
      }) =>
          reportSnapshotFrom(
            dateLabel: '9月20日（日）',
            shiftLabel: '☀日勤',
            siteId: siteId,
            siteName: siteName,
            originType: originType,
            transports: transports,
            carType: carType,
            routeComparisons: {'car': _car(), 'transit': _transit()},
            parkingText: ' 500 ',
            carpoolCompanyText: ' 相乗り商事 ',
            carpoolNameText: ' 相乗 次郎 ',
            workText: ' 1階の配線 ',
            workPhotoCount: 2,
            parkingPhotoCount: 1,
          );
      final a = make(
          transports: {TransportType.train, TransportType.car},
          carType: 'carpool',
          originType: 'office',
          siteId: 's1',
          siteName: '○○ビル 新築工事');
      expect(a.dateLabel, '9月20日（日）');
      expect(a.shiftLabel, '☀日勤');
      expect(a.siteId, 's1');
      expect(a.siteName, '○○ビル 新築工事');
      expect(a.originLabel, '会社');
      expect(a.transportKey, 'car,train', reason: '鍵は名前の順に並べ替える');
      expect(a.transportLabel, '電車・車', reason: '字は選んだ順');
      expect(a.routeRows.map((r) => '${r.label}|${r.dist}|${r.cost}').toList(),
          ['電車|神戸→三宮|💴¥620', '車|12.4km|⛽¥141']);
      expect(a.parkingFeeRaw, '500');
      expect(a.carpoolCompany, '相乗り商事');
      expect(a.carpoolName, '相乗 次郎');
      expect(a.workContent, '1階の配線');
      expect(a.workPhotoCount, 2);
      expect(a.parkingPhotoCount, 1);

      final b = make(transports: {TransportType.car});
      expect(b.siteId, isNull);
      expect(b.siteName, '該当現場なし');
      expect(b.originLabel, '自宅');
      expect(b.carpoolCompany, '', reason: '社用車・自家用車なのに、相乗りの会社名が入った');
      expect(b.carpoolName, '');
      final c = make(transports: {TransportType.train}, carType: 'carpool');
      expect(c.carpoolCompany, '', reason: '車を選んでいないのに、相乗りの会社名が入った');
      expect(c.carpoolName, '', reason: '車を選んでいないのに、相乗りの氏名が入った');
      expect(c.carpoolLabel, '', reason: '車を選んでいないのに、確認の画面に「相乗り」の行が出る');
      final d = make();
      expect(d.transportLabel, '未選択');
      expect(d.transportKey, '');
      expect(d.routeRows, isEmpty);
    });

    test('(d-6) reportRouteParts・reportRouteBreakdown・reportExpenseSnapshot：車・電車・値なし・重ねて数えない', () {
      final both = {'car': _car(), 'transit': _transit()};
      final car = reportRouteParts(TransportType.car, both);
      expect((car.time, car.dist, car.cost), ('28分', '12.4km', '⛽¥141'));
      final train = reportRouteParts(TransportType.train, both);
      expect((train.time, train.dist, train.cost), ('35分', '神戸→三宮', '💴¥620'));
      final walk = reportRouteParts(TransportType.walk, {
        'walking': SimpleRoute(distance: '1.2km', duration: '15分', distanceM: 1200)
      });
      expect((walk.time, walk.dist, walk.cost), ('15分', '1.2km', null));
      final none = reportRouteParts(TransportType.car, const {});
      expect((none.time, none.dist, none.cost), (null, null, null));

      // 電車とバスは同じ目安＝行は1つ。車と電車は2つ（選んだ順）。
      expect(
          reportRouteBreakdown({TransportType.train, TransportType.bus}, both)
              .map((r) => r.label)
              .toList(),
          ['電車']);
      expect(
          reportRouteBreakdown({TransportType.car, TransportType.train}, both)
              .map((r) => '${r.label}|${r.dist}|${r.cost}')
              .toList(),
          ['車|12.4km|⛽¥141', '電車|神戸→三宮|💴¥620']);
      // 値が無い手段も行は残す。
      expect(
          reportRouteBreakdown({TransportType.car}, const {})
              .map((r) => '${r.label}|${r.dist}|${r.cost}')
              .toList(),
          ['車|null|null']);

      // 経費：車と「その他」は同じ目安＝1回だけ数える。
      final e1 = reportExpenseSnapshot(
          {TransportType.car, TransportType.other}, both);
      expect(e1.distanceKm, 12.4);
      expect(e1.fuelCost, 141);
      expect(e1.toll, 300);
      expect(e1.fare, isNull);
      expect(e1.breakdown, [
        {'mode': 'car', 'distance_km': 12.4, 'fuel_cost': 141, 'toll': 300}
      ]);
      // 電車とバスも1回だけ。車と合わせると、両方が入る。
      final e2 = reportExpenseSnapshot(
          {TransportType.train, TransportType.bus, TransportType.car}, both);
      expect(e2.fare, 620);
      expect(e2.fuelCost, 141);
      expect(e2.breakdown, [
        {'mode': 'train', 'fare': 620},
        {'mode': 'car', 'distance_km': 12.4, 'fuel_cost': 141, 'toll': 300}
      ]);
      // 値が無い時は null のまま（0 で埋めない）。
      final e3 = reportExpenseSnapshot({TransportType.car}, const {});
      expect((e3.distanceKm, e3.fuelCost, e3.fare, e3.toll), (null, null, null, null));
      expect(e3.breakdown, [
        {'mode': 'car'}
      ]);
    });

    testWidgets('(d-7) confirmAddTransport：窓の題・文・ボタンの字／「OK」で true・「キャンセル」で false', (tester) async {
      final results = <bool>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  results.add(await confirmAddTransport(context)),
              child: const Text('窓を開く'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('窓を開く'));
      await tester.pumpAndSettle();
      expect(find.text('移動手段を追加'), findsOneWidget);
      expect(find.text('2つ以上の移動手段を記録します。よろしいですか？'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(results, [true]);

      await tester.tap(find.text('窓を開く'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(results, [true, false]);
    });
  });

  // ══════════════════════════════════════════════════════════
  // (e) 送る本文と写真の関数
  // ══════════════════════════════════════════════════════════
  group('(e) 送る本文と写真の関数', () {
    WorkerReportItem full({List<String>? work, List<String>? parking}) =>
        WorkerReportItem(
          id: 'e1',
          name: '検査 太郎',
          transport: TransportType.car,
          transportTypes: ['car'],
          parkingFee: '500',
          workContent: '1階の配線',
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
          workPhotoPaths: work,
          parkingPhotoPaths: parking,
          timestamp: DateTime.utc(2026, 9, 20, 9, 5),
        );

    test('(e-1) reportBodyFor：鍵の並び（21個）と値／現場・座標が無い時はその3つの鍵が無い／駐車料金の形', () {
      final body = reportBodyFor(full());
      expect(body.keys.toList(), [
        'worker_name',
        'worker_company',
        'report_date',
        'shift_type',
        'clock_in_time',
        'transport_type',
        'transport_types_json',
        'parking_fee',
        'gps_address',
        'origin_type',
        'work_content',
        'transport_distance_km',
        'transport_fuel_cost',
        'transport_fare',
        'transport_toll',
        'transport_breakdown',
        'carpool_company',
        'carpool_name',
        'site_id',
        'gps_lat',
        'gps_lon',
      ]);
      expect(body['worker_name'], '検査 太郎');
      expect(body['worker_company'], '');
      expect(body['report_date'], '2026-09-20');
      expect(body['shift_type'], 'day');
      expect(body['clock_in_time'], '09:05:00');
      expect(body['transport_type'], 'car');
      expect(body['transport_types_json'], ['car']);
      expect(body['parking_fee'], 500.0);
      expect(body['gps_address'], 'テスト県テスト市1-2-3');
      expect(body['origin_type'], 'office');
      expect(body['work_content'], '1階の配線');
      expect(body['transport_distance_km'], 12.4);
      expect(body['transport_fuel_cost'], 141);
      expect(body['transport_fare'], isNull);
      expect(body['transport_toll'], 300);
      expect(body['transport_breakdown'], [
        {'mode': 'car', 'distance_km': 12.4, 'fuel_cost': 141, 'toll': 300}
      ]);
      expect(body['carpool_company'], isNull);
      expect(body['carpool_name'], isNull);
      expect(body['site_id'], 'site-1');
      expect(body['gps_lat'], 34.5);
      expect(body['gps_lon'], 135.25);
      expect(body.containsKey('photos'), isFalse, reason: '写真は、本文の関数では入れない');

      // 夜勤の午前（日本の時刻で 9月21日 01:30）＝業務日は前の日。値が無い鍵は null・条件つきの3つは無い。
      final sparse = reportBodyFor(WorkerReportItem(
        id: 'e2',
        name: '検査 太郎',
        transport: TransportType.train,
        shiftType: 'night',
        timestamp: DateTime.utc(2026, 9, 20, 16, 30),
      ));
      expect(sparse.keys.length, 18);
      expect(sparse.containsKey('site_id'), isFalse);
      expect(sparse.containsKey('gps_lat'), isFalse);
      expect(sparse.containsKey('gps_lon'), isFalse);
      expect(sparse['report_date'], '2026-09-20');
      expect(sparse['clock_in_time'], '16:30:00');
      expect(sparse['parking_fee'], isNull);
      expect(sparse['transport_types_json'], isNull);
      expect(sparse['gps_address'], '');
      expect(sparse['origin_type'], 'home');
      // 数として読めない駐車料金は null。
      final bad = reportBodyFor(WorkerReportItem(
        id: 'e3',
        name: '検査 太郎',
        transport: TransportType.car,
        parkingFee: 'abc',
        timestamp: DateTime.utc(2026, 9, 20, 9, 5),
      ));
      expect(bad['parking_fee'], isNull);
    });

    test('(e-2) reportPhotosFor：作業が先・駐車場が後・読めない写真は、作業のも駐車場のも飛ばす／写真が無ければ空', () async {
      final dir = Directory.systemTemp.createTempSync('f8b1_form_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final w1 = File('${dir.path}/w1.jpg')..writeAsBytesSync([1, 2, 3]);
      final w2 = File('${dir.path}/w2.jpg')..writeAsBytesSync([4, 5]);
      final p1 = File('${dir.path}/p1.jpg')..writeAsBytesSync([9, 8, 7, 6]);
      final photos = await reportPhotosFor(full(
        work: [w1.path, '${dir.path}/none.jpg', w2.path],
        parking: ['${dir.path}/none.jpg', p1.path],
      ));
      expect(photos, [
        {'photo_type': 'site', 'base64': 'AQID'},
        {'photo_type': 'site', 'base64': 'BAU='},
        {'photo_type': 'parking', 'base64': 'CQgHBg=='},
      ]);
      expect(await reportPhotosFor(full()), isEmpty);
    });

    test('(e-3) 業務日：日勤の日本の午前はその日・夜勤の日本の午前は前の日（UTC の日付とも違う時刻で見る）', () {
      String dateOf(String shift, DateTime at) => reportBodyFor(WorkerReportItem(
            id: 'e3',
            name: '検査 太郎',
            transport: TransportType.car,
            shiftType: shift,
            timestamp: at,
          ))['report_date'] as String;
      // 2026-09-20 16:30 UTC＝日本の 9月21日 01:30（UTC の日付は 20日）。
      expect(dateOf('day', DateTime.utc(2026, 9, 20, 16, 30)), '2026-09-21');
      expect(dateOf('night', DateTime.utc(2026, 9, 20, 16, 30)), '2026-09-20');
      // 2026-09-21 01:30 UTC＝日本の 9月21日 10:30（UTC の日付は 21日）。
      expect(dateOf('day', DateTime.utc(2026, 9, 21, 1, 30)), '2026-09-21');
      expect(dateOf('night', DateTime.utc(2026, 9, 21, 1, 30)), '2026-09-20');
      // 2026-09-21 03:00 UTC＝日本の 9月21日 12:00（夜勤でも、昼からはその日）。
      expect(dateOf('night', DateTime.utc(2026, 9, 21, 3, 0)), '2026-09-21');
    });
  });

  // ══════════════════════════════════════════════════════════
  // (f) ソースの字（今日の日報のシェルの繋ぎ）
  // ══════════════════════════════════════════════════════════
  group('(f) ソースの字', () {
    const home = 'lib/screens/home_screen.dart';
    const parts = 'lib/widgets/report_form_parts.dart';
    const steps = 'lib/widgets/report_form_steps.dart';

    test('(f-1) シェルの本に、動かした部品の古い名前が無い／新しい2本を読み込んでいる', () {
      final src = _codeOnly(home);
      const oldNames = [
        '_SectionHeader', '_FieldLabel', '_FormCard', '_FormInputShell',
        '_OutlineActionButton', '_StepIndicator', '_StepBackButton',
        '_ReportSnapshot', '_ConfirmSendScreen', '_SiteSelectField',
        '_SitePickerSheet', '_OriginSelector', '_TransportRow',
        '_WorkContentSection', '_SmallMediaButton', '_VoiceInputDialog',
        '_RouteInfoBar', '_routeParts', '_routeBreakdown', '_expenseSnapshot',
      ];
      for (final name in oldNames) {
        expect(RegExp('(?<![A-Za-z0-9_])$name(?![A-Za-z0-9_])').hasMatch(src),
            isFalse,
            reason: '$name がシェルの本に残っている');
      }
      expect(src.contains("import '../widgets/report_form_parts.dart';"), isTrue);
      expect(src.contains("import '../widgets/report_form_steps.dart';"), isTrue);
      // 動かした先に、公開の名前で在る（二者比較）。
      final moved = _codeOnly(parts);
      for (final name in [
        'class ReportSectionHeader ', 'class ReportConfirmScreen ',
        'class ReportSitePickerSheet ', 'class ReportRouteInfoBar ',
        'class ReportSnapshot ', ') reportRouteParts(',
        ' reportRouteBreakdown(', ') reportExpenseSnapshot(',
      ]) {
        expect(moved.contains(name), isTrue, reason: '$name が動かした先に無い');
      }
    });

    test('(f-2) シェルの本の、押した時に呼ぶ物の数が、取り出す前（HEAD eec17e3）と同じ', () {
      final src = _codeOnly(home);
      const counts = <String, int>{
        '_saveDraft(': 7,
        '_saveLastTransport(': 5,
        "_saveWorkStatus('moving')": 2,
        '_parkingCtrl.clear()': 5,
        '_ensureColleaguesLoaded(': 3,
        "prefs.setString('default_origin'": 1,
        '_calculateRoutes(': 3,
        '_parkingPhotoPaths = []': 8,
        '_transports = newSet': 2,
        "_carType = 'own'": 4,
        "_carType = 'carpool'": 1,
        '_originType = type': 1,
        '_workPhotoPaths = v': 1,
        '_parkingPhotoPaths = v': 1,
        'ReportStore.instance.addReport(': 2,
      };
      counts.forEach((pattern, want) {
        expect(pattern.allMatches(src).length, want, reason: '「$pattern」の数');
      });
    });

    test('(f-3) シェルの送る所（_submit）が、値の関数と日報の入れ物へ、今の欄を取り違えずに渡している（値の関数を通らない物・経費の目安も）', () {
      final src = _codeOnly(home);
      expect('reportWorkContentPrefix('.allMatches(src).length, 1);
      expect('reportParkingFeeValue('.allMatches(src).length, 1);
      expect('reportCarpoolValue('.allMatches(src).length, 2);
      final flat = _flat(src);
      expect(
          flat.contains('final contentPrefix = reportWorkContentPrefix( '
              'transports: _transports, otherText: _otherCtrl.text, '
              'memoText: _transportMemoCtrl.text, );'),
          isTrue,
          reason: '作業内容の頭の字へ渡す欄');
      expect(
          flat.contains(
              'final parkingFeeValue = reportParkingFeeValue(_parkingCtrl.text);'),
          isTrue,
          reason: '駐車料金へ渡す欄');
      expect(
          flat.contains('final carpoolCompany = reportCarpoolValue( '
              'transports: _transports, carType: _carType, '
              'text: _carpoolCompanyCtrl.text, );'),
          isTrue,
          reason: '相乗りの会社名へ渡す欄');
      expect(
          flat.contains('final carpoolName = reportCarpoolValue( '
              'transports: _transports, carType: _carType, '
              'text: _carpoolNameCtrl.text, );'),
          isTrue,
          reason: '相乗りの氏名へ渡す欄');
      // 組んだ値を、日報の入れ物の同じ名前の所へ渡している。
      expect(flat.contains('workContent: contentPrefix + _workCtrl.text.trim(),'),
          isTrue);
      expect(flat.contains('parkingFee: parkingFeeValue,'), isTrue);
      expect(flat.contains('carpoolCompany: carpoolCompany,'), isTrue);
      expect(flat.contains('carpoolName: carpoolName,'), isTrue);
      // 値を組むのは、氏名の名簿へ足す所（await）より前＝読む順は取り出す前と同じ。
      final iPrefix = src.indexOf('reportWorkContentPrefix(');
      final iCarpoolName = src.indexOf('final carpoolName = reportCarpoolValue(');
      final iAwait = src.indexOf('await WorkerNameStore.instance.add(name);');
      final iAdd = src.indexOf('ReportStore.instance.addReport(');
      expect(iPrefix > 0 && iCarpoolName > iPrefix, isTrue);
      expect(iCarpoolName < iAwait && iAwait < iAdd, isTrue,
          reason: '値を組む所が、await の後ろへ動いている');
      // 経費の目安へ渡す欄と、日報の入れ物（WorkerReportItem）へ渡す残りの物（値の関数を通らない物）。
      //   最初の addReport が _submit の物（2つ目は、残業の報告の側）。
      expect(
          flat.contains(
              'final exp = reportExpenseSnapshot(_transports, _routeComparisons);'),
          isTrue,
          reason: '経費の目安へ渡す欄');
      final iExp = src.indexOf('final exp = reportExpenseSnapshot(');
      expect(iExp > 0 && iExp < iAwait, isTrue, reason: '経費の目安を組む所が、await の後ろへ動いている');
      final add = _flat(_callOf(src, 'ReportStore.instance.addReport'));
      expect(add.startsWith('ReportStore.instance.addReport(WorkerReportItem( name: name,'),
          isTrue,
          reason: '最初の addReport が、_submit の物でない');
      for (final p in [
        'name: name,',
        'transport: _transport,',
        'transportTypes: _transports.map((t) => t.name).toList(),',
        'workPhotoPaths: _workPhotoPaths,',
        'parkingPhotoPaths: _parkingPhotoPaths,',
        'gpsAddress: gpsAddr,',
        'gpsLat: _lat,',
        'gpsLon: _lon,',
        'originType: _originType,',
        'siteId: _selectedSiteId,',
        'shiftType: _shiftType,',
        'transportDistanceKm: exp.distanceKm, transportFuelCost: exp.fuelCost, '
            'transportFare: exp.fare, transportToll: exp.toll, '
            'transportBreakdown: exp.breakdown.isEmpty ? null : exp.breakdown,',
      ]) {
        expect(add.contains(p), isTrue, reason: '送る入れ物に「$p」が無い');
      }
    });

    test('(f-4) シェルが、段の部品と下のボタンと確認の画面の材料へ、今の欄と今の関数を渡している', () {
      final src = _codeOnly(home);
      for (final name in [
        'ReportStepSite', 'ReportStepMove', 'ReportStepWork',
        'ReportStepButtons', 'reportSnapshotFrom', 'transportsAfterTap',
        'confirmAddTransport',
      ]) {
        expect('$name('.allMatches(src).length, 1, reason: '$name( を使う所の数');
      }
      void has(String call, List<String> parts) {
        final body = _flat(_callOf(src, call));
        expect(body, isNotEmpty, reason: '$call( が無い');
        for (final p in parts) {
          expect(body.contains(p), isTrue, reason: '$call に「$p」が無い');
        }
      }

      has('ReportStepButtons', [
        'step: _reportStep,',
        'onGoStep: _goStep,',
        'checkBusy: _submitting,',
        'onCheck: _onCheckContent,',
      ]);
      has('ReportStepSite', [
        'siteName: _selectedSiteName,',
        'onTap: _showSitePicker,',
      ]);
      has('ReportStepWork', [
        'workController: _workCtrl,',
        'isListening: _isListening,',
        'onMicTap: _startVoice,',
        'workPhotoPaths: _workPhotoPaths,',
        'onWorkPhotosChanged: (v) => setState(() => _workPhotoPaths = v),',
      ]);
      has('ReportStepMove', [
        'originType: _originType,',
        'onOriginChanged: (type) async { setState(() => _originType = type);',
        "await prefs.setString('default_origin', type); await _calculateRoutes(); },",
        'transports: _transports,',
        'onTransportTap: (t) { final newSet = transportsAfterTap(_transports, t);',
        'onTransportDoubleTap: (t) async { final newSet = Set<TransportType>.from(_transports);',
        'final ok = await confirmAddTransport(context); if (!ok) return;',
        'transportMemoController: _transportMemoCtrl,',
        'carType: _carType,',
        "onCarTypeOwn: () { setState(() => _carType = 'own'); _saveLastTransport(); },",
        "onCarTypeCarpool: () { setState(() { _carType = 'carpool'; _parkingCtrl.clear(); _parkingPhotoPaths = []; }); _saveLastTransport();",
        '_ensureColleaguesLoaded(); },',
        'routeTransport: _transport,',
        'routeComparisons: _routeComparisons,',
        'loadingRoutes: _loadingRoutes,',
        'routeFailed: _routeFailed,',
        'routeFromCache: _routeFromCache,',
        'onRouteRetry: _calculateRoutes,',
        'carpoolCompanyController: _carpoolCompanyCtrl,',
        'carpoolCompanyCandidatesOf: () => _carpoolCompanyResults',
        'onCarpoolCompanyChanged: _onCarpoolCompanyChanged,',
        'carpoolNameController: _carpoolNameCtrl,',
        'carpoolNameCandidatesOf: _carpoolNameCandidates,',
        'onCarpoolNameChanged: (_) => _saveDraft(),',
        'parkingFeeController: _parkingCtrl,',
        'onParkingFeeChanged: (_) => _saveDraft(),',
        'parkingPhotoPaths: _parkingPhotoPaths,',
        'onParkingPhotosChanged: (v) => setState(() => _parkingPhotoPaths = v),',
      ]);
      has('reportSnapshotFrom', [
        'dateLabel: _formDateLabel,',
        'shiftLabel: _shiftLabel,',
        'siteId: _selectedSiteId,',
        'siteName: _selectedSiteName,',
        'originType: _originType,',
        'transports: _transports,',
        'carType: _carType,',
        'routeComparisons: _routeComparisons,',
        'parkingText: _parkingCtrl.text,',
        'carpoolCompanyText: _carpoolCompanyCtrl.text,',
        'carpoolNameText: _carpoolNameCtrl.text,',
        'workText: _workCtrl.text,',
        'workPhotoCount: _workPhotoPaths.length,',
        'parkingPhotoCount: _parkingPhotoPaths.length,',
      ]);
      // 移動手段を押した時の中身（片付けと保存）は、シェルの側に今のまま在る。
      final move = _flat(_callOf(src, 'ReportStepMove'));
      expect(
          "_saveWorkStatus('moving'); _saveDraft(); _saveLastTransport();"
              .allMatches(move)
              .length,
          2,
          reason: '1回押した時と2度押した時の、保存の3つの並び');
      // 確認の画面は、今までどおり「内容を確認する」の先でだけ開き、送るのは _submit。
      final flat = _flat(src);
      expect(
          flat.contains('ReportConfirmScreen( initial: _buildSnapshot(), '
              'currentOf: _buildSnapshot, onSend: _submit, '
              'isDone: () => _todayReportDone, )'),
          isTrue);
    });

    test('(f-5) 新しい本の約束：時計・端末の保存・通信を読まない／区切りの字は目に見える書き方で1か所', () {
      final stepsCode = _codeOnly(steps);
      final partsCode = _codeOnly(parts);
      for (final word in ['DateTime.now', 'SharedPreferences', 'http.']) {
        expect(stepsCode.contains(word), isFalse, reason: '$steps に $word が在る');
      }
      for (final word in ['DateTime.now', 'SharedPreferences']) {
        expect(partsCode.contains(word), isFalse, reason: '$parts に $word が在る');
      }
      // 二者比較：シェルの本は、時計も端末の保存も読んでいる（同じ見方で在ると分かる）。
      final homeCode = _codeOnly(home);
      expect(homeCode.contains('DateTime.now'), isTrue);
      expect(homeCode.contains('SharedPreferences'), isTrue);
      // 差の見張りの区切りは、目に見える書き方（\u0001）で1か所。生の字（符号 1）は lib のどこにも無い。
      expect(r".join('\u0001')".allMatches(partsCode).length, 1);
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        expect(f.readAsBytesSync().contains(1), isFalse,
            reason: '${f.path} に、目に見えない字（符号 1）が在る');
      }
    });

    test('(f-6) シェル：移動手段を押した時の中身・会社名の候補の組み方・段の出し分け・上の印', () {
      final src = _codeOnly(home);
      final flat = _flat(src);
      final move = _flat(_callOf(src, 'ReportStepMove'));
      // 1回押した時：選ぶ → 車が無ければ駐車料金と写真を片付ける → 状態を替える → 保存の3つ。
      //   （字は、行の終わりの説明文の手前まで。説明文だけの行は _codeOnly が除いている）
      expect(
          move.contains(
              'onTransportTap: (t) { final newSet = transportsAfterTap(_transports, t); '
              'if (!newSet.contains(TransportType.car)) { _parkingCtrl.clear(); _parkingPhotoPaths = []; } '
              "setState(() => _transports = newSet); _saveWorkStatus('moving'); _saveDraft(); _saveLastTransport();"),
          isTrue,
          reason: '1回押した時の中身（片付けの条件・保存の並び）');
      // 2度押した時：足す → 2つ以上なら確かめの窓 → 車が無ければ片付ける → 状態を替える → 保存の3つ。
      expect(
          move.contains(
              'onTransportDoubleTap: (t) async { final newSet = Set<TransportType>.from(_transports); '
              'if (!newSet.contains(t)) { newSet.add(t); if (newSet.length >= 2) { if (!context.mounted) return; '
              'final ok = await confirmAddTransport(context); if (!ok) return; } '
              'if (!newSet.contains(TransportType.car)) { _parkingCtrl.clear(); if (mounted) setState(() => _parkingPhotoPaths = []); } '
              "if (mounted) setState(() => _transports = newSet); _saveWorkStatus('moving'); _saveDraft(); _saveLastTransport();"),
          isTrue,
          reason: '2度押した時の中身（確かめの窓を出す条件・片付けの条件・保存の並び）');
      // 会社名の候補：検索の答えの company_name を、前後の空白を除いて、空でない物だけ。
      expect(
          move.contains('carpoolCompanyCandidatesOf: () => _carpoolCompanyResults '
              ".map((c) => (c['company_name'] as String? ?? '').trim()) "
              '.where((s) => s.isNotEmpty) .toList(),'),
          isTrue,
          reason: '会社名の候補の組み方');
      // 段の出し分け：段1＝現場・段2＝移動・段3＝作業（どれも1か所ずつ）。上の印へは今の段。
      for (final n in [1, 2, 3]) {
        expect('if (_reportStep == $n)'.allMatches(src).length, 1,
            reason: '段 $n の出し分けの数');
      }
      final i1 = flat.indexOf('if (_reportStep == 1) ...[');
      final iSite = flat.indexOf('ReportStepSite(');
      final i2 = flat.indexOf('if (_reportStep == 2) ...[ ReportStepMove(');
      final i3 = flat.indexOf('if (_reportStep == 3) ...[ ReportStepWork(');
      expect(i1 >= 0 && i1 < iSite && iSite < i2 && i2 < i3, isTrue,
          reason: '段と部品の組が違う（$i1・$iSite・$i2・$i3）');
      expect(flat.contains('ReportStepIndicator(current: _reportStep),'), isTrue,
          reason: '上の印へ今の段を渡していない');
    });

    test('(f-7) シェル：名前だけ替えた呼び出し（現場のシート・音声の窓）の中身', () {
      final src = _codeOnly(home);
      final flat = _flat(src);
      // 現場のシート：選んだ物を今の欄へ入れて、端末に覚える（送る日報の site_id の元）。
      expect('ReportSitePickerSheet('.allMatches(src).length, 1,
          reason: 'ReportSitePickerSheet を呼ぶ所が1つでない');
      expect(
          flat.contains('ReportSitePickerSheet( selectedSiteId: _selectedSiteId, '
              'onSelected: (id, name) { setState(() { _selectedSiteId = id; _selectedSiteName = name; }); '
              '_saveLastSite(id, name); }, )'),
          isTrue,
          reason: '現場のシートで選んだ物を、今の欄へ入れて覚えていない');
      // 音声の窓：決めた字を、作業内容の後ろへ「。」でつなぐ（空なら、その字だけ）。窓は立てない（頭の★）ので、字で見る。
      expect('ReportVoiceInputDialog('.allMatches(src).length, 1,
          reason: 'ReportVoiceInputDialog を呼ぶ所が1つでない');
      expect(
          flat.contains('ReportVoiceInputDialog( manager: _speechMgr, onConfirm: (text) { Navigator.pop(ctx); '
              r"setState(() { _workCtrl.text = _workCtrl.text.isEmpty ? text : '${_workCtrl.text}。$text'; }); }, "
              'onCancel: () { _speechMgr.cancel(); Navigator.pop(ctx); }, )'),
          isTrue,
          reason: '音声の窓で決めた字を、作業内容の後ろへつないでいない');
    });

    test('(f-8) 休憩の短縮のシート：名前だけ替えた呼び出し4つ（欄の名2つ・入力の枠・申告のボタン）の中身と並び', () {
      final src = _codeOnly(home);
      final flat = _flat(src);
      // シェルの本で、この3つの部品を直に呼ぶのは、休憩の短縮のシートの4か所だけ（今日の日報のフォームは、段の部品の中で呼ぶ）。
      expect('ReportFieldLabel('.allMatches(src).length, 2,
          reason: 'ReportFieldLabel を呼ぶ所が2つでない');
      expect('ReportFormInputShell('.allMatches(src).length, 1,
          reason: 'ReportFormInputShell を呼ぶ所が1つでない');
      expect('ReportOutlineActionButton('.allMatches(src).length, 1,
          reason: 'ReportOutlineActionButton を呼ぶ所が1つでない');
      expect(
          _flat(_callOf(src, 'ReportFormInputShell')),
          'ReportFormInputShell( icon: Icons.edit_note, child: TextField( controller: _reasonCtrl, '
          'onChanged: (_) { if (_error != null) setState(() => _error = null); }, '
          "decoration: const InputDecoration( hintText: '例）現場の都合で休憩を取れなかった', border: InputBorder.none, "
          'hintStyle: TextStyle(color: FieldTokens.textFaint, fontSize: 12), contentPadding: EdgeInsets.zero, ), '
          'style: const TextStyle( color: FieldTokens.textBody, fontSize: 13), ), )',
          reason: '理由の入力の枠の中身が違う');
      expect(_flat(_callOf(src, 'ReportOutlineActionButton')),
          "ReportOutlineActionButton( label: '申告する', busy: _submitting, onTap: _submit, )",
          reason: '申告のボタンの中身が違う');
      // 並び：題 → 実休憩の欄の名 → ※ → 理由の欄の名 → 入力の枠 → 申告のボタン。
      final iTitle = flat.indexOf("const Text('休憩の短縮を申告',");
      final iLabel1 = flat.indexOf("const ReportFieldLabel('実休憩'),");
      final iNote = flat.indexOf("'※実際に取れた休憩の合計を選んでください'");
      final iLabel2 = flat.indexOf("const ReportFieldLabel('理由（必須）'),");
      final iShell = flat.indexOf('ReportFormInputShell( icon: Icons.edit_note,');
      final iButton = flat.indexOf("ReportOutlineActionButton( label: '申告する',");
      expect(
          iTitle >= 0 &&
              iTitle < iLabel1 &&
              iLabel1 < iNote &&
              iNote < iLabel2 &&
              iLabel2 < iShell &&
              iShell < iButton,
          isTrue,
          reason: '休憩の短縮のシートの並びが違う（$iTitle・$iLabel1・$iNote・$iLabel2・$iShell・$iButton）');
    });
  });
}
