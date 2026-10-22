// lib/screens/punch_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show fetchGpsAddress, showJsSnackbar;
import '../services/api_result.dart';
import '../services/work_mode_service.dart';
import '../services/reports_service.dart';
import '../core/theme/field_tokens.dart';
import '../core/report_send_texts.dart';
import '../utils/business_date.dart';
import '../utils/rest_day_refresh.dart';
import '../widgets/business_day_dialog_guard.dart';
import '../widgets/deny_reason_line.dart' show denyReasonText;
import '../widgets/pending_report_parts.dart' show kPendingReadFailedNoteDialogView;
import 'rest_day_screen.dart';
import 'rest_day_done_screen.dart';
import 'substitute_detail_screen.dart'
    show SubstituteDetailScreen, SubstituteOpenButton, kCannotAgreeHead;
import 'substitute_list_screen.dart' show kSubstituteWaitColor;

// ── Asphalt Dawn palette ──────────────────────────────────────────────────────
const _bg     = FieldTokens.bgBase;
const _card   = FieldTokens.surfaceCard;
const _accent = FieldTokens.accent;
const _text   = FieldTokens.textBody;
const _label  = FieldTokens.textSupport;
const _border = FieldTokens.outline;

// ── file-level helpers ────────────────────────────────────────────────────────
String _hhmm(String? iso) {
  if (iso == null) return '--:--';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '--:--';
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// みなし時刻の表示整形【表示のみ・値は一切変えない】。
// BE の /work_settings/my は TIME 列をそのまま返すため 'HH:MM:SS' で届く
//（js-office-api/routes/work_settings.js の GET /work-settings/my の deemed_start。既定値リテラルも '08:00:00'）。
// 'HH:MM:SS' / 'HH:MM' を受けて 'H:MM'（秒なし・先頭ゼロなし）にする。
// パースできない値は握り潰さず生値をそのまま返す（fail-soft）。null は '--:--'。
String _fmtTime(String? raw) {
  if (raw == null) return '--:--';
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})(?::\d{2})?\s*$').firstMatch(raw);
  if (m == null) return raw;
  return '${int.parse(m.group(1)!)}:${m.group(2)}';
}

String _elapsed(String? punchInIso) {
  if (punchInIso == null) return '';
  final inTime = DateTime.tryParse(punchInIso)?.toLocal();
  if (inTime == null) return '';
  final d = DateTime.now().difference(inTime);
  return '${d.inHours}時間${d.inMinutes % 60}分';
}

