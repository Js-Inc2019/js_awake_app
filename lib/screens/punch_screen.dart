// lib/screens/punch_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show fetchGpsAddress, showJsSnackbar;
import '../services/work_mode_service.dart';
import '../services/reports_service.dart';
// N1: slide_to_confirm.dart の import は撤去（打刻をボタン+確認ダイアログ化したため）。
//   ウィジェット本体(lib/widgets/slide_to_confirm.dart)は他からの復帰に備えて残す。
import '../core/theme/field_tokens.dart';
import '../utils/business_date.dart';
import 'rest_day_screen.dart';
import 'rest_day_done_screen.dart';

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
//（js-office-api/routes/work_settings.js:27-28。既定値リテラルも '08:00:00'）。
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
    this.revisionCount = 0,
    this.pendingApprovalCount = 0,
    this.onOpenRevisions,
    this.onOpenPendingApprovals,
    this.onPunchStateChanged,
    this.isReportDone,
    this.onBeforeOpenReport,
    this.onBeforeMoveToNextSite,
    this.onPunchOutHandlerReady,
    this.todayClosed = false,
    this.onExtraDeclaration,
  });
  final VoidCallback? onNavigateToReport;
  // ── N7: ホームの「⏰ 追加の申告」（完了ビューの同ボタンとは別の増設・あちらは不変）──
  // 締め済みか。真実源は home_screen の _todayClosed（'closed' を読む _readWorkStatusToday /
  //   _initTodayReportDone / _reevaluateReportDone / _onCloseToday が唯一の書き手）。
  //   ★ここでは判定を作らず受けた真偽だけを見る。
  //   ★素の値で下ろす（bool Function() にしない）: この値は build 中に読むため。
  //     isReportDone(:107) は既存のコールバックのままだが N8 で build 中にも読んでいる。
  //     書き換えが必ず親の setState 経由なので再評価はされる＝動作は正しいが、意図は素の値の方が明快。
  //     親所有かつ build で読む値は shiftType / revisionCount と同じ素の prop に揃える。
  //   ★onPunchStateChanged(:88) には載せない: あちらは子→親（fetchToday で得た値を上げる口）で
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
  //   ★休みゲート(_onReportTap:147) を通過した後にだけ呼ばれる＝ゲートの前後関係は不変。
  final Future<bool> Function()? onBeforeOpenReport;
  // N5: 「現場移動」から日報フォームへ入る直前の親側前処理。
  //   確認は現場移動ダイアログ側で済んでいるため、親は報告済みならリセットするだけ
  //   （home_screen.dart:_prepareMoveToNextSite）。true 固定＝中止経路は持たない。
  final Future<bool> Function()? onBeforeMoveToNextSite;
  // N3: 退勤打刻の実行口を親へ渡す。親（完了ビューの「今日はここまで」）が
  //   打刻ロジックを複製せず既存 _doPunch('out') 経路を呼べるようにするためだけの配線。
  //   initState で1回だけ通知する（値を渡すだけ・親側で setState はしない）。
  final void Function(Future<void> Function() punchOut)? onPunchOutHandlerReady;
  final Widget? weatherPanel;
  // K1: 打刻状態を親(JsMainShell)へ上げる唯一の口。真実源は fetchToday(work_mode_service.dart:205)
  //   ＝この画面が受け取った値をそのまま流すだけで、判定式は親に複製しない。
  //   isActual も同じ便に載せる（完了ビューの出し分けが実打刻/みなしで違うため・_isActual:_設定由来）。
  final void Function(bool isActual, bool punchedIn, bool punchedOut)? onPunchStateChanged;
  // K5(Q9): 当日ぶんの報告が済んでいるか。親が持つ真実を読むだけ
  //   （home_screen:1516 `isDone: () => _todayReportDone` と同じ流儀。prefs 直読みはしない）。
  final bool Function()? isReportDone;
  // ── 要対応の件数と遷移（値も遷移先も親 JsMainShell の既存資産をそのまま下ろす）──
  //   件数取得・遷移先はこの画面では一切作らない（home_screen.dart:1535-1560 を参照）。
  //   0件のときは行そのものを描画しない＝「無いものは見せない」。
  final int revisionCount;          // 差し戻し（home_screen.dart:382 _revisionCount）
  final int pendingApprovalCount;   // 承認待ち（同 :383・職長のときのみ非0が渡る）
  final VoidCallback? onOpenRevisions;
  final VoidCallback? onOpenPendingApprovals;
  // 勤務区分（日勤/夜勤）は親(JsMainShell)が真実を保持し、値+変更通知を下ろす。
  // 送信時の report_date 補正・shift_type 送出は親側で行う。
  final String shiftType;                       // 'day'|'night'
  final ValueChanged<String> onShiftTypeChanged;
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
  int  _legalBreak6h = 45;
  int  _legalBreak8h = 60;

  // 本日休み状態（_RestDayButton から持ち上げ）。ボタン表示と日報報告ゲートが
  // 単一の状態を共有する（照会失敗は fail-open＝rested=false）。
  final ReportsService _reports = ReportsService();
  bool _restLoading = true;
  bool _rested      = false;
  String? _restReason;
  String _restPortion = 'full'; // full / am_half / pm_half（応答に無ければ full）

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
  }

  Future<void> _loadRestStatus() async {
    final res = await _reports.getRestDayToday();
    if (!mounted) return;
    setState(() {
      _restLoading = false;
      if (res['success'] == true) {
        _rested      = res['rested'] == true;
        _restReason  = res['reason'] as String?;
        _restPortion = (res['portion'] as String?) ?? 'full';
      } else {
        _rested      = false; // fail-open
        _restReason  = null;
        _restPortion = 'full';
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
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
    );
    if (proceed != true) return;

    final res = await _reports.deleteRestDay(); // 既存メソッドを再利用
    if (!mounted) return;
    if (res['success'] == true) {
      await _loadRestStatus();               // ボタン表示も最新化
      if (!mounted) return;
      if (gate != null && !await gate()) return;
      widget.onNavigateToReport?.call();      // 従来の日報報告へ
    } else {
      showJsSnackbar(
        context,
        '${res['error'] ?? '休みの取り消しに失敗しました'}'
        '${res['statusCode'] != null ? '（${res['statusCode']}）' : ''}',
        isError: true,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _init();
  }

  // ── シフト切替時の再取得 ────────────────────────────────────────────────
  // 勤怠行は (person, 業務日, shift_type) で1行。シフトを切り替えると「見るべき行」が
  // 別の行に変わるため、切替後の shift_type で必ず取り直す。
  // ★これが無いと _punchedIn/_punchedOut/_record が切替前シフトの値のまま残り、
  //   BE 上は打刻済みの行に対して出勤ボタンが出る（＝退勤済み行への出勤上書きが起きる）。
  // shiftType は親(JsMainShell)が真実を持ち props で下ろすため、値が変わると
  // didUpdateWidget が呼ばれる（親の setState → PunchScreen の widget 更新）。
  //   発火元: _ShiftTypeSelector(:648) → widget.onShiftTypeChanged
  //          → home_screen.dart:1835-1839 setState(_shiftType) → ここ。
  //   起動時の勤務区分復元（home_screen.dart:_restoreShiftType）で値が変わる場合も同じ経路で通る。
  @override
  void didUpdateWidget(covariant PunchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shiftType != oldWidget.shiftType) _reloadForShiftChange();
  }

  // 再取得そのものは既存の取得経路 _init(:241) をそのまま呼ぶ。
  //   ＝fetchToday(shiftType: widget.shiftType) と、その戻り値を
  //     _record/_punchedIn/_punchedOut へ入れる処理は1箇所のまま（状態のコピーを作らない）。
  //   didUpdateWidget の時点で widget.shiftType は既に切替後の値。
  // 競合防御: 取得が終わるまで既存の _busy を立てる。_busy は打刻の入口
  //   （_confirmPunch:376 / _doPunch:295）と打刻ボタンの disabled(:777,:791) が
  //   既に見ている単一のフラグなので、新しい排他機構は作らない。
  Future<void> _reloadForShiftChange() async {
    if (_busy) return;   // 打刻処理中は触らない（_doPunch が完了時に :318 で取り直す）
    setState(() => _busy = true);
    try {
      await _init();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _init() async {
    final (settings, today) = await (
      WorkModeService.instance.fetchFromServer(),
      // K6: 勤怠行は (person, 業務日, shift_type) で1行。見るシフトを明示する。
      WorkModeService.instance.fetchToday(shiftType: widget.shiftType),
    ).wait;
    if (!mounted) return;
    setState(() {
      _settings = settings;
      if (today != null) {
        _record           = today.record;
        _punchedIn        = today.punchedIn;
        _punchedOut       = today.punchedOut;
        _standardBreakMin = today.standardBreakMin;
        _legalBreak6h     = today.legalBreak6h;
        _legalBreak8h     = today.legalBreak8h;
      }
      _loading = false;
    });
    _notifyPunchState();
    if (_punchedIn && !_punchedOut) _startTimer();
    fetchGpsAddress().then((r) {
      if (mounted) setState(() => _gpsAddress = r.address);
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // N3: 完了ビュー「今日はここまで」から親が呼ぶ退勤の口。
  //   打刻の実処理は既存 _doPunch('out') をそのまま通す（判定式・API呼び出しは複製しない）。
  //   ★allowGoReport:false ＝退勤後の日報フォーム自動起動を抑制する。
  //     呼び元が完了ビュー＝既に報告済みの文脈なので、そこから報告フォームを開き直さない。
  //   ★親は関数参照を保持し続けるため、この画面が破棄された後に呼ばれても
  //     unmounted への setState にならないよう入口で mounted を見る（fail-safe）。
  Future<void> _punchOutForClose() async {
    if (!mounted) return;
    await _doPunch('out', allowGoReport: false);
  }

  // allowGoReport: 既定 true＝従来どおり「退勤成功→_onReportTap で日報へ直行」。
  //   false は N3（完了ビュー経由の退勤）だけが渡す。
  Future<void> _doPunch(String type, {bool allowGoReport = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    // 裁定(b): 退勤スライド確定直後は日報へ直行する（ホームに戻さない）。
    // 遷移先の出し分け（未提出=日報フォーム / 提出済=完了ビュー）は既存資産に委ねる:
    //   _onReportTap(:106) → widget.onNavigateToReport → home_screen:1506 `_setTab(1)`
    //   → home_screen:1760 `if (_todayReportDone) AfterReportBody`（提出済判定は
    //     home_screen:_readReportDone が単一の真実源）。判定式はここに複製しない。
    // _busy 解除後に呼ぶため finally の外へ出す（ゲート内のダイアログ中も操作可）。
    bool goReport = false;
    try {
      final gps    = await fetchGpsAddress();
      final result = await WorkModeService.instance.punch(
        type,
        lat:  gps.lat,
        lng:  gps.lon,
        addr: gps.address,
        shiftType: widget.shiftType,   // S5b: 勤務区分をBEへ送出（夜勤は始業日1行に収まる）
      );
      if (!mounted) return;
      if (result.ok) {
        // 出勤打刻で取れた現在地を端末にも残す（日報フォームの初期表示が読む既存3キーへ）。
        // 新しいキーは作らない。退勤(out)では上書きしない＝現場の記録は出勤時の位置を残す。
        if (type == 'in') await _persistPunchGps(gps);
        final today = await WorkModeService.instance.fetchToday(shiftType: widget.shiftType);
        if (!mounted) return;
        setState(() {
          if (today != null) {
            _record           = today.record;
            _punchedIn        = today.punchedIn;
            _punchedOut       = today.punchedOut;
            _standardBreakMin = today.standardBreakMin;
            _legalBreak6h     = today.legalBreak6h;
            _legalBreak8h     = today.legalBreak8h;
          }
        });
        _notifyPunchState();
        if (_punchedIn && !_punchedOut) {
          _startTimer();
        } else {
          _timer?.cancel();
        }
        // 退勤打刻がサーバに反映された時だけ立てる（出勤時・反映漏れ時は従来どおり）
        goReport = allowGoReport && type == 'out' && _punchedOut;
      } else {
        showJsSnackbar(
          context,
          result.errorMessage ?? 'エラーが発生しました',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (goReport && mounted) await _onReportTap();
  }

  // 出勤打刻時のGPSを端末へ保存する。保存条件は home_screen.dart:_fetchGps(971-982) と同一:
  //   ・lat/lng は非nullのときだけ
  //   ・住所は status=='ok'（住所の構築に成功）のときだけ
  //     ＝'GPS取得失敗' / '位置情報の権限がありません' / 座標フォールバックを住所として焼かない
  //       （キャッシュ焼き付きの停止。理由は home_screen.dart:978-981 のコメントと同じ）。
  // 失敗しても打刻の成立は覆さない（例外は握って握り潰さずログのみ・秘匿値は出さない）。
  Future<void> _persistPunchGps(
      ({String address, double? lat, double? lon, String status}) gps) async {
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
  // スライダー(SlideToConfirm)を廃止した代わりに「押す → 時刻を見て確定」の2段にする。
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
    // 却下された事実がどこにも出なかった（BE: attendanceCalculator.js:83-84 で
    // approved 以外は会社設定/法定値にフォールバックする＝計算からも静かに消える）。
    if (status == 'rejected') {
      return _standardBreakMin != null
          ? '休憩の申告は却下されました（会社設定 $_standardBreakMin分）'
          : '休憩の申告は却下されました';
    }
    if (_standardBreakMin != null)          return '休憩 $_standardBreakMin分（会社設定）';
    return '休憩は労働時間に応じて自動';
  }

  void _openBreakRequestSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BreakRequestSheet(
        record:       _record,
        legalBreak6h: _legalBreak6h,
        legalBreak8h: _legalBreak8h,
        // N6: 申告を当てる勤怠行のシフト。いま画面が見ているシフト（fetchToday:200 と同じ値）。
        shiftType:    widget.shiftType,
        onSubmitted:  _onBreakRequestSubmitted,
      ),
    );
  }

  Future<void> _onBreakRequestSubmitted() async {
    showJsSnackbar(context, '申告しました（承認待ち）');
    final today = await WorkModeService.instance.fetchToday(shiftType: widget.shiftType);
    if (!mounted) return;
    setState(() {
      if (today != null) {
        _record           = today.record;
        _punchedIn        = today.punchedIn;
        _punchedOut       = today.punchedOut;
        _standardBreakMin = today.standardBreakMin;
        _legalBreak6h     = today.legalBreak6h;
        _legalBreak8h     = today.legalBreak8h;
      }
    });
    _notifyPunchState();
  }

  // K5(Q9): 「本日休み」を押した瞬間のガード。
  //   みなしモードで当日ぶんの報告が済んでいる（done / closed）ときだけ確認を挟む。
  //   ・報告済みかどうかは親の真実 widget.isReportDone を読むだけ（prefs 直読み・判定式の複製なし）
  //   ・実打刻は締めが退勤打刻であり、そもそも出勤後は「本日休み」ボタンが出ない
  //     （_buildOperationArea の showRestDay）ため対象外＝true を返して素通しする
  //   ・false を返した場合、_RestDayButton は画面遷移しない（袋小路を作らずその場に留まる）
  Future<bool> _restDayGuard() async {
    if (_isActual) return true;
    if (widget.isReportDone?.call() != true) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        title: const Text('本日は報告済みです',
            style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        content: const Text('本日は既に日報を提出済みです。休みとして登録しますか？',
            style: TextStyle(color: FieldTokens.textBody)),
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
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    final isActual = _settings.mode == WorkModeType.actual;
    final now = DateTime.now();
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
                    if (widget.revisionCount > 0)
                      _AttentionRow(
                        accent: FieldTokens.statusWarning,          // 差し戻し = warning系
                        label:  '差し戻し',
                        count:  widget.revisionCount,
                        onTap:  widget.onOpenRevisions,
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
                      onChangeBreak: _openBreakRequestSheet,
                      // みなしモードの表示に使う値。WorkModeService の取得ロジックは
                      // 一切変えず、既に _settings(:58) が持っている値を下ろすだけ。
                      deemedStart:   _settings.deemedStart,
                      deemedEnd:     _settings.deemedEnd,
                      breakMinutes:  _settings.breakMinutes,
                    ),
                    const SizedBox(height: 28),
                    // 勤務区分（日勤/夜勤・1タップ）＋ 送信される業務日
                    // N2: 旧 K4 の表示条件 `if (!isActual || !_punchedIn)` を撤去し無条件表示へ戻す。
                    //   打刻済みシフトの記録は切替で変わらない＝状態はシフト別に独立管理されている:
                    //     ・勤怠行  … (person, work_date, shift_type) で1行（BE の UNIQUE）。
                    //                 この画面が見る行も fetchToday(shiftType:) でシフト指定（:200,:271）。
                    //     ・報告済み … report_done_day / report_done_night の2キー
                    //                 （home_screen.dart:602 reportDoneKey）。
                    //   よって切替は「見るシフトを変える」だけで、既に打刻した側の記録には触れない。
                    //   値の真実源も onChanged 先も親のまま＝_shiftType 機構は1文字も変えていない
                    //   （onShiftTypeChanged → _saveShiftType + _reevaluateReportDone）。
                    _ShiftTypeSelector(
                      selected: widget.shiftType,
                      businessDate: businessDateForShift(
                          widget.shiftType, DateTime.now()),
                      onChanged: widget.onShiftTypeChanged,
                    ),
                  ],
                ),
              ),
            ),
            // ── 操作エリア（親指ゾーン・固定） ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: _buildOperationArea(isActual),
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
    //   isReportDone(:107) 経由で受ける（home_screen.dart:1817 `isReportDone: () => _todayReportDone`）。
    //   その中身は home_screen.dart:628 `_isReportDoneStatus(s) => s == 'done' || s == 'closed'`
    //   ＝送信済み or みなしの締め。判定式はこの画面に複製しない。
    //   ★このコールバックは build 中にも読む。_todayReportDone の書き換えは全て親の setState
    //     経由（home_screen.dart:641 / 658 / 672 / 692 / 718 / 1598）なので、値が変われば
    //     親が rebuild し、ここも読み直される。
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
        //   （:855 の「業務日 …」補足行と同じ FieldTokens.textSupport / fontSize 11）を流用。
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
    //   ★showRestDay(:717) は `!isActual || !_punchedIn` なので、この分岐では常に true
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
  });
  final String selected;        // 'day'|'night'
  final String businessDate;    // 送信される report_date（'YYYY-MM-DD'）
  final ValueChanged<String> onChanged;

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
        // 夜勤を選んでいるときだけ、業務日の切替時刻を注記する。
        //   判定は上の chip(:803) と同じ形（selected == 'night'）＝新しい判定は作らない。
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
    required this.onChangeBreak,
    required this.deemedStart,
    required this.deemedEnd,
    required this.breakMinutes,
  });

  final bool isActual;
  final bool punchedIn;
  final bool punchedOut;
  final Map<String, dynamic>? record;
  final String breakLabel;
  final VoidCallback onChangeBreak;
  // みなし表示用。WorkModeSettings(work_mode_service.dart:16-18) の値をそのまま受け取る。
  final String deemedStart;   // BE の生値 'HH:MM:SS'（表示は _fmtTime(:29) で整形）
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
          _BreakInfoRow(label: breakLabel, onChange: onChangeBreak),
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
        _BreakInfoRow(label: breakLabel, onChange: onChangeBreak),
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

// ── _AttentionRow ─────────────────────────────────────────────────────────────
// 要対応の1行。左に2pxの縦線・右に件数＋「›」。箱で囲まず、下は1pxの線で区切る。
// ★件数が0のときは呼び出し側で行ごと描画しない（punch_screen.dart の build を参照）。
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.accent,
    required this.label,
    required this.count,
    required this.onTap,
  });
  final Color accent;       // 意味の色（差し戻し=warning / 承認待ち=accent）
  final String label;
  final int count;
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
              Text(
                '$count',
                style: const TextStyle(
                  color: _text,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
              const Text('件',
                  style: TextStyle(color: _label, fontSize: 11)),
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
  const _BreakInfoRow({required this.label, required this.onChange});
  final String   label;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    // 補助行(_SupportLine=Wrap)の子になるため Expanded をやめ mainAxisSize は min 固定。
    // ★label（値）の取得元は変えていない: 親から渡る _breakLabel()(:246-253) のまま。
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: const TextStyle(
            color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onChange,
        child: const Text(
          '変更',
          style: TextStyle(
            color: _accent, fontSize: 12,
            decoration: TextDecoration.underline,
            decorationColor: _accent,
          ),
        ),
      ),
    ]);
  }
}

