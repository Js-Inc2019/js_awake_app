// lib/screens/home_screen.dart
// JsMainShell — 全画面共通 2段AppBar + 永続BottomBar + IndexedStack

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/photo_strip_field.dart';
import '../widgets/punch_remind_dialog.dart';
import '../widgets/search_suggest_field.dart';
import '../widgets/closing_period_dialog.dart';
// 代休を取る受け皿。★「本日休み」の画面（rest_day_screen.dart）と同じ1本を使う
//   ＝入口は2つでも、選ばせる部品と書く口は1つ（同じ操作を2通りに書かない）。
import '../widgets/comp_off_dialog.dart';
import '../utils/business_date.dart';

import '../main.dart'
    show
        TransportType,
        ReportStore,
        WorkerReportItem,
        SpeechManager,
        WorkerNameStore,
        fetchGpsAddress,
        showJsSnackbar,
        showConfirmDialog,
        NotificationManager,
        OvertimeDialog;
import '../core/theme/field_tokens.dart';
import 'revision_inbox_screen.dart';
// 承認タブ（ReviewTab）の日付行タップで開く「その日の報告」画面。
import 'approval_day_screen.dart';
import 'site_quick_register_screen.dart';
// company_link_screen.dart の import は撤去（AppBar の 🤝 協力申請アイコンを撤去し
// 当ファイルからの参照が無くなったため。ファイル本体は削除していない）。
// MonthlyHistoryBody は management_history_screen.dart（履歴セグメント）側へ移ったため
// この show リストから外した。JsStatChip/JsReportTile は当ファイル内で使用中。
import 'monthly_history_screen.dart' show JsStatChip, JsReportTile;
// 取消済の判定と「今日やる仕事」に載せる条件は
// lib/utils/report_cancel_gate.dart の1本だけを使う（この画面に手書きしない）。
import '../utils/report_cancel_gate.dart'
    show isCancelledReport, isPendingApproval, isRevisionRequested,
         withReportStatus;
import 'day_reports_screen.dart';
import 'management_history_screen.dart';
import 'profile_screen.dart';
import 'notification_list_screen.dart';
import 'share_hub_screen.dart';
import '../services/notification_service.dart';
// CalendarTab が会社休日(/attendance/holidays/my)と祝日(/attendance/holidays/jp)を取るため。
import '../services/work_mode_service.dart';
import 'after_report_screen.dart';
import 'punch_screen.dart';
import '../widgets/approval_dialogs.dart';
import '../widgets/report_photos.dart';
import '../services/api_result.dart';
import '../services/auth_service.dart';
import '../services/reports_service.dart';
import '../services/site_service.dart';
import '../services/company_service.dart';
import '../services/fcm_service.dart';
import '../services/routes_service.dart';
import '../services/weather_service.dart';
import '../services/profile_service.dart';
import '../services/worker_service.dart';


// ─────────────────────────────────────────────
// 天気データモデル
// ─────────────────────────────────────────────
class _WeatherData {
  final String icon;
  final String desc;
  final double tempC;

  /// 降水確率(%)。★null＝BE が返していない（未取得）。0 とは別の意味。
  ///   `?? 0` を足さない（0% という嘘を作らないため・3状態規約）。
  final int? precipPct;
  final int humidity;
  final double? windSpeed; // m/s

  /// WBGT（暑さ指数）。BE の wbgt.value（weatherEngine.js は日本生気象学会
  /// Ver.4 換算表のルックアップ）。★端末では計算しない＝2アプリで同じ数字になる。
  final double? wbgtValue;

  /// WBGT の危険度。BE の wbgt.level（'safe'|'caution'|'warning'|'severe'|'danger'）。
  final String? wbgtLevel;

  /// WBGT の説明文。BE の wbgt.message。
  /// ★2段式（ボス裁定）で表示は退役した。受けだけ残すのは、BE が返している値を
  ///   モデルで捨てないため（表示を戻すときに取得側から直す必要が無い）。
  final String? wbgtMessage;

  /// 気象アラート。BE の alert.level / alert.message（weatherEngine.js の computeAlert）。
  /// message は絵文字込みの完成文＝端末で組み立て直さない。
  final String? alertLevel;
  final String? alertMessage;

  /// 体感温度(℃)。★モデルで受けるだけ。表示追加はしない（段7の範囲外）。
  final double? feelsLike;

  /// 地点名。★同上（受けるだけ・未表示）。
  final String? location;

  const _WeatherData({
    required this.icon,
    required this.desc,
    required this.tempC,
    required this.precipPct,
    this.humidity = 60,
    this.windSpeed,
    this.wbgtValue,
    this.wbgtLevel,
    this.wbgtMessage,
    this.alertLevel,
    this.alertMessage,
    this.feelsLike,
    this.location,
  });
}

class _ForecastDay {
  final String weekday;
  final String icon;
  final double maxC;
  final double minC;

  /// 日別の降水確率(%)。★null＝未取得（0% と区別する）。
  final int? precipPct;
  const _ForecastDay({
    required this.weekday,
    required this.icon,
    required this.maxC,
    required this.minC,
    required this.precipPct,
  });
}

// ─────────────────────────────────────────────
// WBGT の表示ロジック
//
// ★段7で「計算」は退役した。旧実装（Stull 2011 の湿球温度近似）は
//   端末側の独自式で、OFFICE 側の式とも BE とも違う数字を出していた。
//   WBGT の真実源は BE ただ一つ（日本生気象学会 Ver.4 換算表）。
// ★英語 level → 日本語ラベルの対応は OFFICE(dashboard_screen.dart の
//   _kWbgtLabelJa)と同一。2アプリで同じ値・同じ言葉にする。
// ★色だけは表示ロジックとして残す。閾値 21/25/28/31 は環境省指針で、
//   トークン（FieldTokens.wbgt*）も現行のまま＝見た目は変わらない。
// ─────────────────────────────────────────────
const Map<String, String> _kWbgtLabelJa = {
  'safe':    'ほぼ安全',
  'caution': '注意',
  'warning': '警戒',
  'severe':  '厳重警戒',
  'danger':  '危険',
};

/// WBGT を表示できるか（値とラベルの両方が揃っているか）。
/// ★非表示規約の単一の判定。バッジ本体（_WbgtBadge）と、行ごと出すかの
///   ゲート（_PunchWeatherPanelState.build）が同じ式を見るようにする。
///   2か所で別々に書くと、片方だけ条件が古くなって「枠だけ出る」等が起きる。
/// ★未取得のときに '--' を置かないのは 3状態規約と同じ理由＝
///   「取れていない」を「そういう値」に化けさせない。
bool _hasWbgt(_WeatherData? w) =>
    w != null && w.wbgtValue != null && _kWbgtLabelJa[w.wbgtLevel ?? ''] != null;

Color _wbgtColor(double wbgt) {
  if (wbgt < 21) return FieldTokens.wbgtSafe;
  if (wbgt < 25) return FieldTokens.wbgtCaution;
  if (wbgt < 28) return FieldTokens.wbgtWarning;
  if (wbgt < 31) return FieldTokens.wbgtSevere;
  return FieldTokens.wbgtDanger;
}

// ─────────────────────────────────────────────
// 天気取得
//
// ★段7で BE 統一エンジン（GET /tools/weather）1本になった。
//   退役したもの:
//     旧 OWM 経路 / 旧フォールバック経路 … 端末から気象APIを直接叩いていた2本。
//                                   フォールバックは BE 内で完結する。
//     旧アイコン変換2種            … 天気コード→絵文字の変換表が2系統あった。
//                                   BE が絵文字を返す（weatherEngine.js の weatherEmoji）。
//     旧WBGT計算・閾値ラベル       … 端末側の独自式とラベル判定。
//                                   真実源は BE（日本生気象学会 Ver.4 換算表）。
//   ＝FIELD と OFFICE が同じ数字・同じ絵文字・同じ言葉になる。
//
// ★測位できていない（lat/lon が無い）ときは呼ばない。BE は lat/lon 必須で
//   400 を返すため（tools_weather.js の「lat, lon が必要です」）、投げる前にここで止める。
// ★失敗（非200・401・通信不成立）は data を返さず、呼び手が静かに劣化させる。
//   天気の失敗で snackbar を出さない・ログイン画面へ飛ばさない（現行どおり）。
// ─────────────────────────────────────────────
Future<(_WeatherData?, List<_ForecastDay>)> _fetchWeatherFull({
  double? lat,
  double? lon,
}) async {
  if (lat == null || lon == null) return (null, <_ForecastDay>[]);

  final res  = await WeatherService().fetchWeather(lat: lat, lon: lon);
  final body = res.data;
  if (!res.ok || body == null) return (null, <_ForecastDay>[]);

  final cur   = body['current'] as Map<String, dynamic>?;
  final wbgt  = body['wbgt']    as Map<String, dynamic>?;
  final alert = body['alert']   as Map<String, dynamic>?;

  // temp が無い＝天気そのものが組めていない。空を返して現行の「取得中...」に倒す。
  final temp = (cur?['temp'] as num?)?.toDouble();
  if (temp == null) return (null, <_ForecastDay>[]);

  // ★`?? 0` を付けない。キーが無い＝BE が返していない（未取得）。
  //   0% という嘘を作らず null のまま持ち、表示側で '—' にする（3状態規約）。
  final current = _WeatherData(
    icon:         cur?['icon']    as String? ?? '🌤️',
    desc:         cur?['weather'] as String? ?? '',
    tempC:        temp,
    precipPct:    (cur?['rain_probability'] as num?)?.toInt(),
    humidity:     (cur?['humidity']   as num?)?.toInt() ?? 60,
    windSpeed:    (cur?['wind_speed'] as num?)?.toDouble(),
    wbgtValue:    (wbgt?['value']     as num?)?.toDouble(),
    wbgtLevel:    wbgt?['level']      as String?,
    wbgtMessage:  wbgt?['message']    as String?,
    alertLevel:   alert?['level']     as String?,
    alertMessage: alert?['message']   as String?,
    feelsLike:    (cur?['feels_like'] as num?)?.toDouble(),
    location:     body['location']    as String?,
  );

  final weekly = (body['weekly'] as List?) ?? const [];
  final forecast = weekly
      .whereType<Map>()
      .map((d) => _ForecastDay(
            weekday:   d['day']  as String? ?? '',
            icon:      d['icon'] as String? ?? '🌡️',
            maxC:      ((d['max'] as num?) ?? 0).toDouble(),
            minC:      ((d['min'] as num?) ?? 0).toDouble(),
            precipPct: (d['rain_probability'] as num?)?.toInt(),
          ))
      .toList();

  return (current, forecast);
}

// ─────────────────────────────────────────────
// リトライヘルパー
//
// ★段6で Service 移設した後もここに残す。再試行は「1リクエスト＝1結果」の
//   ApiResult には載らない、この画面固有の方針だから（Service へ入れると
//   同じエンドポイントを叩く revision_inbox_screen まで3回叩き始める）。
// ★試行ごとに制限時間を伸ばす（60 / 80 / 100秒）挙動は移設前のまま。
//   その秒数を fn へも渡すのは、Service 側の .timeout() が先に発火して
//   ここで決めた上限が意味を失うのを防ぐため（Service は timeout を引数で受ける）。
// ─────────────────────────────────────────────
Future<T> _withRetry<T>(
  Future<T> Function(Duration timeout) fn, {
  int maxAttempts = 3,
  Duration firstTimeout = const Duration(seconds: 60),
}) async {
  Object? lastErr;
  for (var i = 0; i < maxAttempts; i++) {
    final attemptTimeout = firstTimeout + Duration(seconds: i * 20);
    try {
      return await fn(attemptTimeout).timeout(attemptTimeout);
    } catch (e) {
      lastErr = e;
      if (i < maxAttempts - 1) await Future.delayed(Duration(seconds: 1 << i));
    }
  }
  throw lastErr!;
}

// ─────────────────────────────────────────────
// JsMainShell — 全画面共通シェル
// ─────────────────────────────────────────────
// ============================================================
// ReportTabNavigator — 日報作成画面（JsMainShell の日報タブ index0）への
// 単一の入口。通知一覧の 'report_remind' タップと FCM 'report_reminder' の
// 両方が「■2と同じルート」でここを経由する。
// シェルが initState で register / dispose で unregister する。
// go() は成功で true、シェル未生成時は false（呼び出し側はフォールバック可）。
// ============================================================
class ReportTabNavigator {
  ReportTabNavigator._();
  static VoidCallback? _handler;
  static void register(VoidCallback cb) => _handler = cb;
  static void unregister(VoidCallback cb) {
    if (identical(_handler, cb)) _handler = null;
  }

  static bool go() {
    final h = _handler;
    if (h == null) return false;
    h();
    return true;
  }
}

// 打刻のお知らせ（FCM: punch_remind_in / punch_remind_out）の2択ダイアログを、
// 画面外（fcm_service.dart）から開くための橋。
//   ・上の ReportTabNavigator と同型。違いは引数を3つ取ることだけ。
//   ・showDialog に渡す context は「生きている画面の State」のもの＝lib 配下の
//     既存 showDialog 35箇所と同じ流儀。navigatorKey.currentContext は使わない
//     （当リポジトリに showDialog での使用実績が無いため）。
//   ・未登録（シェル未生成）のときは false を返し、呼び手が通知一覧へ
//     フォールバックする（fcm_service.dart の report_reminder と同じ形）。
typedef PunchRemindHandler =
    void Function(String side, String shiftType, String bizDate);

class PunchRemindDialogNavigator {
  PunchRemindDialogNavigator._();
  static PunchRemindHandler? _handler;
  static void register(PunchRemindHandler cb) => _handler = cb;
  static void unregister(PunchRemindHandler cb) {
    if (identical(_handler, cb)) _handler = null;
  }

  static bool go(String side, String shiftType, String bizDate) {
    final h = _handler;
    if (h == null) return false;
    h(side, shiftType, bizDate);
    return true;
  }
}

class JsMainShell extends StatefulWidget {
  const JsMainShell({super.key, this.isForeman = false, this.restoreWorkStatus});
  final bool isForeman;
  final String? restoreWorkStatus;

  @override
  State<JsMainShell> createState() => _JsMainShellState();
}

class _JsMainShellState extends State<JsMainShell> with WidgetsBindingObserver {
  // ─── タブ ───
  int _tabIndex = 0;

  // 「管理・履歴」タブ(index1)の中で開きたいセグメントの指定。
  //   ・ラベルで指定する（management_history_screen.dart の _labels の理由による。
  //     枚数と並びが職人2枚/職長4枚で異なるため index は渡さない）。
  //   ・_mgmtSegmentRequestId は「今もう一度開いてほしい」の通し番号。
  //     管理・履歴画面は IndexedStack の子で作り直されないため、
  //     同じラベルを渡し直すだけでは切り替わらない。要求のたびに +1 する。
  //   ★ボトムバッジからのタブ切替(_BottomTabItem の onTap)はこの2値を触らない＝挙動不変。
  String? _mgmtSegment;
  int _mgmtSegmentRequestId = 0;

  // ─── ユーザー情報 ───
  bool _initialLoading = true;
  String _companyName = "";
  String _userName = '';
  int _revisionCount = 0;
  int _pendingApprovalCount = 0;
  // _linkCount（協力申請の未処理件数）は撤去した。
  // 唯一の読み手だった AppBar の 🤝 アイコンを撤去したため、
  // 保持し続けると unused_field 警告になる。取得処理 _loadLinkCount() も併せて撤去
  // （GET /company-links/my を毎起動叩くだけで誰も読まない状態を残さないため）。
  // ※ company_link_screen.dart 本体は削除していない。
  int _unreadCount   = 0; // 通知未読件数（0=バッジ非表示・失敗時も0でfail-soft）

  // 日報タブ(index0)への遷移ハンドラ（ReportTabNavigator へ登録/解除する実体・
  // register/unregister で identical 比較するため単一インスタンスを保持）
  late final VoidCallback _openReportTabCb = _goReportTab;
  void _goReportTab() {
    if (mounted) _setTab(0);
  }

  // 打刻のお知らせ2択ダイアログの表示ハンドラ（PunchRemindDialogNavigator へ
  // 登録/解除する実体・register/unregister で identical 比較するため単一
  // インスタンスを保持。直上の _openReportTabCb と同じ流儀）
  late final PunchRemindHandler _punchRemindCb = _openPunchRemindDialog;
  void _openPunchRemindDialog(String side, String shiftType, String bizDate) {
    if (!mounted) return;
    // 当 State の context を渡す＝ダイアログは生きている画面の上に出る。
    unawaited(showPunchRemindFlow(context,
        side: side, shiftType: shiftType, bizDate: bizDate));
  }

  // 日報フォームを push した先のページを再描画するためのキー。
  // フォームは当 State のフィールド（_transports/_workCtrl/_gpsAddress/_todayReportDone 等）を
  // 直接読むため、push 先は当 State の setState では自動再描画されない。
  // そこで setState をオーバーライドし、既存の setState 呼び出し（約50箇所）を1つも
  // 書き換えずに push 先へも再描画を伝播させる。
  final GlobalKey<_ReportFormPageState> _reportPageKey = GlobalKey<_ReportFormPageState>();