// ── PunchScreen ───────────────────────────────────────────────────────────────
class PunchScreen extends StatefulWidget {
  const PunchScreen({
    super.key,
    this.onNavigateToReport,
    this.weatherPanel,
    required this.shiftType,
    required this.onShiftTypeChanged,
    this.shiftReadFailed = false,
    this.revisionCount = 0,
    this.substituteCount = 0,
    this.substituteTruncated = false,
    this.pendingApprovalCount = 0,
    this.onOpenRevisions,
    this.onOpenSubstitutes,
    this.onOpenPendingApprovals,
    this.onPunchStateChanged,
    this.isReportDone,
    this.onBeforeOpenReport,
    this.onBeforeMoveToNextSite,
    this.onPunchOutHandlerReady,
    this.todayClosed = false,
    this.onExtraDeclaration,
    this.reports,
    this.restStatusRequestId = 0,
    this.pendingReportsCount,
    this.onOpenPendingReports,
    this.isTodayPending,
    this.businessDayTick = 0,
    this.isPendingReadFailed,
  });
  /// 業務日の切り替わりの番号（便BN・下調べの (D5)・見つけた事 (47)(f)）。親（シェル）の時計が次の切り替わりの時刻に鳴った時だけ +1 する。
  ///   ★この数が進んだ時だけ、打刻の行と本日休みの状態を読み直す（_busy は立てない＝(P2)）。アプリへ戻った時は、この画面が自分で読む
  ///     （didChangeAppLifecycleState＝親は番号を進めない＝2回引かない）。既定 0＝今の呼び手は1文字も変わらない。
  final int businessDayTick;
  /// 未送信の箱を読めなかったか（便BN・見つけた事 (46)・【Q155】＝１）。本日休みの窓の本文の下に※を出すためだけに、押した瞬間に
  ///   親の真実（ReportStore.instance.pendingView の readFailed）を読む（isTodayPending と同じ流儀）。既定 null＝読めた事にする（今の窓のまま）。
  final bool Function()? isPendingReadFailed;
  /// 本日休みの状態をもう一度読んでほしいときに親（シェル）が +1 する通し番号（便F13）。
  ///   ★前例＝management_history_screen.dart の segmentRequestId（「今もう一度開いてほしい」の番号）。
  ///   ★この数が【進んだとき】だけ didUpdateWidget で読み直す（同じ数のままの再描画では読まない）。
  ///   ★親が進めるのは、ホームのタブ（index 0）へ入ったときと、🔔 のお知らせの一覧から戻ったとき
  ///     （日が変わった後や、別の端末での同意に追いつくため）。既定 0＝今の呼び手は1文字も変わらない。
  final int restStatusRequestId;
  /// 口の差し替え（検査だけが渡す）。
  ///   ★なぜ要るか【Q70】: この画面は initState から実 HTTP へ行くため、
  ///     要対応の行（0件なら出ない／押すと進む／天井で切れたら + が付く）を
  ///     1つも測れなかった。測れないまま出すのは、直したつもりで直っていない形。
  ///   ★形は ReportsService が既に持っている差し替えの入口
  ///     （@visibleForTesting ReportsService.forTest()）に乗せるだけ。新しい仕組みは作らない。
  ///   ★既定は null＝今までどおり ReportsService()。呼び出し側（home_screen.dart の
  ///     PunchScreen 生成箇所）は1文字も変わらない。
  final ReportsService? reports;
  final VoidCallback? onNavigateToReport;
  // ── N7: ホームの「⏰ 追加の申告」（完了ビューの同ボタンとは別の増設・あちらは不変）──
  // 締め済みか。真実源は home_screen の _todayClosed（'closed' を読む _readWorkStatusToday /
  //   _initTodayReportDone / _reevaluateReportDone / _onCloseToday が唯一の書き手）。
  //   →再（2026-10-21・便BN・下調べの (D1)）: _todayClosed は読み口（写しの勤務の種類と業務日が今の物の時だけ立つ）。写しを書くのは
  //   home_screen の _setMark と _clearMark だけ（読む口は _readWorkStatusToday から _readWorkStatusOn へ名前が替わった）。
  //   ★ここでは判定を作らず受けた真偽だけを見る。
  //   ★素の値で下ろす（bool Function() にしない）: この値は build 中に読むため。
  //     isReportDone は既存のコールバックのままだが N8 で build 中にも読んでいる。
  //     書き換えが必ず親の setState 経由なので再評価はされる＝動作は正しいが、意図は素の値の方が明快。
  //     親所有かつ build で読む値は shiftType / revisionCount と同じ素の prop に揃える。
  //   ★onPunchStateChanged には載せない: あちらは子→親（fetchToday で得た値を上げる口）で
  //     向きが逆。親所有の値を子の通知チャネルに相乗りさせない。
  final bool todayClosed;
  // 「⏰ 追加の申告」の押下先。親の既存ハンドラ home_screen:_openExtraDeclarationPicker を
  //   そのまま下ろすだけ（残業/休憩短縮の出し分けも実処理も親のまま・複製しない）。
  //   ★2件目確認（onBeforeOpenReport）は通さない＝申告ピッカーへ直行する。
  final Future<void> Function()? onExtraDeclaration;
  // N5: 「日報を報告」から日報フォームへ入る直前の親側ゲート。
  //   true=このまま進む / false=中止。null=素通し（＝従来の挙動）。
  //   「もう報告済みか」「締め済みか」の判定と2件目の確認ダイアログは親が持つ。
  //   この画面には判定式を複製しない（home_screen.dart:_confirmSecondReportIfNeeded）。
  //   ★休みゲート(_onReportTap) を通過した後にだけ呼ばれる＝ゲートの前後関係は不変。
  final Future<bool> Function()? onBeforeOpenReport;
  // N5: 「現場移動」から日報フォームへ入る直前の親側前処理。
  //   確認は現場移動ダイアログ側で済んでいるため、親は報告済みならリセットするだけ
  //   （home_screen.dart:_prepareMoveToNextSite）。true 固定＝中止経路は持たない。
  final Future<bool> Function()? onBeforeMoveToNextSite;
  // N3: 退勤打刻の実行口を親へ渡す。親（完了ビューの「今日はここまで」）が
  //   打刻ロジックを複製せず既存 _doPunch('out') 経路を呼べるようにするためだけの配線。
  //   initState で1回だけ通知する（値を渡すだけ・親側で setState はしない）。
  //   →再（2026-10-21・便BN・見つけた事 (50)・【Q156】＝１・下調べの (Z1)）: 口は呼んだ時にその場で答える（PunchOutStart）＝最中（_busy）で
  //   打たない（busy）・打ち始めた（started・done で打ち終わりを待てる）・この画面が無い（absent）。元は Future<void> で、最中の時は
  //   黙って打たなかった（親は打てたか分からずに閉じた）。
  final void Function(PunchOutStart Function() punchOut)? onPunchOutHandlerReady;
  final Widget? weatherPanel;
  // K1: 打刻状態を親(JsMainShell)へ上げる唯一の口。真実源は fetchToday(work_mode_service.dart)
  //   ＝この画面が受け取った値をそのまま流すだけで、判定式は親に複製しない。
  //   isActual も同じ便に載せる（完了ビューの出し分けが実打刻/みなしで違うため・_isActual:_設定由来）。
  final void Function(bool isActual, bool punchedIn, bool punchedOut)? onPunchStateChanged;
  // K5(Q9): 当日ぶんの報告が済んでいるか。親が持つ真実を読むだけ
  //   （home_screen.dart の `isDone: () => _todayReportDone` と同じ流儀。prefs 直読みはしない）。
  //   （元の説明の isDone の口は、便BN の (D4) で確かめの画面から外した＝流儀は「親の真実を関数で読む」のまま）
  final bool Function()? isReportDone;
  // 便BM（見本 claude/field_refused_today_mock_v1.html の ②③・【Q150】＝１）:
  //   ・pendingReportsCount … 要対応の一番上の「未送信日報」の行の数（null＝行を出さない）。数の決まりは親が
  //     lib/utils/pending_view.dart の homePendingCountOf で作る（ここに判定式を複製しない）。
  //   ・onOpenPendingReports … その行を押した時（「未送信日報」の画面を開くのは親）。
  //   ・isTodayPending … 今日の分（今の勤務区分・今の業務日）に未送信の日報が在るか。本日休みの窓の字を替えるためだけに、
  //     押した瞬間に親の真実を読む（isReportDone と同じ流儀）。既定 null＝在る事にしない（今の字のまま）。
  final PendingCountLabel? pendingReportsCount;
  final VoidCallback? onOpenPendingReports;
  final bool Function()? isTodayPending;
  // ── 要対応の件数と遷移（値も遷移先も親 JsMainShell の既存資産をそのまま下ろす）──
  //   件数取得・遷移先はこの画面では一切作らない（home_screen.dart の PunchScreen 生成箇所を参照）。
  //   0件のときは行そのものを描画しない＝「無いものは見せない」。
  final int revisionCount;          // 差し戻し（home_screen.dart の _revisionCount）
  // 振替休日（同 _substituteCount）。★職長かどうかで分けない＝振替は全員のもの。
  //   数えるのは一覧の口が返した行のうち action_needed が true の数（home_screen 側）。
  final int substituteCount;
  // BE の天井で切れた回。★切れていたら数の後ろに + を付ける＝嘘の数を出さない。
  final bool substituteTruncated;
  final int pendingApprovalCount;   // 承認待ち（同 _pendingApprovalCount・職長のときのみ非0が渡る）
  final VoidCallback? onOpenRevisions;
  final VoidCallback? onOpenSubstitutes;
  final VoidCallback? onOpenPendingApprovals;
  // 勤務区分（日勤/夜勤）は親(JsMainShell)が真実を保持し、値+変更通知を下ろす。
  // 送信時の report_date 補正・shift_type 送出は親側で行う。
  final String shiftType;                       // 'day'|'night'
  final ValueChanged<String> onShiftTypeChanged;
  // 勤務の種類を読み込めなかったか（便BK・見本 v3 の ⑰①）。真実は親（home_screen.dart の _shiftReadFailed）。
  //   true の間、選ぶ所の下に kShiftReadFailedNote を出す。既定 false＝今の呼び手は1文字も変わらない。
  final bool shiftReadFailed;
  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen> with WidgetsBindingObserver {
  bool _loading = true;
  WorkModeSettings _settings = WorkModeSettings.defaults;
  Map<String, dynamic>? _record;
  bool _punchedIn  = false;
  bool _punchedOut = false;
  String _gpsAddress = '位置を取得中…';
  Timer? _timer;
  bool _busy = false;
  int? _standardBreakMin;
  // ★法定休憩（6h/8h）の保持は廃止。読み手だった休憩申告シートが退役したため
  //   端末側で持つ意味が無くなった（値の出どころ WorkModeService.fetchToday /
  //   TodayStatus.legalBreak6h/8h は一切変更していない＝BEも他画面も無傷）。

  // 本日休み状態（_RestDayButton から持ち上げ）。ボタン表示と日報報告ゲートが
  // 単一の状態を共有する（照会失敗は fail-open＝rested=false）。
  //   →再（2026-10-21・便BN・見つけた事 (54)・【Q159】＝１・下調べの (S3)）: 照会の失敗は、同じ日に前に読めた値のまま（無い時は今の
  //   fail-open の初めの値）にして、「読めなかった」の印（_restReadFailed）を立てる＝下のボタンの下に※。
  // ★本番は今までどおり ReportsService()。差し替えを渡すのは検査だけ。
  late final ReportsService _reports = widget.reports ?? ReportsService();
  bool _restLoading = true;
  bool _rested      = false;
  String? _restReason;
  String _restPortion = 'full'; // full / am_half / pm_half（応答に無ければ full）
  // 今日が同意待ちの振替の休む日なら、その振替の id（便F13・BE の pending_substitute_rest_day_id）。
  //   ★あるときだけ要対応の行の下に同意待ちの枠を出す。BE はこの日を休みに数えない
  //     （rested:false）ので、下の「本日休み」は「登録済み」にならない。照会の失敗は null（枠を出さない）。
  String? _pendingSubstituteRestDayId;
  // その同意待ちの振替に、ご本人が同意できるかと、できない理由（便F14・BE の pending_substitute_can_agree・
  //   pending_substitute_cannot_agree_reason をそのまま）。照会の失敗は「同意できる」（枠そのものを出さない）。
  bool _pendingSubstituteCanAgree = true;
  String? _pendingSubstituteCannotAgreeReason;

  // ── 便BN（下調べの (D5) の (P1)〜(P4)・(D10)・■7 の (R1)〜(R11)・■8 の (S1)〜(S5)・(O1)）──
  //   読みに番号を付け、打刻の行は出した時の「行」（勤務区分と業務日）と比べて入れる。読めなかった事は※で出す（黙らない）。
  /// 今の行（勤務区分と業務日＝打刻の行はサーバで (人, 業務日, 勤務区分) の1行・(R1)）。
  ({String shift, String bizDate}) _rowNow() => (
        shift: widget.shiftType,
        bizDate: businessDateForShift(widget.shiftType, businessNow()),
      );
  // 打刻の行の読みの番号（(P1)）。_rowIssuedNo＝一番新しく出した番号・_rowEnteredNo＝入れた番号（取れた答えと (R5) で作った時だけ
  //   覚える）・_rowAnsweredNo＝一番新しく出した番号の答えが着いた時のその番号（(R8)＝「取得中...」は、これが _rowIssuedNo より小さい間）。
  int _rowIssuedNo = 0;
  int _rowEnteredNo = 0;
  int _rowAnsweredNo = 0;
  bool get _rowReading => _rowAnsweredNo < _rowIssuedNo;
  // 出している状態の行（(R2)・null＝初めの値＝未出勤のまま・読めた答えを入れた時に、その答えの行にする）。
  ({String shift, String bizDate})? _shownRow;
  // 打刻の状態を読めなかった印（(R3)・立っている間、実勤務の時だけ状態の下に※）。
  bool _punchReadFailed = false;
  // 会社の休憩の設定（standard_break_min）を、この画面で一度でも読めたかと、その値（(R5)・null も「読めた値」）。
  bool _breakMinEverRead = false;
  int? _readBreakMin;
  // 勤務の形の読みの番号（(P1)・_init 同士）と、この画面で勤務の形を一度でも入れたか。
  int _settingsIssuedNo = 0;
  int _settingsEnteredNo = 0;
  bool _settingsEver = false;
  // 今の行の読み（勤務の形と打刻の行の答えがどちらも着き、打刻の行を (R1) で捨てなかった読み）が在るか（(P1) の _loading）。
  bool _rowReadSettled = false;
  // (O1) 勤務の形を読めずに（投げて）、この画面で一度も入れていない印（立っている間、回る印の代わりに (お) の字）。
  bool _settingsFailed = false;
  // (O1) _init の番号（一番新しく出した _init が終わるまでの間、(お) の字は「取得中...」）。
  int _initIssuedNo = 0;
  int _initDoneNo = 0;
  bool get _initReading => _initDoneNo < _initIssuedNo;
  // (P3) _busy の間に見送った打刻の行の読み直し（_busy を下ろした後に1回、_reloadForShiftChange で読む）。
  bool _rowReloadPending = false;
  // 本日休みの読みの番号（(S2)）。_restEnteredNo＝取れた答えを入れた番号・_restReadDay＝その時の日（日本の日）・
  //   _restAnsweredNo＝一番新しく出した番号の答えが着いた時のその番号（(S4) の「取得中...」）。
  int _restIssuedNo = 0;
  int _restEnteredNo = 0;
  int _restAnsweredNo = 0;
  bool get _restReading => _restAnsweredNo < _restIssuedNo;
  String? _restReadDay;
  // 本日休みの状態を読めなかった印（(S3)・立っている間、下のボタンの下に※＝どの姿でも）。
  bool _restReadFailed = false;

  // 実勤務モードか。判定式はこの1本だけ（build:_isActual / K1の通知 / K5のガードが共有する）。
  bool get _isActual => _settings.mode == WorkModeType.actual;

  // K1: 現在の打刻状態を親へ通知する。setState の直後に呼ぶ（値を流すだけ・判定はしない）。
  void _notifyPunchState() {
    widget.onPunchStateChanged?.call(_isActual, _punchedIn, _punchedOut);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // N3: 退勤の実行口を親へ渡す（値を渡すだけ・親は setState しない）。
    widget.onPunchOutHandlerReady?.call(_punchOutForClose);
    _init();
    _loadRestStatus();
    // ★読み直しの知らせ（lib/utils/rest_day_refresh.dart・便F13）。どの道で休みや振替が
    //   変わっても、本日休みの状態をこの1本で読み直す。
    RestDayRefresh.changes.addListener(_onRestDayChanged);
  }

  void _onRestDayChanged() {
    if (mounted) _loadRestStatus();
  }

  // 本日休みの状態を読む。
  //   →再（2026-10-21・便BN・見つけた事 (54)・【Q159】＝１・下調べの (S1)〜(S4)）: 元は、取れなかった時に知らせ無しで「休みでない」に
  //   倒し、同じ日に前に読めた値も消した（投げた時は誰にも見えなかった）。読みに番号と、出した時の日（日本の日＝サーバの
  //   businessDate() と同じ日）を付け、答えは「出した日が着いた時の日と同じ」で「もう入れた取れた答えより新しい番号」の時だけ入れる
  //   （取れなかった答えは番号を覚えない＝後に着いた、それより前に出した取れた答えは入る）。取れなかった時は、同じ日に前に読めた値の
  //   まま（無い時は今の初めの値）にして、「読めなかった」の印を立てる。投げた時も取れなかった時と同じ。捨てた答えでは何もしない
  //   （「取得中...」だけ下ろす＝日をまたいだ時は、時計か戻った時の読みが続く）。
  Future<void> _loadRestStatus() async {
    final no = ++_restIssuedNo;
    final day = jstDateString(businessNow());
    if (_restReadFailed && mounted) setState(() {});   // (S4) 読む間は※の字を「取得中...」に
    ApiResult<RestDayToday>? res;
    try {
      res = await _reports.getRestDayToday();
    } catch (e) {
      debugPrint('本日休みの状態を読めませんでした: $e');
    }
    if (!mounted) return;
    final r = res;
    final rest = r?.data;
    setState(() {
      // (S4) 「取得中...」は、一番新しく出した読みの答えが着いた時に下ろす（入れても捨てても）。
      if (no == _restIssuedNo) _restAnsweredNo = no;
      // (S2) 日をまたいだ答えと、もう入れた取れた答えより古い答えは捨てる（値・_restLoading・印を替えない）。
      if (day != jstDateString(businessNow()) || no <= _restEnteredNo) return;
      _restLoading = false;   // (S1) 門を通った答えなら、取れても取れなくても下ろす
      if (r != null && r.ok && rest != null) {
        _rested      = rest.rested;
        _restReason  = rest.reason as String?;
        _restPortion = rest.portion;
        _pendingSubstituteRestDayId = rest.pendingSubstituteRestDayId;
        _pendingSubstituteCanAgree = rest.pendingSubstituteCanAgree;
        _pendingSubstituteCannotAgreeReason = rest.pendingSubstituteCannotAgreeReason;
        _restEnteredNo = no;
        _restReadDay = day;
        _restReadFailed = false;
      } else {
        // (S3) 同じ日に前に読めていれば、その値のまま（同意待ちの枠も）。読めていない時（読めた事が無い・日が替わった）は今の初めの値。
        if (_restReadDay != day) {
          _rested      = false; // fail-open
          _restReason  = null;
          _restPortion = 'full';
          _pendingSubstituteRestDayId = null;
          _pendingSubstituteCanAgree = true;
          _pendingSubstituteCannotAgreeReason = null;
        }
        _restReadFailed = true;
      }
    });
  }

  // 日報報告への遷移ゲート。終日休み(rested かつ portion=full)なら確認ダイアログを挟み、
  // 「取り消して続行」時のみ DELETE 成功後に従来遷移する（失敗は SnackBar で可視化）。
  // 半休(am_half/pm_half)は「働く日」なので日報は必要＝ゲートせず従来どおり即遷移。
  // rested=false のときも従来どおり即遷移（挙動不変）。
  //
  // N5: 休みゲートを通過した「後」に親側ゲートを1枚だけ挟めるようにした。
  //   ・parentGate 省略時は widget.onBeforeOpenReport（＝「日報を報告」用の2件目確認）。
  //   ・「現場移動」からは widget.onBeforeMoveToNextSite を明示して渡す（確認なし・リセットのみ）。
  //   ★上の休み判定式（!_rested || _restPortion != 'full'）・ダイアログ文言・
  //     deleteRestDay 経路は1文字も変えていない。遷移の直前に1行足しただけ。
  Future<void> _onReportTap({Future<bool> Function()? parentGate}) async {
    final gate = parentGate ?? widget.onBeforeOpenReport;
    if (!_rested || _restPortion != 'full') {
      if (gate != null && !await gate()) return;
      widget.onNavigateToReport?.call();
      return;
    }
    // 便BN（見つけた事 (47)(g)・下調べの (D8)）: 開いたまま業務日が替われば閉じる（「戻る」を押した時と同じ＝何もしない）。
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => CloseOnBusinessDayChange(
        shiftType: widget.shiftType,
        closeValue: false,   // (D8) 「戻る」と同じ値（休みの取り消しの窓）
        child: AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        title: const Text('本日は休み登録済みです',
            style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: const Text('日報を出すには、本日の休み登録を取り消す必要があります。',
            style: TextStyle(color: FieldTokens.textBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('戻る', style: TextStyle(color: FieldTokens.textSupport)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('休みを取り消して続行',
                style: TextStyle(color: FieldTokens.accent)),
          ),
        ],
        ),
      ),
    );
    if (proceed != true) return;

    final res = await _reports.deleteRestDay(); // 既存メソッドを再利用
    // ★今日の休みが変わった。カレンダーとシェルへも知らせる（便F13）。
    //   （元）mounted を見て戻った後に鳴らしていた（通った後にこの画面が閉じていると鳴らない）。
    //   →再（2026-09-30・便F13続）: 通ったら、この画面が閉じたかを見る前に1回だけ鳴らす。
    if (res.ok) RestDayRefresh.ring();
    if (!mounted) return;
    if (res.ok) {
      await _loadRestStatus();               // ボタン表示も最新化
      if (!mounted) return;
      if (gate != null && !await gate()) return;
      widget.onNavigateToReport?.call();      // 従来の日報報告へ
    } else {
      showJsSnackbar(
        context,
        '${res.errorMessage ?? '休みの取り消しに失敗しました'}'
        '${res.statusCode != 0 ? '（${res.statusCode}）' : ''}',
        isError: true,
      );
    }
  }

  // ★（元）前に戻ったとき（resumed）は _init だけで、本日休みの状態は読み直さなかった。
  //   →再（2026-09-29・便F13）: 本日休みの状態も読み直す（日が変わった後や、別の端末での
  //   同意に追いつくため）。要対応の件数はシェルの resumed が読み直す。
  //   ★（便BN・下調べの (P1)）: _busy を見ずに読む（打刻か読み直しの最中でも読む・答えは番号の口で、もう入れた答えより新しい時だけ入る）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _init();
      _loadRestStatus();
    }
  }

  // ── シフト切替時の再取得 ────────────────────────────────────────────────
  // 勤怠行は (person, 業務日, shift_type) で1行。シフトを切り替えると「見るべき行」が
  // 別の行に変わるため、切替後の shift_type で必ず取り直す。
  // ★これが無いと _punchedIn/_punchedOut/_record が切替前シフトの値のまま残り、
  //   BE 上は打刻済みの行に対して出勤ボタンが出る（＝退勤済み行への出勤上書きが起きる）。
  // shiftType は親(JsMainShell)が真実を持ち props で下ろすため、値が変わると
  // didUpdateWidget が呼ばれる（親の setState → PunchScreen の widget 更新）。
  //   発火元: _ShiftTypeSelector → widget.onShiftTypeChanged
  //          → home_screen.dart の setState(_shiftType) → ここ。
  //   起動時の勤務区分復元（home_screen.dart:_restoreShiftType）で値が変わる場合も同じ経路で通る。
  //   →再（2026-10-21・便BN・下調べの (D5) の (P2)(P4)）: 親の時計の番号（businessDayTick）が進んだ時は、戻った時と同じく _busy を立てずに
  //   打刻の行と本日休みの状態を読み直す（_busy が立っていれば、打刻の分は (P3) の印を立てて見送る・本日休みは見送らない）。同じ描きで
  //   勤務区分と時計の番号の両方が替わった時は、打刻の行は _reloadForShiftChange の1回・本日休みは1回だけ読む。
  @override
  void didUpdateWidget(covariant PunchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dayTicked = widget.businessDayTick != oldWidget.businessDayTick;
    if (widget.shiftType != oldWidget.shiftType) {
      _reloadForShiftChange();
    } else if (dayTicked) {
      _reinitNoBusy();
    }
    // 親が「もう一度読んで」の番号を進めたときだけ本日休みの状態を読み直す（便F13）。
    //   便BN (D5): 時計の番号が進んだ時も（同じ描きで両方進んでも1回）。
    if (widget.restStatusRequestId != oldWidget.restStatusRequestId || dayTicked) {
      _loadRestStatus();
    }
  }

  // 再取得そのものは既存の取得経路 _init をそのまま呼ぶ。
  //   ＝fetchToday(shiftType: widget.shiftType) と、その戻り値を
  //     _record/_punchedIn/_punchedOut へ入れる処理は1箇所のまま（状態のコピーを作らない）。
  //   didUpdateWidget の時点で widget.shiftType は既に切替後の値。
  // 競合防御: 取得が終わるまで既存の _busy を立てる。_busy は打刻の入口
  //   （_confirmPunch / _doPunch）と打刻ボタンの disabled 判定が
  //   既に見ている単一のフラグなので、新しい排他機構は作らない。
  //   →再（2026-10-21・便BN・下調べの (P3)・(D10)）: 元は _busy の時に読み直しを捨てた（_doPunch が完了時に読むのは、打った後の読み直しを
  //   呼ぶ前に替わった分だけ＝その後に替わった分は、どこでも読まれなかった）。_busy の間は「読み直し待ち」の印を立てて見送り、
  //   _busy を下ろした後に1回、ここで読む（_afterBusyDown・読む間は _busy＝打刻を押せない）。
  Future<void> _reloadForShiftChange() async {
    if (_busy) {
      _rowReloadPending = true;   // 打刻処理中は触らない（下ろした後に1回読む＝_afterBusyDown）
      return;
    }
    setState(() => _busy = true);
    try {
      await _init();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _afterBusyDown();
      }
    }
  }

  // (P3) _busy を下ろした後：見送った打刻の行の読み直しが在れば、1回だけ読む（_busy を立てて読む）。
  void _afterBusyDown() {
    if (!mounted || !_rowReloadPending) return;
    _rowReloadPending = false;
    _reloadForShiftChange();
  }

  // (P2)(R4) _busy を立てずに _init を呼ぶ（_busy が立っていれば (P3) の印を立てて見送る）。
  void _reinitNoBusy() {
    if (_busy) {
      _rowReloadPending = true;
      return;
    }
    _init();
  }

  // ※と (お) の字を押した時（(R4)・(S4)・(O1)）：読めなかった分をまとめて読み直す（どちらの※を押しても同じ）。
  //   本日休みは _busy でも見送らない（(P2) と同じ）。
  void _onRereadTap() {
    if (_punchReadFailed || _settingsFailed) _reinitNoBusy();
    if (_restReadFailed) _loadRestStatus();
  }

  //   →再（2026-10-21・便BN・下調べの (P1)・(R1)〜(R3)・(R11)・(O1)）: 元は2つの答えを .wait で一緒に受け（どちらかが投げると両方とも
  //   入らず、_loading も下りずに回る印が回り続けた）、打刻の行は取れなかった時に前回値を据え置くだけ（読めなかった事は出なかった）。
  //   勤務の形と打刻の行の答えを1つずつ受け（投げた方だけ取れなかった扱い）、それぞれ番号の口を通して入れる（もう入れた答えより
  //   新しい番号の時だけ）。打刻の行は、出した時の行（勤務区分と業務日）が今の行と同じ時だけ入れる（_takeRowAnswer）。勤務の形が
  //   投げた時は前の値のまま（入れない）。_loading は「今の行の読みが在る」と「勤務の形を一度でも入れた」がそろった時に下ろす
  //   （一度も入れられないうちは、回る印の代わりに (お) の字＝build）。
  Future<void> _init() async {
    final initNo = ++_initIssuedNo;
    final settingsNo = ++_settingsIssuedNo;
    if (_settingsFailed && mounted) setState(() {});   // (O1) 読む間は (お) の字を「取得中...」に
    // K6: 勤怠行は (person, 業務日, shift_type) で1行。見るシフトを明示する（_issueRowRead の中・出した時の行で読む）。
    final rowRead = _issueRowRead();
    WorkModeSettings? settings;
    var settingsThrew = false;
    try {
      settings = await WorkModeService().fetchFromServer();
    } catch (e) {
      debugPrint('勤務の設定を読めませんでした: $e');
      settingsThrew = true;
    }
    final read = await rowRead;
    // (O1) 一番新しく出した _init が終わった時に「取得中...」を下ろす（投げても・捨てても）。
    if (initNo == _initIssuedNo) _initDoneNo = initNo;
    if (!mounted) return;
    setState(() {
      if (settings != null && settingsNo > _settingsEnteredNo) {
        _settings = settings;
        _settingsEnteredNo = settingsNo;
        _settingsEver = true;
        _settingsFailed = false;
      } else if (settingsThrew && !_settingsEver) {
        _settingsFailed = true;
      }
      if (_takeRowAnswer(read.no, read.row, read.res)) _rowReadSettled = true;
      if (_rowReadSettled && _settingsEver) _loading = false;
    });
    _afterPunchStateSet();
    fetchGpsAddress().then((r) {
      if (mounted) setState(() => _gpsAddress = r.address);
    });
  }

  // 打刻の行の読みを1つ出す（(P1) の番号と、(R1) の出した時の行を付ける）。投げた時は res＝null（取れなかった扱い＝(R11)・
  //   投げた事は、今の作りのほかの所と同じく debugPrint だけ）。読む所＝_init・打った後（_doPunch）・断られた後（(R6)）。
  Future<({int no, ({String shift, String bizDate}) row, ApiResult<TodayAttendance>? res})>
      _issueRowRead() async {
    final row = _rowNow();
    final no = ++_rowIssuedNo;
    if (_punchReadFailed && mounted) setState(() {});   // (R8) 読む間は※の字を「取得中...」に
    ApiResult<TodayAttendance>? res;
    try {
      res = await WorkModeService().fetchToday(shiftType: row.shift);
    } catch (e) {
      debugPrint('打刻の状態を読めませんでした: $e');
    }
    return (no: no, row: row, res: res);
  }

  // 打刻の行の答えを入れる（(R1)(P1)(R3)(R8)・★setState の中で呼ぶ）。返り＝(R1) で捨てなかったか（_loading の「今の行の読み」に数える）。
  //   ・一番新しく出した読みの答えなら「取得中...」を下ろす（入れても捨てても）。
  //   ・出した時の行が今の行と違えば捨てる（取れた答えも取れなかった答えも）。
  //   ・もう入れた答えより古い番号は入れない（取れていても・取れていなくても）。
  //   ・取れた答え＝値と出している状態の行を入れ、番号を覚え、読めなかった印を下ろす。
  //   ・取れなかった答え（ok:false・投げた＝res が null）＝番号を覚えずに、読めなかった印を立てる（_markPunchReadFailed）。
  bool _takeRowAnswer(int no, ({String shift, String bizDate}) row, ApiResult<TodayAttendance>? res) {
    if (no == _rowIssuedNo) _rowAnsweredNo = no;   // (R8) 一番新しく出した読みの答え
    if (row != _rowNow()) return false;
    if (no <= _rowEnteredNo) return true;
    final today = res?.data;
    if (res != null && res.ok && today != null) {
      _record           = today.record;
      _punchedIn        = today.punchedIn;
      _punchedOut       = today.punchedOut;
      _standardBreakMin = today.standardBreakMin;
      _readBreakMin     = today.standardBreakMin;
      _breakMinEverRead = true;
      _shownRow         = row;
      _rowEnteredNo     = no;
      _punchReadFailed  = false;
    } else {
      _markPunchReadFailed();
    }
    return true;
  }

  // 打った後の読み直しが取れなかった時（(R5)・★setState の中で呼ぶ）。(R1)(P1) を通した上で、押した時の行が今の行と同じで、
  //   打てた時の答えに行（record）が在り、会社の休憩の設定をこの画面で一度でも読めていれば、打てた時の答えで状態を作る
  //   （打った後の読み直しの番号を入れた事にする＝後に着いた古い番号の答えは入らない）。作らない時は (R3) と同じ※。
  //   ★比べるのは端末の押した時の行（答えの record の work_date は使わない）。
  void _takeRowAnswerAfterPunch(int no, ({String shift, String bizDate}) row,
      ({String shift, String bizDate}) pressedRow, Map<String, dynamic>? rec) {
    if (no == _rowIssuedNo) _rowAnsweredNo = no;   // (R8)（打った後の読み直し）
    final now = _rowNow();
    if (row != now) return;
    if (no <= _rowEnteredNo) return;
    if (pressedRow == now && rec != null && _breakMinEverRead) {
      _record           = rec;
      _punchedIn        = rec['punch_in'] != null;    // GET /attendance/today の punched_in と同じ決め方
      _punchedOut       = rec['punch_out'] != null;   // 同 punched_out
      _standardBreakMin = _readBreakMin;              // 前に読めた値のまま
      _shownRow         = now;
      _rowEnteredNo     = no;
      _punchReadFailed  = false;
      return;
    }
    _markPunchReadFailed();
  }

  // 読めなかった印を立てる（(R3)）。出している状態の行が今の行でない時は、値を初めの値（未出勤）に戻し、出している状態の行を
  //   「無し」にする（前の行の状態を出さない＝※の字は「未出勤で表示しています」）。今の行の時は値をそのまま（「前に読めた状態」）。
  void _markPunchReadFailed() {
    _punchReadFailed = true;
    if (_shownRow != _rowNow()) {
      _record           = null;
      _punchedIn        = false;
      _punchedOut       = false;
      _standardBreakMin = null;
      _shownRow         = null;
    }
  }

  // 打刻の値を替えた後（親の写し＝K1・経過の時計）。
  void _afterPunchStateSet() {
    _notifyPunchState();
    if (_punchedIn && !_punchedOut) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    RestDayRefresh.changes.removeListener(_onRestDayChanged);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // 同意待ちの枠の［振替休日を開く］（便F13）。★読み直しは1件の画面が鳴らす知らせで届く
  //   （lib/utils/rest_day_refresh.dart）ので、ここで戻った後の読み直しを書き足さない。
  //   →再（2026-09-30・便F13続）: 鳴らすのは1件の画面（同意・取り下げ・取り消し）と、そこから開く
  //   休む日の変更の画面（申し出）。鳴らす所の名簿は lib/utils/rest_day_refresh.dart の冒頭。
  //   ★差し替え口（検査の reports）はそのまま1件の画面へ下ろす。
  Future<void> _openPendingSubstitute(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          SubstituteDetailScreen(restDayId: id, service: widget.reports),
    ));
  }

  // N3: 完了ビュー「今日はここまで」から親が呼ぶ退勤の口。
  //   打刻の実処理は既存 _doPunch('out') をそのまま通す（判定式・API呼び出しは複製しない）。
  //   ★allowGoReport:false ＝退勤後の日報フォーム自動起動を抑制する。
  //     呼び元が完了ビュー＝既に報告済みの文脈なので、そこから報告フォームを開き直さない。
  //   ★親は関数参照を保持し続けるため、この画面が破棄された後に呼ばれても
  //     unmounted への setState にならないよう入口で mounted を見る（fail-safe）。
  //   →再（2026-10-21・便BN・見つけた事 (50)・【Q156】＝１・下調べの (Z1)）: その場で答える。最中（_busy）なら打たずに busy・
  //   打ち始めたら started（done＝打ち終わりの結果＝_doPunch が _busy を下ろした時に返る）・この画面が無ければ absent
  //   （親は取れなかった時と同じに扱い、既定の字で知らせる）。
  PunchOutStart _punchOutForClose() {
    if (!mounted) return (kind: PunchOutStartKind.absent, done: null);
    if (_busy) return (kind: PunchOutStartKind.busy, done: null);
    return (kind: PunchOutStartKind.started, done: _doPunch('out', allowGoReport: false));
  }

  // allowGoReport: 既定 true＝従来どおり「退勤成功→_onReportTap で日報へ直行」。
  //   false は N3（完了ビュー経由の退勤）だけが渡す。
  //   →再（2026-10-21・便BN・下調べの (D10)・(R5)(R6)・(52)・(Z1)）:
  //   ・返り＝打てたか（締めの窓の退勤が待つ）。最中（_busy）の時は false（呼び手の _punchOutForClose が先に見る）。
  //   ・押した時の勤務の種類と業務日（行）は頭で1回だけ取り、打つ所だけに使う（GPS を待つ間に勤務の種類が替わっても、押した時の
  //     種類で打つ）。打った後の読み直しは、終わった時の勤務の種類で読む（_reloadForShiftChange の「打刻処理中は触らない」の約束＝
  //     画面と親の打刻の状態は今の種類の行）。
  //   ・打つ所（GPS と送る所）が投げた時は、取れなかった時と同じ（既定の字で知らせる・_busy は finally で下ろす）＝(52)。
  //   ・打った後の読み直しが取れなかった時は、打てた時の答えで状態を作る（(R5)・_takeRowAnswerAfterPunch）。
  //   ・断られた時（すでに出勤・すでに退勤・出勤の打刻が無い）は、知らせの後に、_busy を下ろす前に読み直す（(R6)）。
  //   ・退勤の後に日報のフォームを開くかは「この打刻の答え」（読めた時は読み直しの答え・読めなかった時は打てた時の答え）が退勤済みで、
  //     押した時と今の勤務の種類が同じ時だけ（替わっていた時は開かない＝反映漏れの時と同じ）。
  Future<bool> _doPunch(String type, {bool allowGoReport = true}) async {
    if (_busy) return false;
    final pressedRow = _rowNow();   // (D10) 押した時の行（勤務の種類と業務日）
    setState(() => _busy = true);
    // 裁定(b): 退勤スライド確定直後は日報へ直行する（ホームに戻さない）。
    // 遷移先の出し分け（未提出=日報フォーム / 提出済=完了ビュー）は既存資産に委ねる:
    //   _onReportTap → widget.onNavigateToReport → home_screen.dart の `_openReportForm`（日報のフォームを全画面で開く）
    //   → そのフォームの中の `if (_todayReportDone) AfterReportBody`（提出済判定は
    //     home_screen の _todayReportDone（読む時は _readWorkStatusToday の印を _isReportDoneStatus で見る）が単一の真実源）。
    //     判定式はここに複製しない。
    //   →再（2026-10-21・便BN・下調べの (D1)(D3)）: フォームの中の出し分けは「出している印」（home_screen の _shownMark＝今日の写しか、
    //     またいで送った印）。読む口は _readWorkStatusOn（勤務の種類と業務日を受ける）。
    //   （元の説明は「_setTab(1)」＝フォームを日報タブに置いていた頃の作り＝便BM で今の作りに合わせた・見つけた事 (43)。
    //   元の説明の「home_screen:_readReportDone」は今は無い名前＝便BM の検分 a329 の R1 で今の名前にした）
    // _busy 解除後に呼ぶため finally の外へ出す（ゲート内のダイアログ中も操作可）。
    bool goReport = false;
    var punched = false;
    try {
      ({String address, double? lat, double? lon, String status, String? failReason})? gps;
      ApiResult<Map<String, dynamic>>? result;
      try {
        gps = await fetchGpsAddress();
        result = await WorkModeService().punch(
          type,
          lat:  gps.lat,
          lng:  gps.lon,
          addr: gps.address,
          shiftType: pressedRow.shift,   // S5b: 勤務区分をBEへ送出（夜勤は始業日1行に収まる）・便BN (D10): 押した時の種類
        );
      } catch (e) {
        debugPrint('打刻を送れませんでした: $e');   // (52) 投げた事は debugPrint だけ（知らせは下の既定の字）
      }
      if (!mounted) return false;
      final g = gps;
      final r = result;
      if (g == null || r == null) {
        showJsSnackbar(context, kPunchErrorText, isError: true);
        return false;
      }
      if (r.ok) {
        punched = true;
        // 出勤打刻で取れた現在地を端末にも残す（日報フォームの初期表示が読む既存3キーへ）。
        // 新しいキーは作らない。退勤(out)では上書きしない＝現場の記録は出勤時の位置を残す。
        if (type == 'in') await _persistPunchGps(g);
        // (P3) 下の読み直しが今の勤務の種類で読む＝この前に見送った読み直しは、ここで読む（2回読まない）。
        _rowReloadPending = false;
        final read = await _issueRowRead();
        if (!mounted) return true;
        final readRes = read.res;
        final today = readRes?.data;
        final rec = r.data;
        final readOk = readRes != null && readRes.ok && today != null;
        setState(() {
          if (readOk) {
            _takeRowAnswer(read.no, read.row, readRes);
          } else {
            _takeRowAnswerAfterPunch(read.no, read.row, pressedRow, rec);
          }
        });
        _afterPunchStateSet();
        // 退勤打刻がサーバに反映された時だけ立てる（出勤時・反映漏れ時は従来どおり）
        //   →再（便BN (D10)(R5)）: 「この打刻の答え」で決める（読めた時は読み直しの答え・読めなかった時は打てた時の答えの行）。
        //   押した時と今で勤務の種類が違えば開かない。
        final outByThis = readOk
            ? today.punchedOut
            : (rec != null && rec['punch_out'] != null);
        goReport = allowGoReport &&
            type == 'out' &&
            outByThis &&
            pressedRow.shift == widget.shiftType;
      } else {
        showJsSnackbar(
          context,
          r.errorMessage ?? kPunchErrorText,
          isError: true,
        );
        // (R6) 断られた時（今の行の状態が画面と違う）は、知らせの後に、_busy を下ろす前に読み直す（打った後の読み直しと同じ口）。
        if (kPunchRefusalRereadCodes.contains(r.errorCode)) {
          _rowReloadPending = false;
          final read = await _issueRowRead();
          if (!mounted) return false;
          setState(() => _takeRowAnswer(read.no, read.row, read.res));
          _afterPunchStateSet();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _afterBusyDown();   // (P3)
      }
    }
    if (goReport && mounted) await _onReportTap();
    return punched;
  }

  // 出勤打刻時のGPSを端末へ保存する。保存条件は home_screen.dart:_fetchGps(971-982) と同一:
  //   ・lat/lng は非nullのときだけ
  //   ・住所は status=='ok'（住所の構築に成功）のときだけ
  //     ＝'GPS取得失敗' / '位置情報の権限がありません' / 座標フォールバックを住所として焼かない
  //       （キャッシュ焼き付きの停止。理由は home_screen.dart の _readWorkStatusToday のコメントと同じ）。
  //       （元の説明の「_readWorkStatusToday のコメント」は場所の違い＝理由が書いてあるのは home_screen.dart の _fetchGps の
  //       「キャッシュ焼き付きの停止」の説明・_readWorkStatusToday は便BN で _readWorkStatusOn に替わった）
  // 失敗しても打刻の成立は覆さない（例外は握って握り潰さずログのみ・秘匿値は出さない）。
  Future<void> _persistPunchGps(
      ({String address, double? lat, double? lon, String status, String? failReason}) gps) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (gps.lat != null) await prefs.setDouble('gps_lat', gps.lat!);
      if (gps.lon != null) await prefs.setDouble('gps_lon', gps.lon!);
      if (gps.status == 'ok') await prefs.setString('gps_address', gps.address);
    } catch (e) {
      debugPrint('打刻GPSの端末保存に失敗: $e');
    }
  }

  // ── N1: 打刻の確認ダイアログ ───────────────────────────────────────────
  // 打刻は「押す → 時刻を見て確定」の2段にする（旧スライド確定UIは撤去済み）。
  // ★表示している時刻は端末の現在時刻＝確認のための目安。実際に刻まれるのは BE の now()
  //   （routes/attendance.js の POST /punch が punch_in/punch_out に now() を入れる）。
  //   ここから時刻を送ることはしない＝真実源は BE のまま1文字も変えていない。
  // OK のときだけ既存 _doPunch(type) を呼ぶ（打刻処理・goReport 経路は不変）。
  Future<void> _confirmPunch(String type) async {
    if (_busy) return;
    final isIn = type == 'in';
    final now  = DateTime.now();
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:'
                 '${now.minute.toString().padLeft(2, '0')}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        title: Text(isIn ? '出勤' : '退勤',
            style: const TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 現在時刻が主役（金 #D9C08A ＝ FieldTokens.brand）。
            Text(
              hhmm,
              style: const TextStyle(
                color: FieldTokens.brand,
                fontSize: 40,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isIn ? 'この時刻で出勤しますか？' : '退勤して日報の作成に進みます',
              textAlign: TextAlign.center,
              style: const TextStyle(color: FieldTokens.textBody),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isIn ? '出勤する' : '退勤する',
                style: const TextStyle(color: FieldTokens.accent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _doPunch(type);
  }

  // ── 現場移動（22bcfd3 の確認ダイアログ。文言は1文字も変えていない）──────────
  // 「日報を作成」を選んだときだけ既存の単一ゲート _onReportTap へ流す＝休みゲートも
  // 二重pushガードもそのまま通る（判定式はここに複製しない）。
  // N5: 親側前処理 onBeforeMoveToNextSite を明示して渡す＝報告済みなら親が
  //   _resetForNextReport を通してからフォームを開く（2件目の確認は挟まない）。
  Future<void> _onMoveToNextSiteTap() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        title: const Text('現場移動',
            style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: const Text(
            '現在地を記録して、この現場の日報を作成します。',
            style: TextStyle(color: FieldTokens.textBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('日報を作成',
                style: TextStyle(color: FieldTokens.accent)),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    await _onReportTap(parentGate: widget.onBeforeMoveToNextSite);
  }

  String _breakLabel() {
    final status = _record?['break_override_status'] as String?;
    final min    = _record?['break_override_min']    as int?;
    if (status == 'approved' && min != null) return '休憩 $min分（申告受理済み）';
    if (status == 'pending')                return '休憩変更を申告中（${min ?? '--'}分）';
    // 却下の可視化。ここが無いと rejected は下の「会社設定」／「自動」へ黙って落ち、
    // 却下された事実がどこにも出なかった（BE: attendanceCalculator.js の computeBreakAndNet の break_override_status === 'approved' 判定で
    // approved 以外は会社設定/法定値にフォールバックする＝計算からも静かに消える）。
    if (status == 'rejected') {
      return _standardBreakMin != null
          ? '休憩の申告は却下されました（会社設定 $_standardBreakMin分）'
          : '休憩の申告は却下されました';
    }
    if (_standardBreakMin != null)          return '休憩 $_standardBreakMin分（会社設定）';
    return '休憩は労働時間に応じて自動';
  }

  // ★休憩の申告シート（_openBreakRequestSheet / _onBreakRequestSubmitted /
  //   _BreakRequestSheet）は退役（ボス裁定＝二重導線の解消）。休憩の申告は
  //   退勤後の報告フロー（home_screen.dart の「追加の申告」＝休憩の短縮）に
  //   一本化した。送信API WorkModeService().breakRequest はそちらが使い続ける。
  //   この画面の休憩は _breakLabel() による表示のみ（申告状態の可視化は継続）。

  // K5(Q9): 「本日休み」を押した瞬間のガード。
  //   みなしモードで当日ぶんの報告が済んでいる（done / closed）ときだけ確認を挟む。
  //   ・報告済みかどうかは親の真実 widget.isReportDone を読むだけ（prefs 直読み・判定式の複製なし）
  //   ・実打刻は締めが退勤打刻であり、そもそも出勤後は「本日休み」ボタンが出ない
  //     （_buildOperationArea の showRestDay）ため対象外＝true を返して素通しする
  //   ・false を返した場合、_RestDayButton は画面遷移しない（袋小路を作らずその場に留まる）
  //   →再（2026-10-19・便BM・見本 claude/field_refused_today_mock_v1.html の ③・【Q150】＝１）: 今日の分に未送信の日報が在る時
  //   （widget.isTodayPending・親の真実）だけ、題と本文を事実に合わせる（「提出済みです」と言わない）。全部届いている時は今の字。
  //   →再（2026-10-21・便BN・見つけた事 (46)・【Q155】＝１）: 未送信の箱を読めなかった時（widget.isPendingReadFailed・押した瞬間に読む）
  //   だけ、本文の下に※（kPendingReadFailedNote・左寄せ）。題と本文は今の決まりのまま（前に読めた姿で決まる）。
  //   →再（2026-10-21・便BN・見つけた事 (47)(g)・下調べの (D8)）: 開いたまま業務日が替われば閉じる（「戻る」を押した時と同じ）。
  Future<bool> _restDayGuard() async {
    if (_isActual) return true;
    if (widget.isReportDone?.call() != true) return true;
    final pending = widget.isTodayPending?.call() == true;
    final readFailed = widget.isPendingReadFailed?.call() == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => CloseOnBusinessDayChange(
        shiftType: widget.shiftType,
        closeValue: false,   // (D8) 「戻る」と同じ値（本日休みの窓）
        child: AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        title: Text(pending ? kTodayPendingTitle : '本日は報告済みです',
            style: const TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                pending ? kRestDayPendingBody : '本日は既に日報を提出済みです。休みとして登録しますか？',
                style: const TextStyle(color: FieldTokens.textBody)),
            if (readFailed) kPendingReadFailedNoteDialogView,
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('戻る', style: TextStyle(color: FieldTokens.textSupport)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('休みとして登録',
                style: TextStyle(color: FieldTokens.accent)),
          ),
        ],
        ),
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    // (O1)（便BN・見つけた事 (51) の (お)・【Q161】＝１）: 勤務の形を一度も入れられないまま読みが投げた時は、回る印の代わりに字を出す
    //   （押すと「取得中...」にして読み直す・読めれば今の画面・読めなければまた同じ字）。初めの値（みなし）の姿では描かない。
    if (_loading) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: _settingsFailed
              ? _RereadNote(
                  text: _initReading ? kRereadingText : kSettingsReadFailedText,
                  fontSize: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onTap: _onRereadTap,
                )
              : const CircularProgressIndicator(color: _accent),
        ),
      );
    }

    final isActual = _settings.mode == WorkModeType.actual;
    final now = businessNow();
    final dow = '日月火水木金土'[now.weekday % 7];
    final dateLabel =
        '${now.year}年'
        '${now.month.toString().padLeft(2, '0')}月'
        '${now.day.toString().padLeft(2, '0')}日（$dow）';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            if (widget.weatherPanel != null) widget.weatherPanel!,
            // ── 情報エリア（スクロール） ───────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 日付 + モードピル
                    Row(children: [
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: _text, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      _ModePill(isActual: isActual),
                    ]),
                    const SizedBox(height: 10),
                    // 住所
                    Row(children: [
                      const Icon(Icons.location_on_outlined, color: _label, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _gpsAddress,
                          style: const TextStyle(color: _label, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    const Divider(color: _border, thickness: 1, height: 1),
                    // ── 要対応行（0件の行は描画しない）────────────────
                    //   件数・遷移先は親から下ろした既存の値だけを使う。
                    // ★この2本の色は lib/utils/report_status_style.dart の
                    //   対応表へ【寄せていない】。承知している例外である。
                    //   ・寄せられないのではなく、寄せると見た目が変わるため
                    //     裁定を待っている。対応表は差戻し＝statusError（赤）・
                    //     未承認＝statusWarning（橙）なので、寄せると
                    //     差し戻しの帯が橙から赤へ、承認待ちの帯が accent（青緑）から
                    //     橙へ変わる。
                    //   ・ここの色は日報1枚に付ける状態のバッジではなく、
                    //     件数を数えた行の左に立てる2pxの帯（_AttentionRow の accent）で、
                    //     押して次の画面へ行く導線の印である。バッジとは役割が違う。
                    //   ・検査 test/report_status_style_test.dart の名簿
                    //     kKnownOutsideStatusTable にこのファイルを載せてある。
                    //     寄せると決めた日は、名簿から外して検査を緑に戻すこと。
                    //   ・便BM の「未送信日報」の行（下）と振替休日の行も、同じ帯（statusWarning）＝同じ例外。
                    // 未送信日報（便BM・見本 claude/field_refused_today_mock_v1.html の ②・【Q150】＝１）。★要対応の一番上。
                    //   形・高さ・帯の色（statusWarning＝橙）は差し戻し・振替休日の行と同じ。数の字は送った後の画面の
                    //   「未送信日報」の見出しと同じ決まり（N件・N件以上・件数不明＝親の homePendingCountOf）。どの状態のホームでも出る。
                    if (widget.pendingReportsCount != null)
                      _AttentionRow(
                        accent: FieldTokens.statusWarning,
                        label:  kPendingSectionLabel,
                        count:  null,                             // 数は下の countLabel だけ（_AttentionRow の★）
                        countLabel: widget.pendingReportsCount,
                        onTap:  widget.onOpenPendingReports,
                      ),
                    if (widget.revisionCount > 0)
                      _AttentionRow(
                        accent: FieldTokens.statusWarning,          // 差し戻し = warning系
                        label:  '差し戻し',
                        count:  widget.revisionCount,
                        onTap:  widget.onOpenRevisions,
                      ),
                    // 振替休日。★差し戻しのすぐ下（どちらも「自分が動く番」の行）。
                    //   帯と数字の色は差し戻しと同じ statusWarning のまま
                    //   （この節の色は状態の語彙で、振替に新しい色を作らない）。
                    //   0件なら行ごと出さない（差し戻しと同じ＝無いものは見せない）。
                    if (widget.substituteCount > 0)
                      _AttentionRow(
                        accent: FieldTokens.statusWarning,
                        label:  '振替休日',
                        count:  widget.substituteCount,
                        countTruncated: widget.substituteTruncated,
                        onTap:  widget.onOpenSubstitutes,
                      ),
                    // 今日が同意待ちの振替の休む日（便F13・見本 v1 の P1）。★振替休日の行の直後・
                    //   承認待ちの行の前（振替休日の行が出ない回も同じ位置）。要対応の行は今までどおり。
                    //   →再（2026-09-30・便F13続）: 下に次の行が続く回だけ枠の下に間を入れる（枠の★）。
                    if (_pendingSubstituteRestDayId != null)
                      _PendingSubstituteBox(
                        onOpen: () => _openPendingSubstitute(
                            _pendingSubstituteRestDayId!),
                        rowFollows: widget.pendingApprovalCount > 0,
                        canAgree: _pendingSubstituteCanAgree,
                        cannotAgreeReason: _pendingSubstituteCannotAgreeReason,
                      ),
                    if (widget.pendingApprovalCount > 0)
                      _AttentionRow(
                        accent: FieldTokens.accent,           // 承認待ち = accent系
                        label:  '承認待ち',
                        count:  widget.pendingApprovalCount,
                        onTap:  widget.onOpenPendingApprovals,
                      ),
                    const SizedBox(height: 28),
                    // 状態表示
                    _StatusSection(
                      isActual:      isActual,
                      punchedIn:     _punchedIn,
                      punchedOut:    _punchedOut,
                      record:        _record,
                      breakLabel:    _breakLabel(),
                      // みなしモードの表示に使う値。WorkModeService の取得ロジックは
                      // 一切変えず、既に _settings が持っている値を下ろすだけ。
                      deemedStart:   _settings.deemedStart,
                      deemedEnd:     _settings.deemedEnd,
                      breakMinutes:  _settings.breakMinutes,
                    ),
                    // (51)（便BN・【Q157】＝１・見本 claude/field_punch_read_failed_mock_v1.html・下調べの (R3)(R4)(R8)(R9)）: 実勤務で打刻の状態を
                    //   読めなかった時だけ、状態の下に※（押すと読み直す・読む間は「取得中...」）。上下は 8 と 12（※が無い時は今の 28）。
                    if (isActual && _punchReadFailed) ...[
                      const SizedBox(height: 8),
                      _RereadNote(
                        text: _rowReading
                            ? kRereadingText
                            : (_shownRow == null ? kPunchReadFailedResetNote : kPunchReadFailedKeptNote),
                        onTap: _onRereadTap,
                      ),
                      const SizedBox(height: 12),
                    ] else
                      const SizedBox(height: 28),
                    // 勤務区分（日勤/夜勤・1タップ）＋ 送信される業務日
                    // N2: 旧 K4 の表示条件 `if (!isActual || !_punchedIn)` を撤去し無条件表示へ戻す。
                    //   打刻済みシフトの記録は切替で変わらない＝状態はシフト別に独立管理されている:
                    //     ・勤怠行  … (person, work_date, shift_type) で1行（BE の UNIQUE）。
                    //                 この画面が見る行も fetchToday(shiftType:) でシフト指定。
                    //     ・報告済み … report_done_day / report_done_night の2キー
                    //                 （home_screen.dart の reportDoneKey）。
                    //   よって切替は「見るシフトを変える」だけで、既に打刻した側の記録には触れない。
                    //   値の真実源も onChanged 先も親のまま＝_shiftType 機構は1文字も変えていない
                    //   （onShiftTypeChanged → _saveShiftType + _reevaluateReportDone）。
                    _ShiftTypeSelector(
                      selected: widget.shiftType,
                      businessDate: businessDateForShift(
                          widget.shiftType, businessNow()),
                      onChanged: widget.onShiftTypeChanged,
                      readFailed: widget.shiftReadFailed,
                    ),
                  ],
                ),
              ),
            ),
            // ── 操作エリア（親指ゾーン・固定） ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildOperationArea(isActual),
                  // (54)（便BN・【Q159】＝１・見本 claude/field_unread_unwritten_mock_v1.html・下調べの (S4)(S5)）: 本日休みの状態を読めなかった
                  //   時だけ、下のボタンの下に※（どの姿でも・押すと読み直す・読む間は「取得中...」・上は 6）。ボタンは止めない。
                  if (_restReadFailed) ...[
                    const SizedBox(height: 6),
                    _RereadNote(
                      text: _restReading ? kRereadingText : kRestReadFailedNote,
                      onTap: _onRereadTap,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 操作エリアの組み立て ─────────────────────────────────────────────
  // 「本日休み」ボタンの表示条件は従来の式のまま（`!isActual || !_punchedIn`）:
  //   ・みなしモード(!isActual): 表示（横2分割の右側）
  //   ・実打刻モード(isActual): 未出勤(!_punchedIn)のみ表示。
  //     出勤中・退勤済(=_punchedIn)は非表示（働いた日に休み登録は矛盾）。
  //   ※ _punchedIn は _PunchScreenState の状態。出勤中判定 `_punchedIn && !_punchedOut`
  //     と同じ状態変数を参照（判定式は複製しない）。
  //
  // N1: 実打刻の下部はスライダーを廃し「2択の横並び」に統一する（高さ52・gap 8）:
  //   未出勤 … ［出勤=生成り主］［本日休み=二次］
  //   出勤中 … ［退勤=生成り主］［現場移動=エメラルド枠 二次］
  //   退勤済 … ［日報を報告］1本（従来のまま・N5でボタン文言も据え置き）
  //
  // N7: 「⏰ 追加の申告」を下段へ増設する（完了ビュー側の同ボタンは不変・こちらは増設のみ）。
  //   出すのは「1日が終わっている」2状態だけ（原則⑤＝満たさない条件は行ごと出さない）:
  //     ・実打刻・退勤済     … _punchedIn && _punchedOut
  //     ・みなし・締め済み   … !isActual && widget.todayClosed
  //   未出勤・出勤中・みなし未締め では出さない（まだ主行動が残っている＝申告は完了後の行為）。
  Widget _buildOperationArea(bool isActual) {
    final showRestDay = !isActual || !_punchedIn;

    // N7: 増設ボタンの表示条件。判定式はこの1本だけ（下の2分岐が同じ変数を読む）。
    final showExtraDeclaration = isActual
        ? (_punchedIn && _punchedOut)   // 実打刻: 退勤済
        : widget.todayClosed;           // みなし: 締め済み

    // N8: 報告が済んでいる日は「日報を報告」を出さない（1日の主行動が終わっているため）。
    //   ★未報告なら日報は絶対必須なので必ず出す＝隠すのは reportDone のときだけ。
    //   報告済みの真実は親(JsMainShell)の _todayReportDone。既存 props の
    //   isReportDone 経由で受ける（home_screen.dart の `isReportDone: () => _todayReportDone`）。
    //   その中身は home_screen.dart の `_isReportDoneStatus(s) => s == 'done' || s == 'closed'`
    //   ＝送信済み or みなしの締め。判定式はこの画面に複製しない。
    //   ★このコールバックは build 中にも読む。_todayReportDone の書き換えは全て親の setState
    //     経由（home_screen.dart の _todayReportDone を書く全ての setState）なので、値が変われば
    //     親が rebuild し、ここも読み直される。
    //   →再（2026-10-21・便BN・下調べの (D1)(D5)）: _todayReportDone は読み口になった（写しの勤務の種類と業務日が今の物の時だけ
    //     立つ・写しを書くのは親の _setMark と _clearMark＝setState の中）。業務日が替わった時は、業務日の切り替わりの時計と
    //     戻った時が親を描き直す＝ここも読み直される。
    final reportDone = widget.isReportDone?.call() == true;

    // 「日報を報告」を隠す条件。対象は裁定どおり
    //   「実打刻・退勤済」と「みなし・締め後」の2分岐だけ＝showExtraDeclaration と同一の範囲。
    //   ★みなし・未締め（showExtraDeclaration=false）では報告済みでも隠さない。
    //     そこは2件目作成の唯一の入口（N5: 押すと親が2件目確認→_resetForNextReport）なので、
    //     消すと2件目が作れなくなる。
    final hideReportButton = showExtraDeclaration && reportDone;

    // 増設ボタン本体（二次様式＝暗枠1px・textSupport系。高さは2択行と同じ 52）＋直下の注記。
    // 押下先は親の既存ハンドラをそのまま呼ぶだけ（判定も実処理もここには作らない）。
    // ★ボタンと注記を1ブロックにまとめる: 下の2分岐はどちらも showExtraDeclaration で
    //   ゲート済みなので、これを置くだけで「ボタンが出る時だけ注記も出る」が構造的に成立する
    //   ＝注記のための新しい表示判定は作らない。
    final extraBlock = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SecondaryOutlineButton(
          label:     '⏰ 追加の申告',
          icon:      Icons.more_time,
          color:     FieldTokens.textSupport,
          onPressed: widget.onExtraDeclaration == null
              ? null
              : () => widget.onExtraDeclaration!(),
        ),
        const SizedBox(height: 4),
        // 何を申告できるのかをボタンの直下で言う。スタイルは同一ファイル内の既存注記
        //   （「業務日 …」補足行と同じ FieldTokens.textSupport / fontSize 11）を流用。
        //   新しい色・独自トークンは定義しない。
        const Text(
          '※残業や休憩の短縮を、あとから申告できます',
          textAlign: TextAlign.center,
          style: TextStyle(color: FieldTokens.textSupport, fontSize: 11),
        ),
      ],
    );

    final restBtn = _RestDayButton(
      rested:    _rested,
      reason:    _restReason,
      portion:   _restPortion,
      loading:   _restLoading,
      onChanged: _loadRestStatus,
      // K5(Q9): 遷移前のガード（みなし∧報告済みのときだけ確認を挟む）。
      preTapGuard: _restDayGuard,
      // 横並びの相方と高さを揃える（みなし=56 / 実打刻=52＝N1の2択行）
      height:    isActual ? _kOpButtonHeight : 56,
    );

    // みなしモード（案Z）: 下部は横2分割［日報を報告=主］［本日休み=二次］
    // N7: 締め済みのときだけ、その下に「⏰ 追加の申告」を縦積み（gap 8）。
    // N8: 締め後かつ報告済み（hideReportButton）なら［日報を報告］を落とし［本日休み］だけ残す。
    //   ★showRestDay は `!isActual || !_punchedIn` なので、この分岐では常に true
    //     ＝日報を落としても行が空にならない。
    if (!isActual) {
      final deemedRow = Row(
        children: [
          if (!hideReportButton) ...[
            Expanded(child: _ReportOutlineButton(onPressed: _onReportTap)),
            if (showRestDay) const SizedBox(width: 10),
          ],
          if (showRestDay) Expanded(child: restBtn),
        ],
      );
      if (!showExtraDeclaration) return deemedRow;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          deemedRow,
          const SizedBox(height: 8),
          extraBlock,
        ],
      );
    }

    // 実打刻・退勤済: 1日の勤務が終わっている＝主行動は日報だけ（全幅1本・文言も従来のまま）
    // N7: その下に「⏰ 追加の申告」を縦積み（gap 8）。
    // N8: 報告済みなら［日報を報告］は出さず［⏰ 追加の申告］だけにする。
    //   未報告のときは従来どおり［日報を報告］を出す（日報は絶対必須）。
    if (_punchedIn && _punchedOut) {
      // この分岐では showExtraDeclaration は必ず true（条件式が同一）なので、
      // hideReportButton == reportDone。申告ブロックは必ず残る＝袋小路にならない。
      if (hideReportButton) return extraBlock;
      final reportBtn = _ReportOutlineButton(onPressed: _onReportTap);
      if (!showExtraDeclaration) return reportBtn;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          reportBtn,
          const SizedBox(height: 8),
          extraBlock,
        ],
      );
    }

    // 実打刻・未出勤 / 出勤中: 2択の横並び
    final isCheckin = !_punchedIn;
    return Row(
      children: [
        Expanded(
          child: _PunchPrimaryButton(
            label: isCheckin ? '出勤' : '退勤',
            icon:  isCheckin ? Icons.login : Icons.logout,
            busy:  _busy,
            // タップ＝即打刻ではない。必ず時刻確認ダイアログを挟む（_confirmPunch）。
            onPressed: () => _confirmPunch(isCheckin ? 'in' : 'out'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: isCheckin
              // 未出勤の右側＝本日休み（showRestDay は isActual∧!_punchedIn で常に true）
              ? restBtn
              // 出勤中の右側＝現場移動（エメラルド枠の二次。確認ダイアログは温存）
              : _SecondaryOutlineButton(
                  label:     '現場移動',
                  color:     FieldTokens.accent,
                  onPressed: _busy ? null : _onMoveToNextSiteTap,
                ),
        ),
      ],
    );
  }
}