// ── _PunchPrimaryButton ───────────────────────────────────────────────────────
// N1: 出勤／退勤の主ボタン（旧 SlideToConfirm の置き換え）。
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

// ── _BreakRequestSheet ────────────────────────────────────────────────────────
class _BreakRequestSheet extends StatefulWidget {
  const _BreakRequestSheet({
    required this.record,
    required this.legalBreak6h,
    required this.legalBreak8h,
    required this.shiftType,
    required this.onSubmitted,
  });
  final Map<String, dynamic>? record;
  final int legalBreak6h;
  final int legalBreak8h;
  final String shiftType;   // N6: 'day'|'night'。BE で申告を当てる行の特定に使う
  final Future<void> Function() onSubmitted;

  @override
  State<_BreakRequestSheet> createState() => _BreakRequestSheetState();
}

class _BreakRequestSheetState extends State<_BreakRequestSheet> {
  static const _presets = [0, 30, 45, 60, 90];
  int _selectedMin = 60;
  final _reasonCtrl = TextEditingController();
  bool _submitting  = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  // シート内エラー。理由未入力でボタンを無効化して黙る＝理由の分からない
  // 袋小路になるため、押させてその場で理由を出す方式にした。
  String? _error;

  int? _legalFloor() {
    final punchIn  = widget.record?['punch_in']  as String?;
    final punchOut = widget.record?['punch_out'] as String?;
    if (punchIn == null || punchOut == null) return null;
    final inDt  = DateTime.tryParse(punchIn);
    final outDt = DateTime.tryParse(punchOut);
    if (inDt == null || outDt == null) return null;
    var gross = outDt.difference(inDt).inMinutes;
    if (gross < 0) gross += 1440;
    if (gross > 480) return widget.legalBreak8h;
    if (gross > 360) return widget.legalBreak6h;
    return 0;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = '休憩の理由を入力してください');
      return;   // 送信しない
    }
    setState(() { _error = null; _submitting = true; });
    try {
      final result = await WorkModeService.instance.breakRequest(
        breakMinutes: _selectedMin,
        reason: reason,
        // N6: 同日に日勤/夜勤の2行が並存しうるため、どちらの行への申告かを明示する。
        //   BE は未指定=day 互換（routes/attendance.js POST /break-request）。
        shiftType: widget.shiftType,
      );
      if (!mounted) return;
      if (result.ok) {
        Navigator.of(context).pop();
        await widget.onSubmitted();
      } else {
        showJsSnackbar(
          context,
          result.errorMessage ?? 'エラーが発生しました',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final floor      = _legalFloor();
    final belowLegal = floor != null && floor > 0 && _selectedMin < floor;

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '休憩時間の変更を申告',
            style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          const Text('実休憩', style: TextStyle(color: _label, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((min) {
              final selected = _selectedMin == min;
              return GestureDetector(
                onTap: () => setState(() => _selectedMin = min),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? _accent.withValues(alpha: 0.15) : _card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: selected ? _accent : _border),
                  ),
                  child: Text(
                    '$min 分',
                    style: TextStyle(
                      color: selected ? _accent : _label,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (belowLegal) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.shield_outlined, color: Color(0xFFE05252), size: 14),
              const SizedBox(width: 4),
              Text(
                '⚠️ これは法定休憩($floor分)を下回ります',
                style: const TextStyle(color: Color(0xFFE05252), fontSize: 12),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          const Text('理由（必須）', style: TextStyle(color: _label, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonCtrl,
            maxLines: 3,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            style: const TextStyle(color: _text, fontSize: 14),
            decoration: InputDecoration(
              hintText: '例）現場の都合で休憩を取れなかった',
              hintStyle: TextStyle(color: _label.withValues(alpha: 0.6), fontSize: 13),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accent),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.error_outline, color: Color(0xFFE05252), size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(_error!,
                    style: const TextStyle(color: Color(0xFFE05252), fontSize: 12)),
              ),
            ]),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                disabledBackgroundColor: _border,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(color: _bg, strokeWidth: 2.5),
                    )
                  : const Text(
                      '申告する',
                      style: TextStyle(
                        color: _bg, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