  // 共有/設定タブの Body へアクセスするキー。シェルが Body の公開 State 経由で
  // 「タブ進入時の再取得」「編集」を実行するために持つ
  // （RevisionInboxBodyState を GlobalKey で使う既存流儀と同型）。
  //
  // ★通知タブは退役した（ボトム index2 は「共有」）。旧 _notifBodyKey は
  //   AppBar の「すべて既読」をタブ内 Body へ届けるためのものだったが、
  //   通知は AppBar の🔔から NotificationListScreen（自前 AppBar に
  //   「すべて既読」を持つ・notification_list_screen.dart の canMarkAllRead / markAllRead）を push する形へ
  //   戻したので、シェル側から Body を掴む必要が無くなった＝キーごと退役。
  final GlobalKey<ShareHubBodyState> _shareBodyKey =
      GlobalKey<ShareHubBodyState>();
  final GlobalKey<ProfileBodyState> _profileBodyKey =
      GlobalKey<ProfileBodyState>();

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _reportPageKey.currentState?.refresh();
  }

  // ─── GPS ───
  String _gpsAddress = '';
  // fetchGpsAddress(main.dart) の status をそのまま保持する。
  // '' = 未取得 / 'ok' / 'address_failed'（座標フォールバック）/ 'gps_failed'
  String _gpsStatus = '';
  bool _gpsLoading = false;
  double? _lat;
  double? _lon;

  // ─── 作業現場選択（null=対象なし） ───
  // 裁定A+引き継ぎ: 初回は「対象なし」がデフォルト。以降は前回選んだものを prefs から復元する。
  // 「対象なし」を選んだ場合もそれが保存され、次回のデフォルトになる（毎回上書き・日付をまたいでも維持）。
  String? _selectedSiteId;
  String? _selectedSiteName;

  // ─── 天気 ───
  _WeatherData? _weather;
  List<_ForecastDay> _forecast = [];
  bool _weatherLoading = false;

  // ─── 季節 ───
  DateTime? _healthCheckDate;

  // ─── 起点 ───
  String _originType = 'home';
  String _companyAddress = '';

  // ─── 移動手段 ───
  Set<TransportType> _transports = {};
  TransportType get _transport => _transports.isEmpty ? TransportType.none : _transports.first;
  String _carType = 'own';
  final _carpoolNameCtrl       = TextEditingController();
  // 作業2/3: 相乗り相手の会社名（サジェスト付き）。氏名 _carpoolNameCtrl と2欄構成。
  final _carpoolCompanyCtrl    = TextEditingController();
  // 作業3: 会社名サジェストの候補（searchCompanies の結果を親stateに保持し candidates を再生成）
  List<Map<String, dynamic>> _carpoolCompanyResults = [];
  Timer? _carpoolCompanyDebounce;
  // E-3: 相乗り氏名サジェストの候補（自社の同僚氏名）。/workers/colleagues の結果を保持。
  //   会社スコープはBEのJWT由来（他社を指定する余地なし）。一度だけ取得する。
  List<String> _carpoolColleagues = [];
  bool _carpoolColleaguesLoaded = false;
  final _transportMemoCtrl = TextEditingController();
  Map<String, dynamic> _routeComparisons = {};
  bool _loadingRoutes = false;
  // ルート取得が失敗した（timeout/network/http/空）。UIで正直に出すためのフラグ。
  bool _routeFailed = false;
  // いま出している _routeComparisons が鍵付きキャッシュ由来か（「前回の目安」表示用）。
  bool _routeFromCache = false;
  // 世代トークン。_calculateRoutes 開始時に採番し、setState 直前に最新か検査して
  // 古い結果を破棄する（GPS再取得 × 起点変更 の競合根治）。
  int _routeGen = 0;

  // ─── 作業内容 ───
  final _workCtrl    = TextEditingController();
  final _otherCtrl   = TextEditingController();
  final _parkingCtrl = TextEditingController();
  List<String> _workPhotoPaths = [];
  List<String> _parkingPhotoPaths = [];
  bool _isListening = false;
  final _speechMgr = SpeechManager();

  // ─── 勤務区分（日勤/夜勤）───
  // 送信データ組み立てまで保持。業務日(report_date)の夜勤補正とBEへの shift_type 送出に使う。
  String _shiftType = 'day';   // 'day'|'night'

  // ─── 送信 ───
  bool _submitting = false;
  // 完了ビューが日報タブ(index1)を占有中か。true の間フォームへ到達不能＝二重報告防止の要
  bool _todayReportDone = false;
  // K1: 打刻状態のミラー。真実源は PunchScreen が fetchToday から受け取った値で、
  //   onPunchStateChanged(punch_screen.dart) 経由で流れてくるだけ＝ここで判定は作らない。
  //   初期値は「実打刻でない・未打刻」＝完了ビューの出し分けが最も緩い側（従来と同じ見え方）。
  bool _punchIsActual = false;
  bool _punchedInToday = false;
  bool _punchedOutToday = false;
  // N3: 退勤打刻の実行口。PunchScreen が initState で自分の _doPunch('out') 経路を
  //   渡してくる（onPunchOutHandlerReady）。ここは受け皿であって打刻ロジックではない
  //   ＝判定式もAPI呼び出しもこちら側には作らない。未マウント時は null のまま。
  Future<void> Function()? _punchOutFromHome;

  // K3(Q8): みなしの「締め」。work_status == 'closed' の日は true。
  //   done と同じく報告済み扱い（_readReportDone）だが、完了ビューのアクションを
  //   「追加の申告」だけに絞るために done と区別して保持する。
  bool _todayClosed = false;

  // 完了ビューに渡す送信成否。送信直後経路は実成否、復元経路は暫定true
  // （S4-②: 送信成否がtoday_work_statusに永続化されていないため復元時の実態は不明。今回は未修正）
  bool _lastSentOk = true;

  // ─── 日報フォームのステップ（現場→移動→作業→確認）───
  // 1=現場 / 2=移動 / 3=作業。確認(=4)は既存の別画面 _ConfirmSendScreen が担うため
  // このフィールドは 1〜3 しか取らない（_onCheckContent → Navigator.push の経路は不変）。
  int _reportStep = 1;
  // ステップ切替時にスクロールを先頭へ戻すためのコントローラ。
  final ScrollController _reportScrollCtrl = ScrollController();

  /// スクロール位置を先頭へ。まだ描画されていない（hasClients=false）ときは何もしない。
  void _scrollReportTop() {
    if (_reportScrollCtrl.hasClients) _reportScrollCtrl.jumpTo(0);
  }

  /// フォーム内のステップ移動（「次へ」「戻る」）。
  /// ★ブロックしない＝バリデーションは一切足さない（送信中断3件は _submit のまま）。
  void _goStep(int s) {
    setState(() => _reportStep = s);
    _scrollReportTop();
  }

  /// エラー時の自動ジャンプ。確認画面(_ConfirmSendScreen)を1枚 pop してフォームへ戻り、
  /// 指定ステップを開いてスクロールを先頭へ戻す。
  ///   ・_submit の呼び手は確認画面の onSend のみ（実測・1箇所のみ）。
  ///     よって pop 対象は常に確認画面1枚。
  ///   ・pop 後も _ConfirmSendScreenState は退場アニメ中 mounted のままだが、
  ///     ②③の中断経路は _todayReportDone が false のため
  ///     `if (widget.isDone()) Navigator.pop(context);` は発火せず二重popしない。
  void _jumpToStep(int s) {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
    setState(() => _reportStep = s);
    // pop 直後はまだ旧ルートが載っているため、次フレームでスクロールを戻す。
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollReportTop());
  }

  // ★裁定A+引き継ぎ: 現場は常にデフォルトが入っている（初回=「対象なし」／以降は前回選択）。
  //   よって「未選択で止める」場面が構造的に存在せず、必須判定・琥珀バッジ・
  //   スクロール対象（_alertSite / _secSiteKey）は全て撤去した。嘘の記号を残さない。

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ReportTabNavigator.register(_openReportTabCb);
    PunchRemindDialogNavigator.register(_punchRemindCb);
    _loadCacheAndStart();
    _loadUnreadCount();
    _restoreTabIndex();
    _loadOriginPrefs();
    _initTodayReportDone();
    _restoreShiftType();
    _restoreLastSite();
    _restoreLastTransport();
    _workCtrl.addListener(_onWorkContentChanged);
    if (widget.restoreWorkStatus != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _restoreDraft(widget.restoreWorkStatus!));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await FcmService.ready;
      final d = FcmService.pendingTapData;
      if (d != null) {
        FcmService.pendingTapData = null;
        FcmService().handleNotificationTap(d);
      }
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _speechMgr.ensureReady();
        ReportStore.instance.retryPending();
      }
    });
  }

  void _onWorkContentChanged() {
    if (_workCtrl.text.isNotEmpty) {
      _saveWorkStatus('working');
      _saveDraft();
    }
  }

  // S5b追補(B案): 勤務状態はシフト別の2キーに分離して保持する。
  //   report_done_day   = '<業務日>|<status>'   例 '2026-07-23|done'
  //   report_done_night = '<業務日>|<status>'
  // 業務日は暦日ではなく businessDateForShift(shift) （夜勤の深夜〜午前は始業日=前日）で、
  // 送信される report_date と同じ物差しになる。
  // シフトごとに独立しているため、夜勤done後に日勤へ切り替えても夜勤のdone記録は消えない。
  static String reportDoneKey(String shiftType) => 'report_done_$shiftType';

  // 現 _shiftType のキーにのみ書く（他シフトのキーには触れない）。
  Future<void> _saveWorkStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    final bizDate = businessDateForShift(_shiftType, DateTime.now());
    await prefs.setString(reportDoneKey(_shiftType), '$bizDate|$status');
  }

  // 現 _shiftType のキーを読み、業務日が一致するときだけ status 文字列を返す。
  // 一致しない・欠落・不正形式はすべて null（＝当日ぶんの記録なし）。
  // 旧形式（today_date / today_work_status / report_done_shift の3キー）は読み捨て。
  // 旧キーしか無い端末は新キーが null → 未完了＝フォームに落ちるだけで袋小路なし。
  // 送信済みデータはBEにあるため、ここで無理に移行するより開ける方を選ぶ。
  Future<String?> _readWorkStatusToday() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(reportDoneKey(_shiftType));
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 2) return null;   // 不正値は記録なし扱い（袋小路禁止）
    if (parts[0] != businessDateForShift(_shiftType, DateTime.now())) return null;
    return parts[1];
  }

  // 「報告済み」判定式はこの1本だけ。
  // 'done'（送信済み）と 'closed'（K3: みなしの締め）はどちらも報告済み扱いにする。
  static bool _isReportDoneStatus(String? s) => s == 'done' || s == 'closed';

  // 起動時: 現在のシフトの業務日ぶんが報告済み(done/closed)なら完了ビューを日報タブに出す。
  // closed かどうかも同時に拾う＝再起動しても「締めた日」のアクション制限が維持される。
  Future<void> _initTodayReportDone() async {
    final s = await _readWorkStatusToday();
    final done = _isReportDoneStatus(s);
    if (mounted && done) {
      setState(() {
        _todayReportDone = true;
        _todayClosed = s == 'closed';
      });
    }
  }

  // ✏️ 続けて日報（同一シフトで2枚目）。
  // S5b仕上げの裁定で完了ビューのアクションは3択に絞られ、このハンドラは
  // AfterReportBody へ渡していない＝現在は未配線。将来ボタンを復活させる際に
  // そのまま `onContinueReport: _onContinueReport` で繋げられるよう温存する。
  // シフト/現場/GPS/移動手段は維持し、本文と写真だけを白紙にする（🚗と直交）。
  // ignore: unused_element
  Future<void> _onContinueReport() async {
    _workCtrl.clear();
    await _saveWorkStatus('working');
    if (!mounted) return;
    setState(() {
      _todayReportDone = false;
      _workPhotoPaths = [];
      _parkingPhotoPaths = [];
    });
  }

  // チップ切替など _shiftType が変わった直後に判定をやり直す。
  // 夜勤done後に日勤へ切替 → 複合キー不一致 → false → フォームが自然に開く。
  Future<void> _reevaluateReportDone() async {
    final s = await _readWorkStatusToday();
    final done = _isReportDoneStatus(s);
    final closed = s == 'closed';
    if (mounted && (done != _todayReportDone || closed != _todayClosed)) {
      setState(() {
        _todayReportDone = done;
        _todayClosed = closed;   // 切替先シフトの締め状態に追随（未締めなら false へ戻る）
      });
    }
  }

  // ─── N4/N5: 「次の現場へ」のリセット ────────────────────────────────────
  // 旧・完了ビューの「🚗次の現場へ移動」が持っていた処理を、そのまま private メソッドへ
  // 移しただけ（中身は1文字も変えていない）。完了ビューからカードは消えたが、
  // N5 の「2件目の入口＝ホーム」がこれを流用する＝リセットの定義を2つに増やさない。
  //   ・完了ビュー解除（_todayReportDone=false）＋ prefs を 'working' へ
  //   ・現場/GPS/移動手段/本文まわりを白紙にし、ステップを「現場」から入り直す
  Future<void> _resetForNextReport() async {
    _otherCtrl.clear();
    _parkingCtrl.clear();
    _carpoolNameCtrl.clear();
    _transportMemoCtrl.clear();
    await _saveWorkStatus('working');
    if (!mounted) return;
    setState(() {
      _todayReportDone = false;
      _gpsAddress = '';
      _transports = {};
      _carType = 'own';
      _routeComparisons = {};
      _workPhotoPaths = [];
      _parkingPhotoPaths = [];
      // 現場移動：現場選択は「対象なし」にリセット
      _selectedSiteId = null;
      _selectedSiteName = null;
      // 4ステップ化：次の現場は「現場」ステップから入り直す
      _reportStep = 1;
    });
    _fetchGps();
  }

  // 🌙/☀ シフト継続：現在の勤務区分の逆へ移行して次の勤務に入る。
  // N4 で完了ビューのカードを撤去したため現在は未配線（中身は撤去前と同一）。
  // ホームの勤務区分セレクタ（N2 で常時表示に戻した）が同じ役目を果たすが、
  // 「切替＋working の刻み直し」をひとまとめにしたこの手順は消さずに温存する。
  // ignore: unused_element
  Future<void> _onShiftContinue() async {
    final next = _shiftType == 'night' ? 'day' : 'night';
    _workCtrl.clear();
    setState(() {
      _shiftType = next;
      _todayReportDone = false;
      _workPhotoPaths = [];
      _parkingPhotoPaths = [];
      // 4ステップ化：新しいシフトも「現場」ステップから入り直す
      _reportStep = 1;
    });
    await _saveShiftType(next);
    await _saveWorkStatus('working');   // 新シフトの業務日で working を刻む
    if (!mounted) return;
    showJsSnackbar(
      context,
      next == 'night' ? '🌙 夜勤へ切り替えました' : '☀ 日勤へ切り替えました',
    );
  }

  // ─── N5: 2件目の入口はホームに一本化する ────────────────────────────────
  // 日報フォームへ入る直前に親が1枚だけ挟むゲート。判定はここ1箇所で、
  // punch_screen 側には複製しない（punch_screen.dart:onBeforeOpenReport が呼ぶ）。
  //   ・未報告                → true（1件目＝従来どおりフォームへ）
  //   ・報告済み × 締め済み    → true（リセットしない＝従来どおり完了ビューが出る。
  //                              締めた日のアクションは「追加の申告」だけ）
  //   ・報告済み × 未締め      → 確認ダイアログ → OK なら _resetForNextReport してフォームへ
  // 対象は「日報を報告」ボタン全経路（みなしの主ボタン／実打刻・退勤済の主ボタン）。
  Future<bool> _confirmSecondReportIfNeeded() async {
    if (!_todayReportDone) return true;
    if (_todayClosed) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('本日は報告済みです',
            style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: const Text('本日の日報は提出済みです。2件目を作成しますか？',
            style: TextStyle(color: FieldTokens.textSupport, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('2件目を作成',
                style: TextStyle(color: FieldTokens.statusWarning)),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    await _resetForNextReport();
    return true;
  }

  // N5: 「現場移動」（実打刻・出勤中）からフォームへ入る直前の前処理。
  //   確認は現場移動ダイアログ側で既に済んでいるので、ここでは確認を重ねない。
  //   報告済みなら _resetForNextReport を通してから開く＝完了ビューに突き当たらない。
  //   常に true（中止経路を持たない）。
  Future<bool> _prepareMoveToNextSite() async {
    if (_todayReportDone) await _resetForNextReport();
    return true;
  }

  // ─── K3(Q8)+N3: 「今日はここまで」─────────────────────────────────────
  //   実打刻・出勤中(punchedIn && !punchedOut)
  //        … N3: 締めの真実は退勤打刻なので、ここで確認して退勤を打ってから閉じる。
  //          打刻は punch_screen の既存 _doPunch('out') 経路を呼ぶだけ（_punchOutFromHome）。
  //          ★報告フォームの自動起動は抑制される（完了ビュー＝報告済みの文脈のため。
  //            抑制は punch_screen 側 _punchOutForClose の allowGoReport:false が担う）。
  //   実打刻・退勤済 … 従来どおり route を閉じるだけ（ダイアログなし）。
  //   みなし … 打刻という確定点が無いので、ここで確認して 'closed' を刻む＝1日の締めにする。
  //            締めた日は完了ビューのアクションが「追加の申告」だけになり、再起動しても維持される
  //            （_initTodayReportDone が closed を読み直す）。
  Future<void> _onCloseToday() async {
    if (_punchIsActual) {
      // N3: 出勤中のまま締めようとしている＝退勤打刻がまだ無い。
      //   打刻の口が親に届いていない場合（PunchScreen 未マウント等）は従来どおり閉じるだけ
      //   ＝嘘の確認を出さない・袋小路も作らない。
      final punchOut = _punchOutFromHome;
      if (_punchedInToday && !_punchedOutToday && punchOut != null) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: FieldTokens.surfaceCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Text('退勤して今日を締めますか？',
                style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
            content: const Text(
                'まだ退勤していません。退勤を記録して、この画面を閉じます。',
                style: TextStyle(color: FieldTokens.textSupport, height: 1.6)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('キャンセル',
                    style: TextStyle(color: FieldTokens.textSupport)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('退勤して締める',
                    style: TextStyle(color: FieldTokens.statusWarning)),
              ),
            ],
          ),
        );
        if (ok != true) return;          // キャンセル＝何も変えずその場に留まる
        await punchOut();                // 既存 _doPunch('out') 経路（打刻ロジックは複製しない）
        if (!mounted) return;
      }
      Navigator.of(context).maybePop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('今日の報告を締めますか？',
            style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: const Text(
            '締めると、この日は「次の現場へ移動」と「勤務区分の切替」ができなくなります。\n'
            '残業や休憩の申告はこのあとも行えます。',
            style: TextStyle(color: FieldTokens.textSupport, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('締める',
                style: TextStyle(color: FieldTokens.statusWarning)),
          ),
        ],
      ),
    );
    if (ok != true) return;                 // キャンセル＝何も変えずその場に留まる
    await _saveWorkStatus('closed');
    if (!mounted) return;
    setState(() => _todayClosed = true);
    Navigator.of(context).maybePop();
  }

  // 勤務区分の永続化：業務日スコープ。
  // 「同じ業務日のあいだだけ選択を維持する」＝夜勤者の1タップを守りつつ、
  // 別の業務日へ夜勤設定を引きずる誤爆を防ぐ。
  Future<void> _saveShiftType(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shift_type', v);
    await prefs.setString(
        'shift_business_date', businessDateForShift(v, DateTime.now()));
  }

  // 起動時: 保存時の業務日と「いま同じ勤務区分で計算した業務日」が一致する場合のみ復元。
  // 不一致・欠落・不正値は 'day' にリセットし prefs も掃除する（引きずり防止）。
  Future<void> _restoreShiftType() async {
    final prefs = await SharedPreferences.getInstance();
    final savedType = prefs.getString('shift_type');
    final savedDate = prefs.getString('shift_business_date');
    final valid = (savedType == 'day' || savedType == 'night') &&
        savedDate != null &&
        savedDate == businessDateForShift(savedType!, DateTime.now());
    if (valid) {
      if (mounted) setState(() => _shiftType = savedType);
      return;
    }
    await prefs.remove('shift_type');
    await prefs.remove('shift_business_date');
    if (mounted && _shiftType != 'day') setState(() => _shiftType = 'day');
  }

  // ─── 現場の引き継ぎ（裁定A）───
  // 勤務区分(shift_type)と違い業務日スコープを持たせない＝日付をまたいでも引き継ぐ。
  // 現場は「日をまたいで続く」ものなので、毎日選び直させない方が現場の実態に合う。
  // 「対象なし」は id を空文字で保存して区別する（キー欠落=初回 と分けるため）。
  static const _kLastSiteId   = 'last_site_id';
  static const _kLastSiteName = 'last_site_name';

  Future<void> _saveLastSite(String? id, String? name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSiteId,   id ?? '');     // '' = 対象なし
    await prefs.setString(_kLastSiteName, name ?? '');
  }

  // 起動時: 前回の選択を復元。キーが無い（初回）ならデフォルトの「対象なし」のまま。
  Future<void> _restoreLastSite() async {
    final prefs = await SharedPreferences.getInstance();
    final id   = prefs.getString(_kLastSiteId);
    if (id == null) return;                              // 初回＝対象なし（既定値のまま）
    final name = prefs.getString(_kLastSiteName) ?? '';
    if (!mounted) return;
    setState(() {
      _selectedSiteId   = id.isEmpty   ? null : id;      // '' → 対象なし
      _selectedSiteName = name.isEmpty ? null : name;
    });
  }

  // ─── 移動手段のデフォルト復元 ───
  // 既存の 'today_transport'（_saveDraft）は「今日の下書き」で _clearDraft が
  // 送信時に消す上、復元は _restoreDraft が呼ばれる経路（restoreWorkStatus != null）でしか
  // 効かなかった。デフォルトとして日をまたいで残すのは別責務なので、
  // last_site_* と同じ流儀で専用キーを新設する（既存キーには一切触れない）。
  static const _kLastTransports = 'last_transports';
  static const _kLastCarType    = 'last_car_type';

  Future<void> _saveLastTransport() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastTransports, _transports.map((t) => t.name).join(','));
    await prefs.setString(_kLastCarType, _carType);
  }

  Future<void> _restoreLastTransport() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastTransports);
    if (raw == null) return;                             // 初回＝未選択のまま
    final restored = raw.isEmpty
        ? <TransportType>{}
        : raw.split(',')
            .map((n) => TransportType.values
                .firstWhere((t) => t.name == n, orElse: () => TransportType.none))
            .where((t) => t != TransportType.none)
            .toSet();
    final car = prefs.getString(_kLastCarType);
    if (!mounted) return;
    setState(() {
      _transports = restored;
      if (car == 'own' || car == 'carpool') _carType = car!;
    });
    // E-3: 復元時点で既に相乗りが選択されているなら同僚を取得（氏名サジェスト用）。
    if (_transports.contains(TransportType.car) && _carType == 'carpool') {
      _ensureColleaguesLoaded();
    }
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('today_transport', _transports.map((t) => t.name).join(','));
    await prefs.setString('today_work_content', _workCtrl.text);
    await prefs.setString('today_parking_fee', _parkingCtrl.text);
    // 作業2: 相乗り2欄を下書きに含める（旧 _carpoolCtrl は保存されず再起動で消えていた）。
    await prefs.setString('today_carpool_company', _carpoolCompanyCtrl.text);
    await prefs.setString('today_carpool_name', _carpoolNameCtrl.text);
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('today_transport');
    await prefs.remove('today_work_content');
    await prefs.remove('today_parking_fee');
    await prefs.remove('today_carpool_company');
    await prefs.remove('today_carpool_name');
  }

  Future<void> _restoreDraft(String workStatus) async {
    final prefs = await SharedPreferences.getInstance();
    final transportName = prefs.getString('today_transport') ?? '';
    final workContent   = prefs.getString('today_work_content') ?? '';
    final parkingFee    = prefs.getString('today_parking_fee') ?? '';
    final carpoolCompany = prefs.getString('today_carpool_company') ?? '';
    final carpoolName    = prefs.getString('today_carpool_name') ?? '';
    final restored = transportName.isEmpty
        ? <TransportType>{}
        : transportName.split(',').map((n) => TransportType.values.firstWhere(
              (t) => t.name == n, orElse: () => TransportType.none))
            .where((t) => t != TransportType.none)
            .toSet();
    if (!mounted) return;
    setState(() {
      _transports = restored;
      _workCtrl.text = workContent;
      _parkingCtrl.text = parkingFee;
      _carpoolCompanyCtrl.text = carpoolCompany;
      _carpoolNameCtrl.text = carpoolName;
    });
  }

  // 作業3: 会社名サジェスト。company_link_screen.dart と同じ流儀（300msデバウンス）。
  //   結果を _carpoolCompanyResults に格納し、SearchSuggestField の candidates を再生成する。
  void _onCarpoolCompanyChanged(String v) {
    _carpoolCompanyDebounce?.cancel();
    _saveDraft();   // 相乗り会社名の下書き保存（他欄と同じ流儀）
    final q = v.trim();
    if (q.isEmpty) {
      setState(() => _carpoolCompanyResults = []);
      return;
    }
    _carpoolCompanyDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await CompanyService().searchCompanies(q);
      if (!mounted) return;
      // ★失敗時は空リスト（統一前も非200・例外は [] を返していた）。
      setState(() => _carpoolCompanyResults = results.data ?? const []);
    });
  }

  // E-3: 相乗り氏名サジェスト用に自社の同僚を一度だけ取得（会社スコープはBEのJWT由来）。
  //   二重取得防止のためフラグを先に立てる（in-flight中の再入も抑止）。
  Future<void> _ensureColleaguesLoaded() async {
    if (_carpoolColleaguesLoaded) return;
    _carpoolColleaguesLoaded = true;
    final names = await CompanyService().getColleagues();
    if (!mounted) return;
    // ★失敗時は空リスト（統一前も非200・例外は [] を返していた）。
    setState(() => _carpoolColleagues = names.data ?? const []);
  }

  // BE utils/normalize_company.js の normalizeCompanyName と同等を目指した簡易正規化。
  //   ★NFKC は省略: dart:core に Unicode 正規化が無く、pubspec にも正規化パッケージが
  //     無いため。実装は「小文字化＋半角/全角スペース除去＋法人格の前後除去」。
  //     （NFKC 省略により全角括弧の法人格『（株）』等は除去しきれない場合がある）。
  static const List<String> _kLegalForms = [
    '株式会社', '有限会社', '合同会社', '合資会社', '合名会社',
    '(株)', '(有)', '(同)', '(資)', '(名)',
    '一般社団法人', '一般財団法人',
    '公益社団法人', '公益財団法人',
    '特定非営利活動法人', 'npo法人',
  ];

  String _normalizeCompanyLocal(String name) {
    if (name.isEmpty) return '';
    var s = name.toLowerCase().replaceAll(RegExp(r'[\s　]+'), '');
    var changed = true;
    while (changed) {
      changed = false;
      for (final form in _kLegalForms) {
        if (s.startsWith(form)) {
          s = s.substring(form.length);
          changed = true;
        }
        if (s.endsWith(form)) {
          s = s.substring(0, s.length - form.length);
          changed = true;
        }
      }
    }
    return s.replaceAll(RegExp(r'[\s　]+'), '');
  }

  // E-3 発動条件: 相乗り氏名サジェストの候補を返す。
  //   (a) 相乗り会社名欄が空（＝自社の相乗りと解釈）、または
  //   (b) 相乗り会社名欄が自社名と正規化一致 → 自社の同僚氏名を候補に出す。
  //   それ以外（他社名が入っている）→ 候補は空（他社の同僚は出さない＝掟）。
  List<String> _carpoolNameCandidates() {
    final company = _carpoolCompanyCtrl.text.trim();
    final isOwn = company.isEmpty ||
        _normalizeCompanyLocal(company) == _normalizeCompanyLocal(_companyName);
    return isOwn ? _carpoolColleagues : const <String>[];
  }

  // 最後のタブを復元（モード別キー）
  Future<void> _restoreTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final key   = widget.isForeman ? 'last_tab_index_v2_foreman' : 'last_tab_index_v2_worker';
    // 4タブ化前は職長が index4 まで保存し得たため、復元時に 0..3 へ丸める
    // （範囲外がそのまま入ると IndexedStack の clamp 任せになり「設定」に着地する）。
    final saved = (prefs.getInt(key) ?? 0).clamp(0, 3);
    if (mounted) setState(() => _tabIndex = saved);
  }

  // タブ切り替え＋保存
  void _setTab(int index) {
    setState(() => _tabIndex = index);
    // 承認セグメントを含む「管理・履歴」タブ(index1)進入時のみバッジ2値を再取得
    // （全index一律はAPI連打になるため回避）。旧 index3=承認・是正 から付け替え。
    if (index == 1) {
      _loadPendingApprovalCount();
      _loadRevisionCount();
    }
    // 共有タブ(index2)進入時は共有2鍵と未読枚数を取り直す。
    //   ★鍵を prefs へ長期キャッシュしない（ボス裁定）ため、入るたびに引く。
    //     会社の管理者が後から鍵を付けたときに「付与されたのに使えない」を残さない。
    if (index == 2) {
      _shareBodyKey.currentState?.reload();
    }
    SharedPreferences.getInstance().then((p) {
      final key = widget.isForeman ? 'last_tab_index_v2_foreman' : 'last_tab_index_v2_worker';
      p.setInt(key, index);
    });
  }

  @override
  void dispose() {
    _workCtrl.removeListener(_onWorkContentChanged);
    _workCtrl.dispose();
    _otherCtrl.dispose();
    _parkingCtrl.dispose();
    _carpoolNameCtrl.dispose();
    _carpoolCompanyCtrl.dispose();
    _carpoolCompanyDebounce?.cancel();
    _transportMemoCtrl.dispose();
    _reportScrollCtrl.dispose();   // 4ステップ化で新設したスクロール制御
    ReportTabNavigator.unregister(_openReportTabCb);
    PunchRemindDialogNavigator.unregister(_punchRemindCb);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ─── 通知未読件数の取得（fail-soft: 失敗時は0＝バッジ非表示）───
  Future<void> _loadUnreadCount() async {
    final res = await NotificationService().fetchUnreadCount();
    if (!mounted) return;
    setState(() {
      _unreadCount = res.ok ? (res.data ?? 0) : 0;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchGps();
      _loadUnreadCount();
    }
  }

  // ─── キャッシュ即時表示 → バックグラウンド最新取得 ───
  Future<void> _loadCacheAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedLat  = prefs.getDouble('gps_lat');
    final cachedLon  = prefs.getDouble('gps_lon');
    final cachedAddr = prefs.getString('gps_address') ?? '';
    final revCount   = prefs.getInt('cache_revision_count') ?? 0;
    final hcIso      = prefs.getString('health_check_date_iso');
    // 天気キャッシュ。★段7で新形（cache_weather_v2_*）へ改称した。
    //   旧 cache_weather_* は「precip が null 不可（0 で埋めていた）」「icon は
    //   端末側の変換表で作った絵文字」で、新形とは意味が違う。同じキーを読み続けると
    //   取れていない降水確率が 0% として復活し、WBGT も無い旧値が混ざる。
    //   新旧を混ぜないためにキーごと変え、旧キーはここで捨てる
    //   （OFFICE の dashboard_weather_v2 と同じ手口）。
    for (final k in const [
      'cache_weather_icon', 'cache_weather_temp', 'cache_weather_desc',
      'cache_weather_precip', 'cache_weather_humidity', 'cache_weather_wind',
    ]) {
      await prefs.remove(k);
    }
    final wIcon      = prefs.getString('cache_weather_v2_icon');
    final wTempC     = prefs.getDouble('cache_weather_v2_temp');
    final wDesc      = prefs.getString('cache_weather_v2_desc') ?? '';
    // ★`?? 0` を付けない。キャッシュに無い＝一度も取れていない（0% を作らない）。
    final wPrecip    = prefs.getInt('cache_weather_v2_precip');
    final wHumidity  = prefs.getInt('cache_weather_v2_humidity') ?? 60;
    final wWindSpeed = prefs.getDouble('cache_weather_v2_wind');
    final wWbgtVal   = prefs.getDouble('cache_weather_v2_wbgt_value');
    final wWbgtLvl   = prefs.getString('cache_weather_v2_wbgt_level');
    final wAlertLvl  = prefs.getString('cache_weather_v2_alert_level');
    final wAlertMsg  = prefs.getString('cache_weather_v2_alert_message');

    if (mounted) {
      setState(() {
        _userName        = prefs.getString('user_name') ?? '';
        _companyName     = prefs.getString('company_name') ?? "";
        _healthCheckDate = hcIso != null ? DateTime.tryParse(hcIso) : null;
        _revisionCount   = revCount;
        if (cachedAddr.isNotEmpty) _gpsAddress = cachedAddr;
        if (wIcon != null && wTempC != null) {
          _weather = _WeatherData(
            icon: wIcon, desc: wDesc, tempC: wTempC,
            precipPct: wPrecip, humidity: wHumidity,
            windSpeed: wWindSpeed,
            wbgtValue: wWbgtVal, wbgtLevel: wWbgtLvl,
            alertLevel: wAlertLvl, alertMessage: wAlertMsg);
        }
        _initialLoading = false;
      });
    }

    if (cachedLat != null && cachedLon != null) {
      _lat = cachedLat;
      _lon = cachedLon;
      _loadWeather();
    }

    await Future.wait([
      _fetchGps(prefs: prefs),
      _loadRevisionCount(prefs: prefs),
      _loadPendingApprovalCount(),
      _fetchCompanyAddress(),
    ]);
    // 位置 → 通知許可 → token取得・POST の順を保証（権限衝突完全解消）
    await FcmService().requestNotificationPermission();
    await FcmService().registerToken();
  }

  Future<void> _fetchGps({SharedPreferences? prefs}) async {
    if (mounted) setState(() => _gpsLoading = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
        _lat = pos.latitude;
        _lon = pos.longitude;
        prefs?.setDouble('gps_lat', _lat!);
        prefs?.setDouble('gps_lon', _lon!);
      }
    } catch (e) {
      debugPrint('GPS取得エラー: $e');
    }
    final (:address, lat: _, lon: _, :status) = await fetchGpsAddress();
    // キャッシュ焼き付きの停止: 住所の構築に成功した値だけを保存する。
    // 座標フォールバック('address_failed')や '位置情報の権限がありません' 等
    // ('gps_failed')を保存すると、次回起動時に _loadCacheAndStart が
    // それを復元して住所のふりをして表示し続けるため。
    if (status == 'ok') prefs?.setString('gps_address', address);
    if (mounted) {
      setState(() { _gpsAddress = address; _gpsStatus = status; _gpsLoading = false; });
      _loadWeather();
      // GPSが揃った時点が「フォームに目的地が確定した時点」。
      // 鍵が完全一致するキャッシュがあれば即表示し、続けて必ず再計算する。
      _restoreRouteCacheThenRefresh();
    }
  }

  Future<void> _loadWeather() async {
    if (mounted) setState(() => _weatherLoading = true);
    final (data, forecast) = await _fetchWeatherFull(lat: _lat, lon: _lon);
    if (!mounted) return;
    setState(() {
      // ★取得できたときだけ差し替える。非200・401・通信不成立で null を代入すると、
      //   _loadCacheAndStart が復元したキャッシュ表示まで消えて「天気データ取得中...」
      //   に戻ってしまう。失敗は静かに劣化＝前回値を残す（snackbar も出さない）。
      if (data != null) _weather = data;
      if (forecast.isNotEmpty) _forecast = forecast;
      _weatherLoading = false;
    });
    if (data != null) {
      SharedPreferences.getInstance().then((p) {
        p.setString('cache_weather_v2_icon',     data.icon);
        p.setDouble('cache_weather_v2_temp',     data.tempC);
        p.setString('cache_weather_v2_desc',     data.desc);
        p.setInt('cache_weather_v2_humidity',    data.humidity);
        // ★null のキーは書かずに消す。書かないだけだと前回の値が残り、
        //   「今回は取れていない」が「前回の値」として復活する。
        if (data.precipPct != null) {
          p.setInt('cache_weather_v2_precip', data.precipPct!);
        } else {
          p.remove('cache_weather_v2_precip');
        }
        if (data.windSpeed != null) {
          p.setDouble('cache_weather_v2_wind', data.windSpeed!);
        } else {
          p.remove('cache_weather_v2_wind');
        }
        if (data.wbgtValue != null) {
          p.setDouble('cache_weather_v2_wbgt_value', data.wbgtValue!);
        } else {
          p.remove('cache_weather_v2_wbgt_value');
        }
        if (data.wbgtLevel != null) {
          p.setString('cache_weather_v2_wbgt_level', data.wbgtLevel!);
        } else {
          p.remove('cache_weather_v2_wbgt_level');
        }
        if (data.alertLevel != null) {
          p.setString('cache_weather_v2_alert_level', data.alertLevel!);
        } else {
          p.remove('cache_weather_v2_alert_level');
        }
        if (data.alertMessage != null) {
          p.setString('cache_weather_v2_alert_message', data.alertMessage!);
        } else {
          p.remove('cache_weather_v2_alert_message');
        }
      });
    }
  }

  String? _buildHealthBannerMsg() {
    final hc = _healthCheckDate;
    if (hc == null) return null;
    final next = DateTime(hc.year + 1, hc.month, hc.day);
    final days = next.difference(DateTime.now()).inDays;
    if (days <= 14) return '🔴 健康診断期限まで$days日 — 今すぐ予約を！';
    if (days <= 30) return '🟡 健康診断まで$days日 — 早めに予約を';
    return null;
  }

  Future<void> _loadOriginPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _originType     = prefs.getString('default_origin') ?? 'home';
        _companyAddress = prefs.getString('company_address') ?? '';
      });
    }
  }

  Future<void> _fetchCompanyAddress() async {
    try {
      final companyId = await AuthService().getCompanyId();
      if (companyId == null || companyId.isEmpty) return;
      final result = await CompanyService().getCompanyById(companyId);
      if (result.ok) {
        final company = result.data;
        final address = company?['address'] as String? ?? '';
        if (address.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('company_address', address);
          if (mounted) setState(() => _companyAddress = address);
        }
      }
    } catch (e) {
      debugPrint('会社住所取得エラー: $e');
    }
  }

  Future<void> _loadRevisionCount({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final res = await _withRetry<ApiResult<List<dynamic>>>(
        (t) async {
          final r = await ReportsService().getRevisionRequested(timeout: t);
          // 移設前は http.get が投げたときだけ再試行していた（＝通信不成立）。
          // ApiResult は例外を statusCode:0 に畳んで返すため、ここで投げ直して
          // 同じ再試行条件へ戻す。非200（サーバは答えている）は再試行しない。
          if (!r.ok && r.statusCode == 0) {
            throw Exception(r.errorMessage ?? '通信に失敗しました');
          }
          return r;
        },
        firstTimeout: const Duration(seconds: 60),
      );
      if (res.ok && mounted) {
        // ★取消済を数から外す。BE の GET /reports?revision_requested=true は
        //   取消済を除外せず（js-office-api routes/reports.js の GET '/' は
        //   revision_requested の条件しか足さない）、取消は revision_requested を
        //   落とさない（同 PATCH /cancel は status だけを書く）。
        //   件数だけをそのまま数えると、取り消した日報がバッジに残り続ける。
        final count = (res.data ?? const <dynamic>[])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where(isRevisionRequested)
            .length;
        p.setInt('cache_revision_count', count);
        setState(() => _revisionCount = count);
      }
    } catch (e) {
      debugPrint('是正件数取得エラー: $e');
    }
  }

  // 承認待ち件数（送信済み・未承認・差戻し中でない）をシェルへ取得
  Future<void> _loadPendingApprovalCount() async {
    try {
      final result = await ReportsService().getReports(limit: 50);
      if (result.ok && mounted) {
        final raw = List<Map<String, dynamic>>.from(result.data ?? const []);
        // ★条件は report_cancel_gate の isPendingApproval ただ1本。
        //   式（is_sent / approved / revision_requested）は従来と同一で、
        //   「取消済でないこと」が先頭に足されている。
        final count = raw.where(isPendingApproval).length;
        setState(() => _pendingApprovalCount = count);
      }
    } catch (e) {
      debugPrint('承認待ち件数取得エラー: $e');
    }
  }

  // 目的地キー: 現場を選んでいればその site_id、未選択なら GPS 座標（無ければ住所）。
  // ルート計算の destination と鍵付きキャッシュのキーで同じ値を使う。
  String get _routeDestKey {
    if (_selectedSiteId != null) return 'site:${_selectedSiteId!}';
    if (_lat != null && _lon != null) {
      return 'gps:${_lat!.toStringAsFixed(6)},${_lon!.toStringAsFixed(6)}';
    }
    return 'addr:$_gpsAddress';
  }

  // 鍵付きキャッシュのキー。1つでも違えば復元しない＝違う現場の金額を絶対に出さない。
  String _routeCacheKeyFor(String originAddr) => [
        'o:$_originType',
        'oa:$originAddr',                                   // 実際に使った起点住所
        _routeDestKey,                                      // 目的地
        'd:${businessDateForShift(_shiftType, DateTime.now())}',  // 取得日（業務日）
      ].join('|');

  Future<void> _calculateRoutes() async {
    if (_gpsAddress.isEmpty) return;

    // ★世代トークン: 開始時に採番し、setState 直前に自分が最新かを検査する。
    //   GPS再取得(_fetchGps) と 起点変更(_OriginSelector) が同時に走ったとき、
    //   後から返った古い結果が新しい結果を上書きする事故を根治する。
    final myGen = ++_routeGen;

    final String originAddr;
    if (_originType == 'office' && _companyAddress.isNotEmpty) {
      originAddr = _companyAddress;
    } else {
      originAddr = await ProfileService().getHomeAddress() ?? '兵庫県神戸市長田区';
    }
    // ★段4: token の prefs 直読みを撤去。RoutesService が AuthService 経由で載せる
    //   （画面がトークンを持ち回らない）。送るヘッダの中身は不変。
    if (myGen != _routeGen) return;             // 追い越された＝この計算は捨てる

    if (mounted) {
      setState(() {
        _loadingRoutes = true;
        _routeFailed   = false;
      });
    }

    // リトライは1回だけ（1秒待機）。旧実装は3回×60秒timeoutで最長約3分「計算中」が残っていた。
    RouteCompareResult res = const RouteCompareResult.failed(RouteFailure.empty);
    for (int attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future.delayed(const Duration(seconds: 1));
      if (myGen != _routeGen) return;
      res = await RoutesService().compareRoutesV2(
        origin: originAddr,
        destination: (_lat != null && _lon != null)
            ? '${_lat!.toStringAsFixed(6)},${_lon!.toStringAsFixed(6)}'
            : _gpsAddress,
      );
      if (res.isOk) break;
    }

    if (myGen != _routeGen || !mounted) return;  // 古い世代の結果は破棄
    setState(() {
      _loadingRoutes  = false;
      _routeFromCache = false;                   // 実計算で塗り替えた＝「前回の目安」を降ろす
      if (res.isOk) {
        _routeComparisons = res.routes;
        _routeFailed      = false;
      } else {
        _routeComparisons = {};
        _routeFailed      = true;
        debugPrint('routes failed: ${res.reasonLabel}');
      }
    });
    if (res.isOk) await _saveRouteCache(_routeCacheKeyFor(originAddr), res.rawRoutes);
  }

  // ─── ルート結果の鍵付きキャッシュ（表示の高速化のみ・送信には使わない）───
  // ★キーが1つでも違えば復元しない。違う現場・違う起点・違う日の金額を出さないための鍵。
  static const _kRouteCacheKey  = 'route_cache_key';
  static const _kRouteCacheJson = 'route_cache_json';

  Future<void> _saveRouteCache(String key, Map<String, dynamic> rawRoutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRouteCacheKey, key);
      await prefs.setString(_kRouteCacheJson, jsonEncode(rawRoutes));
    } catch (e) {
      debugPrint('route cache save failed (${e.runtimeType})');  // 保存失敗は無視（表示用のため）
    }
  }

  // フォームを開いた時に呼ぶ。キー完全一致なら即表示し、裏で再計算を走らせる。
  // 復元表示中は _routeFromCache=true で「前回の目安」と明示する（嘘をつかない）。
  Future<void> _restoreRouteCacheThenRefresh() async {
    if (_gpsAddress.isEmpty) return;   // 目的地キーが定まらない＝復元も再計算もできない
    try {
      final String originAddr;
      if (_originType == 'office' && _companyAddress.isNotEmpty) {
        originAddr = _companyAddress;
      } else {
        originAddr = await ProfileService().getHomeAddress() ?? '兵庫県神戸市長田区';
      }
      final prefs    = await SharedPreferences.getInstance();
      final savedKey = prefs.getString(_kRouteCacheKey);
      final savedJson = prefs.getString(_kRouteCacheJson);
      // キー欠落・JSON欠落は復元しない（fail-safe＝再計算に落とす）
      if (savedKey != null && savedJson != null &&
          savedKey == _routeCacheKeyFor(originAddr)) {
        final decoded = jsonDecode(savedJson);
        if (decoded is Map) {
          final parsed = RoutesService.parseRoutes(Map<String, dynamic>.from(decoded));
          if (parsed.isNotEmpty && mounted) {
            setState(() {
              _routeComparisons = parsed;
              _routeFromCache   = true;
              _routeFailed      = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('route cache restore skipped (${e.runtimeType})');  // パース失敗も再計算に落とす
    }
    // 復元の成否にかかわらず必ず裏で再計算（世代トークンで競合は防がれる）
    await _calculateRoutes();
  }

  Future<void> _startVoice() async {
    final ready = await _speechMgr.ensureReady();
    if (!ready) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: const Text('マイク/音声認識の権限がありません。設定から許可してください',
              style: TextStyle(color: FieldTokens.textBody, fontSize: 18, fontWeight: FontWeight.bold)),
          backgroundColor: FieldTokens.statusError,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '設定を開く',
            textColor: FieldTokens.textBody,
            onPressed: () => launchUrl(Uri.parse('app-settings:')),
          ),
        ));
      return;
    }
    setState(() => _isListening = true);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VoiceInputDialog(
        manager: _speechMgr,
        onConfirm: (text) {
          Navigator.pop(ctx);
          setState(() {
            _workCtrl.text =
                _workCtrl.text.isEmpty ? text : '${_workCtrl.text}。$text';
          });
        },
        onCancel: () { _speechMgr.cancel(); Navigator.pop(ctx); },
      ),
    );
    setState(() => _isListening = false);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_userName.isEmpty) {
      showJsSnackbar(context, '氏名が取得できていません', isError: true);
      return;
    }
    if (_transports.isEmpty) {
      showJsSnackbar(context, '移動手段を選択してください', isError: true);
      _jumpToStep(2);   // 直せる場所（移動ステップ）へ戻す。条件式・文言は不変
      return;
    }
    setState(() => _submitting = true);
    if ((_transports.contains(TransportType.car) || _transports.contains(TransportType.other)) && _parkingPhotoPaths.isEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('写真が添付されていません'),
          content: const Text('駐車場の看板または領収書の写真が添付されていません。このまま送信しますか？\n\n※戻ると、駐車場写真の帯にある「＋撮影」から撮影できます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('戻って撮影する'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('このまま送信'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        if (mounted) setState(() => _submitting = false);
        _jumpToStep(2);   // 駐車場写真の帯は移動ステップにある。条件式・ダイアログ本文は不変
        return; // 「戻って撮影する」→送信中断。駐車場写真は帯の「＋撮影」から追加してもらう
      }
    }
    final name = _userName;
    final gpsAddr = _gpsAddress;
    try {
      // 作業2: [相乗り:〇〇] の work_content 連結は撤去。相乗りは carpool_company/carpool_name
      //   列を真実源にする（二重真実の禁止）。
      // D-2: 駐車料金の parkingPrefix（work_content への文字列埋め込み）は撤去済。
      //      金額の真実源を parking_fee 列ひとつに寄せる。
      final otherPrefix = (_transports.contains(TransportType.other) && _otherCtrl.text.trim().isNotEmpty)
          ? '[その他:${_otherCtrl.text.trim()}] '
          : '';
      // D-1: 移動手段の補足テキスト。従来 UI にはあるが payload に載らず消えていた。
      //      other prefix と同じ流儀で work_content へ連結する。空なら付けない。
      final memoPrefix = _transportMemoCtrl.text.trim().isEmpty
          ? ''
          : '【移動】${_transportMemoCtrl.text.trim()} ';
      // D-2: 駐車料金を実値で送る。未入力/パース不能/負数は null、0以上はその値をそのまま渡す
      //      （0を空に丸めない＝BE側 POST /reports の `parking_fee || null` は別途BEで是正予定）。
      final parkingRaw    = _parkingCtrl.text.trim();
      final parkingParsed = parkingRaw.isEmpty ? null : double.tryParse(parkingRaw);
      final parkingFeeValue =
          (parkingParsed != null && parkingParsed >= 0) ? parkingRaw : null;
      // 作業1: 提出時点の経費スナップショット（合計＋内訳）。ルート検索結果由来。
      final exp = _expenseSnapshot(_transports, _routeComparisons);
      // 作業2: 相乗り2欄（相乗り時のみ・空欄は null）。
      final isCarpool = _transports.contains(TransportType.car) && _carType == 'carpool';
      final carpoolCompany = isCarpool && _carpoolCompanyCtrl.text.trim().isNotEmpty
          ? _carpoolCompanyCtrl.text.trim() : null;
      final carpoolName = isCarpool && _carpoolNameCtrl.text.trim().isNotEmpty
          ? _carpoolNameCtrl.text.trim() : null;
      await WorkerNameStore.instance.add(name);
      final sent = await ReportStore.instance.addReport(WorkerReportItem(
        name: name,
        transport: _transport,
        transportTypes: _transports.map((t) => t.name).toList(),
        workContent: otherPrefix + memoPrefix + _workCtrl.text.trim(),
        parkingFee: parkingFeeValue,   // D-2: 実値送出（未入力/不正はnull）
        workPhotoPaths: _workPhotoPaths,
        parkingPhotoPaths: _parkingPhotoPaths,
        gpsAddress: gpsAddr,
        // 提出座標（_fetchGps が置いた最新値）。null なら main.dart が送らない。
        // ★diffKey（差異検知の7要素）には入れない＝確認画面の判定は1文字も変えていない。
        gpsLat: _lat,
        gpsLon: _lon,
        originType: _originType,
        siteId: _selectedSiteId,   // 「対象なし」= null（BE側 NULL）
        shiftType: _shiftType,     // 'day'|'night'（業務日補正+BE送出）
        // 作業1: 経費スナップショット（null は 0 で埋めない）
        transportDistanceKm: exp.distanceKm,
        transportFuelCost:   exp.fuelCost,
        transportFare:       exp.fare,
        transportToll:       exp.toll,
        transportBreakdown:  exp.breakdown.isEmpty ? null : exp.breakdown,
        // 作業2: 相乗り相手（構造化）
        carpoolCompany: carpoolCompany,
        carpoolName:    carpoolName,
      ));
      await ReportStore.instance.retryPending();
      _saveWorkStatus('done');
      _clearDraft();
      NotificationManager.instance.cancelOvertimeReminder();
      if (!mounted) return;
      // 送信完了の snackbar は撤去。直後に出る完了ビュー(AfterReportBody)が
      // 「報告完了 / ☀日勤 7/22分を送信しました」または「未送信（再送待ち）」を
      // バッジ付きで正面に出しており、同じ事実の二重表示だった。
      // snackbar 側は完了ビューの行動カードに数秒かぶるだけで情報を足していない。
      // ★成否(sent)は下の _lastSentOk へそのまま渡っており、表示の真実は失われない。
      _carpoolNameCtrl.clear();
      _transportMemoCtrl.clear();
      setState(() {
        _transports = {};
        _carType = 'own';
        _workCtrl.clear();
        _otherCtrl.clear();
        _parkingCtrl.clear();
        _workPhotoPaths = [];
        _parkingPhotoPaths = [];
        // ★裁定A+引き継ぎ: 送信後に現場を「対象なし」へ戻す処理は撤去した。
        //   選んだ現場は次回のデフォルトとして残るのが裁定であり、
        //   ここで null に戻すと同じ日の2枚目で毎回選び直しになるため。
        //   payload は上の addReport で送信済み＝この変更の影響を受けない。
        // 全画面push(AfterReportScreen)は廃止。完了ビューを日報タブ(index1)に出す。
        // ＝日報フォームへ到達不能にして二重報告を防止する不変条件。
        _lastSentOk = sent;   // 送信直後経路は実際の送信成否を渡す
        _todayReportDone = true;
        // K3: 直前に刻んだ work_status は 'done'＝締め済みではない。
        //   prefs とミラーがズレないようここでも false に揃える。
        _todayClosed = false;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // 作業現場の選択ボトムシート（getSites をサルベージ・「対象なし」を最上段固定）
  Future<void> _showSitePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FieldTokens.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SitePickerSheet(
        selectedSiteId: _selectedSiteId,
        onSelected: (id, name) {
          setState(() {
            _selectedSiteId = id;
            _selectedSiteName = name;
          });
          // 裁定A+引き継ぎ: 「対象なし」を選んだ場合も含め、毎回上書き保存する
          _saveLastSite(id, name);
        },
      ),
    );
  }

  // ─── J's Tool 起動 ───
  Future<void> _launchToolApp() async {
    final prefs     = await SharedPreferences.getInstance();
    final token     = prefs.getString('auth_token')  ?? '';
    if (token.isEmpty) {
      if (mounted) showJsSnackbar(context, 'ログイン情報がありません', isError: true);
      return;
    }
    final userName  = prefs.getString('user_name')   ?? '';
    final companyId = prefs.getString('company_id')  ?? '';
    final role      = prefs.getString('user_role')   ?? ''; // 二重キー統一: 'user_role' に一本化
    final userId    = prefs.getString('user_id')     ?? '';

    final uri = Uri(
      scheme: 'jstool',
      host:   'auth',
      queryParameters: {
        'token':      token,
        'user_name':  userName,
        'company_id': companyId,
        'role':       role,
        'user_id':    userId,
      },
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        showJsSnackbar(context, "J's Toolがインストールされていません", isWarning: true);
      }
    }
  }

  // ─── 日付ラベル ───
  // 日報タブ(index1)では勤務区分に応じた業務日（JST固定・夜勤の深夜〜午前は始業日=前日）を出す。
  // ＝送信される report_date と画面表示を一致させる（黙って日付を変えない）。
  String get _dateLabel {
    final ds = businessDateForShift(
        _tabIndex == 1 ? _shiftType : 'day', DateTime.now());
    final d  = DateTime.parse(ds);
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final w = weekdays[d.weekday - 1];
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}（$w）';
  }

  // ─── 日報フォームv2 ヘッダの日付（M月d日（曜））───
  // 既存の _dateLabel（AppBar用・YYYY/MM/DD）は改変せず、フォーム専用に別途組む。
  // 物差しは同じ businessDateForShift（送信される report_date と一致）。
  String get _formDateLabel {
    final d = DateTime.parse(businessDateForShift(_shiftType, DateTime.now()));
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return '${d.month}月${d.day}日（${weekdays[d.weekday - 1]}）';
  }

  String get _shiftLabel => _shiftType == 'night' ? '🌙夜勤' : '☀日勤';

  // ─── 「内容を確かめる」→ 確認画面へ ───
  // ここでは送信しない。_submit は確認画面の「送る」からのみ呼ぶ。
  //
  // ★必須判定は無い。
  //   ・作業内容(_workCtrl) … 任意入力（必須化は撤回済み）
  //   ・現場(_selectedSiteId) … 裁定A+引き継ぎで常にデフォルトが入っているため、
  //     「未選択で止める」場面が構造的に存在しない
  Future<void> _onCheckContent() async {
    FocusScope.of(context).unfocus();   // 確認画面へ行く前にキーボードを畳む

    // ルート計算の途中なら、金額が入らないことを伝えて選ばせる（ブロックはしない＝袋小路禁止）
    if (_loadingRoutes) {
      final goAnyway = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FieldTokens.surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('移動の目安を計算中です',
              style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
          content: const Text('このまま送ると金額が入りません。',
              style: TextStyle(color: FieldTokens.textSupport, height: 1.6)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('待つ',
                  style: TextStyle(color: FieldTokens.textBody)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('このまま送る',
                  style: TextStyle(color: FieldTokens.statusWarning)),
            ),
          ],
        ),
      );
      if (goAnyway != true) return;   // 「待つ」＝フォームに留まる（計算は継続中）
      if (!mounted) return;
    }

    // 押下時点の値をスナップショットして確認画面へ渡す（表示はこの静止画）。
    // 送信は従来どおり現在stateを読む _submit がやる。
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ConfirmSendScreen(
          initial:   _buildSnapshot(),
          currentOf: _buildSnapshot,
          onSend:    _submit,
          isDone:    () => _todayReportDone,
        ),
      ),
    );
  }

  // 確認画面の表示材料と差異検知キーを一度に作る。読むだけ・stateは変えない。
  _ReportSnapshot _buildSnapshot() {
    // 作業2: 先頭1件(_transport)ではなく選択中の全手段から内訳を作る。
    final routeRows  = _routeBreakdown(_transports, _routeComparisons);
    final parkingRaw = _parkingCtrl.text.trim();
    return _ReportSnapshot(
      dateLabel:         _formDateLabel,
      shiftLabel:        _shiftLabel,
      siteId:            _selectedSiteId,
      siteName:          _selectedSiteName ?? '該当現場なし',
      originLabel:       _originType == 'office' ? '会社' : '自宅',
      transportKey:      (_transports.map((t) => t.name).toList()..sort()).join(','),
      transportLabel:    _transports.isEmpty
          ? '未選択'
          : _transports.map((t) => t.label).join('・'),
      routeRows:         routeRows,
      parkingFeeRaw:     parkingRaw,
      // 作業4: 相乗り2項目（相乗り時のみ・空欄は空文字）。表示・差異検知に使う。
      carpoolCompany:    (_transports.contains(TransportType.car) && _carType == 'carpool')
          ? _carpoolCompanyCtrl.text.trim() : '',
      carpoolName:       (_transports.contains(TransportType.car) && _carType == 'carpool')
          ? _carpoolNameCtrl.text.trim() : '',
      workContent:       _workCtrl.text.trim(),
      workPhotoCount:    _workPhotoPaths.length,
      parkingPhotoCount: _parkingPhotoPaths.length,
    );
  }

  // ─── ページタイトル（ボトム4タブと1:1・役割で変えない）───
  String get _pageTitle {
    switch (_tabIndex) {
      case 0: return 'ホーム';
      case 1: return '管理・履歴';
      case 2: return '共有';
      case 3: return '設定';
      default: return 'ホーム';
    }
  }

  // ─────────────────────── BUILD ───────────────────────
  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return Scaffold(
        backgroundColor: FieldTokens.bgBase,
        appBar: _buildAppBar(),
        body: const SafeArea(child: _HomeSkeletonBody()),
      );
    }

    // IndexedStack の children リスト。ボトム4タブと1:1（職長でも数・並びは同じ）。
    //   0: ホーム(PunchScreen) / 1: 管理・履歴 / 2: 共有 / 3: 設定
    // 日報フォーム(_buildHomeTabContent)はタブから外し、Navigator.push の全画面へ移した（_openReportForm）。
    final tabChildren = <Widget>[
      PunchScreen(
        // 日報フォームはタブ切替ではなく全画面 push で開く（push 先で同一の
        // _buildHomeTabContent() をそのまま描画する＝フォームの中身は不変）。
        onNavigateToReport: _openReportForm,
        // K1: 打刻状態を受け取る唯一の口。PunchScreen が fetchToday から受けた値をそのまま
        //   流してくるだけで、こちら側に判定式は作らない（真実源の複製の禁止）。
        //   同じ値なら setState しない＝ビルド中の無駄な再描画を作らない。
        onPunchStateChanged: (isActual, punchedIn, punchedOut) {
          if (!mounted) return;
          if (_punchIsActual == isActual &&
              _punchedInToday == punchedIn &&
              _punchedOutToday == punchedOut) {
            return;
          }
          setState(() {
            _punchIsActual   = isActual;
            _punchedInToday  = punchedIn;
            _punchedOutToday = punchedOut;
          });
        },
        // K5(Q9): 「本日休み」を押した瞬間のガードが読む真実（done/closed）。
        //   isDone(:確認画面) と同じ「関数を下ろす」流儀。prefs 直読みはさせない。
        isReportDone: () => _todayReportDone,
        // N5: 日報フォームへ入る直前の親側ゲート（判定と確認文言は親が持つ）。
        //   「日報を報告」経路 → 報告済み(未締め)なら2件目の確認＋リセット。
        onBeforeOpenReport: _confirmSecondReportIfNeeded,
        //   「現場移動」経路 → 確認は現場移動側で済み。報告済みならリセットのみ。
        onBeforeMoveToNextSite: _prepareMoveToNextSite,
        // N3: 完了ビュー「今日はここまで」から退勤を打つための実行口を受け取る。
        onPunchOutHandlerReady: (fn) => _punchOutFromHome = fn,
        // N7: ホームへ増設した「⏰ 追加の申告」（完了ビュー側の同ボタンは不変・こちらは増設）。
        //   ・todayClosed … みなしの締め状態。判定は当State（_todayClosed）が唯一の真実源で、
        //     PunchScreen は受けた真偽で表示を出し分けるだけ（判定式を複製しない）。
        //     build 中に読む親所有の値なので shiftType と同じく素の値で下ろす。
        //   ・onExtraDeclaration … 完了ビューの onOvertime と同一の既存ハンドラ。
        //     残業/休憩短縮の出し分けも実処理も _openExtraDeclarationPicker のまま＝入口が増えただけ。
        todayClosed: _todayClosed,
        onExtraDeclaration: _openExtraDeclarationPicker,
        // 勤務区分の真実は当State側（送信で使う）。値+変更通知を下ろす既存の流儀に追随。
        shiftType: _shiftType,
        onShiftTypeChanged: (v) {
          setState(() => _shiftType = v);
          _saveShiftType(v);        // 業務日スコープで永続化
          _reevaluateReportDone();  // S5b: 複合キーで報告済み判定をやり直す
        },
        weatherPanel: _PunchWeatherPanel(
          weather:       _weather,
          forecast:      _forecast,
          loading:       _weatherLoading,
        ),
        // ── 要対応の件数（取得処理は既存のものをそのまま使う。新APIは作っていない）──
        //   差し戻し   = _revisionCount        (取得は _loadRevisionCount)
        //   承認待ち   = _pendingApprovalCount (取得は _loadPendingApprovalCount)
        //     ※職長のみ。isForeman の掛け方はボトムバッジと同一の流儀。
        revisionCount: _revisionCount,
        pendingApprovalCount: widget.isForeman ? _pendingApprovalCount : 0,
        // 遷移先も既存のものを使う:
        //   差し戻し → RevisionInboxScreen（notification_list_screen.dart /
        //              monthly_history_screen.dart / fcm_service.dart の RevisionInboxScreen 遷移と同一）
        onOpenRevisions: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RevisionInboxScreen()),
          );
          if (mounted) _loadRevisionCount();
        },
        //   承認待ち → 「管理・履歴」タブへ切替し、そのまま「承認」セグメントを開く。
        //     セグメントはラベルで要求する（index直指定はしない）。職長以外は
        //     '承認' が並びに存在せず、受け手側(_resolve)が 0=カレンダーへ倒す。
        onOpenPendingApprovals: () {
          setState(() {
            _mgmtSegment = '承認';
            _mgmtSegmentRequestId++;
          });
          _setTab(1);
        },
      ),
      ManagementHistoryScreen(
        isForeman:        widget.isForeman,
        initialSegment:   _mgmtSegment,
        segmentRequestId: _mgmtSegmentRequestId,
      ),
      // 共有・設定は Scaffold なしの Body を使う（各画面の自前 AppBar と二重にならない）。
      // 設定の AppBar アクション（編集）はシェルの AppBar 側から GlobalKey 経由で呼ぶ。
      // ★共有タブは AppBar アクションを持たない（更新は本文の引っ張り更新と
      //   タブ進入時の reload で足りる）。
      ShareHubBody(key: _shareBodyKey),
      ProfileBody(
        key: _profileBodyKey,
        onStateChanged: () { if (mounted) setState(() {}); },
      ),
    ];

    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: _buildAppBar(),
      body: SafeArea(
        // タブは常に4枚。旧foremanの index4 が prefs に残っていても clamp で 3 に収まる。
        child: IndexedStack(
          index: _tabIndex.clamp(0, tabChildren.length - 1),
          children: tabChildren,
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ─── 日報フォームを全画面で開く（旧: index1 のタブ） ───────────────
  // ★フォーム本体 _buildHomeTabContent() は1行も変更していない。描画位置だけを移した。
  //   ・_ReportFormPage は _buildHomeTabContent を呼ぶだけの器。
  //   ・当 State の setState をオーバーライド（下記）して push 先も再描画するため、
  //     フォーム内の全ての setState 駆動UI（チップ選択・写真帯・GPS・ルート計算結果・
  //     _todayReportDone による AfterReportBody 差替）は従来どおり動く。
  bool _reportFormOpen = false;

  Future<void> _openReportForm() async {
    // 二重 push 防止。同じ _reportPageKey を持つページが同時に2枚存在すると
    // GlobalKey の重複で例外になるため（日報報告ボタンの連打対策）。
    if (_reportFormOpen) return;
    _reportFormOpen = true;
    // フォームを開く瞬間に現在地を取り直す（既存 _fetchGps を呼ぶだけ・新しい測位ロジックは作らない）。
    // ★await しない＝非ブロッキング。フォームは即開き、成功したら setState で
    //   _gpsAddress が差し替わる。失敗しても保存値のまま出る＝ここで詰まらせない。
    _fetchGps();
    try {
      await _pushReportForm();
    } finally {
      _reportFormOpen = false;
    }
  }

  Future<void> _pushReportForm() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: FieldTokens.bgBase,
          appBar: AppBar(
            backgroundColor: FieldTokens.bgBase,
            elevation: 0,
            iconTheme: const IconThemeData(color: FieldTokens.textSupport),
            title: const Text('日報',
                style: TextStyle(
                    color: FieldTokens.brand, fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          body: SafeArea(
            child: _ReportFormPage(key: _reportPageKey, builder: _buildHomeTabContent),
          ),
        ),
      ),
    );
  }

  // ─── 2段 AppBar ───
  // 共有/設定は Body 化した（ShareHubBody / ProfileBody）ため自前の AppBar を持たない。
  // よって全4タブでシェルの AppBar を出す＝_pageTitle の「共有」「設定」が実際に表示される。
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: FieldTokens.bgBase,
      elevation: 0,
      titleSpacing: 12,
      title: Row(
        children: [
          Text(
            _pageTitle,
            style: const TextStyle(
                color: FieldTokens.brand, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            _dateLabel,
            style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11),
          ),
          const Spacer(),
        ],
      ),
      actions: [
        // 🔔 お知らせ ─ TOOL アイコンのすぐ左隣（ボス裁定）。
        //   ボトム「通知」タブを「共有」へ差し替えたため、通知の入口を AppBar へ戻した。
        //   ★通知画面本体（NotificationListScreen）は退役させていない。ここから push する。
        //     あちらは自前 AppBar に「すべて既読」を持つ（notification_list_screen.dart）
        //     ので、シェル側にそのアクションを置き直す必要は無い。
        //   ★バッジの見た目は _BottomTabItem の _badgeDot と同型
        //     （丸・statusError 地・textBody 文字9px bold）。同じ意味の記号を2つの形で出さない。
        //   ★_unreadCount の取得（_loadUnreadCount）は1文字も変えていない。
        //     呼ばれる場所だけ「通知タブ進入時」→「通知画面から戻った時」へ移した
        //     （初期取得とアプリ復帰時は不変）。
        IconButton(
          tooltip: 'お知らせ',
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationListScreen()),
            );
            if (mounted) _loadUnreadCount();
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none, color: FieldTokens.brand),
              if (_unreadCount > 0)
                Positioned(
                  top: -4, right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: FieldTokens.statusError, shape: BoxShape.circle),
                    child: Text('$_unreadCount',
                        style: const TextStyle(
                            color: FieldTokens.textBody,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
        // 🧮 TOOL（ARC FLASH）ボタン。
        // 撤去したもの（ボトム4タブ側へ移設 or 導線消滅）:
        //   ・🤝 協力申請 Icons.handshake_outlined（＋_linkCount バッジ）
        //   ・⚙️ 設定 Icons.settings → ボトム「設定」タブへ
        IconButton(
          icon: const Icon(Icons.calculate, color: FieldTokens.toolBrand),
          tooltip: 'TOOL',
          onPressed: _launchToolApp,
        ),
        // 設定タブ(3): 旧 ProfileScreen の AppBar アクション（アイコン・色・tooltip は同一）
        if (_tabIndex == 3 && (_profileBodyKey.currentState?.canEdit ?? false))
          IconButton(
            icon: const Icon(Icons.edit, color: FieldTokens.brand),
            tooltip: '編集',
            onPressed: () => _profileBodyKey.currentState?.openEdit(),
          ),
      ],
      // 2段目: 上段=会社名（薄・小）、下段=アイコン+氏名（メイン）
      //   ★左1列のみ。WBGTバッジと注意文はここには置かない（配置替え・ボス裁定）。
      //     置き場は天気パネル先頭の独立1行（_PunchWeatherPanelState.build）ただ一つ。
      //   ★高さ 46 は会社名(11.5px)＋間隔1＋氏名(13px)＋上下padding(5+6) の実所要高。
      //     右列を持たないので可変にする必要がない＝統合前と同じ固定値へ戻す。
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: Container(
          width: double.infinity,
          color: FieldTokens.surfaceCard,
          padding: const EdgeInsets.fromLTRB(14, 5, 14, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _companyName,
                style: const TextStyle(
                    color: FieldTokens.textSupport,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  const Icon(Icons.business, color: FieldTokens.brand, size: 13),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _userName.isEmpty ? '---' : _userName,
                      style: const TextStyle(
                          color: FieldTokens.textBody,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── BottomBar（全役割共通の4タブ）───
  // 職長かどうかでタブ数・並びを変えない＝isForeman による分岐をボトムから撤去した。
  //   0: ホーム / 1: 管理・履歴 / 2: 共有 / 3: 設定
  // バッジ変数は1つも削除していない。付け替え先:
  //   _pendingApprovalCount → 「管理・履歴」1つ目（職長のときのみ。承認セグメントがそこに入るため）
  //   _revisionCount        → 「管理・履歴」2つ目（同上）
  //   _unreadCount          → AppBar の🔔（通知タブ退役に伴い戻した）
  // ★「共有」タブにはバッジを付けない。共有の未読【枚数】は共有タブ本文の
  //   「受信トレイ」タイルのバッジが持つ（share_hub_screen.dart）。件数だけを返す
  //   API は無く、ボトムに出すために受信明細一覧を常時叩く形にはしない。
  // BottomAppBar/色/高さ/divider/_BottomTabItem は既存のまま（デザイン変更なし）。
  Widget _buildBottomBar() {
    final divider = Container(width: 1, height: 36, color: FieldTokens.outline);
    return BottomAppBar(
      color: FieldTokens.surfaceCard,
      height: 60,
      padding: EdgeInsets.zero,
      child: Row(children: [
        _BottomTabItem(
          icon: Icons.home_outlined,
          label: 'ホーム',
          active: _tabIndex == 0,
          onTap: () => _setTab(0),
        ),
        divider,
        _BottomTabItem(
          icon: Icons.list_alt,
          label: '管理・履歴',
          active: _tabIndex == 1,
          onTap: () => _setTab(1),
          // badge（承認待ち）は職長のときのみ点灯（職人は承認セグメントを持たないため 0＝非表示）
          badge: widget.isForeman ? _pendingApprovalCount : 0,
          badgeColor: FieldTokens.statusSuccess,
          // badge2（差し戻し）は職人にも点灯させる。差し戻しは「自分の日報が
          // 突き返された」通知で、直すのは本人（RevisionEditScreen は本人のみ・
          // revision_inbox_screen.dart の本人判定）。ホームの差し戻し行も
          // 既に職人へ出しているため、バッジと表示条件を揃える。
          // ※ _revisionCount の取得(_loadRevisionCount)は元から
          //   isForeman で絞っていない（初期取得 / タブ進入とも）ため、
          //   値はそのまま使える＝取得ロジックは1文字も変更していない。
          badge2: _revisionCount,
          badge2Color: FieldTokens.statusWarning,
        ),
        divider,
        _BottomTabItem(
          icon: Icons.folder_shared_outlined,
          label: '共有',
          active: _tabIndex == 2,
          onTap: () => _setTab(2),
        ),
        divider,
        _BottomTabItem(
          icon: Icons.settings_outlined,
          label: '設定',
          active: _tabIndex == 3,
          onTap: () => _setTab(3),
        ),
      ]),
    );
  }

  // ─── ホームタブ本体 ───
  Widget _buildHomeTabContent() {
    // 完了ビューが占有中は日報フォームを出さない＝到達不能（二重報告防止の要）
    if (_todayReportDone) {
      return AfterReportBody(
        workerName: _userName,
        sent: _lastSentOk,
        // 主ボタン「今日はここまで」＝日報フォームの全画面route(_pushReportForm)を閉じる。
        // maybePop: 閉じられる route が無い場合は何もしない（袋小路もクラッシュも作らない）。
        // K3(Q8): みなしのときだけ「締めますか？」を挟んで 'closed' を刻む（_onCloseToday）。
        //   実打刻はそのまま maybePop＝従来の挙動のまま。
        onClose: _onCloseToday,
        // N4: アクションは「⏰追加の申告」と「今日はここまで」の2つだけ。
        //   出し分けの引数（showMoveToNextSite / showShiftContinue）も、
        //   「🚗次の現場へ移動」「☀/🌙シフト切替」の2ハンドラも渡さなくなった。
        shiftType: _shiftType,   // ヘッダのサブ行「☀日勤 7/22分を送信しました」に使う
        // 「今すぐ再送」：既存の再送手段(retryPending)のみ使用。addReport再呼び出しはしない（二重報告防止）
        onRetry: () async {
          await ReportStore.instance.retryPending();
          final remaining = await ReportStore.instance.pendingCount();
          if (mounted) {
            showJsSnackbar(
              context,
              remaining == 0
                  ? '✅ 再送しました'
                  : '📋 まだ未送信です（$remaining件・自動再送を継続します）',
              isWarning: remaining != 0,
            );
          }
        },
        // 「追加の申告」＝種別を選ばせる1段を挟むだけ。残業の実処理は build の下の
        // _openOvertimeDialog() へ丸ごと退避しており、中身は1文字も変えていない。
        onOvertime: _openExtraDeclarationPicker,
      );
    }
    return Container(
      color: FieldTokens.bgBase,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // コンテンツエリア
        Expanded(
          child: SingleChildScrollView(
            controller: _reportScrollCtrl,   // ステップ切替で先頭へ戻すため
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── ステップインジケータ（全ステップ共通・切替の外）──
                _StepIndicator(current: _reportStep),
                const SizedBox(height: 18),

                // 健康診断警告（表示条件は不変: _buildHealthBannerMsg() != null）
                // ★全ステップ共通のためステップ切替の外に置く（条件式は1文字も変えていない）
                if (_buildHealthBannerMsg() != null) ...[
                  _HealthCheckBanner(message: _buildHealthBannerMsg()!),
                  const SizedBox(height: 18),
                ],

                // ═══════ ステップ1 = 日付・シフト見出し ＋「現場」 ═══════
                if (_reportStep == 1) ...[
                // ── ヘッダ（日付・シフト / 今日の報告）──
                Text('$_formDateLabel・$_shiftLabel',
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 12)),
                const SizedBox(height: 3),
                const Text('今日の報告',
                    style: TextStyle(
                        color: FieldTokens.textBody,
                        fontSize: 19,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 18),

                // ═══ ① 今日の現場 ═══
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionHeader('現場'),
                    _SiteSelectField(
                      siteName: _selectedSiteName,
                      onTap: _showSitePicker,
                    ),
                    const SizedBox(height: 6),
                    // 現在地（枠なし・textFaint）
                    _GpsBar(
                      address: _gpsAddress,
                      status: _gpsStatus,
                      loading: _gpsLoading,
                      onRefresh: _fetchGps,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ],

                // ═══════ ステップ2 =「移動」セクション全部 ═══════
                //   条件表示4件（補足テキスト／車種2択／相乗り2欄／駐車料金+写真）は
                //   条件式を1文字も変えずこの中に入っている。
                if (_reportStep == 2) ...[
                // ═══ ② 現場までの移動 ═══
                const _SectionHeader('移動'),
                _FormCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _FieldLabel('出発地'),
                      const SizedBox(height: 8),
                      // 起点選択（自宅/会社）— onChanged は現行のまま（await _calculateRoutes() 維持）
                      _OriginSelector(
                        selected: _originType,
                        onChanged: (type) async {
                          setState(() => _originType = type);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('default_origin', type);
                          await _calculateRoutes();
                        },
                      ),
                      const SizedBox(height: 16),
                      const _FieldLabel('移動手段'),
                      const SizedBox(height: 8),

                // ④ 移動手段 4択（1タップ排他・ダブルタップで複数追加）→ 車種別/相乗り → ルート情報
                _TransportRow(
                  selectedSet: _transports,
                  onTap: (t) {
                    final newSet = Set<TransportType>.from(_transports);
                    if (!newSet.contains(t)) {
                      newSet.clear();
                      newSet.add(t);
                    } else if (newSet.length > 1) {
                      newSet.remove(t);
                    }
                    if (!newSet.contains(TransportType.car)) {
                      _parkingCtrl.clear();
                      _parkingPhotoPaths = [];
                    }
                    setState(() => _transports = newSet);
                    _saveWorkStatus('moving');
                    _saveDraft();
                    _saveLastTransport();   // 次回のデフォルト（既存の副作用群は不変・追加のみ）
                  },
                  onDoubleTap: (t) async {
                    final newSet = Set<TransportType>.from(_transports);
                    if (!newSet.contains(t)) {
                      newSet.add(t);
                      if (newSet.length >= 2) {
                        if (!context.mounted) return;
                        final ok = await showConfirmDialog(context,
                          title: '移動手段を追加',
                          message: '2つ以上の移動手段を記録します。よろしいですか？',
                          confirmText: 'OK', cancelText: 'キャンセル',
                        );
                        if (!ok) return;
                      }
                      if (!newSet.contains(TransportType.car)) {
                        _parkingCtrl.clear();
                        if (mounted) setState(() => _parkingPhotoPaths = []);
                      }
                      if (mounted) setState(() => _transports = newSet);
                      _saveWorkStatus('moving');
                      _saveDraft();
                      _saveLastTransport();   // 次回のデフォルト（既存の副作用群は不変・追加のみ）
                    }
                  },
                ),
                // 作業5: 複数選択の操作方法を明示（ダブルタップは発見されにくいため）
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('※タップで選択　／　2つ以上使うときはダブルタップで追加',
                      style: TextStyle(color: FieldTokens.textFaint, fontSize: 11)),
                ),
                // 補足テキスト（その他 or 複数選択時）— 注意書き直下・トグルより前へ移設
                if (_transports.contains(TransportType.other) || _transports.length >= 2) ...[
                  const SizedBox(height: 10),
                  _FormInputShell(
                    icon: Icons.edit_note,
                    child: TextField(
                      controller: _transportMemoCtrl,
                      decoration: const InputDecoration(
                        hintText: '移動手段の補足（任意）例：バイクで駅まで → 電車 → 徒歩',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                            color: FieldTokens.textFaint, fontSize: 12),
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                          color: FieldTokens.textBody, fontSize: 13),
                    ),
                  ),
                ],
                // 車選択時: 社用車/相乗り 2択 → 各入力欄
                if (_transports.contains(TransportType.car)) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _carType = 'own');
                          _saveLastTransport();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _carType == 'own'
                                ? FieldTokens.outlineStrong
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _carType == 'own'
                                    ? FieldTokens.textSupport
                                    : FieldTokens.outline),
                          ),
                          child: Center(child: Text('社用車・自家用車',
                            style: TextStyle(
                              color: _carType == 'own'
                                  ? FieldTokens.textBody
                                  : FieldTokens.textSupport,
                              fontSize: 12,
                              fontWeight: _carType == 'own' ? FontWeight.bold : FontWeight.normal,
                            ))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _carType = 'carpool';
                            _parkingCtrl.clear();
                            _parkingPhotoPaths = [];
                          });
                          _saveLastTransport();
                          // E-3: 相乗り選択時に自社同僚を取得（氏名サジェスト用）。
                          _ensureColleaguesLoaded();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _carType == 'carpool'
                                ? FieldTokens.outlineStrong
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _carType == 'carpool'
                                    ? FieldTokens.textSupport
                                    : FieldTokens.outline),
                          ),
                          child: Center(child: Text('相乗り',
                            style: TextStyle(
                              color: _carType == 'carpool'
                                  ? FieldTokens.textBody
                                  : FieldTokens.textSupport,
                              fontSize: 12,
                              fontWeight: _carType == 'carpool' ? FontWeight.bold : FontWeight.normal,
                            ))),
                        ),
                      ),
                    ),
                  ]),
                ],
                // ルート情報バー（距離・時間・金額）。
                // 位置: 車のときは「社用車・自家用車/相乗り」2択の直下＝駐車料金入力の上。
                //       他の手段のときは手段チップの直下（上の car ブロックが出ないため自然にそうなる）。
                // 表示条件は従来どおり無条件（_transports に依存しない）。
                const SizedBox(height: 12),
                _RouteInfoBar(
                  transport: _transport,
                  comparisons: _routeComparisons,
                  loading: _loadingRoutes,
                  failed: _routeFailed,
                  fromCache: _routeFromCache,
                  onRetry: _calculateRoutes,
                ),
                // 車選択かつ相乗り時: 相乗り相手（会社名サジェスト＋氏名の2欄）。
                //   駐車料金は出さない＝現行仕様のまま。work_content には連結しない（二重真実の禁止）。
                if (_transports.contains(TransportType.car) &&
                    _carType == 'carpool') ...[
                  const SizedBox(height: 10),
                  // 作業3: 会社名はサジェスト付き（searchCompanies・300msデバウンス・共通部品）
                  SearchSuggestField(
                    controller: _carpoolCompanyCtrl,
                    candidates: _carpoolCompanyResults
                        .map((c) => (c['company_name'] as String? ?? '').trim())
                        .where((s) => s.isNotEmpty)
                        .toList(),
                    hintText: '相乗り相手の会社名（任意）',
                    onChanged: _onCarpoolCompanyChanged,
                    onSelected: _onCarpoolCompanyChanged,
                    // 候補はサーバ(/companies/search)が正規化検索で絞り済み。
                    // 生テキスト部分一致の再フィルタでサーバ候補を捨てない。
                    serverFiltered: true,
                  ),
                  // 作業2: 会社名欄の下に補足（既存の ※ 補足と同じ textFaint / fontSize 11）
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('※自社なら空欄のままでOK',
                        style: TextStyle(color: FieldTokens.textFaint, fontSize: 11)),
                  ),
                  const SizedBox(height: 10),
                  // E-3: 氏名欄はサジェスト付き（自社同僚を候補に）。会社名欄(:上)と同じく
                  //   素の SearchSuggestField。候補は _carpoolNameCandidates() が
                  //   E-3発動条件（会社名が空 or 自社名一致）で出し分ける。
                  //   serverFiltered:false＝同僚は全件返るのでローカルで部分一致絞り込み。
                  SearchSuggestField(
                    controller: _carpoolNameCtrl,
                    candidates: _carpoolNameCandidates(),
                    hintText: '相乗り相手の氏名（任意）',
                    onChanged: (_) => _saveDraft(),
                    serverFiltered: false,
                  ),
                ],
                // 駐車料金 + 駐車場写真（1組だけ描画する）
                // ★根治: 旧実装は「車(own)の分岐」と「その他の分岐」が独立していたため、
                //   car と other を同時選択すると同じ _parkingCtrl / _parkingPhotoPaths を
                //   共有する入力欄と写真帯が2組並んでいた。条件を OR で1本化して解消する。
                //   controller・paths は従来と同一のため、下書き保存(_saveDraft)・復元(_restoreDraft)・
                //   送信の経路は一切変わらない。
                if ((_transports.contains(TransportType.car) && _carType == 'own') ||
                    _transports.contains(TransportType.other)) ...[
                  const SizedBox(height: 10),
                  _FormInputShell(
                    icon: Icons.local_parking,
                    child: TextField(
                      controller: _parkingCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '駐車料金（円）',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                            color: FieldTokens.textFaint, fontSize: 12),
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                          color: FieldTokens.textBody, fontSize: 13),
                      onChanged: (_) => _saveDraft(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 駐車場写真（複数・横スクロール帯）
                  PhotoStripField(
                    label: '駐車場写真（看板・領収書）',
                    paths: _parkingPhotoPaths,
                    onChanged: (v) => setState(() => _parkingPhotoPaths = v),
                  ),
                ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ],

                // ═══════ ステップ3 =「作業」セクション ═══════
                if (_reportStep == 3) ...[
                // ═══ ③ 今日の作業 ═══（任意入力＝必須バッジなし）
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionHeader('作業'),
                    _FormCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ⑤ 作業内容テキスト（音声入力）
                          _WorkContentSection(
                            controller: _workCtrl,
                            showMediaButtons: true,
                            isListening: _isListening,
                            onMicTap: _startVoice,
                          ),
                          const SizedBox(height: 14),
                          // 作業写真（複数・横スクロール帯）
                          PhotoStripField(
                            label: '写真',
                            note: '※なくても報告できます',
                            paths: _workPhotoPaths,
                            onChanged: (v) => setState(() => _workPhotoPaths = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ],
                // ⑥ 残業入力は撤去（提出後の残業報告導線=OvertimeDialogに一本化）
              ],
            ),
          ),
        ),

        // 送信導線（画面最下部に固定・スクロール外）。
        // スライド送信は廃止し「内容を確かめる」→確認画面→「送る」の2段タップへ。
        Container(
          color: FieldTokens.bgBase,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ステップ1: 「次へ」だけ（ブロックなし＝バリデーションは足さない）
              if (_reportStep == 1)
                _OutlineActionButton(
                  label: '次へ',
                  onTap: () async => _goStep(2),
                ),
              // ステップ2: 「戻る」＋「次へ」
              if (_reportStep == 2)
                Row(
                  children: [
                    Expanded(child: _StepBackButton(onTap: () => _goStep(1))),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _OutlineActionButton(
                        label: '次へ',
                        onTap: () async => _goStep(3),
                      ),
                    ),
                  ],
                ),
              // ステップ3: 「戻る」＋既存の「内容を確認する」（_onCheckContent 呼出は不変）
              if (_reportStep == 3) ...[
                Row(
                  children: [
                    Expanded(child: _StepBackButton(onTap: () => _goStep(2))),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _OutlineActionButton(
                        label: '内容を確認する',
                        busy:  _submitting,
                        onTap: _onCheckContent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                const Text('※次の画面で見直してから送信します',
                    style: TextStyle(
                        color: FieldTokens.textFaint, fontSize: 11)),
              ],
            ],
          ),
        ),
      ],
      ),
    );
  }

  // ── 「追加の申告」種別選択（残業 / 休憩の短縮）─────────────────────────
  //   提出後画面 after_report_screen.dart の続行1行目から onOvertime 経由で来る。
  //   縦2行・暗枠1px・塗りなし（カードは使わない＝_ActionCard 様式は持ち込まない）。
  Future<void> _openExtraDeclarationPicker() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('追加の申告',
            style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DeclarationChoiceRow(
                icon:  Icons.more_time,
                label: '残業',
                note:  '残業した時間を追加で記録',
                onTap: () => Navigator.pop(ctx, 'overtime'),
              ),
              const SizedBox(height: 10),
              _DeclarationChoiceRow(
                icon:  Icons.free_breakfast_outlined,
                label: '休憩の短縮',
                note:  '取れなかった休憩を申告',
                onTap: () => Navigator.pop(ctx, 'break'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;   // 閉じる/背景タップ＝何もしない
    if (choice == 'overtime') {
      await _openOvertimeDialog();
    } else {
      await _openShortBreakSheet();
    }
  }

  // 「休憩の短縮」申告シート。送信は既存 WorkModeService.breakRequest をそのまま使い、
  // ＝夜勤の業務日ズレ（深夜〜午前は始業日=前日）が日報と一致する。
  Future<void> _openShortBreakSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FieldTokens.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ShortBreakSheet(
        workDate: businessDateForShift(_shiftType, DateTime.now()),
        // N6: 申告を当てる勤怠行のシフト。workDate と同じ _shiftType から採る
        //   ＝業務日とシフトが常に同じ勤務を指す（BE は (person, work_date, shift_type) で1行）。
        shiftType: _shiftType,
        onNotify: (message, isError) {
          if (!mounted) return;
          showJsSnackbar(context, message, isError: isError);
        },
      ),
    );
  }

  // ── 残業報告（既存処理。showDialog 以下は1文字も変えず、呼出を1段ラップしただけ）──
  Future<void> _openOvertimeDialog() async {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => OvertimeDialog(
              workerName: _userName,
              gpsAddress: _gpsAddress,
              onSubmit: (start, end, overtime) async {
                final sentOt = await ReportStore.instance.addReport(WorkerReportItem(
                  name: _userName,
                  transport: TransportType.other,
                  workContent: '【残業】$start〜$end $overtime',
                  gpsAddress: _gpsAddress,
                  shiftType: _shiftType,   // 残業報告も同じ勤務区分で業務日を揃える
                ));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  showJsSnackbar(
                  context,
                  sentOt ? '✅ 残業報告を送信しました' : '📋 残業報告を保存しました（再送待ち）',
                  isWarning: !sentOt,
                );
                }
              },
            ),
          );
  }

}