// N1: 実打刻の2択行の高さ（モック承認済）。相方の「本日休み」もこの値に揃える。
const double _kOpButtonHeight = 52;

/// 勤務の種類を読み込めなかった時の※（便BK・見本 claude/field_report_fix_mock_v3.html の ⑰①）。
const String kShiftReadFailedNote = '※勤務区分を読み込めませんでした。日勤で表示しています。';

// ── 便BN の字（見本 claude/field_punch_read_failed_mock_v1.html・claude/field_unread_unwritten_mock_v1.html・【Q157】【Q159】【Q161】＝１）──
/// 打刻の状態を読めなかった時の※（実勤務の時だけ・状態の下）。出している状態が今の行（勤務区分と業務日）の物の時。
const String kPunchReadFailedKeptNote =
    '※最新の打刻状態を確認できませんでした。前に読めた状態で表示しています（タップで再取得）';
/// 同じ※の、今の行の状態を出していない時（未出勤の姿にした時）。
const String kPunchReadFailedResetNote =
    '※最新の打刻状態を確認できませんでした。未出勤で表示しています（タップで再取得）';
/// 本日休みの状態を読めなかった時の※（どの姿でも・下のボタンの下）。
const String kRestReadFailedNote = '※本日休みの登録状況を確認できませんでした（タップで再取得）';
/// 開いた時に勤務の設定を一度も読めない時の字（回る印の所・(お)）。
const String kSettingsReadFailedText = '勤務の設定を読み込めませんでした（タップで再取得）';
/// 読み直す間の字（上の3つの※と (お) の字・前例＝home_screen.dart の _GpsBar の「取得中...」）。
const String kRereadingText = '取得中...';
/// 打刻の既定の知らせ（サーバの理由の字が無い時・打つ所が投げた時・締めの窓から打てる画面が無い時）。
const String kPunchErrorText = 'エラーが発生しました';
/// 打ってサーバに断られた時に、打刻の行を読み直す符号（便BN・下調べの (R6)＝すでに出勤・すでに退勤・出勤の打刻が無い）。
///   ★サーバの符号の字（routes/attendance.js の POST /punch の 409・400）。ほかの断りでは読み直さない。
const Set<String?> kPunchRefusalRereadCodes = {
  'ALREADY_PUNCHED_IN',
  'ALREADY_PUNCHED_OUT',
  'NO_PUNCH_IN',
};

/// 締めの窓の退勤の口（PunchScreen.onPunchOutHandlerReady）が、呼んだ時に返す種類（便BN・下調べの (Z1)・見つけた事 (50)）。
enum PunchOutStartKind {
  /// 打刻か打刻の行の読み直しの最中（_busy）で、打たなかった。
  busy,

  /// 打ち始めた（done で打ち終わりを待てる＝true は打てた・false は取れなかった＝理由の知らせは打刻の画面が出した）。
  started,

  /// 打刻の画面が無かった（取れなかった時と同じに扱う＝知らせは呼び手が kPunchErrorText で出す）。
  absent,
}

/// 締めの窓の退勤の口の答え（done は started の時だけ在る）。
typedef PunchOutStart = ({PunchOutStartKind kind, Future<bool>? done});

// ── _RereadNote（便BN）──────────────────────────────────────────────
// 読めなかった時の※と (お) の字（押すと読み直す）。押せる高さ 44 以上・中寄せ・statusWarning（見本の .note＝11.5・.tapfail＝14）。
//   前例＝home_screen.dart の _GpsBar の押す所（GestureDetector・HitTestBehavior.opaque）。
class _RereadNote extends StatelessWidget {
  const _RereadNote({
    required this.text,
    required this.onTap,
    this.fontSize = 11.5,
    this.padding = EdgeInsets.zero,
  });
  final String text;
  final VoidCallback onTap;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: double.infinity),
        child: Padding(
          padding: padding,
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: FieldTokens.statusWarning, fontSize: fontSize),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ⓪ 勤務区分 2択（日勤 / 夜勤）＋ 業務日表示
//   タッチターゲット 44pt以上・選択=ゴールド / 非選択=沈み
//   （home_screen.dart から移設・見た目は変更なし）
// ─────────────────────────────────────────────
class _ShiftTypeSelector extends StatelessWidget {
  const _ShiftTypeSelector({
    required this.selected,
    required this.businessDate,
    required this.onChanged,
    this.readFailed = false,
  });
  final String selected;        // 'day'|'night'
  final String businessDate;    // 送信される report_date（'YYYY-MM-DD'）
  final ValueChanged<String> onChanged;
  final bool readFailed;        // 勤務の種類を読み込めなかったか（便BK・⑰①）