// 「追加の申告」ダイアログの選択肢1行。暗枠1px・塗りなし。
// 枠トークンは同ファイルのチップ群と同じ FieldTokens.outline。
class _DeclarationChoiceRow extends StatelessWidget {
  const _DeclarationChoiceRow({
    required this.icon,
    required this.label,
    required this.note,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FieldTokens.outline),
            ),
            child: Row(
              children: [
                Icon(icon, color: FieldTokens.textSupport, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: FieldTokens.textBody,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(note,
                          style: const TextStyle(
                              color: FieldTokens.textFaint, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: FieldTokens.textSupport, size: 18),
              ],
            ),
          ),
        ),
      );
}

// 「休憩の短縮」申告シート。
//   ・分チップ [0,15,30,45]（＝実際に取れた休憩の合計）
//   ・理由は必須。空のまま申告を押したらシート内にエラーを出し、送信はしない
//     （ボタンを無効化して黙る＝理由の分からない袋小路にはしない）
//   ・送信は既存 WorkModeService().breakRequest（新APIは作らない）
class _ShortBreakSheet extends StatefulWidget {
  const _ShortBreakSheet({
    required this.workDate,
    required this.shiftType,
    required this.onNotify,
  });
  final String workDate;   // 呼び出し側が businessDateForShift で確定させた業務日
  final String shiftType;  // N6: 'day'|'night'。BE で申告を当てる行の特定に使う
  final void Function(String message, bool isError) onNotify;