  @override
  Widget build(BuildContext context) {
    Widget chip(String type, String label, IconData icon) {
      final sel = selected == type;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 46,                       // タッチターゲット 44pt以上
            decoration: BoxDecoration(
              color: sel
                  ? FieldTokens.accent.withValues(alpha: 0.15)
                  : FieldTokens.surfaceCard,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(
                color: sel ? FieldTokens.accent : FieldTokens.outline,
                width: sel ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16,
                    color: sel ? FieldTokens.accent : FieldTokens.textSupport),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: sel ? FieldTokens.accent : FieldTokens.textSupport,
                    fontSize: 14,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          chip('day',   '日勤', Icons.wb_sunny_outlined),
          const SizedBox(width: 8),
          chip('night', '夜勤', Icons.nightlight_outlined),
        ]),
        const SizedBox(height: 4),
        Text(
          '業務日 $businessDate',
          textAlign: TextAlign.center,
          style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11),
        ),
        // 勤務の種類を読み込めなかった時だけ（便BK・見本 v3 の ⑰①＝その場で夜勤に切り替えられる）。
        //   大きさは見本 v3 の※（.note＝11.5）・色は意味の色（statusWarning）。
        if (readFailed) ...[
          const SizedBox(height: 2),
          const Text(
            kShiftReadFailedNote,
            textAlign: TextAlign.center,
            style: TextStyle(color: FieldTokens.statusWarning, fontSize: 11.5),
          ),
        ],
        // 夜勤を選んでいるときだけ、業務日の切替時刻を注記する。
        //   判定は上の chip と同じ形（selected == 'night'）＝新しい判定は作らない。
        //   ★表示だけ。業務日の算出（businessDateForShift）には一切触れていない。
        //   スタイルは直上の補足行をそのまま流用（FieldTokens.textSupport / fontSize 11）＝
        //   新しい色・独自トークンは定義しない。
        if (selected == 'night') ...[
          const SizedBox(height: 2),
          const Text(
            '※夜勤は正午が切替（午前中は前夜分を表示）',
            textAlign: TextAlign.center,
            style: TextStyle(color: FieldTokens.textSupport, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

// ── _ModePill ─────────────────────────────────────────────────────────────────
class _ModePill extends StatelessWidget {
  const _ModePill({required this.isActual});
  final bool isActual;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isActual ? _accent.withValues(alpha: 0.15) : _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActual ? _accent : _border),
      ),
      child: Text(
        isActual ? '実勤務モード' : 'みなし',
        style: TextStyle(
          color: isActual ? _accent : _label,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── _StatusSection ────────────────────────────────────────────────────────────
class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.isActual,
    required this.punchedIn,
    required this.punchedOut,
    required this.record,
    required this.breakLabel,
    required this.deemedStart,
    required this.deemedEnd,
    required this.breakMinutes,
  });

  final bool isActual;
  final bool punchedIn;
  final bool punchedOut;
  final Map<String, dynamic>? record;
  final String breakLabel;
  // みなし表示用。WorkModeSettings(work_mode_service.dart) の値をそのまま受け取る。
  final String deemedStart;   // BE の生値 'HH:MM:SS'（表示は _fmtTime で整形）
  final String deemedEnd;     // 同上
  final int    breakMinutes;

  @override
  Widget build(BuildContext context) {
    if (!isActual) {
      // みなしモード（案Z）: 時刻が主役（28px・中央）。
      return _ClockBlock(
        label:    'みなし勤務',
        time:     '${_fmtTime(deemedStart)} − ${_fmtTime(deemedEnd)}',
        timeSize: 28,
        support: Text(
          '休憩 $breakMinutes分　実際の勤務に応じて修正されます',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _label, fontSize: 12),
        ),
      );
    }

    if (!punchedIn) {
      return const SizedBox(
        width: double.infinity,
        child: Text(
          '今日はまだ出勤していません',
          textAlign: TextAlign.center,
          style: TextStyle(color: _label, fontSize: 14),
        ),
      );
    }

    final punchInIso  = record?['punch_in']  as String?;
    final punchOutIso = record?['punch_out'] as String?;

    if (punchedOut) {
      return _ClockBlock(
        label:    '本日終了',
        time:     '${_hhmm(punchInIso)} − ${_hhmm(punchOutIso)}',
        timeSize: 34,
        support: _SupportLine(children: [
          _BreakInfoRow(label: breakLabel),
        ]),
      );
    }

    // 出勤中
    return _ClockBlock(
      label:    '出勤中',
      time:     '${_hhmm(punchInIso)} −',
      timeSize: 34,
      support: _SupportLine(children: [
        _InfoRow(label: '経過', value: _elapsed(punchInIso)),
        _BreakInfoRow(label: breakLabel),
      ]),
    );
  }
}

// ── _ClockBlock ───────────────────────────────────────────────────────────────
// 「ラベル（小・字間広め）＋ 時刻（最大の文字・中央）＋ 補助行」の共通の型。
// 色は意味だけに使う原則により、時刻は本文色(_text)固定＝状態はラベルで示す。
class _ClockBlock extends StatelessWidget {
  const _ClockBlock({
    required this.label,
    required this.time,
    required this.timeSize,
    this.support,
  });
  final String label;
  final String time;
  final double timeSize;
  final Widget? support;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _label,
              fontSize: 10,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            time,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _text,
              fontSize: timeSize,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.5,
              height: 1.1,
            ),
          ),
          if (support != null) ...[
            const SizedBox(height: 12),
            support!,
          ],
        ],
      ),
    );
  }
}

// ── _SupportLine ──────────────────────────────────────────────────────────────
// 時刻の下の補助行。Wrap なので長い休憩ラベルでも溢れず折り返す。
class _SupportLine extends StatelessWidget {
  const _SupportLine({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: children,
      );
}

// ── _PendingSubstituteBox ─────────────────────────────────────────────────────
// 今日が事務から持ちかけられた振替休日の休む日で、まだ同意していないときの枠（便F13・見本 v1 の P1）。
//   ★形: 線は待ちの色の1・左だけ待ちの色の3・角丸8・中は surfaceCard・中の余白は上下11×左右12・
//     中の並びの間8。札「同意待ち」（待ちの色の枠1・待ちの色の字11.5・角は丸いきり・余白は上下3×左右10・
//     左に寄せる）・文2つ・［振替休日を開く］（形は substitute_detail_screen.dart の SubstituteOpenButton
//     ただ1本・左に寄せる）。
//   ★待ちの色は substitute_list_screen.dart の kSubstituteWaitColor ただ1本（【Q112】＝２・橙）。
//   ★文は見本 v1 の P1 のまま（一字一句）。
//   ★間（元は上だけ 8・下は無し）。→再（2026-09-30・便F13続）: 見本 v1 の P1（.screen{gap:14px}）に合わせ、
//     上は 14。下は、枠の後ろに要対応の行が続く回（rowFollows）だけ 14（続かない回は、要対応の塊の
//     後ろの SizedBox 28 のまま足さない）。下を無しにしていたため、続く行が枠の下の線に付いていた。
//   ★（元）文2つ（1行目と「同意すると、今日は休みになります。」）。
//     →再（2026-10-01・便F14・見本 substitute_cannot_agree_mock_v1 の P1）: ご本人がこの振替に同意できない回
//     （canAgree が false＝BE の pending_substitute_can_agree が false）は、2行目の代わりに
//     「同意できません：{理由}」（頭の語は substitute_detail_screen.dart の kCannotAgreeHead・組み方は
//     lib/widgets/deny_reason_line.dart の denyReasonText・理由は BE の文をそのまま）と
//     「休むときは、事務へご連絡ください。」の2行。どちらも今の2行目と同じ色と大きさ・2行の間は 0・
//     1行目との間と［振替休日を開く］との間は今の 8。札・枠・1行目・ボタン・枠の上下の間は今のまま。
//     同意できる回（true・キーなし）は今のまま。
class _PendingSubstituteBox extends StatelessWidget {
  const _PendingSubstituteBox({
    required this.onOpen,
    required this.rowFollows,
    this.canAgree = true,
    this.cannotAgreeReason,
  });
  final VoidCallback onOpen;
  final bool rowFollows;
  final bool canAgree;
  final String? cannotAgreeReason;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 14, bottom: rowFollows ? 14 : 0),
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          top: BorderSide(color: kSubstituteWaitColor),
          right: BorderSide(color: kSubstituteWaitColor),
          bottom: BorderSide(color: kSubstituteWaitColor),
          left: BorderSide(color: kSubstituteWaitColor, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kSubstituteWaitColor),
            ),
            child: const Text('同意待ち',
                style: TextStyle(color: kSubstituteWaitColor, fontSize: 11.5)),
          ),
          const SizedBox(height: 8),
          const Text('今日は、事務から持ちかけられた振替休日の休む日です。',
              style: TextStyle(color: _text, fontSize: 13)),
          const SizedBox(height: 8),
          if (canAgree)
            const Text('同意すると、今日は休みになります。',
                style: TextStyle(color: _label, fontSize: 12))
          else ...[
            Text(denyReasonText(kCannotAgreeHead, cannotAgreeReason),
                style: const TextStyle(color: _label, fontSize: 12)),
            const Text('休むときは、事務へご連絡ください。',
                style: TextStyle(color: _label, fontSize: 12)),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SubstituteOpenButton(onPressed: onOpen),
          ),
        ],
      ),
    );
  }
}