  @override
  State<_ShortBreakSheet> createState() => _ShortBreakSheetState();
}

class _ShortBreakSheetState extends State<_ShortBreakSheet> {
  static const _presets = [0, 15, 30, 45];
  int _selectedMin = 0;
  final _reasonCtrl = TextEditingController();
  String? _error;        // シート内エラー（理由未入力・送信失敗の両方をここに出す）
  bool _submitting = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = '休憩の理由を入力してください');
      return;   // 送信しない
    }
    setState(() { _error = null; _submitting = true; });
    final r = await WorkModeService().breakRequest(
      breakMinutes: _selectedMin,
      reason:       reason,
      workDate:     widget.workDate,
      // N6: 同日に日勤/夜勤の2行が並存しうるため、どちらの行への申告かを明示する。
      //   BE は未指定=day 互換（routes/attendance.js POST /break-request）。
      shiftType:    widget.shiftType,
    );
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop();
      widget.onNotify('休憩の申告を送信しました', false);
      return;
    }
    // 失敗は非ブロック: シートは開いたまま残し、理由をその場とsnackbarの両方に出す
    //（シートが最前面のため snackbar だけだと隠れて沈黙障害になりうる）。
    final msg = r.errorMessage ?? '休憩の申告を送信できませんでした';
    setState(() { _submitting = false; _error = msg; });
    widget.onNotify(msg, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('休憩の短縮を申告',
              style: TextStyle(
                  color: FieldTokens.textBody,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          const _FieldLabel('実休憩'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((m) {
              final selected = _selectedMin == m;
              return GestureDetector(
                onTap: () => setState(() => _selectedMin = m),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? FieldTokens.outlineStrong
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: selected
                            ? FieldTokens.textSupport
                            : FieldTokens.outline),
                  ),
                  child: Text('$m 分',
                      style: TextStyle(
                        color: selected
                            ? FieldTokens.textBody
                            : FieldTokens.textSupport,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      )),
                ),
              );
            }).toList(),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('※実際に取れた休憩の合計を選んでください',
                style:
                    TextStyle(color: FieldTokens.textFaint, fontSize: 11)),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('理由（必須）'),
          const SizedBox(height: 8),
          _FormInputShell(
            icon: Icons.edit_note,
            child: TextField(
              // _FormInputShell は height:46 固定なので1行のまま使う
              controller: _reasonCtrl,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: const InputDecoration(
                hintText: '例）現場の都合で休憩を取れなかった',
                border: InputBorder.none,
                hintStyle:
                    TextStyle(color: FieldTokens.textFaint, fontSize: 12),
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(
                  color: FieldTokens.textBody, fontSize: 13),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.error_outline,
                  color: FieldTokens.statusWarning, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(_error!,
                    style: const TextStyle(
                        color: FieldTokens.statusWarning, fontSize: 12)),
              ),
            ]),
          ],
          const SizedBox(height: 20),
          _OutlineActionButton(
            label: '申告する',
            busy:  _submitting,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// HomeScreen / ForemanHomeScreen — 後方互換ラッパー
// ─────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.restoreWorkStatus});
  final String? restoreWorkStatus;
  @override
  Widget build(BuildContext context) =>
      JsMainShell(isForeman: false, restoreWorkStatus: restoreWorkStatus);
}