// ── _AttentionRow ─────────────────────────────────────────────────────────────
// 要対応の1行。左に2pxの縦線・右に件数＋「›」。箱で囲まず、下は1pxの線で区切る。
// ★件数が0のときは呼び出し側で行ごと描画しない（punch_screen.dart の build を参照）。
//   →再（2026-10-19・便BM）: 「未送信日報」の行は、数を countLabel（数と単位に分けた字・数が無い時は「件数不明」）で渡し、
//   count は null を渡す（行を出すかは呼び手の pendingReportsCount が null かで決める）。今までの3本（差し戻し・振替休日・
//   承認待ち）は count を渡す（今までどおり）。
//   count は required のまま int?（既定の 0＝数の実体の無い値を置かない・渡し忘れは型が止める）。
//   count と countLabel の両方が null の時は assert で止める（数も字も無い行を作らせない＝そのまま描くと「null件」になる）。
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.accent,
    required this.label,
    required this.count,
    required this.onTap,
    this.countTruncated = false,
    this.countLabel,
  }) : assert(count != null || countLabel != null);
  final Color accent;       // 意味の色（差し戻し=warning / 承認待ち=accent）
  final String label;
  final int? count;         // 数（今までの3本）。null＝数は countLabel で渡す（未送信日報の行だけ）
  // 天井で切れた回だけ true。★数の後ろに + を付けるためだけの純追加で、
  //   既定 false ＝今までの呼び手（差し戻し・承認待ち）の見え方は1ピクセルも変わらない。
  final bool countTruncated;
  // 数の字を、数と単位に分けた字で渡す時（便BM・「未送信日報」の行だけ）。渡すと count と countTruncated は使わない。
  //   数が在れば 数（20）＋単位（11）・数が無い時（件数不明）は1つの字（13・w600・本文の色＝見本の形）。
  //   既定 null ＝今までの呼び手の見え方は1ピクセルも変わらない。
  final PendingCountLabel? countLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Container(width: 2, height: 28, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: _label, fontSize: 13),
                ),
              ),
              // 数字が主役: 件数20px / 単位11px
              if (countLabel != null && countLabel!.number == null)
                Text(countLabel!.unit,
                    style: const TextStyle(
                        color: _text, fontSize: 13, fontWeight: FontWeight.w600))
              else ...[
                Text(
                  countLabel?.number ?? (countTruncated ? '$count+' : '$count'),
                  style: const TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
                Text(countLabel?.unit ?? '件',
                    style: const TextStyle(color: _label, fontSize: 11)),
              ],
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: _label, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // 補助行(_SupportLine=Wrap)の子になるため mainAxisSize は min 固定。
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label  ', style: const TextStyle(color: _label, fontSize: 12)),
      Text(value,
          style: const TextStyle(
            color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _BreakInfoRow extends StatelessWidget {
  const _BreakInfoRow({required this.label});
  final String   label;

  @override
  Widget build(BuildContext context) {
    // 補助行(_SupportLine=Wrap)の子になるため Expanded をやめ mainAxisSize は min 固定。
    // ★label（値）の取得元は変えていない: 親から渡る _breakLabel() のまま。
    // ★「変更」タップ導線は退役（ボス裁定）。休憩の申告は退勤後の報告フロー
    //   （home_screen.dart の「追加の申告」＝休憩の短縮）に一本化した。
    //   ここは表示専用＝タップできる要素を持たない。
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: const TextStyle(
            color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
    ]);
  }
}

// ── _PunchPrimaryButton ───────────────────────────────────────────────────────
// N1: 出勤／退勤の主ボタン（旧スライド確定UIの置き換え）。
//   生成り枠1.5px＋同色文字＝_ReportOutlineButton と同一の「主」様式に揃える
//   （トークンは FieldTokens.textBody。塗り面は作らない）。
//   高さ 52（_kOpButtonHeight）。busy 中は押下不可＋インジケータ。
//   ★このボタンは打刻しない。押下先は必ず確認ダイアログ（_confirmPunch）を経由する。
class _PunchPrimaryButton extends StatelessWidget {
  const _PunchPrimaryButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: _kOpButtonHeight,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: FieldTokens.textBody,
          disabledForegroundColor: FieldTokens.textFaint,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? FieldTokens.textFaint
                    : FieldTokens.textBody,
                width: 1.5,
              )),
        ),
        child: busy
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: FieldTokens.textFaint, strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
      ),
    );
  }
}

// ── _SecondaryOutlineButton ───────────────────────────────────────────────────
// N1: 2択行の右側に置く二次ボタン（枠1px＋同色文字・塗りなし）。
//   色は呼び出し側が意味で決める（出勤中の「現場移動」= FieldTokens.accent＝エメラルド）。
// N7: 任意の先頭アイコンを追加（既定 null＝従来の描画は1ピクセルも変わらない）。
//   「⏰ 追加の申告」だけが icon: Icons.more_time / color: FieldTokens.textSupport（暗枠）を渡す。
class _SecondaryOutlineButton extends StatelessWidget {
  const _SecondaryOutlineButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final IconData? icon;   // null＝アイコンなし（現場移動＝従来どおり文字のみ）

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: _kOpButtonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: FieldTokens.textFaint,
          side: BorderSide(color: color),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _ReportOutlineButton ──────────────────────────────────────────────────────
// 生成り抜きの主ボタン（accent 塗りではなく枠1.5px）。
// 押下先は呼び出し側から渡る単一のゲート _onReportTap のみ。
// 文言は '日報を報告' 固定。N1 で '現場移動' は _SecondaryOutlineButton（エメラルド枠の
// 二次様式）へ移ったため、可変 label は呼び手が居なくなり撤去した。
// 呼び手はみなしの主ボタンと実打刻・退勤済の主ボタンの2箇所（どちらも表示は不変）。
class _ReportOutlineButton extends StatelessWidget {
  const _ReportOutlineButton({required this.onPressed});
  final VoidCallback? onPressed;
  static const String label = '日報を報告';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: FieldTokens.textBody,
          disabledForegroundColor: FieldTokens.textFaint,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? FieldTokens.textFaint
                    : FieldTokens.textBody,
                width: 1.5,
              )),
        ),
        child: const Text(
          label,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ── _RestDayButton ────────────────────────────────────────────────────────────
// 「本日休み」ボタン（表示は親から受け取る props 駆動）。状態(rested/reason)は
// 親 _PunchScreenState が単一の真実源として保持し、日報報告ゲートと共有する。
//   rested=true → 「本日休み 登録済み」＋タップでねぎらい画面
//   rested=false（or 照会失敗=fail-open）→ 「本日休み」＋タップで休み登録画面
//   （→再（2026-10-21・便BN・(54)）: 照会失敗の時は、同じ日に前に読めた値のまま（無い時は fail-open）。読めなかった事は親の※が出す）
// 序列は日報報告より下（OutlinedButton・textSupport系の控えめ配色）。
class _RestDayButton extends StatelessWidget {
  const _RestDayButton({
    required this.rested,
    required this.reason,
    required this.portion,
    required this.loading,
    required this.onChanged,
    this.preTapGuard,
    this.height = 48,
  });

  final bool rested;
  final String? reason;
  final String portion; // full / am_half / pm_half
  final bool loading;
  final Future<void> Function() onChanged; // 遷移から戻った後に親が状態を取り直す
  // 遷移前のガード。false を返したら遷移しない（判定と文言は親が持つ）。null=素通し。
  final Future<bool> Function()? preTapGuard;
  final double height; // みなしは日報ボタンと横並びになるため呼び出し側で高さを揃える

  // 登録済みボタン文言。半休は「午前休/午後休」を明示。
  String get _label {
    if (!rested) return '本日休み';
    switch (portion) {
      case 'am_half': return '本日午前休 登録済み';
      case 'pm_half': return '本日午後休 登録済み';
      default:        return '本日休み 登録済み';
    }
  }

  Future<void> _onTap(BuildContext context) async {
    if (preTapGuard != null && !await preTapGuard!()) return;
    if (!context.mounted) return;
    if (rested) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RestDayDoneScreen(reason: reason, portion: portion)));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const RestDayScreen()));
    }
    await onChanged(); // 戻ったら状態を取り直す（親が mounted を判定）
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(
        // 暗枠1px・textSupport系（日報＝生成り枠より一段下の序列）
        onPressed: loading ? null : () => _onTap(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: FieldTokens.textSupport,
          side: const BorderSide(color: FieldTokens.textSupport),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          _label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }
}