// ─────────────────────────────────────────────
// 日報フォームv2 の共通部品（このフォーム専用・他画面は不触）
// ─────────────────────────────────────────────

/// セクション見出し。
/// ※ 旧 alert 引数（琥珀の「必須」バッジ）は作業内容の必須化撤回に伴い削除した。
///   現場カード側の「必須」バッジは _SiteSelectField が自前で持っている。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title,
              style: const TextStyle(
                  color: FieldTokens.textSupport,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ),
      );
}

/// カード内の小ラベル（「どこから」「なにで」）
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style:
                const TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
      );
}

/// 枠線なし・背景の明度差だけで立てるカード
class _FormCard extends StatelessWidget {
  const _FormCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

/// カード内の入力欄の外装（アイコン+高さ44の帯）
class _FormInputShell extends StatelessWidget {
  const _FormInputShell({required this.icon, required this.child});
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: FieldTokens.bgBase,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FieldTokens.outline),
        ),
        child: Row(children: [
          Icon(icon, color: FieldTokens.textSupport, size: 16),
          const SizedBox(width: 10),
          Expanded(child: child),
        ]),
      );
}

/// 主要アクション。塗りつぶさない＝暗い面 + オフホワイト文字 + シルバー1px枠。
class _OutlineActionButton extends StatelessWidget {
  const _OutlineActionButton({
    required this.label,
    required this.onTap,
    this.busy = false,
  });
  final String label;
  final Future<void> Function() onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : () => onTap(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: FieldTokens.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FieldTokens.textSupport),
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: FieldTokens.textSupport))
                  : Text(label,
                      style: const TextStyle(
                          color: FieldTokens.textBody,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────
// ステップインジケータ（現場 → 移動 → 作業 → 確認）
//   ・数字が主役: 1〜4 の番号を大きく置き、ラベルはその下の小さい文字にする
//   ・色は意味だけ: 現在ステップ = FieldTokens.brand(#D9C08A) /
//     それ以外 = FieldTokens.textSupport(= FieldTokens.textSupport #7B7567・補助色)
//   ・カード・枠・塗り・線は一切持たない。区切りは Expanded による余白のみ
//   ・「確認」(4) は別画面 _ConfirmSendScreen。フォーム内で current=4 にはならない。
// ─────────────────────────────────────────────
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current});

  /// 1=現場 / 2=移動 / 3=作業 / 4=確認
  final int current;

  static const List<String> _labels = ['現場', '移動', '作業', '確認'];

  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(_labels.length, (i) {
          final n = i + 1;
          final isCurrent = n == current;
          final c = isCurrent ? FieldTokens.brand : FieldTokens.textSupport;
          return Expanded(
            child: Column(
              children: [
                Text('$n',
                    style: TextStyle(
                        color: c,
                        fontSize: 20,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal)),
                const SizedBox(height: 2),
                Text(_labels[i],
                    style: TextStyle(
                        color: c,
                        fontSize: 12,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal)),
              ],
            ),
          );
        }),
      );
}

/// ステップの「戻る」＝二次ボタン。暗枠1px（outline=#2E333A）＋補助色の文字。
/// 主ボタン(_OutlineActionButton)と高さ56を揃え、面は塗らない＝序列を枠と色だけで示す。
class _StepBackButton extends StatelessWidget {
  const _StepBackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FieldTokens.outline),
            ),
            child: const Center(
              child: Text('戻る',
                  style: TextStyle(
                      color: FieldTokens.textSupport,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────
// 送信前スナップショット（確認画面の表示材料と差異検知キー）
// ─────────────────────────────────────────────
class _ReportSnapshot {
  const _ReportSnapshot({
    required this.dateLabel,
    required this.shiftLabel,
    required this.siteId,
    required this.siteName,
    required this.originLabel,
    required this.transportKey,
    required this.transportLabel,
    required this.routeRows,
    required this.parkingFeeRaw,
    required this.carpoolCompany,
    required this.carpoolName,
    required this.workContent,
    required this.workPhotoCount,
    required this.parkingPhotoCount,
  });

  final String  dateLabel;
  final String  shiftLabel;
  final String? siteId;
  final String  siteName;
  final String  originLabel;
  final String  transportKey;    // 差異検知用（順序非依存に正規化済み）
  final String  transportLabel;
  /// 作業2: 手段ごとの内訳。旧 distanceLabel / routeCostLabel（各1個のString）は
  /// 先頭1件しか持てず、複数選択時に2件目以降が消えていたため置き換えた。
  final List<({String label, String? dist, String? cost})> routeRows;
  final String  parkingFeeRaw;   // 入力そのまま（空文字=未入力）
  final String  carpoolCompany;  // 作業4: 相乗り会社名（空文字=相乗りでない/未入力）
  final String  carpoolName;     // 作業4: 相乗り氏名（空文字=相乗りでない/未入力）
  final String  workContent;
  final int     workPhotoCount;
  final int     parkingPhotoCount;

  String get parkingFeeLabel =>
      parkingFeeRaw.isEmpty ? '—' : '¥$parkingFeeRaw';

  /// ルート金額の差異検知キー。旧 routeCostLabel（単一文字列）の代替。
  /// 手段名で昇順ソートしてから畳むため、選択順が違っても同じ値になる
  /// （transportKey と同じ「順序非依存」の性質を保つ）。
  String get routeCostKey =>
      (routeRows.map((r) => '${r.label}:${r.cost ?? ''}').toList()..sort())
          .join(',');

  /// 差異検知は4項目に限定: 現場ID・移動手段・作業内容・金額（ルート金額+駐車料金）。
  /// 相乗り相手のラベル。会社名・氏名のどちらか一方でもあれば「会社名　氏名」。
  /// 両方空なら空文字（＝相乗りを選んでいない or 未入力）。
  String get carpoolLabel =>
      [carpoolCompany, carpoolName].where((s) => s.isNotEmpty).join('　');

  // 作業4: 差異検知に相乗り2項目を追加（金額・移動に加えて相乗りの変更も検知する）。
  String get diffKey => [
        siteId ?? '',
        transportKey,
        workContent,
        routeCostKey,
        parkingFeeRaw,
        carpoolCompany,
        carpoolName,
      ].join('');
}

// ─────────────────────────────────────────────
// 確認画面（2段タップの2段目）
// ─────────────────────────────────────────────
class _ConfirmSendScreen extends StatefulWidget {
  const _ConfirmSendScreen({
    required this.initial,
    required this.currentOf,
    required this.onSend,
    required this.isDone,
  });

  /// 「内容を確かめる」を押した時点の静止画
  final _ReportSnapshot initial;
  /// 現在stateから作り直すための取得口（送信直前の差異検知に使う）
  final _ReportSnapshot Function() currentOf;
  /// 実送信。従来どおり現在stateを読む _submit をそのまま呼ぶ
  final Future<void> Function() onSend;
  /// 送信が成立したか（_todayReportDone）。成立時のみ画面を閉じる
  final bool Function() isDone;

  @override
  State<_ConfirmSendScreen> createState() => _ConfirmSendScreenState();
}

class _ConfirmSendScreenState extends State<_ConfirmSendScreen> {
  late _ReportSnapshot _snap = widget.initial;
  bool _sending = false;

  Future<void> _handleSend() async {
    if (_sending) return;
    // 値ズレ対策: 表示中の静止画と現在stateがズレていたら送らず、静止画を更新して見せ直す。
    final now = widget.currentOf();
    if (now.diffKey != _snap.diffKey) {
      setState(() => _snap = now);
      showJsSnackbar(context, '内容が変わりました。もう一度ご確認ください',
          isWarning: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSend();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    // _submit が途中で中断した場合（移動手段未選択・駐車写真ダイアログで戻る等）は
    // _todayReportDone が立たない＝閉じずにこの画面へ留まる。
    if (widget.isDone()) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        elevation: 0,
        iconTheme: const IconThemeData(color: FieldTokens.textSupport),
        title: const Text('確認',
            style: TextStyle(
                color: FieldTokens.textBody, fontSize: 16)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('この内容で送ります',
                        style: TextStyle(
                            color: FieldTokens.textBody,
                            fontSize: 19,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 18),
                    _FormCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _row('日付', '${_snap.dateLabel}・${_snap.shiftLabel}'),
                          _row('現場', _snap.siteName),
                          _row('移動',
                              '${_snap.originLabel}から ${_snap.transportLabel}'),
                          _row('距離・時間',
                              _snap.routeRows.isEmpty
                                  ? '—'
                                  : _snap.routeRows
                                      .map((r) =>
                                          '${r.label}　${r.dist ?? '—'}　${r.cost ?? '—'}')
                                      .join('\n'),
                              multiline: true),
                          _row('交通費（駐車料金）', _snap.parkingFeeLabel),
                          // 作業4: 相乗りを選んでいる時だけ行を出す（未選択・未入力なら行ごと省く）
                          if (_snap.carpoolLabel.isNotEmpty)
                            _row('相乗り', _snap.carpoolLabel),
                          _row('作業内容', _snap.workContent, multiline: true),
                          _row('写真',
                              '作業 ${_snap.workPhotoCount}枚 / 駐車 ${_snap.parkingPhotoCount}枚',
                              last: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OutlineActionButton(
                      label: '報告を送信', busy: _sending, onTap: _handleSend),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _sending ? null : () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('戻って直す',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: FieldTokens.textSupport, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value,
      {bool multiline = false, bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: FieldTokens.textSupport, fontSize: 11)),
          const SizedBox(height: 3),
          Text(value.isEmpty ? '—' : value,
              maxLines: multiline ? null : 2,
              overflow: multiline ? null : TextOverflow.ellipsis,
              style: const TextStyle(
                  color: FieldTokens.textBody,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class ForemanHomeScreen extends StatelessWidget {
  const ForemanHomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const JsMainShell(isForeman: true);
}

// ─────────────────────────────────────────────
// BottomTabItem
// ─────────────────────────────────────────────
// ─────────────────────────────────────────────
// 日報フォームの push 先ページ（器のみ）
//   builder は _JsMainShellState._buildHomeTabContent。フォームの中身は一切持たない。
//   refresh() は親 State の setState オーバーライドから呼ばれる。
// ─────────────────────────────────────────────
class _ReportFormPage extends StatefulWidget {
  const _ReportFormPage({super.key, required this.builder});
  final Widget Function() builder;
  @override
  State<_ReportFormPage> createState() => _ReportFormPageState();
}

class _ReportFormPageState extends State<_ReportFormPage> {
  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder();
}

class _BottomTabItem extends StatelessWidget {
  const _BottomTabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
    this.badge2 = 0,
    this.badgeColor = FieldTokens.statusError,
    this.badge2Color = FieldTokens.statusError,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;
  final int badge2;
  final Color badgeColor;
  final Color badge2Color;

  // 数値バッジ（丸）1個を生成
  Widget _badgeDot(int n, Color c) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        child: Text('$n',
            style: TextStyle(
                // c は success / error / warning の3値のみ（本ファイルの呼び出し2箇所）。
                // success(#6FD6B4) は明るい面なので白文字だと 1.76:1 で読めない。
                // 暗色 onAccent なら 8.75:1。
                // error/warning は白のまま＝今回のスコープ(success)外のため未変更。
                // ただし白は error 3.82:1 / warning 3.56:1 で AA 未達（本件以前からの既存課題）。
                color: c == FieldTokens.statusSuccess ? FieldTokens.onAccent : FieldTokens.textBody,
                fontSize: 9,
                fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon,
                  color: active ? FieldTokens.accent : FieldTokens.textSupport, size: 22),
              // 1つ目の丸（右上）
              if (badge > 0)
                Positioned(
                  top: -4, right: -6,
                  child: _badgeDot(badge, badgeColor),
                ),
              // 2つ目の丸（1つ目の左隣＝右上領域に横並び）
              if (badge2 > 0)
                Positioned(
                  top: -4, right: badge > 0 ? 12 : -6,
                  child: _badgeDot(badge2, badge2Color),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: active ? FieldTokens.accent : FieldTokens.textSupport,
                  fontSize: 11,
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// ①' 作業現場 選択欄（GPS住所の直下・金枠強調・選択必須バッジ）
// ─────────────────────────────────────────────
class _SiteSelectField extends StatelessWidget {
  const _SiteSelectField({
    required this.siteName,
    required this.onTap,
  });
  /// null = 「対象なし」。裁定A+引き継ぎにより常にデフォルトが入っている状態なので、
  /// これは「未選択」ではなく「対象なしという選択」を意味する。
  /// ★琥珀の「必須」バッジは撤去した（止める場面が無いのに必須と書くのは嘘の記号）。
  final String? siteName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isNone = siteName == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.place,
                color: isNone ? FieldTokens.textSupport : FieldTokens.textBody,
                size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isNone ? '該当現場なし' : siteName!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isNone
                      ? FieldTokens.textSupport
                      : FieldTokens.textBody,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('変更',
                style: TextStyle(
                    color: FieldTokens.textSupport,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// 作業現場 選択ボトムシート（getSites サルベージ・「対象なし」最上段固定）
class _SitePickerSheet extends StatefulWidget {
  const _SitePickerSheet(
      {required this.selectedSiteId, required this.onSelected});
  final String? selectedSiteId;
  final void Function(String? id, String? name) onSelected;
  @override
  State<_SitePickerSheet> createState() => _SitePickerSheetState();
}

class _SitePickerSheetState extends State<_SitePickerSheet> {
  final SiteService _siteService = SiteService();
  List<dynamic> _sites = [];
  bool _loading = true;
  String? _error;

  // 現場名の部分一致フィルタ（ローカルのみ・APIは叩かない）。「対象なし」は常に先頭固定＝未選択の道を塞がない。
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // 検索候補（登録現場名・重複除去・非空）。取得済み _sites から生成（新規API無し）。
  List<String> get _candidates {
    final seen = <String>{};
    final out = <String>[];
    for (final s in _sites) {
      final n = ((s as Map)['site_name'] as String? ?? '').trim();
      if (n.isNotEmpty && seen.add(n)) out.add(n);
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _siteService.getSites();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _sites = result.data ?? const [];
      } else {
        _error = result.errorMessage ?? '現場一覧を取得できませんでした';
      }
    });
  }

  void _choose(String? id, String? name) {
    widget.onSelected(id, name);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('作業現場を選択',
                style: TextStyle(
                    color: FieldTokens.accent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Divider(color: FieldTokens.outline, height: 1),
            // 上段=スクロール（「対象なし」＋現場リスト）。高さ不足時はここが逃げる。
            Flexible(child: _buildBody()),
            // 下段=固定: 検索欄（最下段）＋候補チップ（直上）。キーボード追従（viewInsets）。
            // 既存の絞り込みは _buildBody の .where が担当（onChanged で _query 更新）。
            Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchSuggestField(
                  controller: _searchCtrl,
                  candidates: _candidates,
                  hintText: '現場名で検索',
                  onChanged: (v) => setState(() => _query = v),
                  onSelected: (v) => setState(() => _query = v),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: FieldTokens.accent)),
      );
    }
    // 「対象なし」は最上段固定（エラー時でも必ず選べる）
    final noneTile = _tile(
      id: null,
      title: '該当現場なし',
      subtitle: '該当現場がない・現場未登録',
      selected: widget.selectedSiteId == null,
    );
    if (_error != null) {
      return ListView(
        shrinkWrap: true,
        children: [
          noneTile,
          const Divider(color: FieldTokens.outline, height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(_error!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: FieldTokens.statusError, fontSize: 13)),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, color: FieldTokens.accent),
                  label: const Text('再試行',
                      style: TextStyle(color: FieldTokens.accent)),
                ),
              ],
            ),
          ),
        ],
      );
    }
    // 現場名の部分一致でローカルフィルタ（登録現場の並びは getSites の順を維持）。
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _sites
        : _sites.where((s) =>
            ((s as Map)['site_name'] as String? ?? '').toLowerCase().contains(q)).toList();
    // 検索0件でも「対象なし」は必ず残す（未選択の道を塞がない＝袋小路禁止）。
    if (shown.isEmpty && q.isNotEmpty) {
      return ListView(
        shrinkWrap: true,
        children: [
          noneTile,
          const Divider(color: FieldTokens.outline, height: 1),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('該当する現場がありません',
                textAlign: TextAlign.center,
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
          ),
        ],
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: shown.length + 1,
      separatorBuilder: (_, __) =>
          const Divider(color: FieldTokens.outline, height: 1),
      itemBuilder: (context, i) {
        if (i == 0) return noneTile;
        final site = shown[i - 1] as Map<String, dynamic>;
        final id = site['site_id'] as String?;
        final name = site['site_name'] as String? ?? '(名称未設定)';
        final addr = site['address'] as String?;
        return _tile(
          id: id,
          title: name,
          subtitle: (addr != null && addr.isNotEmpty) ? addr : null,
          selected: widget.selectedSiteId == id,
        );
      },
    );
  }

  Widget _tile({
    required String? id,
    required String title,
    String? subtitle,
    required bool selected,
  }) {
    return ListTile(
      title: Text(title,
          style: TextStyle(
            color: id == null ? FieldTokens.textFaint : FieldTokens.textBody,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          )),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: const TextStyle(color: FieldTokens.textSupport, fontSize: 12))
          : null,
      trailing:
          selected ? const Icon(Icons.check, color: FieldTokens.accent) : null,
      onTap: () => _choose(id, id == null ? null : title),
    );
  }
}

// 提出時刻を JST「MM/DD HH:mm」へ整形（端末TZ=Asia/Tokyo前提・punch_screen.dart と同型の手動整形）
String? _fmtSubmittedJst(String? iso) {
  if (iso == null) return null;
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return null;
  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mi = dt.minute.toString().padLeft(2, '0');
  return '$mm/$dd $hh:$mi';
}

// 職長承認ゲート：site_id が null の日報を承認する前に現場を選ばせる
class _SiteLinkGateDialog extends StatefulWidget {
  const _SiteLinkGateDialog({required this.report});
  final Map<String, dynamic> report;
  @override
  State<_SiteLinkGateDialog> createState() => _SiteLinkGateDialogState();
}

class _SiteLinkGateDialogState extends State<_SiteLinkGateDialog> {
  final SiteService _siteService = SiteService();
  List<dynamic> _sites = [];
  bool _loading = true;
  String? _error;
  String? _selectedId; // null = 現場未登録（事務へ回す）＝デフォルト

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _siteService.getSites();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _sites = result.data ?? const [];
      } else {
        _error = result.errorMessage ?? '現場一覧を取得できませんでした';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final worker = r['worker_name'] as String? ?? '(氏名不明)';
    final submitted = _fmtSubmittedJst(r['created_at'] as String?);  // 生ISO禁止・JST整形
    final gps = r['gps_address'] as String?;
    return AlertDialog(
      backgroundColor: FieldTokens.surfaceCard,
      title: const Text('現場の紐づけ',
          style: TextStyle(color: FieldTokens.brand, fontSize: 17)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 参考情報
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: FieldTokens.surfaceRaised,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('提出者', worker),
                  if (submitted != null) _infoRow('提出時刻', submitted),
                  if (gps != null && gps.isNotEmpty) _infoRow('GPS住所', gps),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(child: _buildList()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // キャンセル → null
          child: const Text('キャンセル',
              style: TextStyle(color: FieldTokens.textSupport)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {'site_id': _selectedId}),
          style: ElevatedButton.styleFrom(
            backgroundColor: FieldTokens.statusSuccess,
            foregroundColor: FieldTokens.onAccent,
          ),
          child: const Text('選択して承認'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style:
                    const TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ＋新規現場を登録 → 仮登録フォームへ。site_id が返ったら既存の現場選択フローに合流:
  // ゲートを {'site_id': ...} 付きで pop → 承認ハンドラが PATCH /reports/:id/site → 承認 を実行。
  Future<void> _openQuickRegister() async {
    final siteId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SiteQuickRegisterScreen(
          // a案: 対象日報の gps_address を渡し、画面は即開く（geocode を待たない）。
          // 住所欄の初期値になり、かつ画面側で gps_address→geocode→matchSites の重複チェックに使う。
          initialAddress: widget.report['gps_address'] as String?,
          // reports に lat/lng 列は無い（prod_schema）ため数値座標は渡さない（画面が gps_address を
          // geocode して座標化する）。職長の現在GPSは使わない（誤マッチ回避・確定設計）。
          lat: null,
          lng: null,
        ),
      ),
    );
    if (!mounted || siteId == null || siteId.isEmpty) return;
    Navigator.pop(context, {'site_id': siteId});
  }

  Widget _buildList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: FieldTokens.accent)),
      );
    }
    // 最上段固定は上から順に:
    //   ① ＋新規現場を登録（緑・仮登録の正のアクション＝OFFICE S3 ダイアログの並びに合わせ最上段）
    //   ② 現場未登録（事務へ回す）（オレンジ・既存の退避選択肢）
    // ①は選択(radio)ではなくアクションのため RadioListTile ではなくタップ行にする。
    final children = <Widget>[
      InkWell(
        onTap: _openQuickRegister,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: const Row(children: [
            Icon(Icons.add_location_alt, color: FieldTokens.statusSuccess, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text('＋新規現場を登録',
                  style: TextStyle(
                      color: FieldTokens.statusSuccess, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            Icon(Icons.chevron_right, color: FieldTokens.statusSuccess, size: 20),
          ]),
        ),
      ),
      const Divider(color: FieldTokens.outline, height: 1),
      RadioListTile<String?>(
        value: null,
        groupValue: _selectedId,
        onChanged: (v) => setState(() => _selectedId = v),
        activeColor: FieldTokens.statusWarning,
        title: const Text('現場未登録（事務へ回す）',
            style: TextStyle(
                color: FieldTokens.statusWarning,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
        subtitle: const Text('承認は完了・紐づけは事務の未紐づけ一覧に残る',
            style: TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
        contentPadding: EdgeInsets.zero,
      ),
    ];
    if (_error != null) {
      children.add(Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: FieldTokens.statusError, fontSize: 12)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon:
                  const Icon(Icons.refresh, color: FieldTokens.accent, size: 18),
              label:
                  const Text('再試行', style: TextStyle(color: FieldTokens.accent)),
            ),
          ],
        ),
      ));
    } else {
      for (final s in _sites) {
        final site = s as Map<String, dynamic>;
        final id = site['site_id'] as String?;
        final name = site['site_name'] as String? ?? '(名称未設定)';
        children.add(RadioListTile<String?>(
          value: id,
          groupValue: _selectedId,
          onChanged: (v) => setState(() => _selectedId = v),
          activeColor: FieldTokens.accent,
          title: Text(name,
              style:
                  const TextStyle(color: FieldTokens.textBody, fontSize: 14)),
          contentPadding: EdgeInsets.zero,
        ));
      }
    }
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

// ─────────────────────────────────────────────
// ① GPS バー
// ─────────────────────────────────────────────
class _GpsBar extends StatelessWidget {
  const _GpsBar({
    required this.address,
    required this.status,
    required this.loading,
    required this.onRefresh,
  });
  final String address;
  /// fetchGpsAddress(main.dart) の status。'' = 未取得。
  final String status;
  final bool loading;
  final VoidCallback onRefresh;

  // v2: 枠なし・地の上に直接置く小さな1行（「現在地 <住所>」）。
  // 更新アイコンは残す＝この画面で唯一の手動GPS再取得導線であり、
  // _fetchGps → _calculateRoutes（金額の再計算）に繋がっているため落とせない。

  // status で表示を分岐する。座標や権限エラー文字列を「住所」のふりをして
  // 出さないことが目的（嘘をつかない・再取得の導線を必ず添える）。
  String _displayText() {
    if (loading) return '取得中...';
    if (status == 'ok') return address;
    if (status == 'address_failed') return '住所を取得できません（タップで再取得）';
    if (status == 'gps_failed') return '$address（タップで再取得）';
    return '未取得';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('現在地',
              style: TextStyle(color: FieldTokens.textFaint, fontSize: 11)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _displayText(),
              style: const TextStyle(
                  color: FieldTokens.textFaint, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onRefresh,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(left: 8, top: 1),
              child: Icon(Icons.refresh,
                  color: FieldTokens.textFaint, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 打刻タブ 天気パネル（JsMainShell → PunchScreen へ渡す Widget）
// ─────────────────────────────────────────────
class _PunchWeatherPanel extends StatefulWidget {
  const _PunchWeatherPanel({
    required this.weather,
    required this.forecast,
    required this.loading,
  });
  final _WeatherData? weather;
  final List<_ForecastDay> forecast;
  final bool loading;

  @override
  State<_PunchWeatherPanel> createState() => _PunchWeatherPanelState();
}

class _PunchWeatherPanelState extends State<_PunchWeatherPanel> {
  bool _showForecast = false;

  @override
  Widget build(BuildContext context) {
    // カード撤去: 箱で囲まず、区切りは1pxの線と余白だけで表す。
    // 横padding は PunchScreen 本体（punch_screen.dart の horizontal:20）と
    // 揃えて、1pxの線が本文の区切り線と同じ位置で始まるようにする。
    return Container(
      color: FieldTokens.bgBase,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── WBGT行（独立1行・ボス裁定の配置替え）────────────────────
          //   会社名・氏名の行（AppBar bottom）と天気メトリクス行の間に入る。
          //   この天気パネルは本文の先頭に置かれる（punch_screen.dart の本文先頭）ため、
          //   パネルの先頭＝ヘッダー直下＝狙いの位置になる。
          //   【左】WBGTバッジ（値＋5段階ラベル）
          //   【右】注意文（alert.message）＝Expanded で残り幅を全部取り、右寄せ1行
          //   ★非表示規約: wbgt が未取得なら「この行ごと」出さない。
          //     alert が info・無しのときは注意文だけ消え、バッジは残る
          //     （_WeatherAlertLine が SizedBox.shrink を返す）。
          //   ★バッジ・注意文を描くのはここだけ。ヘッダーにも他のどこにも置かない。
          if (_hasWbgt(widget.weather)) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                // ★バッジと注意文の上下中心を揃える（バッジ縮小後も高さ差が出る）。
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _WbgtBadge(weather: widget.weather!),
                  const SizedBox(width: 8),
                  // ★Expanded（tight）で残り幅を確定させる。これが FittedBox の
                  //   「どこまで縮めれば入るか」の基準になる。Flexible（loose）だと
                  //   箱が内容幅まで縮んで右端が動き、右寄せが効かない。
                  Expanded(child: _WeatherAlertLine(weather: widget.weather!)),
                ],
              ),
            ),
            const Divider(color: FieldTokens.outline, thickness: 1, height: 1),
            const SizedBox(height: 8),
          ],
          // 天気メトリクス行。週間予報はこの行をタップしたときだけ開く（この行の展開）。
          _PunchWeatherRow(
            weather:      widget.weather,
            loading:      widget.loading,
            expanded:     _showForecast,
            onToggle:     () => setState(() => _showForecast = !_showForecast),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve:    Curves.easeInOut,
            child: _showForecast && widget.forecast.isNotEmpty
                ? _PunchForecastStrip(forecast: widget.forecast)
                : const SizedBox.shrink(),
          ),
          const Divider(color: FieldTokens.outline, thickness: 1, height: 1),
        ],
      ),
    );
  }
}

class _PunchWeatherRow extends StatelessWidget {
  const _PunchWeatherRow({
    required this.weather,
    required this.loading,
    required this.expanded,
    required this.onToggle,
  });
  final _WeatherData? weather;
  final bool loading;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    // 箱なし（背景色・角丸・枠を撤去）。気温/降水/風速/天気を横4分割で並べるだけ。
    // 折りたたみトグル（onToggle）は従来どおり行全体タップで動く。
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 56,
        child: loading
            ? const Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: FieldTokens.accent)))
            : weather == null
                ? const Center(
                    child: Text('天気データ取得中...',
                        style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)))
                : Row(
                    children: [
                      _PunchWeatherItem(
                          label: '気温',
                          value: '${weather!.tempC.round()}',
                          unit:  '°C'),
                      // ★3状態規約: 値あり='N' / 0='0' / null(未取得)='—'。
                      //   `?? 0` を足さない（0% という嘘を作らないため）。
                      //   単位の '%' も未取得のときは出さない（'—%' にしない）。
                      _PunchWeatherItem(
                          label: '降水',
                          value: weather!.precipPct?.toString() ?? '—',
                          unit:  weather!.precipPct != null ? '%' : '',
                          valueColor: (weather!.precipPct ?? 0) >= 50
                              ? FieldTokens.externalBlue
                              : null),
                      _PunchWeatherItem(
                          label: '風速',
                          value: weather!.windSpeed != null
                              ? weather!.windSpeed!.toStringAsFixed(1)
                              : '--',
                          unit:  'm/s'),
                      _PunchWeatherItem(
                          label: '天気',
                          value: weather!.icon,
                          isEmoji: true),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: FieldTokens.textSupport,
                        size: 18,
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _PunchWeatherItem extends StatelessWidget {
  const _PunchWeatherItem({
    required this.label,
    required this.value,
    this.unit,
    this.valueColor,
    this.isEmoji = false,
  });
  final String label;
  final String value;
  final String? unit;   // 数字と分けて小さく描く（単位は情報を落とさず脇役にする）
  final Color? valueColor;
  final bool isEmoji;

  @override
  Widget build(BuildContext context) {
    // 数字が主役: 値20px / 単位10px / ラベル9px。
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: FieldTokens.textSupport, fontSize: 9)),
          const SizedBox(height: 2),
          isEmoji
              ? Text(value, style: const TextStyle(fontSize: 22))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value,
                        style: TextStyle(
                            color: valueColor ?? FieldTokens.textBody,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            height: 1.0)),
                    if (unit != null)
                      Text(unit!,
                          style: const TextStyle(
                              color: FieldTokens.textSupport, fontSize: 10)),
                  ],
                ),
        ],
      ),
    );
  }
}

// WBGT行 右: 気象アラート1行（BE の alert{level,message}・weatherEngine.js の computeAlert）。
//
// ★判定・色は OFFICE（dashboard_screen.dart の showAlert 判定）と同一仕様:
//   ・level=='warning' / 'danger' のときだけ出す。
//   ・'info' は出さない。info は「夏季です」「花粉シーズン」「ご安全に」等の
//     常時帯で、毎日出ると帯そのものが読み飛ばされる＝要る時に効かなくなる。
//   ・alert キー欠落（旧キャッシュ・旧サーバ）・message 空も出さない。
//   ・面塗りせず文字色のみ。アイコンは持たない（message の先頭に BE が絵文字を含む）。
// ★message は BE の完成文をそのまま描く（絵文字込み・端末で組み立て直さない）。
//
// ★1行表示の約束（ボス裁定・案C＝自動縮小）:
//   FittedBox(fit: BoxFit.scaleDown) で「全文が残り幅に収まるまで縮める」。
//   ・基準は fontSize 12。収まるときは縮めない（scaleDown は拡大しない）。
//   ・maxLines:1 / softWrap:false は維持＝縮んでも必ず1行。
//   ・文字は1文字も欠けない。ellipsis（…）も clip も発生しない構成にしてある:
//     FittedBox は子へ幅の制限を渡さないため Text は自然幅で組まれ、
//     はみ出しではなく「拡大率」で辻褄を合わせる。だから overflow は visible。
//   ・alignment は centerRight。呼び手の Expanded が確定させた箱の右端に貼り付き、
//     縮んでも右端が動かない（バッジは左端に固定・注意文は右端に固定）。
class _WeatherAlertLine extends StatelessWidget {
  const _WeatherAlertLine({required this.weather});
  final _WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final level = weather.alertLevel;
    final msg   = weather.alertMessage;
    if ((level != 'warning' && level != 'danger') || msg == null || msg.isEmpty) {
      return const SizedBox.shrink();
    }
    // 色は FieldTokens の用途名トークンをそのまま使う（BE の level 名と1対1）。
    // 新色は作らない。WBGT の5色（FieldTokens.wbgt*）は熱中症危険度の物差しなので
    // 流用しない（すぐ上の WBGT バッジと同色になると意味が混ざる）。
    final color = level == 'danger'
        ? FieldTokens.statusError
        : FieldTokens.statusWarning;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        msg,
        maxLines: 1,
        softWrap: false,
        // ★FittedBox が子へ幅の制限を渡さない＝Text 側でのはみ出しは起きない。
        //   clip / ellipsis にすると「切れる経路がある」と読めてしまうので visible。
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}

class _PunchForecastStrip extends StatelessWidget {
  const _PunchForecastStrip({required this.forecast});
  final List<_ForecastDay> forecast;

  @override
  Widget build(BuildContext context) {
    // 箱撤去: 上に1pxの線を置き、余白だけで週間予報の帯を区切る。
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FieldTokens.outline)),
      ),
      child: Row(
        children: forecast.map((day) {
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(day.weekday,
                    style: const TextStyle(
                        color: FieldTokens.textSupport,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(day.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 2),
                Text('${day.maxC.round()}°',
                    style: const TextStyle(
                        color: FieldTokens.statusError,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
                Text('${day.minC.round()}°',
                    style: const TextStyle(
                        color: FieldTokens.externalBlue, fontSize: 11)),
                // ★3状態規約: 値あり='N%' / 0='0%' / null(未取得)='—'。
                //   移設前は `> 0` で 0% を丸ごと隠していたが、それだと
                //   「降らない日」と「取れていない日」が同じ空欄になっていた。
                Text(day.precipPct != null ? '${day.precipPct}%' : '—',
                    style: TextStyle(
                        color: (day.precipPct ?? 0) >= 50
                            ? FieldTokens.externalBlue
                            : FieldTokens.textSupport,
                        fontSize: 9)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// WBGT行 左: WBGTバッジ（値＋5段階ラベル）。
//
// ★枠付きバッジの中身は従来のまま流用。塗り面なし・枠だけ、数字が主役
//   （値14px / ラベル10px＝右の注意文12px とのバランスで一回り縮小・ボス裁定）、
//   色は _wbgtColor（閾値 21/25/28/31 は環境省指針）。
//   外枠（Padding や Row）は持たない＝置き場所ごとの余白は呼び手が決める。
// ★値もラベルも BE（wbgt.value / wbgt.level）。端末では計算しない。
//   BE は wbgt を常時返す（tools_weather.js の応答契約）ため通年表示は現行のまま。
// ★非表示規約: 未取得（value か level が無い）ならバッジごと出さない。
//   実際には呼び手が _hasWbgt で先に弾くが、この widget 単体でも安全側に倒す。
class _WbgtBadge extends StatelessWidget {
  const _WbgtBadge({required this.weather});
  final _WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final wbgt  = weather.wbgtValue;
    final level = _kWbgtLabelJa[weather.wbgtLevel ?? ''];
    if (wbgt == null || level == null) return const SizedBox.shrink();
    final color = _wbgtColor(wbgt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          const Text('WBGT ',
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 10)),
          Text('${wbgt.round()}',
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  height: 1.0)),
          const SizedBox(width: 5),
          Text(level,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// スケルトンローディング
// ─────────────────────────────────────────────
class _HomeSkeletonBody extends StatefulWidget {
  const _HomeSkeletonBody();
  @override
  State<_HomeSkeletonBody> createState() => _HomeSkeletonBodyState();
}

class _HomeSkeletonBodyState extends State<_HomeSkeletonBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.25, end: 0.55)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Widget _box({double h = 16, double? w, double radius = 8}) =>
      AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: FieldTokens.textBody.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _box(h: 44, w: double.infinity, radius: 10),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _box(h: 90, radius: 10)),
          const SizedBox(width: 8),
          Expanded(child: _box(h: 90, radius: 10)),
        ]),
        const SizedBox(height: 8),
        _box(h: 34, w: double.infinity, radius: 8),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < 4; i++) ...[
            Expanded(child: _box(h: 56, radius: 8)),
            if (i < 3) const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: _box(h: double.infinity, w: double.infinity, radius: 10),
        ),
        const SizedBox(height: 8),
        _box(h: 52, w: double.infinity, radius: 10),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// 健康診断警告バナー
// ─────────────────────────────────────────────
class _HealthCheckBanner extends StatelessWidget {
  const _HealthCheckBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final isDanger = message.startsWith('🔴');
    final base =
        isDanger ? FieldTokens.statusError : FieldTokens.statusWarning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: base.withValues(alpha: 0.6)),
      ),
      child: Text(
        message,
        style: TextStyle(
            color: isDanger
                ? FieldTokens.statusError
                : FieldTokens.statusWarning,
            fontSize: 12,
            fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ③.5 起点選択（自宅 / 会社）
// ─────────────────────────────────────────────
class _OriginSelector extends StatelessWidget {
  const _OriginSelector({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  // v2: 「どこから」チップ。onChanged の中身は呼び出し側のまま（await _calculateRoutes() 維持）。
  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['home', 'office'].map((type) {
        final label = type == 'home' ? '自宅' : '会社';
        final sel = selected == type;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? FieldTokens.outlineStrong : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: sel
                        ? FieldTokens.textSupport
                        : FieldTokens.outline),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: sel
                      ? FieldTokens.textBody
                      : FieldTokens.textSupport,
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────
// ④ 移動手段 4択横並び
// ─────────────────────────────────────────────
class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.selectedSet,
    required this.onTap,
    required this.onDoubleTap,
  });
  final Set<TransportType> selectedSet;
  final Function(TransportType) onTap;
  final Function(TransportType) onDoubleTap;

  static const _options = [
    TransportType.car,
    TransportType.train,
    TransportType.bus,
    TransportType.other,
  ];

  // v2: 「なにで」チップ。onTap/onDoubleTap の中身（排他判定・駐車情報リセット・
  // _saveWorkStatus('moving')・_saveDraft）は呼び出し側にそのまま残してある。
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        children: _options.map((t) {
          final sel = selectedSet.contains(t);
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(t),
              onDoubleTap: () => onDoubleTap(t),
              child: Container(
                margin: EdgeInsets.only(right: t != _options.last ? 8 : 0),
                decoration: BoxDecoration(
                  color: sel ? FieldTokens.outlineStrong : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: sel
                          ? FieldTokens.textSupport
                          : FieldTokens.outline),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(t.icon,
                        size: 18,
                        color: sel
                            ? FieldTokens.textBody
                            : FieldTokens.textSupport),
                    const SizedBox(height: 3),
                    Text(t.label,
                        style: TextStyle(
                            color: sel
                                ? FieldTokens.textBody
                                : FieldTokens.textSupport,
                            fontSize: 11,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ⑤ 作業内容セクション（マイク / カメラ / テキスト）
// ─────────────────────────────────────────────
class _WorkContentSection extends StatelessWidget {
  const _WorkContentSection({
    required this.controller,
    this.showMediaButtons = false,
    this.isListening = false,
    this.onMicTap,
  });
  final TextEditingController controller;
  final bool showMediaButtons;
  final bool isListening;
  final VoidCallback? onMicTap;

  // v2: カード内に置かれる前提。外枠は _FormCard 側が持つので自前の枠は張らない。
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('作業内容',
                  style: TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12)),
            ),
            if (showMediaButtons)
              _SmallMediaButton(
                icon: isListening ? Icons.mic : Icons.mic_none,
                active: isListening,
                onTap: onMicTap,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: FieldTokens.bgBase,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: FieldTokens.outline),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: TextField(
              controller: controller,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '1階の配線、コンセント10箇所　など',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintStyle:
                    TextStyle(color: FieldTokens.textFaint, fontSize: 13),
              ),
              style: const TextStyle(
                  color: FieldTokens.textBody, fontSize: 14),
            ),
          ),
        ),
        // 作業5: 未記入でも報告できることを明示（必須と誤解させない）
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('※未記入のままでも報告できます',
              style: TextStyle(color: FieldTokens.textFaint, fontSize: 11)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// メディアボタン（マイク / カメラ）
// ─────────────────────────────────────────────
class _SmallMediaButton extends StatelessWidget {
  const _SmallMediaButton({
    required this.icon,
    required this.active,
    this.onTap,
  });
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40,
      height: 32,
      decoration: BoxDecoration(
        color: active ? FieldTokens.outlineStrong : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: active ? FieldTokens.textSupport : FieldTokens.outline),
      ),
      child: Icon(icon,
          size: 16,
          color: active ? FieldTokens.textBody : FieldTokens.textSupport),
    ),
  );
}

// ─────────────────────────────────────────────
// 音声入力ダイアログ
// ─────────────────────────────────────────────
class _VoiceInputDialog extends StatefulWidget {
  const _VoiceInputDialog(
      {required this.manager,
      required this.onConfirm,
      required this.onCancel});
  final SpeechManager manager;
  final void Function(String) onConfirm;
  final VoidCallback onCancel;

  @override
  State<_VoiceInputDialog> createState() => _VoiceInputDialogState();
}

class _VoiceInputDialogState extends State<_VoiceInputDialog>
    with SingleTickerProviderStateMixin {
  String _text          = '';
  bool   _listening     = false;
  bool   _manualStop    = false;
  String _committed     = '';
  int    _emptyRestarts = 0;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _start();
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  void _onResult(String text, bool isFinal) {
    if (!mounted) return;
    if (text.trim().isNotEmpty) _emptyRestarts = 0;
    setState(() => _text = '$_committed$text'.trim());
    if (isFinal && text.trim().isNotEmpty) _committed = '$_committed$text ';
  }

  void _onSessionDone() {
    if (!mounted || !_listening || _manualStop) return;
    if (++_emptyRestarts > 6) { setState(() => _listening = false); return; }
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted && _listening && !_manualStop) {
        widget.manager.startListening(
          onResult: _onResult,
          onSessionDone: _onSessionDone,
          onPermanentError: _onPermanentError,
        );
      }
    });
  }

  void _onPermanentError(String errorMsg) async {
    if (!mounted) return;
    setState(() => _listening = false);
    final ok = await widget.manager.hasPermission;
    if (!ok && mounted) {
      showJsSnackbar(context, 'マイクの権限がありません。設定から許可してください', isError: true);
    }
  }

  void _start() {
    _listening     = true;
    _manualStop    = false;
    _emptyRestarts = 0;
    _committed     = _text.isEmpty ? '' : '${_text.trim()} ';
    setState(() {});
    widget.manager.startListening(
      onResult: _onResult,
      onSessionDone: _onSessionDone,
      onPermanentError: _onPermanentError,
    );
  }

  void _stop() {
    _manualStop = true;
    _listening  = false;
    widget.manager.stop();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: FieldTokens.surfaceCard,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('🎤 作業内容 音声入力',
        style: TextStyle(color: FieldTokens.accent)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _listening
                  ? FieldTokens.accent.withValues(
                      alpha: 0.15 + _pulse.value * 0.15)
                  : FieldTokens.surfaceCard,
            ),
            child: Icon(
                _listening ? Icons.mic : Icons.mic_off,
                color:
                    _listening ? FieldTokens.accent : FieldTokens.textSupport,
                size: 32),
          ),
        ),
        const SizedBox(height: 6),
        Text(_listening ? '聞いています...' : '認識完了',
            style: TextStyle(
                color: _listening ? FieldTokens.accent : FieldTokens.textSupport,
                fontSize: 12)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: FieldTokens.surfaceCard,
              borderRadius: BorderRadius.circular(8)),
          constraints: const BoxConstraints(minHeight: 56),
          child: Text(
            _text.isEmpty
                ? '例：1階電気配線工事 コンセント10箇所設置'
                : _text,
            style: TextStyle(
                color: _text.isEmpty
                    ? FieldTokens.textSupport
                    : FieldTokens.textBody,
                fontSize: _text.isEmpty ? 12 : 14,
                height: 1.5),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
          onPressed: widget.onCancel,
          child: const Text('キャンセル',
              style: TextStyle(color: FieldTokens.textSupport))),
      if (_listening)
        TextButton(
            onPressed: _stop,
            child: const Text('停止',
                style: TextStyle(color: FieldTokens.accent))),
      if (!_listening && _text.isNotEmpty)
        ElevatedButton(
            onPressed: () => widget.onConfirm(_text),
            child: const Text('確定')),
    ],
  );
}

// ─────────────────────────────────────────────
// ルート情報バー
// ─────────────────────────────────────────────
class _RouteInfoBar extends StatelessWidget {
  const _RouteInfoBar({
    required this.transport,
    required this.comparisons,
    required this.loading,
    this.failed = false,
    this.fromCache = false,
    this.onRetry,
  });
  final TransportType transport;
  final Map<String, dynamic> comparisons;
  final bool loading;
  /// 取得に失敗した（timeout/network/http/空）。タップで再取得できる状態。
  final bool failed;
  /// いま出している値が鍵付きキャッシュ由来。「前回の目安」と明示する。
  final bool fromCache;
  final Future<void> Function()? onRetry;

  // 枠だけの共通シェル
  Widget _shell({required Widget child, Color? borderColor}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: FieldTokens.bgBase,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor ?? FieldTokens.outline),
        ),
        child: child,
      );

  // 取得できなかった（タップで再取得）
  Widget _failedBar() => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onRetry == null ? null : () => onRetry!(),
          borderRadius: BorderRadius.circular(10),
          child: _shell(
            borderColor: FieldTokens.statusWarning,
            child: const Row(children: [
              Icon(Icons.refresh, color: FieldTokens.statusWarning, size: 14),
              SizedBox(width: 6),
              Expanded(
                child: Text('移動情報を取得できません（タップで再取得）',
                    style: TextStyle(
                        color: FieldTokens.statusWarning, fontSize: 12)),
              ),
            ]),
          ),
        ),
      );

  // 取得はできたが、いま選んでいる手段のキーが無い
  Widget _noDataForMode() => _shell(
        child: const Row(children: [
          Icon(Icons.route, color: FieldTokens.textFaint, size: 14),
          SizedBox(width: 6),
          Expanded(
            child: Text('この手段の目安は取得できません',
                style: TextStyle(color: FieldTokens.textFaint, fontSize: 12)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: FieldTokens.bgBase,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FieldTokens.outline),
        ),
        child: const Row(children: [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: FieldTokens.textSupport)),
          SizedBox(width: 8),
          Text('ルート計算中...',
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
        ]),
      );
    }

    // 取得そのものが失敗している（＝再取得すれば直る可能性がある）
    if (failed) return _failedBar();

    // 表示文言の組み立ては _routeParts に一本化（確認画面のスナップショットと同じ値になる）
    final parts = _routeParts(transport, comparisons);
    final timeStr = parts.time;
    final costStr = parts.cost;
    final distStr = parts.dist;

    // 取得は成功したが、いま選んでいる手段のキーがレスポンスに無い
    // （BE は walking/bicycling を返さない＝徒歩・自転車は構造的にここへ来る）
    if (timeStr == null) return _noDataForMode();

    return _shell(
      borderColor: fromCache ? FieldTokens.textFaint : null,
      child: Row(children: [
        const Icon(Icons.route, color: FieldTokens.textSupport, size: 14),
        const SizedBox(width: 6),
        if (distStr != null) ...[
          Flexible(
            child: Text(distStr,
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
          ),
          const SizedBox(width: 8),
        ],
        const Icon(Icons.access_time, color: FieldTokens.textSupport, size: 13),
        const SizedBox(width: 3),
        Text(timeStr,
            style: const TextStyle(
                color: FieldTokens.textBody,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        if (costStr != null) ...[
          const SizedBox(width: 10),
          Text(costStr,
              style: const TextStyle(
                  color: FieldTokens.textBody,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
        // キャッシュ由来なら小さく明示する（再計算が終われば消える＝嘘をつかない）
        if (fromCache) ...[
          const SizedBox(width: 8),
          const Text('前回の目安',
              style: TextStyle(color: FieldTokens.textFaint, fontSize: 10)),
        ],
      ]),
    );
  }
}

// ルート表示文言の組み立て。元 _RouteInfoBar.build 内の分岐をそのまま関数へ出したもの。
// 判定順・条件・書式は1文字も変えていない（確認画面と表示バーで同じ値を使うため共有化）。
({String? time, String? cost, String? dist}) _routeParts(
    TransportType transport, Map<String, dynamic> comparisons) {
  String? timeStr, costStr, distStr;

  if (comparisons.isNotEmpty) {
    if (transport == TransportType.car || transport == TransportType.other) {
      final c = comparisons['car'] as CarRoute?;
      if (c != null) {
        timeStr = '${c.time}分';
        distStr = c.distanceText;
        if (c.gasCost > 0) costStr = '⛽¥${c.gasCost}';
      }
    } else if (transport == TransportType.train ||
        transport == TransportType.bus) {
      final t = comparisons['transit'] as TransitRoute?;
      if (t != null) {
        timeStr = '${t.time}分';
        costStr = '💴¥${t.fareIc}';
        if (t.depStation.isNotEmpty && t.arrStation.isNotEmpty) {
          distStr = '${t.depStation}→${t.arrStation}';
        }
      }
    } else if (transport == TransportType.bike) {
      final b = comparisons['bicycling'] as SimpleRoute?;
      if (b != null) { timeStr = b.duration; distStr = b.distance; }
    } else {
      final w = comparisons['walking'] as SimpleRoute?;
      if (w != null) { timeStr = w.duration; distStr = w.distance; }
    }
  }

  return (time: timeStr, cost: costStr, dist: distStr);
}

// 作業2: 選択中の【全手段】の内訳を作る。
// 判定順・条件・書式を二重に書かないため、要素ごとに上の _routeParts をそのまま呼ぶ。
//
// ★train と bus の重複回避（理由）:
//   _routeParts は train も bus も同じ comparisons['transit'] を参照する。
//   BE の POST /routes/compare が返すのは route_transit 1本だけで、バス単独の経路検索は
//   存在しない（js-office-api/routes/routes-calc.js は transit と car の2種のみ算出）。
//   したがって train と bus を同時に選ぶと「同一ルートの運賃・所要時間」が2行に
//   重複計上されてしまう。transit を参照する手段は最初の1件だけを残す。
//
// 値が取れない手段も行は残す（dist/cost が null＝表示側で '—'）。
// 「選んだのに行が消える」ほうが利用者には不可解なため。
List<({String label, String? dist, String? cost})> _routeBreakdown(
    Set<TransportType> transports, Map<String, dynamic> comparisons) {
  final rows = <({String label, String? dist, String? cost})>[];
  var transitUsed = false;
  for (final t in transports) {
    final usesTransit = t == TransportType.train || t == TransportType.bus;
    if (usesTransit) {
      if (transitUsed) continue;   // 同一 transit ルートの二重計上を防ぐ
      transitUsed = true;
    }
    final p = _routeParts(t, comparisons);
    rows.add((label: t.label, dist: p.dist, cost: p.cost));
  }
  return rows;
}

// 作業1: ルート検索結果(_routeComparisons)から【提出時点の経費スナップショット】を作る。
//   ★これは提出した瞬間の値の写し。後から燃費単価や運賃が変わっても、この報告の
//     過去の値は書き換わらない（BE側で reports 列に保存＝不変のスナップショット）。
//   ・4列（distance_km / fuel_cost / fare / toll）は選択中の全手段の【合計】。
//   ・breakdown は手段ごとの【内訳】配列（例: [{mode:'car',distance_km:12.3,...},{mode:'train',fare:620}]）。
//   ・train と bus は同一 transit ルートのため 1件だけ計上（_routeBreakdown の transitUsed と同判定）。
//     car と other も同一 comparisons['car'] を指すため 1件だけ計上する
//     （同一ルートの toll/fuel を二重計上しない＝例の内訳が car 1件なのと整合）。
//   ・値が取れない場合は null（0 で埋めない）。合計はどの手段も寄与しなければ null のまま。
({double? distanceKm, int? fuelCost, int? fare, int? toll,
  List<Map<String, dynamic>> breakdown}) _expenseSnapshot(
    Set<TransportType> transports, Map<String, dynamic> comparisons) {
  final breakdown = <Map<String, dynamic>>[];
  double? distanceKm;
  int? fuelCost, fare, toll;
  var transitUsed = false, carUsed = false;

  for (final t in transports) {
    final usesTransit = t == TransportType.train || t == TransportType.bus;
    final usesCar     = t == TransportType.car   || t == TransportType.other;
    if (usesTransit) {
      if (transitUsed) continue;   // 同一 transit ルートの二重計上を防ぐ
      transitUsed = true;
      final tr = comparisons['transit'] as TransitRoute?;
      final f = tr?.fareIc;
      breakdown.add({'mode': t.name, if (f != null) 'fare': f});
      if (f != null) fare = (fare ?? 0) + f;
    } else if (usesCar) {
      if (carUsed) continue;       // car と other は同一 comparisons['car']＝1件のみ
      carUsed = true;
      final c = comparisons['car'] as CarRoute?;
      final km   = c != null ? c.distanceM / 1000.0 : null;
      final fuel = c?.gasCost;
      final tl   = c?.tollNormal;
      breakdown.add({
        'mode': t.name,
        if (km != null)   'distance_km': km,
        if (fuel != null) 'fuel_cost': fuel,
        if (tl != null)   'toll': tl,
      });
      if (km != null)   distanceKm = (distanceKm ?? 0) + km;
      if (fuel != null) fuelCost   = (fuelCost ?? 0) + fuel;
      if (tl != null)   toll       = (toll ?? 0) + tl;
    }
    // bike/walk は経費列を持たないため内訳・合計とも計上しない
  }
  return (distanceKm: distanceKm, fuelCost: fuelCost, fare: fare,
          toll: toll, breakdown: breakdown);
}

// ─────────────────────────────────────────────
// 職長管理・集計タブ本体（3入口）
// ─────────────────────────────────────────────
// 公開化（管理・履歴タブから同一実体を呼ぶため）。中身は1行も変更していない。
class ForemanManagementBody extends StatelessWidget {
  const ForemanManagementBody({super.key});

  @override
  Widget build(BuildContext context) {
    // 「📅 カレンダー」は撤去した（管理・履歴タブの1つ目が同じ CalendarTab を持つため二重表示だった）。
    // CalendarTab クラス本体は削除していない（management_history_screen.dart で使用中）。
    // 「👥 社員」「🏢 協力」の中身（_StaffTab / _CooperationTab）は1行も変更していない。
    // ★3つ目の節「⏱ 勤怠」を足した。tabs と children は同じ並び・同じ数で持つ
    //   （片方だけ足すと index がずれて別の節が開く）。length も一緒に動かす。
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: FieldTokens.surfaceCard,
            child: const TabBar(
              tabs: [
                Tab(text: '👥 社員'),
                Tab(text: '🏢 協力'),
                Tab(text: '⏱ 勤怠'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _StaffTab(),
                _CooperationTab(),
                _AttendanceConfirmTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────
// 勤怠の確認事項（職長は【見るだけ】）
// ─────────────────────────────────────────────
// ★この節は決着（承認・却下）の口を1つも持たない。確定は事務と社長の仕事で、
//   BE も職長には can_resolve=false / cannot_resolve_reason='BOSS_CONFIRMATION_FORBIDDEN'
//   しか返さない。押せないボタンを置くと「不具合で押せない」と読まれるため、
//   ボタンを置かずに『確定は事務または社長が行います』と先に書く。
// ★1行＝1日。日付・合計件数・種別ごとの内訳を出し、0の内訳は描かない
//   （同ファイルの ReviewTab の日付行と同じ掟）。
// ★見た目は ReviewTab の日付行をそのまま写す（surfaceCard / 角丸12 / margin bottom 8 /
//   padding 14 / 文字サイズと色）。新しい色・余白・フォントは足していない。
//   唯一の違いは行末の chevron を置かないこと＝開く先が無いため（嘘の記号を作らない）。
class _AttendanceConfirmTab extends StatefulWidget {
  const _AttendanceConfirmTab();
  @override
  State<_AttendanceConfirmTab> createState() => _AttendanceConfirmTabState();
}

class _AttendanceConfirmTabState extends State<_AttendanceConfirmTab> {
  List<Map<String, dynamic>> _rows = [];
  bool    _loading = false;
  bool    _failed  = false;
  String? _failMessage;   // BE が理由を言っているならそのまま出す（丸めない）

  // confirm_type → 内訳の見出し語。BE の3種以外が来たら内訳に出さない
  //   （知らない種別を勝手に名付けると嘘になる。合計件数には数える）。
  static const Map<String, String> _kTypeLabel = {
    'forgot_punch':       '打刻漏れ',
    'comp_off':           '休日の打刻',
    'overtime_or_forgot': '残業',
  };
  // 内訳の並びは固定（日によって順が入れ替わらないようにする）。
  static const List<String> _kTypeOrder = [
    'forgot_punch', 'comp_off', 'overtime_or_forgot',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _failed = false; _failMessage = null; });
    final res = await WorkModeService().fetchAttendanceConfirmations();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _rows = res.data ?? const <Map<String, dynamic>>[];
      } else {
        _failed      = true;
        _failMessage = res.errorMessage;
      }
    });
  }

  // 業務日。列の work_date が無い行は raw_value の work_date へ落ちる
  //   （BE は勤怠行が無い申告でも raw_value に日付を持つ）。どちらも無ければ空。
  static String _dateKey(Map<String, dynamic> r) {
    final direct = r['work_date'];
    if (direct is String && direct.length >= 10) return direct.substring(0, 10);
    final raw = r['raw_value'];
    if (raw is Map) {
      final d = raw['work_date'];
      if (d is String && d.length >= 10) return d.substring(0, 10);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    // 日付グループ化。日付が読めない行は行にできないので飛ばす
    //   （同ファイルの ReviewTab の日付グループ化と同じ扱い）。
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final r in _rows) {
      final key = _dateKey(r);
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []).add(r);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        _noticeBar(),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: FieldTokens.accent))
              : _failed
                  ? _failView()
                  : sortedDates.isEmpty
                      ? const Center(
                          child: Text('確認事項はありません',
                              style: TextStyle(
                                  color: FieldTokens.textSupport, fontSize: 13)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: sortedDates.length,
                          itemBuilder: (_, i) {
                            final ds = sortedDates[i];
                            return _dayRow(ds, grouped[ds] ?? const []);
                          },
                        ),
        ),
      ],
    );
  }

  // 裁定B の一文。読込中・0件・失敗のいずれでも常に見える位置（行より上）に置く。
  // 器は同ファイルの ReviewTab の1行バナーと同じ形（surfaceCard・左アイコン・小さい文字）。
  Widget _noticeBar() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: FieldTokens.surfaceCard,
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: FieldTokens.textSupport, size: 14),
            SizedBox(width: 6),
            Expanded(
              child: Text('確定は事務または社長が行います（ここでは内容の確認のみできます）',
                  style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
            ),
          ],
        ),
      );

  // 失敗は黙って空にしない。理由（BE の言い分）とやり直す手を必ず出す。
  // 形は同ファイルの ReviewTab の失敗ビューをそのまま写す。
  Widget _failView() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: FieldTokens.statusWarning, size: 32),
              const SizedBox(height: 8),
              const Text('確認事項を取得できませんでした',
                  style: TextStyle(
                      color: FieldTokens.statusWarning, fontSize: 13)),
              if (_failMessage != null && _failMessage!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_failMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('再試行'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FieldTokens.textBody,
                  side: const BorderSide(
                      color: FieldTokens.textBody, width: 1.5),
                ),
              ),
            ],
          ),
        ),
      );

  // 1行 = 1日。合計 = その日の全件。内訳は0のものを出さない。
  //   例: 7/27（月）　3件　打刻漏れ2 残業1
  Widget _dayRow(String ds, List<Map<String, dynamic>> rows) {
    final parts = ds.split('-').map(int.parse).toList();
    final date  = DateTime(parts[0], parts[1], parts[2]);

    final Map<String, int> byType = {};
    for (final r in rows) {
      final t = r['confirm_type'];
      if (t is String && t.isNotEmpty) {
        byType[t] = (byType[t] ?? 0) + 1;
      }
    }
    // 内訳に出すのは名前の分かる3種だけ。並びは _kTypeOrder に固定する。
    final breakdown = <String>[
      for (final t in _kTypeOrder)
        if ((byType[t] ?? 0) > 0) '${_kTypeLabel[t]}${byType[t]}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('${date.month}/${date.day}（${_kWeekLabels[date.weekday % 7]}）',
              style: const TextStyle(
                  color: FieldTokens.textBody,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Text('${rows.length}件',
              style: const TextStyle(
                  color: FieldTokens.textSupport, fontSize: 13)),
          const Spacer(),
          for (int i = 0; i < breakdown.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Text(breakdown[i],
                style: const TextStyle(
                    color: FieldTokens.textSupport,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────
// 承認タブ: 対応が必要な報告を「日付ごとの1行」で並べる
// ─────────────────────────────────────────────
// 旧実装は [承認待ち/差戻し] の2サブタブで、承認待ち側は getReports(limit:50)＝
// 直近50件しか取れず、承認待ちが51件目以降にあると表示されない構造だった。
// 月指定（GET /reports?date=YYYY-MM&limit=300）に変えてこれを解消する。
// 抽出条件（判定式）は旧実装のものをそのまま使う。
class ReviewTab extends StatefulWidget {
  const ReviewTab({super.key});
  @override
  State<ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<ReviewTab> {
  DateTime _selectedMonth = DateTime.now();
  List<Map<String, dynamic>> _targets = []; // 承認待ち＋差し戻し
  bool _loading = false;
  bool _failed  = false;

  // 締め日を変えた月の「どちらの期間か」を人に選ばせる受け皿。
  //   ★日報と休憩の2本で共有する。どちらも同じ月を見るので、1度選べば両方に効く。
  final ClosingPeriodGate _closing = ClosingPeriodGate();

  // ─── 休憩申請（pending のみ・月に依存せず全件が返る）───
  // 日報の取得とは独立に扱う＝fail-soft。休憩が取れなくても日報一覧は必ず出す。
  List<Map<String, dynamic>> _breaks = [];
  bool _breakFailed = false;

  // 休憩申請の日付キー（'YYYY-MM-DD'）。BE は work_date::text で返す
  // （routes/attendance.js の GET /attendance/break-requests の ar.work_date::text）ので先頭10文字で足りる。
  static String _breakDateKey(Map<String, dynamic> b) {
    final raw = b['work_date'] as String? ?? '';
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  String get _monthStr =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 月ナビ（CalendarTab の流儀に揃える）
  void _prevMonth() {
    setState(() =>
        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1));
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year && _selectedMonth.month == now.month) {
      return;
    }
    setState(() =>
        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1));
    _load();
  }

  // 抽出条件は旧実装の判定式をそのまま使う。
  //   承認待ち＝送信済み かつ 未承認 かつ 差戻し中でない（旧 _loadPending）
  //   差し戻し＝revision_requested==true（旧 RevisionInboxBody の ?revision_requested=true）
  // ★判定の実体は lib/utils/report_cancel_gate.dart の1本（式は従来と同一で、
  //   「取消済でないこと」だけが先頭に足されている）。この画面には条件を書かない。
  //   ここを別名で受けているのは、下の where(_isPending) 等の呼び出し側を
  //   1文字も変えないため。
  static bool _isPending(Map<String, dynamic> r) => isPendingApproval(r);
  static bool _isRevision(Map<String, dynamic> r) => isRevisionRequested(r);

  Future<void> _load() async {
    _closing.beginRound();
    setState(() {
      _loading = true;
      _failed  = false;
      _targets = [];
    });
    // 日報と休憩を並行取得。休憩は fail-soft＝失敗しても日報一覧は出す。
    // ★2本とも同じ月を見るので受け皿は1つ。並行のままでよい（受け皿は先に見つかった
    //   事情を後から来た結果で上書きしないため、結果が実行順で変わらない）。
    final reportsF = _closing.send(
      months: [_monthStr],
      run: (dates) =>
          ReportsService().getReportsByMonth(_monthStr, closingDates: dates),
    );
    final breaksF = _closing.send(
      months: [_monthStr],
      run: (dates) => WorkModeService()
          .fetchBreakRequests(month: _monthStr, closingDates: dates),
    );
    final result   = await reportsF;
    final breakRes = await breaksF;
    if (!mounted) return;
    // 締め日が決まっていない＝「対応が必要な報告はありません」と嘘をつかず、
    // 理由と選ぶ道を出す。
    if (_closing.isPending) {
      setState(() {
        _loading     = false;
        _targets     = [];
        _breaks      = <Map<String, dynamic>>[];
        _breakFailed = false;
      });
      return;
    }
    // 休憩の結果を先に反映（沈黙禁止＝失敗は _breakFailed で1行バナーに出す）
    setState(() {
      _breaks       = (breakRes.ok ? breakRes.data : null) ?? <Map<String, dynamic>>[];
      _breakFailed  = !breakRes.ok;
    });
    if (result.ok) {
      final raw = List<Map<String, dynamic>>.from(result.data ?? const []);
      // ★_isPending / _isRevision が取消済を落とすので、この一覧＝
      //   「今日やる仕事」に取消済は1件も入らない。
      // ★status の作り直しは report_cancel_gate の1本に寄せた
      //   （旧: 'status': _isRevision(r) ? 'rejected' : 'pending'）。
      //   ここへ来る行は取消済でないため結果は従来と同じ値になり、
      //   式が画面ごとに散らばる形だけが消える。
      final targets = raw
          .where((r) => _isPending(r) || _isRevision(r))
          .map(withReportStatus)
          .toList();
      setState(() {
        _targets = targets;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _failed  = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth =
        _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    // 日付グループ化（monthly_history_screen.dart の日付グループ化と同じ作り方・新しい順）
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final r in _targets) {
      final key = r['report_date'] as String? ?? '';
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []).add(r);
    }
    // 休憩申請の日付グループ化。日報の grouped には混ぜない＝上の作り方は1文字も変えない。
    // 休憩APIは月に依存せず pending 全件を返すため、表示中の月だけに絞る。
    final Map<String, List<Map<String, dynamic>>> breakGrouped = {};
    for (final b in _breaks) {
      final key = _breakDateKey(b);
      if (key.isEmpty || !key.startsWith(_monthStr)) continue;
      breakGrouped.putIfAbsent(key, () => []).add(b);
    }
    // 表示する日＝日報の日 ∪ 休憩の日（休憩だけの日も行にする）。
    // 並び順は従来と同一の降順（b.compareTo(a)）のまま。
    final sortedDates = <String>{...grouped.keys, ...breakGrouped.keys}.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        // 月ナビ（CalendarTab の流儀）
        Container(
          color: FieldTokens.surfaceCard,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: FieldTokens.brand),
                onPressed: _prevMonth,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_selectedMonth.year}年${_selectedMonth.month}月',
                    style: const TextStyle(
                        color: FieldTokens.brand,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth ? FieldTokens.textSupport : FieldTokens.brand),
                onPressed: isCurrentMonth ? null : _nextMonth,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: FieldTokens.textSupport, size: 18),
                onPressed: _load,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        // 休憩だけ取得できなかったときに1行で知らせる（日報一覧は下にそのまま出る）
        if (_breakFailed && !_loading) _breakFailBanner(),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: FieldTokens.accent))
              // 締め日の変更で期間が2つある月。理由を出し、押されたときだけ選ばせる。
              : _closing.isPending
                  ? ClosingPeriodNotice(gate: _closing, onResolved: _load)
              : _failed
                  ? _failView()
                  : sortedDates.isEmpty
                      ? const Center(
                          child: Text('対応が必要な報告はありません',
                              style: TextStyle(
                                  color: FieldTokens.textSupport, fontSize: 13)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: sortedDates.length,
                          itemBuilder: (_, i) {
                            final ds = sortedDates[i];
                            return _dayRow(
                              ds,
                              grouped[ds] ?? const [],       // 休憩だけの日は日報0件
                              breakGrouped[ds] ?? const [],
                            );
                          },
                        ),
        ),
      ],
    );
  }

  // 休憩の取得だけが失敗したときの1行バナー（沈黙禁止）。
  // 日報一覧はそのまま出す＝fail-soft。タップで再取得。
  Widget _breakFailBanner() => GestureDetector(
        onTap: _load,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: FieldTokens.surfaceCard,
          child: const Row(
            children: [
              Icon(Icons.error_outline,
                  color: FieldTokens.statusWarning, size: 14),
              SizedBox(width: 6),
              Expanded(
                child: Text('休憩申請を取得できませんでした',
                    style: TextStyle(color: FieldTokens.statusWarning, fontSize: 12)),
              ),
              Text('再試行',
                  style: TextStyle(
                      color: FieldTokens.statusWarning,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );

  Widget _failView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: FieldTokens.statusWarning, size: 32),
            const SizedBox(height: 8),
            const Text('報告を取得できませんでした',
                style: TextStyle(color: FieldTokens.statusWarning, fontSize: 13)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('再試行'),
              style: OutlinedButton.styleFrom(
                foregroundColor: FieldTokens.textBody,
                side: const BorderSide(
                    color: FieldTokens.textBody, width: 1.5),
              ),
            ),
          ],
        ),
      );

  // 1行 = 1日。件数0の日はそもそも grouped/breakGrouped に現れないため行が作られない。
  //   例: 7/27（月）　4件　承認待ち2 差し戻し1 休憩1
  //   合計 = 承認待ち + 差し戻し + 休憩。内訳は0のものを出さない。
  Widget _dayRow(String ds, List<Map<String, dynamic>> reps,
      List<Map<String, dynamic>> breaks) {
    final parts = ds.split('-').map(int.parse).toList();
    final date  = DateTime(parts[0], parts[1], parts[2]);
    final pendingCount  = reps.where(_isPending).length;
    final revisionCount = reps.where(_isRevision).length;
    final breakCount    = breaks.length;
    final totalCount    = pendingCount + revisionCount + breakCount;

    return GestureDetector(
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ApprovalDayScreen(
                date: date, reports: reps, breakRequests: breaks),
          ),
        );
        if (changed == true) _load(); // 旧 _reloadBoth 相当（呼び出し元も最新化）
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text('${date.month}/${date.day}（${_kWeekLabels[date.weekday % 7]}）',
                style: const TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Text('$totalCount件',
                style: const TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
            const Spacer(),
            // 内訳は0のものを出さない
            if (pendingCount > 0)
              Text('承認待ち$pendingCount',
                  style: const TextStyle(
                      color: FieldTokens.textSupport,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            if (pendingCount > 0 && revisionCount > 0)
              const SizedBox(width: 8),
            if (revisionCount > 0)
              Text('差し戻し$revisionCount',
                  style: const TextStyle(
                      color: FieldTokens.statusWarning,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            if ((pendingCount > 0 || revisionCount > 0) && breakCount > 0)
              const SizedBox(width: 8),
            if (breakCount > 0)
              Text('休憩$breakCount',
                  style: const TextStyle(
                      color: FieldTokens.textSupport,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: FieldTokens.textSupport, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ④ 承認待ちカード（旧 _PendingApprovalTabState._pendingCard を公開ウィジェット化）
// ─────────────────────────────────────────────
// ★承認/修正依頼の判定式・API 呼び出し・確認ダイアログ（OriginConfirmDialog /
//   _SiteLinkGateDialog / RevisionReasonDialog）は1文字も変更していない。
//   変更したのは「成功後に呼ぶ再読込コールバック」だけ:
//     旧 (widget.onActionSuccess ?? _loadPending)()  … タブ自身が一覧を保持していたため
//     新 onActionSuccess()                           … 一覧は呼び出し元（画面）が保持する
//   一覧の取得（旧 _loadPending の getReports(limit: 50)）は
//   ReviewTab / ApprovalDayScreen 側へ移した（月指定に変更）。
class PendingApprovalCard extends StatelessWidget {
  const PendingApprovalCard({
    super.key,
    required this.report,
    required this.onActionSuccess,
  });
  final Map<String, dynamic> report;
  // 承認/修正依頼の成功後に呼ぶ（呼び出し元が一覧を再読込する）。
  final VoidCallback onActionSuccess;

  // 読み取り専用の日報詳細ボトムシートを開く（根因a対策：承認待ちカードの詳細導線）。
  void _openDetail(BuildContext context, Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      backgroundColor: FieldTokens.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ReportDetailSheet(report: r),
    );
  }

  // カード1件: 共有部品 JsReportTile(非改変) に写真とアクション行を合成。
  @override
  Widget build(BuildContext context) {
    final r = report;
    final reportId = r['report_id']?.toString() ?? '';
    bool sending = false;
    // カード本体タップで詳細シートを開く。承認/修正依頼ボタンは自前でタップを消費するため干渉しない。
    // JsReportTile は自前 onTap（不完全な旧詳細）を持つため AbsorbPointer で無効化し、導線を一本化する。
    return GestureDetector(
      onTap: () => _openDetail(context, r),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AbsorbPointer(child: JsReportTile(report: r, myCompanyId: '')),
          const SizedBox(height: 8),
          ReportPhotos(reportId: reportId, report: r),
          const SizedBox(height: 8),
          StatefulBuilder(
            builder: (context, setSending) => Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: sending
                        ? null
                        : () async {
                            String selectedOrigin =
                                r['origin_type'] as String? ?? 'home';
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (_) => OriginConfirmDialog(
                                initialOrigin: selectedOrigin,
                                onChanged: (v) => selectedOrigin = v,
                              ),
                            );
                            if (confirmed != true || !context.mounted) return;

                            // 現場紐づけゲート：site_id が null の日報は承認前に現場選択を促す。
                            // site_id が既にある日報は従来どおりダイアログなしで承認する。
                            final existingSiteId = r['site_id'] as String?;
                            if (existingSiteId == null) {
                              final gate =
                                  await showDialog<Map<String, dynamic>>(
                                context: context,
                                builder: (_) => _SiteLinkGateDialog(report: r),
                              );
                              // キャンセル（null）→ 何もしない
                              if (gate == null || !context.mounted) return;
                              final chosenSiteId =
                                  gate['site_id'] as String?;
                              if (chosenSiteId != null) {
                                // 現場を選択 → PATCH site を先に実行。非200は無言禁止＝承認中断。
                                setSending(() => sending = true);
                                final linkRes = await ReportsService()
                                    .linkReportToSite(reportId, chosenSiteId);
                                if (!linkRes.ok) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '現場の紐づけに失敗しました：${linkRes.errorMessage}'),
                                        backgroundColor: FieldTokens.statusError,
                                      ),
                                    );
                                    setSending(() => sending = false);
                                  }
                                  return; // 承認は中断
                                }
                              }
                              // chosenSiteId == null（事務へ回す）→ 紐づけせず承認へ進む
                            }

                            setSending(() => sending = true);
                            final result = await ReportsService()
                                .approveReport(reportId,
                                    originType: selectedOrigin);
                            final ok = result.ok;
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? '承認しました'
                                        : '承認に失敗しました：${result.errorMessage}',
                                    // statusSuccess 塗りの上だけ暗色にする。null は
                                    // app_theme.dart の snackBarTheme.contentTextStyle
                                    // (textBody #EAE3D0) 継承＝statusError 側は現状維持。
                                    style: ok
                                        ? const TextStyle(
                                            color: FieldTokens.onAccent)
                                        : null,
                                  ),
                                  backgroundColor:
                                      ok ? FieldTokens.statusSuccess : FieldTokens.statusError,
                                ),
                              );
                              if (ok) onActionSuccess();
                            }
                            if (context.mounted) {
                              setSending(() => sending = false);
                            }
                          },
                    icon: const Icon(Icons.check),
                    label: const Text('承認'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FieldTokens.statusSuccess,
                      foregroundColor: FieldTokens.onAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: sending
                        ? null
                        : () async {
                            final result =
                                await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (_) => RevisionReasonDialog(
                                transportTypes: r['transport_types_json']
                                    as List<dynamic>?,
                              ),
                            );
                            if (result == null || !context.mounted) return;
                            final reasons = result['reasons'] as List<String>;
                            if (reasons.isEmpty) return;
                            final comment = result['comment'] as String?;
                            setSending(() => sending = true);
                            final res = await ReportsService().requestRevision(
                                reportId, reasons,
                                reason: comment ?? '');
                            final ok = res.ok;
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? '修正依頼を送りました'
                                      : '修正依頼に失敗しました：${res.errorMessage}'),
                                  backgroundColor:
                                      ok ? FieldTokens.statusWarning : FieldTokens.statusError,
                                ),
                              );
                              if (ok) onActionSuccess();
                            }
                            if (context.mounted) {
                              setSending(() => sending = false);
                            }
                          },
                    icon: const Icon(Icons.edit_note),
                    label: const Text('修正依頼'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FieldTokens.statusWarning,
                      foregroundColor: FieldTokens.onStatusWarning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ② 社員一覧タブ
// ─────────────────────────────────────────────
class _StaffTab extends StatefulWidget {
  const _StaffTab();
  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  List<Map<String, dynamic>> _staff = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _loading = true);
    {
      final res = await WorkerService().getWorkers(membershipType: 'employee');
      if (!mounted) return;
      if (res.ok) {
        final companies = res.data ?? const <Map<String, dynamic>>[];
        final own = companies.firstWhere(
          (c) => c['is_own'] == true,
          orElse: () => <String, dynamic>{},
        );
        setState(() {
          _staff = List<Map<String, dynamic>>.from(own['workers'] ?? []);
          _loading = false;
        });
      } else {
        // 非200・通信不成立とも移設前は同じ「読み込みを終える」だけ（_staff は据え置き）。
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: FieldTokens.accent));
    }
    if (_staff.isEmpty) {
      return const Center(
        child: Text('社員がいません',
            style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _staff.length,
      itemBuilder: (context, i) => _StaffCard(worker: _staff[i]),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.worker});
  final Map<String, dynamic> worker;

  @override
  Widget build(BuildContext context) {
    final name = worker['name'] as String? ?? '不明';
    final role = worker['role'] as String? ?? '';
    final roleLabel = role == 'boss' ? '職長' : '職人';
    final expYears = (worker['experience_years'] as num?)?.toInt() ?? 0;
    final personId = worker['user_id'] as String? ?? '';

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: FieldTokens.surfaceCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => _StaffMonthlySheet(personId: personId, name: name),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.person_outline, color: FieldTokens.textSupport, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FieldTokens.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(roleLabel,
                  style:
                      const TextStyle(color: FieldTokens.accent, fontSize: 10)),
            ),
            const SizedBox(width: 8),
            Text('$expYears年',
                style:
                    const TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _StaffMonthlySheet extends StatefulWidget {
  const _StaffMonthlySheet({required this.personId, required this.name});
  final String personId;
  final String name;

  @override
  State<_StaffMonthlySheet> createState() => _StaffMonthlySheetState();
}

class _StaffMonthlySheetState extends State<_StaffMonthlySheet> {
  DateTime _selectedMonth = DateTime.now();
  Map<String, dynamic>? _summary;
  bool _loading = false;

  // 締め日を変えた月の「どちらの期間か」を人に選ばせる受け皿。
  final ClosingPeriodGate _closing = ClosingPeriodGate();

  String get _monthStr =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadMonthly();
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _loadMonthly();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year &&
        _selectedMonth.month == now.month) {
      return;
    }
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _loadMonthly();
  }

  Future<void> _loadMonthly() async {
    _closing.beginRound();
    setState(() => _loading = true);
    {
      // monthly_stats_screen と同じ1本（person_id の出所だけが違う）。
      final res = await _closing.send(
        months: [_monthStr],
        run: (dates) => WorkModeService().fetchMonthlySummary(
          personId: widget.personId,
          month:    _monthStr,
          closingDates: dates,
        ),
      );
      if (!mounted) return;
      // 締め日が決まっていない＝0の集計で黙らず、理由と選ぶ道を出す。
      if (_closing.isPending) {
        setState(() { _summary = null; _loading = false; });
        return;
      }
      final summary = res.data;
      setState(() {
        // 非200・通信不成立はどちらも移設前と同じく _summary = null（未取得）。
        _summary = (res.ok && summary != null) ? summary : null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;
    final note = _summary?['note'] as String? ??
        '参考値です。労働時間・賃金の最終確定は貴社の責任で行ってください';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: FieldTokens.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.name,
                style: const TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Container(
            color: FieldTokens.surfaceCard,
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: FieldTokens.accent),
                  onPressed: _prevMonth,
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_selectedMonth.year}年${_selectedMonth.month}月',
                      style: const TextStyle(
                          color: FieldTokens.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.chevron_right,
                    color: isCurrentMonth
                        ? FieldTokens.outline
                        : FieldTokens.accent,
                  ),
                  onPressed: isCurrentMonth ? null : _nextMonth,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: FieldTokens.accent))
                // 締め日の変更で期間が2つある月。「データなし」で黙らず理由を出す。
                : _closing.isPending
                    ? ClosingPeriodNotice(
                        gate: _closing, onResolved: _loadMonthly)
                : _summary == null
                    // 本文相当の状態表示。補助色(textSupport #7B7567)では地に沈むため textBody。
                    ? const Center(
                        child: Text('データなし',
                            style: TextStyle(
                                color: FieldTokens.textBody, fontSize: 13)))
                    : ListView(
                        controller: controller,
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        children: [
                          // 数値は valueColor: textBody(#EAE3D0) で高コントラストに描く。
                          // 出勤日数だけ valueColor 未指定＝statusSuccess のまま（安全色・裁定）。
                          // 枠・背景・ラベルは従来のセマンティック色を維持し階層を残す
                          // （_StaffStatChip＝面 α0.1／枠 α0.4／ラベルは色そのもの）。
                          Row(
                            children: [
                              _StaffStatChip(
                                '出勤日数',
                                '${(_summary!['days_worked'] as num?)?.toInt() ?? 0}',
                                FieldTokens.statusSuccess,
                              ),
                              const SizedBox(width: 4),
                              _StaffStatChip(
                                '実働',
                                () {
                                  final mins =
                                      (_summary!['total_net_minutes']
                                                  as num?)
                                              ?.toDouble() ??
                                          0;
                                  return '${(mins / 60).toStringAsFixed(1)}h';
                                }(),
                                FieldTokens.accent,
                                valueColor: FieldTokens.textBody,
                              ),
                              const SizedBox(width: 4),
                              _StaffStatChip(
                                '残業',
                                '${((_summary!['overtime'] as Map<String, dynamic>?)?['total_min'] as num?)?.toInt() ?? 0}',
                                FieldTokens.statusWarning,
                                valueColor: FieldTokens.textBody,
                              ),
                              const SizedBox(width: 4),
                              _StaffStatChip(
                                '休日出勤',
                                '${(_summary!['holiday_work_days'] as num?)?.toInt() ?? 0}',
                                FieldTokens.statusError,
                                valueColor: FieldTokens.textBody,
                              ),
                            ],
                          ),
                        ],
                      ),
          ),
          // note は summary の有無にかかわらず常時表示（法務の盾3層目）
          // 読めない注意書きは盾にならないため可読水準へ。補助色では地に沈むので
          // accent を使い、不透明のままだと見出しと同格になり階層が壊れるため
          // alpha 0.85 に落として一段下げている。サイズは最低可読の11へ。
          // ★かつてここに記載していたコントラスト実測値(1.91/2.83/4.87 等)は
          //   #181810/#484830/#686040 という退役済みパレット基準のもので、
          //   現行 Asphalt Dawn の値では未再測。再測は次工程。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              note,
              style: TextStyle(
                  color: FieldTokens.accent.withValues(alpha: 0.85), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// JsStatChip の String値版（実働時間 h表記用）
// valueColor: 数値だけを高コントラスト色にするための任意指定。
//   月次シートの数値が地の色に沈んで読めなかったため、値とラベル/枠の色を分離できるようにした。
//   省略時は color と同一＝従来挙動（レイアウト・サイズ・枠は不変）。
class _StaffStatChip extends StatelessWidget {
  const _StaffStatChip(this.label, this.value, this.color, {this.valueColor});
  final String label;
  final String value;
  final Color color;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    color: valueColor ?? color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────
// ③ 協力業者タブ
// ─────────────────────────────────────────────
class _CooperationTab extends StatefulWidget {
  const _CooperationTab();

  @override
  State<_CooperationTab> createState() => _CooperationTabState();
}

class _CooperationTabState extends State<_CooperationTab> {
  DateTime _selectedMonth = DateTime.now();
  List<Map<String, dynamic>> _companies = [];
  bool _loading = false;

  // 締め日を変えた月の「どちらの期間か」を人に選ばせる受け皿。
  final ClosingPeriodGate _closing = ClosingPeriodGate();

  String get _monthStr =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadByCompany();
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _loadByCompany();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year &&
        _selectedMonth.month == now.month) {
      return;
    }
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _loadByCompany();
  }

  Future<void> _loadByCompany() async {
    _closing.beginRound();
    setState(() => _loading = true);
    {
      final res = await _closing.send(
        months: [_monthStr],
        run: (dates) =>
            ReportsService().getReportsByCompany(_monthStr, closingDates: dates),
      );
      if (!mounted) { return; }
      // 締め日が決まっていない＝「実績はありません」と嘘をつかず、理由と選ぶ道を出す。
      if (_closing.isPending) {
        setState(() { _companies = []; _loading = false; });
        return;
      }
      if (res.ok) {
        setState(() {
          _companies = res.data ?? const [];
          _loading = false;
        });
      } else {
        // 非200・通信不成立とも移設前は同じ（_companies は据え置き）。
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;

    return Column(
      children: [
        Container(
          color: FieldTokens.surfaceCard,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: FieldTokens.accent),
                onPressed: _prevMonth,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_selectedMonth.year}年${_selectedMonth.month}月',
                    style: const TextStyle(
                        color: FieldTokens.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: isCurrentMonth ? FieldTokens.outline : FieldTokens.accent,
                ),
                onPressed: isCurrentMonth ? null : _nextMonth,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: FieldTokens.accent))
              // 締め日の変更で期間が2つある月。理由を出し、押されたときだけ選ばせる。
              : _closing.isPending
                  ? ClosingPeriodNotice(
                      gate: _closing, onResolved: _loadByCompany)
              : _companies.isEmpty
                  ? const Center(
                      child: Text(
                        'この月の協力業者実績はありません',
                        style:
                            TextStyle(color: FieldTokens.textSupport, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _companies.length,
                      itemBuilder: (context, i) =>
                          _CoopCard(company: _companies[i]),
                    ),
        ),
      ],
    );
  }
}

class _CoopCard extends StatelessWidget {
  const _CoopCard({required this.company});
  final Map<String, dynamic> company;

  @override
  Widget build(BuildContext context) {
    final id = company['coop_company_id'] as String? ?? '';
    final isPerson = id.startsWith('person:');
    final name = company['company_name'] as String? ?? '不明';
    final reportCount =
        (company['report_count'] as num?)?.toInt() ?? 0;
    final workerCount =
        (company['worker_count'] as num?)?.toInt() ?? 0;
    final siteCount =
        (company['site_count'] as num?)?.toInt() ?? 0;
    final parkingFee =
        (company['parking_fee_total'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPerson
                    ? Icons.person_outline
                    : Icons.business_outlined,
                color: FieldTokens.externalBlue,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isPerson)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FieldTokens.externalBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '個人',
                    style: TextStyle(
                        color: FieldTokens.externalBlue, fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              JsStatChip('延べ人工', reportCount, FieldTokens.textSupport),
              const SizedBox(width: 4),
              JsStatChip('職人', workerCount,
                  FieldTokens.externalBlue),
              const SizedBox(width: 4),
              JsStatChip('現場', siteCount, FieldTokens.accent),
              const SizedBox(width: 4),
              JsStatChip('¥駐車料金', parkingFee, FieldTokens.textSupport),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ① カレンダータブ
// ─────────────────────────────────────────────
// 曜日ラベル（日=0 起点）。グリッド見出しと選択日ラベルで共有する。
const List<String> _kWeekLabels = ['日', '月', '火', '水', '木', '金', '土'];

// 公開化（管理・履歴タブから同一実体を呼ぶため）。
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _selectedMonth = DateTime.now();
  List<Map<String, dynamic>> _monthReports = [];
  Set<String> _submittedDates = {};
  bool _monthLoading = false;
  String _myCompanyId = '';

  // 締め日を変えた月の「どちらの期間か」を人に選ばせる受け皿。
  //   ★日報と自分の休みの2本で共有する（同じ月・同じ期間で切るため）。
  //   ★カレンダーは他の情報（会社休日・祝日）と並ぶので、理由は全面ではなく
  //     1行の帯で出す＝既存の _buildFailureBar と同じ並びに置く。
  final ClosingPeriodGate _closing = ClosingPeriodGate();

  /// 選択中の日（'YYYY-MM-DD'）。null=未選択。
  /// 旧実装は _DayCell へ isSelected:false を固定で渡していて選択が機能していなかった。
  String? _selectedDate;

  // ── 会社休日（GET /attendance/holidays/my）──
  //   weekly: {"0".."6" → 'legal'|'scheduled'} / dates: {"YYYY-MM-DD" → 'legal'|'scheduled'}
  //   セル塗り（会社がその日を休みにしているか）にのみ使う。文字色には使わない。
  Map<String, String> _holidayWeekly = {};
  Map<String, String> _holidayDates  = {};
  bool _holidayFailed = false;

  // ── 自分の休み（GET /rest-days/my?month=）──
  //   'YYYY-MM-DD' → portion('full'|'am_half'|'pm_half') / reason
  Map<String, Map<String, dynamic>> _myRestDays = {};
  bool _restFailed = false;

  // ── 日本の祝日（GET /attendance/holidays/jp?year=）──
  //   ★値は【祝日名の文字列】。holidays/my の 'legal'|'scheduled' とは別物。
  //   文字色（朱）の判定にのみ使い、会社の休業設定とは無関係（OFFICE
  //   holiday_calendar_screen.dart の _holidayText の裁定と同一の思想）。
  //   取得は年単位。成功した年だけ _jpYearsLoaded に入れる＝失敗年は再訪で再試行される。
  final Map<String, String> _jpHolidays  = {};
  final Set<int> _jpYearsLoaded  = {};
  final Set<int> _jpYearsLoading = {};
  bool _jpFailed = false;

  // 日報取得の失敗（旧実装は catch で握り潰して空表示だった＝沈黙障害）
  bool _reportsFailed = false;

  String get _monthStr =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _initCompanyId();
    _loadMonth();
  }

  Future<void> _initCompanyId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _myCompanyId = prefs.getString('company_id') ?? '');
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      _selectedDate = null; // 月をまたいだ選択は持ち越さない
    });
    _loadMonth();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year &&
        _selectedMonth.month == now.month) {
      return;
    }
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      _selectedDate = null;
    });
    _loadMonth();
  }

  // ── 月切替のたびに3本を並列取得（fail-soft）──────────────────
  //   ・日報 / 会社休日 / 自分の休み を Future.wait で同時に投げる。
  //   ・どれか1本が失敗しても他は描画する。失敗したものは _*Failed を立て、
  //     画面上部の注意バー（_buildFailureBar）で必ず可視化する（黙って空にしない）。
  //   ・祝日は「年単位」なので月ではなく年が変わったときだけ追加取得する。
  Future<void> _loadMonth() async {
    _closing.beginRound();
    setState(() {
      _monthLoading   = true;
      _monthReports   = [];
      _submittedDates = {};
      _reportsFailed  = false;
      _holidayFailed  = false;
      _restFailed     = false;
    });

    await Future.wait([
      _loadReports(),
      _loadCompanyHolidays(),
      _loadMyRestDays(),
    ]);

    if (!mounted) return;
    setState(() => _monthLoading = false);
    // 祝日は年単位（月ではない）。2026-12 → 2027-01 のような年跨ぎで追加取得される。
    _ensureJpHolidays(_selectedMonth.year);
  }

  // 日報（既存のまま GET /reports?date=YYYY-MM&limit=300）
  Future<void> _loadReports() async {
    {
      // limit=300 は getReportsByMonth の既定値（monthly_history_screen は 200 を明示）。
      final res = await _closing.send(
        months: [_monthStr],
        run: (dates) =>
            ReportsService().getReportsByMonth(_monthStr, closingDates: dates),
      );
      if (!mounted) return;
      // 締め日が決まっていない＝提出済みの日が0件のカレンダーで黙らない。
      // 理由は上部の帯（ClosingPeriodBar）が出す。
      if (_closing.isPending) {
        setState(() { _monthReports = []; _submittedDates = {}; });
        return;
      }
      if (res.ok) {
        final raw = List<Map<String, dynamic>>.from(res.data ?? const []);
        // ★status の作り直しは report_cancel_gate の1本。旧実装はこの場で
        //   approved/revision の2値だけを見ており、BE が載せてきた 'cancelled'
        //   （LIST_COLS の r.status）をここで捨てていた。
        // ★取消済の行は捨てない。カレンダーから DayReportsScreen へ渡す元が
        //   この一覧で、捨てると取り消した日報を見に行く道が消える。
        final enriched = raw.map(withReportStatus).toList();
        // ★セルのドットは「日報提出済」の印。取り消した日報は提出の効力を
        //   失っている（BE の取消は勤怠の記録まで戻す）ので、取消済しか無い日に
        //   ドットは出さない。取消済は上の enriched に残っており、その日を選べば
        //   下の詳細から必ず見に行ける（袋小路を作らない）。
        final dates = enriched
            .where((r) => !isCancelledReport(r))
            .map((r) => r['report_date'] as String? ?? '')
            .where((d) => d.isNotEmpty)
            .toSet();
        setState(() {
          _monthReports   = enriched;
          _submittedDates = dates;
        });
      } else {
        // 非200も通信不成立も移設前は同じ「取得失敗」。失敗の可視化（statusCode と
        // 本文先頭200文字）は runApiCall の debugPrint が担う。
        setState(() => _reportsFailed = true);
      }
    }
  }

  // 会社休日（GET /attendance/holidays/my）
  Future<void> _loadCompanyHolidays() async {
    final res = await WorkModeService().fetchCompanyHolidays();
    if (!mounted) return;
    setState(() {
      // ★失敗時は空マップ（統一前も ok:false のとき weekly/dates は空だった）。
      _holidayWeekly = res.data?.weekly ?? const {};
      _holidayDates  = res.data?.dates  ?? const {};
      _holidayFailed = !res.ok;
    });
  }

  // 自分の休み（GET /rest-days/my?month=）
  Future<void> _loadMyRestDays() async {
    final res = await _closing.send(
      months: [_monthStr],
      run: (dates) =>
          ReportsService().getRestDaysMy(_monthStr, closingDates: dates),
    );
    if (!mounted) return;
    // 締め日が決まっていない＝休みが0件のカレンダーで黙らない（理由は上部の帯）。
    if (_closing.isPending) {
      setState(() { _myRestDays = {}; _restFailed = false; });
      return;
    }
    if (res.ok) {
      final map = <String, Map<String, dynamic>>{};
      for (final d in (res.data ?? const <Map<String, dynamic>>[])) {
        final m = Map<String, dynamic>.from(d);
        final date = m['rest_date'] as String? ?? '';
        if (date.isNotEmpty) map[date] = m;
      }
      setState(() {
        _myRestDays = map;
        _restFailed = false;
      });
    } else {
      setState(() => _restFailed = true);
    }
  }

  // 祝日（年単位・成功した年は再取得しない）
  Future<void> _ensureJpHolidays(int year) async {
    if (_jpYearsLoaded.contains(year) || _jpYearsLoading.contains(year)) return;
    _jpYearsLoading.add(year);
    final res = await WorkModeService().fetchJpHolidays(year);
    _jpYearsLoading.remove(year);
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        _jpHolidays.addAll(res.data ?? const {});
        _jpYearsLoaded.add(year);
      } else {
        _jpFailed = true; // 祝日色なしで描画を続行する（操作は止めない）
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;

    return Column(
      children: [
        // ① 月ナビ
        Container(
          color: FieldTokens.surfaceCard,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: FieldTokens.brand),
                onPressed: _prevMonth,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_selectedMonth.year}年${_selectedMonth.month}月',
                    style: const TextStyle(
                        color: FieldTokens.brand,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth ? FieldTokens.textSupport : FieldTokens.brand),
                onPressed: isCurrentMonth ? null : _nextMonth,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.refresh,
                    color: FieldTokens.textSupport, size: 18),
                onPressed: _loadMonth,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        // ②-a 締め日の変更で期間が2つある月（理由＋押したら選べる。黙って空にしない）
        if (_closing.isPending && !_monthLoading)
          ClosingPeriodBar(gate: _closing, onResolved: _loadMonth),
        // ② 取得失敗の可視化（黙って空にしない）
        _buildFailureBar(),
        // ③ カレンダーグリッド
        _monthLoading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: CircularProgressIndicator(color: FieldTokens.accent)))
            : _buildCalendarGrid(),
        // ④ 選択日の詳細（旧「日付をタップして日報を確認」のヒントを置換）
        const Divider(height: 1, color: FieldTokens.outline),
        Expanded(
          child: _buildSelectedDay(),
        ),
      ],
    );
  }

  // ── 取得失敗バー ────────────────────────────────────────────
  // fail-soft の相方。取れなかったものを必ず名指しで出す（沈黙障害の禁止）。
  Widget _buildFailureBar() {
    final failed = <String>[
      if (_reportsFailed) '日報',
      if (_holidayFailed) '会社休日',
      if (_restFailed)    '自分の休み',
      if (_jpFailed)      '祝日',
    ];
    if (failed.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: FieldTokens.surfaceCard,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        const Icon(Icons.error_outline, color: FieldTokens.statusWarning, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${failed.join('・')}を取得できませんでした',
              style: const TextStyle(color: FieldTokens.statusWarning, fontSize: 12)),
        ),
        GestureDetector(
          onTap: _loadMonth,
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text('再試行',
                style: TextStyle(
                    color: FieldTokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

  // その日が会社の休業日か（holiday_def の dates 優先 → weekly）。
  // 返り値は 'legal'|'scheduled'|null。セル塗りの判定にのみ使う。
  String? _companyHolidayType(String ds, int weekdayIdx) =>
      _holidayDates[ds] ?? _holidayWeekly['$weekdayIdx'];

  Widget _buildCalendarGrid() {
    // (a) 日曜始まり。ヘッダも日→土。
    const weekdays = _kWeekLabels;
    final now      = DateTime.now();
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay  =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    // DateTime.weekday は 月=1..日=7。%7 で 日=0..土=6 になる（OFFICE
    // holiday_calendar_screen.dart の _buildCalendar と同一の作り方）。
    final startOffset = firstDay.weekday % 7;
    final rowCount = ((startOffset + lastDay.day) / 7).ceil();

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Table(
        children: [
          // 曜日ヘッダー（日=0 起点。色は本文の文字色ルールと揃える）
          TableRow(
            children: weekdays.asMap().entries.map((e) {
              final color = e.key == 0
                  ? FieldTokens.statusError          // 日曜=赤
                  : e.key == 6
                      ? FieldTokens.saturday  // 土曜=水色
                      : FieldTokens.textSupport;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Center(
                  child: Text(e.value,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              );
            }).toList(),
          ),
          // 日付行
          for (int row = 0; row < rowCount; row++)
            TableRow(
              children: List.generate(7, (col) {
                final cellIndex = row * 7 + col;
                final dayNum = cellIndex - startOffset + 1;
                if (dayNum < 1 || dayNum > lastDay.day) {
                  return const SizedBox(height: 48);
                }
                final date = DateTime(
                    _selectedMonth.year, _selectedMonth.month, dayNum);
                final ds = _ymd(date);
                // (d) 文字色は【実曜日】で判定する。列位置(col)では判定しない。
                //     日曜始まりなので col と一致はするが、判定の根拠を日付側に置く。
                final weekdayIdx = date.weekday % 7; // 日=0..土=6
                final isToday = date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;
                final rest = _myRestDays[ds];
                return _DayCell(
                  day: dayNum,
                  hasReport: _submittedDates.contains(ds),
                  isSelected: _selectedDate == ds,
                  isToday: isToday,
                  isSunday:  weekdayIdx == 0,
                  isSaturday: weekdayIdx == 6,
                  isJpHoliday: _jpHolidays.containsKey(ds),
                  isCompanyHoliday: _companyHolidayType(ds, weekdayIdx) != null,
                  restPortion: rest?['portion'] as String?,
                  // タップは「選択」。日報へは下の詳細パネルの導線から行く
                  // （DayReportsScreen への遷移は削除していない・_buildSelectedDay 参照）。
                  onTap: () => setState(() => _selectedDate = ds),
                );
              }),
            ),
        ],
      ),
    );
  }

  // ── (e) 選択日の詳細 ────────────────────────────────────────
  // 表示: 会社休み / 自分の休み（終日・午前休・午後休）/ 日報の有無。
  // 旧「日付をタップして日報を確認」のヒントはこれに置き換えた。
  // ★DayReportsScreen への遷移は削除せず、日報がある日は必ずここから行ける。
  Widget _buildSelectedDay() {
    final ds = _selectedDate;
    if (ds == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app_outlined, color: FieldTokens.textSupport, size: 32),
            SizedBox(height: 8),
            Text('日付をタップすると内容を表示します',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
          ],
        ),
      );
    }

    final parts = ds.split('-').map(int.parse).toList();
    final date  = DateTime(parts[0], parts[1], parts[2]);
    final weekdayIdx = date.weekday % 7;
    final holidayType = _companyHolidayType(ds, weekdayIdx);
    final rest = _myRestDays[ds];
    // ★その日の日報は取消済も含めて全部持つ（DayReportsScreen へはこれを渡す
    //   ＝取り消した日報を後から見る道をここで断たない）。
    //   数えるときだけ生きている日報と取消済を分ける。
    final dayReps      = _monthReports.where((r) => r['report_date'] == ds).toList();
    final dayLiveReps  = dayReps.where((r) => !isCancelledReport(r)).toList();
    final dayCancelled = dayReps.length - dayLiveReps.length;
    final jpName = _jpHolidays[ds];

    String restLabel(String? portion) {
      switch (portion) {
        case 'am_half': return '午前休';
        case 'pm_half': return '午後休';
        default:        return '終日休み';
      }
    }

    Widget row(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: FieldTokens.textBody, fontSize: 13)),
            ),
          ]),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${date.month}月${date.day}日（${_kWeekLabels[weekdayIdx]}）',
              style: const TextStyle(
                  color: FieldTokens.textBody,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          // 祝日名（あれば）。会社の休業設定とは独立した「その日の性質」。
          if (jpName != null) row(Icons.flag_outlined, FieldTokens.holidayText, '祝日：$jpName'),

          // 会社休み
          if (holidayType != null)
            row(Icons.business_outlined, FieldTokens.statusError,
                '会社休み（${holidayType == 'legal' ? '法定休日' : '所定休日'}）')
          else
            row(Icons.business_outlined, FieldTokens.textSupport, '会社休み：なし'),

          // 自分の休み
          if (rest != null)
            row(Icons.event_busy_outlined, FieldTokens.accent,
                '自分の休み：${restLabel(rest['portion'] as String?)}'
                '${(rest['reason'] as String?) != null ? '（${rest['reason']}）' : ''}')
          else ...[
            row(Icons.event_available_outlined, FieldTokens.textSupport, '自分の休み：なし'),
            // ── 代休で休む（入口②）────────────────────────────
            //  ★日はここ（入口）が持つ。人がカレンダーでタップした ds を
            //    そのまま部品へ渡すだけで、部品は自分では日を決めない
            //    （画面に出ている日と送る日がずれない）。
            //  ★選ばせる部品と書く口は「本日休み」の画面と同じ1本
            //    （lib/widgets/comp_off_dialog.dart の showCompOffFlow）。
            //    入口が2つでも操作は1通り。
            //  ★既に休みが在る日には出さない（上の if の else 側）。
            //    出しても BE が ALREADY_RESTED で断るだけで、押せるのに
            //    必ず失敗するボタンになる。
            //  ★形は同じパネルの「日報を確認」と同じ OutlinedButton.icon。
            //    新しい見た目を作らない・タブも増やさない（増えたのは入口だけ）。
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final took = await showCompOffFlow(context, restDate: ds);
                  if (took && mounted) _loadMonth();   // BE の真実へ追随
                },
                icon: const Icon(Icons.event_repeat, size: 16),
                label: const Text('代休で休む'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FieldTokens.textBody,
                  side: const BorderSide(color: FieldTokens.textBody, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // 日報の有無 ＋ DayReportsScreen への導線（既存遷移を維持）
          // ★件数は生きている日報だけを数える。取消済は同じ行に足さず、
          //   下に別の行で出す（足すとセルのドットが無いのに「日報：1件」と
          //   出て食い違う）。
          // ★導線を出す条件は dayReps（取消済を含む全部）が空でないこと。
          //   その日の全部を取り消した日でも「日報を確認」が残る＝取り消した
          //   日報を見に行く道が必ず在る。
          if (dayReps.isNotEmpty) ...[
            if (dayLiveReps.isNotEmpty)
              row(Icons.description_outlined, FieldTokens.accent,
                  '日報：${dayLiveReps.length}件')
            else
              row(Icons.description_outlined, FieldTokens.textSupport,
                  '日報：なし'),
            // 取消済の印。色は日報1枚の取消済バッジと同じ textSupport
            // （monthly_history_screen.dart の JsReportTile）。新色は作らない。
            if (dayCancelled > 0)
              row(Icons.cancel_outlined, FieldTokens.textSupport,
                  '取消済：$dayCancelled件'),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                // ★戻り値を待つ。DayReportsScreen で日報を取り消すと true が返る。
                //   dayReps の元は _monthReports で、それを埋めるのは _loadReports()
                //   ただ一つ。既存のそれをそのまま呼び直す（新しい取得の口は作らない
                //   ＝締め日の解決 _closing.send も今までどおり通る）。
                //   ★_loadMonth() ではなく _loadReports() を呼ぶ。取消で変わるのは
                //     日報だけで、会社休日・自分の休みは変わらないため。
                //   true 以外（見ただけで戻った・null）では何もしない。
                onPressed: () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DayReportsScreen(
                        date: date,
                        reports: dayReps,
                        myCompanyId: _myCompanyId,
                      ),
                    ),
                  );
                  if (changed == true && mounted) await _loadReports();
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('日報を確認'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FieldTokens.textBody,
                  side: const BorderSide(
                      color: FieldTokens.textBody, width: 1.5),
                ),
              ),
            ),
          ] else
            row(Icons.description_outlined, FieldTokens.textSupport, '日報：なし'),
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────
// カレンダーのセル
// ─────────────────────────────────────────────
// 意味の役割分離（この5つは互いに独立し、同時に出てよい）:
//   セル塗り   = 会社の休業日（isCompanyHoliday）
//   実線リング = 自分の休み full（restPortion=='full'）
//   破線リング = 自分の休み 半休（am_half / pm_half）
//   ドット     = 日報提出済（hasReport）
//   今日=金の枠 / 選択中=本文色の枠
// 文字色は「その日の性質」であり休日設定とは無関係に固定（OFFICE
// holiday_calendar_screen.dart の _holidayText の裁定と同一）。優先順は 日曜 ＞ 祝日 ＞ 土曜 ＞ 平日。
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.hasReport,
    required this.isSelected,
    required this.isToday,
    this.isSaturday = false,
    this.isSunday = false,
    this.isJpHoliday = false,
    this.isCompanyHoliday = false,
    this.restPortion,
    required this.onTap,
  });
  final int day;
  final bool hasReport;
  final bool isSelected;
  final bool isToday;
  final bool isSaturday;
  final bool isSunday;
  /// 内閣府データ由来の祝日か（文字色＝朱の判定にのみ使う）
  final bool isJpHoliday;
  /// 会社がその日を休みにしているか（セル塗りの判定にのみ使う）
  final bool isCompanyHoliday;
  /// 自分の休み。null=休みなし / 'full' / 'am_half' / 'pm_half'
  final String? restPortion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // (d) 文字色: 日曜赤 ＞ 祝日朱 ＞ 土曜水色 ＞ 平日。判定は呼び出し側が実曜日で作る。
    final Color textColor = isSunday
        ? FieldTokens.statusError
        : isJpHoliday
            ? FieldTokens.holidayText
            : isSaturday
                ? FieldTokens.saturday
                : FieldTokens.textBody;

    final hasRest  = restPortion != null;
    final fullRest = restPortion == 'full';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          // セル塗り＝会社休業日のみ（選択の表現には使わない＝意味を混ぜない）
          color: isCompanyHoliday
              ? FieldTokens.statusError.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          // 選択＝本文色の枠2px / 今日＝淡い金の枠1.5px（顔＝brand）
          border: isSelected
              ? Border.all(color: FieldTokens.textBody, width: 2)
              : isToday
                  ? Border.all(color: FieldTokens.brand, width: 1.5)
                  : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 自分の休み: full=実線リング / 半休=破線リング
            if (hasRest)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: fullRest
                      ? const DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                                BorderSide(color: FieldTokens.accent, width: 1.5)),
                          ),
                        )
                      : const CustomPaint(
                          painter: _DashedRingPainter(color: FieldTokens.accent),
                        ),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: (isToday || isSelected)
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                if (hasReport)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 2),
                    // 日報提出済ドット＝【ポイント】。accent(#6FD6B4)。
                    decoration: const BoxDecoration(
                      color: FieldTokens.accent,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  const SizedBox(height: 7),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 破線リング（半休の表現）。Flutter に破線 Border が無いため最小の自前描画。
// 色は呼び出し側から既存トークンを受け取るだけで、新しい色は定義しない。
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addOval(Rect.fromLTWH(0, 0, size.width, size.height));
    const dash = 3.0, gap = 3.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final end = min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter old) => old.color != color;
}

// ─────────────────────────────────────────────
// ForemanManagementScreen — 後方互換用フルスクリーン
// ─────────────────────────────────────────────
class ForemanManagementScreen extends StatelessWidget {
  const ForemanManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        iconTheme: const IconThemeData(color: FieldTokens.brand),
        title: const Text('管理・集計',
            style: TextStyle(
                color: FieldTokens.brand,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
      body: const ForemanManagementBody(),
    );
  }
}
