// ============================================================
// lib/screens/late_report_screen.dart
//   事務の許可が出た過去の1日ぶんの日報を、職人が後から出す画面（便F8b-2・見本 field_late_report_mock_v1 の G・H）。
//
// ★入口は2つ（どちらも尋ねる口が「許可が出ている日」＝ALREADY_PERMITTED と答えた時だけ）:
//   ・カレンダーの箱（lib/widgets/day_request_entry.dart の DayRequestEntry・見本 G1）
//   ・振替の3択の画面（lib/screens/substitute_past_day_screen.dart の WorkDateNoReportScreen・見本 G2）
//   出せるかはサーバに聞いて決める（端末で数えない）。送る口は POST /reports/permitted
//   （lib/services/reports_service.dart の submitPermittedReport）。
//
// ★フォームの段と確認の画面は、今日の日報と同じ部品と値の関数を使う（lib/widgets/report_form_steps.dart・
//   lib/widgets/report_form_parts.dart＝同じ決まりを2通りに書かない）。違うのは:
//   段1に勤務の2択（ReportShiftChoice）を置き、「現在地」の行と健康診断の帯を出さない（どちらも今日の物）／
//   日付・時刻・場所を送らない（permittedReportBodyFor が口の断る鍵を除く）／字は「送信」でなく「提出」。
//
// ★決まり:
//   ・自分の状態だけを持つ。端末の保存に書かない。読むのは user_name・company_name・company_address・
//     default_origin・last_transports・last_car_type と、ProfileService().getHomeAddress() だけ。
//   ・今日の印・保留の箱・前回の値・下書き・目安の覚え書きに触らない。ReportStore と createReport と
//     WorkerNameStore を呼ばない（出せたかは、この画面がサーバの答えで決める＝保留の箱に入れない）。
//   ・この本のコードで時計を読まない（コードに DateTime.now を書かない）。今日の日付を使う所が無い。
//     曜日の字は jpMonthDayDowOf（'YYYY-MM-DD' の字から DateTime.utc で引く＝時計は読まない）。
//   ・サーバの文は言い換えない・切らない。例外の字や本文の頭の字は画面に出さない。
//   ・色は FieldTokens のみ（直書き禁止・新しい色を作らない）。
// ============================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/permitted_report_labels.dart' show permittedReportMarkOrNull;
import '../core/report_send_texts.dart';
import '../core/theme/field_tokens.dart';
import '../main.dart'
    show
        SpeechManager,
        TransportType,
        WorkerReportItem,
        permittedReportBodyFor,
        reportPhotosFor,
        showConfirmDialog,
        showJsSnackbar;
import '../services/api_result.dart';
import '../services/company_service.dart';
import '../services/profile_service.dart';
import '../services/reports_service.dart';
import '../services/routes_service.dart';
import '../widgets/report_form_parts.dart';
import '../widgets/report_form_steps.dart';
import 'substitute_list_screen.dart' show jpMonthDay;
import 'substitute_past_day_screen.dart' show PastDayFrame, kPastDayFrameBody;

/// この画面が返す答え。★出す前に戻って閉じた時は null。
enum LateReportResult {
  /// 出せた。出せた後は、提出完了の「閉じる」・AppBar の戻る矢印・端末の戻るの、どの閉じ方でもこれを返す。
  submitted,

  /// 直しても通らない理由（許可が見つからない・もう出している・期限を過ぎた）で「閉じる」を押した。
  closed,
}

/// 'YYYY-MM-DD' → 'M月D日（曜）'。曜日は DateTime.utc(年, 月, 日).weekday から引く（時計は読まない）。
///   形が違う字・在らない日は、受けた字をそのまま返す（黙って化けさせない）。
String jpMonthDayDowOf(String ymd) {
  final p = ymd.split('-');
  if (p.length != 3) return ymd;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return ymd;
  final dt = DateTime.utc(y, m, d);
  // 2026-02-30 のように在らない日は、DateTime.utc が次の月へ繰り上げる＝そのままの字を返す。
  if (dt.year != y || dt.month != m || dt.day != d) return ymd;
  const dows = ['月', '火', '水', '木', '金', '土', '日'];
  return '$m月$d日（${dows[dt.weekday - 1]}）';
}

/// 事務の許可が出た過去の1日ぶんの日報を出す画面。
class LateReportScreen extends StatefulWidget {
  const LateReportScreen({
    super.key,
    required this.workDate,
    required this.dateText,
    required this.confirmationId,
    required this.confirmType,
    required this.permitUntil,
    this.reportsService,
    this.routesService,
  });

  /// その日（'YYYY-MM-DD'）。
  final String workDate;

  /// その日の「M月D日（曜）」（呼び手が渡す）。
  final String dateText;

  /// 尋ねる口の request_id を字にした物（POST /reports/permitted の confirmation_id）。
  final String confirmationId;

  /// 尋ねる口の confirm_type（許可の種類 'attendance_fix' か 'report_missing'・null あり）。
  final String? confirmType;

  /// 尋ねる口の permit_until（'YYYY-MM-DD'）。
  final String permitUntil;

  /// 口の差し替え（検査だけが渡す）。既定は null＝ReportsService()／RoutesService()。
  final ReportsService? reportsService;
  final RoutesService? routesService;

  @override
  State<LateReportScreen> createState() => _LateReportScreenState();
}

class _LateReportScreenState extends State<LateReportScreen> {
  late final ReportsService _api = widget.reportsService ?? ReportsService();
  late final RoutesService _routes = widget.routesService ?? RoutesService();
  // ★音声の係は画面ごとに1つ（初めてマイクを押した時に作る）。
  late final SpeechManager _speechMgr = SpeechManager();
  final ScrollController _scrollCtrl = ScrollController();

  final _transportMemoCtrl = TextEditingController();
  final _carpoolCompanyCtrl = TextEditingController();
  final _carpoolNameCtrl = TextEditingController();
  final _parkingCtrl = TextEditingController();
  final _workCtrl = TextEditingController();

  // ── 端末から読むだけの値 ────────────────────────────────
  String _userName = '';
  String _companyName = '';
  String _companyAddress = '';

  // ── 入力 ──────────────────────────────────────────────
  int _step = 1;
  String _shiftType = 'day';
  String? _siteId;
  String? _siteName;
  String _originType = 'home';
  Set<TransportType> _transports = {};
  String _carType = 'own';
  List<String> _workPhotoPaths = [];
  List<String> _parkingPhotoPaths = [];
  bool _isListening = false;

  // 初めの値（前回の値を読み終えた時の値）。途中で戻る時に「何も変えていないか」を見る。
  String _initOriginType = 'home';
  Set<TransportType> _initTransports = {};
  String _initCarType = 'own';

  // ── 相乗りの候補（ホームと同じ読み方・端末に書かない）──────────────
  List<Map<String, dynamic>> _carpoolCompanyResults = [];
  Timer? _carpoolCompanyDebounce;
  bool _carpoolColleaguesLoaded = false;
  List<String> _carpoolColleagues = [];

  // ── 目安（自分の状態だけ・覚え書きに書かない）──────────────────
  Map<String, dynamic> _routeComparisons = {};
  bool _loadingRoutes = false;
  bool _routeFailed = false;
  // 出発地の住所が無い時（便BJ・見本 v1 の ⑥）。true の間は帯の外に kHomeAddressMissingNote の※を出す。
  bool _homeAddressMissing = false;
  int _routeGen = 0;

  // ── 提出 ──────────────────────────────────────────────
  bool _submitting = false;
  bool _done = false;
  // 確認の画面に出す知らせ（送れなかった時の枠）と、「閉じる」だけの形。
  Widget? _notice;
  bool _closeOnly = false;
  // 届いたか分からなかった回に送った内容（本文の字と写真のパスの並び）。回のたびに足す（消さない）。
  final List<String> _unknownSent = [];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _carpoolCompanyDebounce?.cancel();
    _transportMemoCtrl.dispose();
    _carpoolCompanyCtrl.dispose();
    _carpoolNameCtrl.dispose();
    _parkingCtrl.dispose();
    _workCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // 前回の値を、ホームと同じ読み方で読むだけ（書かない）。
  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final userName = prefs.getString('user_name') ?? '';
    final companyName = prefs.getString('company_name') ?? '';
    final companyAddress = prefs.getString('company_address') ?? '';
    final origin = prefs.getString('default_origin') ?? 'home';
    final restored = reportTransportsFromSaved(prefs.getString('last_transports'));
    // ★車の種類はホームと同じく、移動手段を覚えている時だけ読む（覚えていなければ初めのまま）。
    final car = restored == null ? null : prefs.getString('last_car_type');
    if (!mounted) return;
    setState(() {
      _userName = userName;
      _companyName = companyName;
      _companyAddress = companyAddress;
      _originType = origin;
      if (restored != null) _transports = restored;
      if (car == 'own' || car == 'carpool') _carType = car!;
      _initOriginType = _originType;
      _initTransports = Set<TransportType>.from(_transports);
      _initCarType = _carType;
    });
    // ホームと同じく、読んだ時点で相乗りなら同僚を読む（氏名の候補）。
    if (_transports.contains(TransportType.car) && _carType == 'carpool') {
      _ensureColleaguesLoaded();
    }
  }

  // ── 字 ─────────────────────────────────────────────────
  String get _shiftLabel => _shiftType == 'night' ? '🌙夜勤' : '☀日勤';

  TransportType get _transport =>
      _transports.isEmpty ? TransportType.none : _transports.first;

  /// 確認の画面の※の2行目と、提出完了の※（許可の種類で分ける・表に無ければ無し）。
  String? get _kindNote {
    switch (widget.confirmType) {
      case 'attendance_fix':
        return '※事務が承認すると、この日を振替休日の出勤する日に選べるようになります。';
      case 'report_missing':
        return '※出した日報は、事務の承認で確定します。';
      default:
        return null;
    }
  }

  /// 'YYYY-MM-DD' → 'M/D'（先頭のゼロなし）。形が違えば受けた字。
  String get _slashMonthDay {
    final p = widget.workDate.split('-');
    if (p.length != 3) return widget.workDate;
    final m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (m == null || d == null) return widget.workDate;
    return '$m/$d';
  }

  /// 帯（見本 H1〜H4）：許可の印の語＋全角の空白＋日付（語が無ければ日付だけ）。
  Widget _band() {
    final mark = permittedReportMarkOrNull(widget.confirmType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FieldTokens.brand, width: 1),
      ),
      child: Text(mark == null ? widget.dateText : '$mark　${widget.dateText}',
          style: const TextStyle(color: FieldTokens.brand, fontSize: 12)),
    );
  }

  /// 入力が初めのまま（どの欄も初めの値から変えていない）か。
  ///   →再（2026-10-14・便BJ・見本 v1 の (8)）: 隠れた欄（補足・駐車料金と駐車場写真・相乗りの2欄）の字と写真は数えない
  ///   （隠れた欄の物は送らない＝送らない物で「閉じますか？」を出さない）。欄を出す式は report_form_steps.dart の
  ///   reportTransportMemoVisible・reportParkingVisible・reportCarpoolVisible（欄を出す所と同じ1本）。
  bool get _isPristine =>
      _shiftType == 'day' &&
      _siteId == null &&
      _siteName == null &&
      _originType == _initOriginType &&
      setEquals(_transports, _initTransports) &&
      _carType == _initCarType &&
      (!reportParkingVisible(_transports, _carType) ||
          (_parkingCtrl.text.isEmpty && _parkingPhotoPaths.isEmpty)) &&
      (!reportCarpoolVisible(_transports, _carType) ||
          (_carpoolCompanyCtrl.text.isEmpty && _carpoolNameCtrl.text.isEmpty)) &&
      (!reportTransportMemoVisible(_transports) ||
          _transportMemoCtrl.text.isEmpty) &&
      _workCtrl.text.isEmpty &&
      _workPhotoPaths.isEmpty;

  // ── 段の移り ─────────────────────────────────────────────
  void _scrollTop() {
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  void _goStep(int s) {
    setState(() => _step = s);
    _scrollTop();
  }

  // 確認の画面を1枚閉じて、直せる段へ戻す（ホームの _jumpToStep と同じ動き）。
  void _jumpToStep(int s) {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
    setState(() => _step = s);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTop());
  }

  // ── 段1：現場 ───────────────────────────────────────────
  // ホームの _showSitePicker と同じシート。選んだ物は自分の状態にだけ入れる（端末に覚えない）。
  Future<void> _showSitePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FieldTokens.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ReportSitePickerSheet(
        selectedSiteId: _siteId,
        onSelected: (id, name) {
          setState(() {
            _siteId = id;
            _siteName = name;
          });
          _calculateRoutes();
        },
      ),
    );
  }

  // ── 目安 ───────────────────────────────────────────────
  // 取らない時（現場なし・出発地の住所が無い）の後片付け。前の目安を残さない（送る本文の目安の値も null になる）。
  //   →再（2026-10-14・便BJ・見本 v1 の ⑥）: 出発地の住所が無い時（homeAddressMissing）は、帯の外に
  //   kHomeAddressMissingNote の※を出す（ホームと同じ字）。
  void _clearRoutes({bool homeAddressMissing = false}) {
    if (!mounted) return;
    setState(() {
      _routeComparisons = {};
      _loadingRoutes = false;
      _routeFailed = false;
      _homeAddressMissing = homeAddressMissing;
    });
  }

  // ★ホームの _calculateRoutes と同じく、2回まで（2回目の前に1秒）・世代の番号で古い答えを捨てる。
  //   違うのは、行き先を選んだ現場（siteId）で渡す事と、住所が無い時に決め打ちの住所を使わない事。
  Future<void> _calculateRoutes() async {
    // 世代を先に進める＝走っている計算の答えは、取る時も取らない時も捨てる。
    final myGen = ++_routeGen;
    final siteId = _siteId;
    if (siteId == null) {
      _clearRoutes();
      return;
    }
    final String? originAddr;
    if (_originType == 'office' && _companyAddress.isNotEmpty) {
      originAddr = _companyAddress;
    } else {
      originAddr = await ProfileService().getHomeAddress();
    }
    if (myGen != _routeGen) return;
    if (originAddr == null || originAddr.isEmpty) {
      _clearRoutes(homeAddressMissing: true);
      return;
    }
    if (!mounted) return;
    // 元: 取り直しの頭で前の目安を消さなかった（取り直しの間に提出すると前の値が入った＝窓の「金額が入りません」と違う）。
    // →再（2026-10-14・便BJ・見本 v1 の (9)）: 取り直しの頭で前の値を消す。
    setState(() {
      _loadingRoutes = true;
      _routeFailed = false;
      _routeComparisons = {}; // 取り直しの頭で前の値を消す（便BJ）
      _homeAddressMissing = false;
    });

    RouteCompareResult res = const RouteCompareResult.failed(RouteFailure.empty);
    for (int attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future.delayed(const Duration(seconds: 1));
      if (myGen != _routeGen) return;
      res = await _routes.compareRoutesV2(origin: originAddr, siteId: siteId);
      if (res.isOk) break;
    }

    if (myGen != _routeGen || !mounted) return;
    setState(() {
      _loadingRoutes = false;
      if (res.isOk) {
        _routeComparisons = res.routes;
        _routeFailed = false;
      } else {
        _routeComparisons = {};
        // ★空の答え（現場にもその住所にも座標が無い）は、取り直しても同じ＝「この手段の目安は取得できません」。
        _routeFailed = res.failure != RouteFailure.empty;
        debugPrint('late report routes failed: ${res.reasonLabel}');
      }
    });
  }

  // ── 相乗り（ホームと同じ読み方・端末に書かない）───────────────────
  void _onCarpoolCompanyChanged(String v) {
    _carpoolCompanyDebounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() => _carpoolCompanyResults = []);
      return;
    }
    _carpoolCompanyDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await CompanyService().searchCompanies(q);
      if (!mounted) return;
      setState(() => _carpoolCompanyResults = results.data ?? const []);
    });
  }

  Future<void> _ensureColleaguesLoaded() async {
    if (_carpoolColleaguesLoaded) return;
    _carpoolColleaguesLoaded = true;
    final names = await CompanyService().getColleagues();
    if (!mounted) return;
    setState(() => _carpoolColleagues = names.data ?? const []);
  }

  // ── 段3：音声入力 ─────────────────────────────────────────
  Future<void> _startVoice() => runReportVoiceInput(
        context,
        manager: _speechMgr,
        controller: _workCtrl,
        onListening: (v) {
          if (mounted) setState(() => _isListening = v);
        },
      );

  // ── 確認の画面 ───────────────────────────────────────────
  ReportSnapshot _buildSnapshot() => reportSnapshotFrom(
        dateLabel: widget.dateText,
        shiftLabel: _shiftLabel,
        siteId: _siteId,
        siteName: _siteName,
        originType: _originType,
        transports: _transports,
        carType: _carType,
        routeComparisons: _routeComparisons,
        parkingText: _parkingCtrl.text,
        carpoolCompanyText: _carpoolCompanyCtrl.text,
        carpoolNameText: _carpoolNameCtrl.text,
        workText: _workCtrl.text,
        workPhotoCount: _workPhotoPaths.length,
        parkingPhotoCount: _parkingPhotoPaths.length,
      );

  List<String> get _confirmNotes => [
        // ★1行目に「提出できるのは1回だけです。」は書かない（ボス裁定【Q136】＝2・職長のほかは、
        //   出した日報を取り消せば同じ許可で出し直せる＝見本の字は事実と違う）。
        '※提出期限は ${jpMonthDayDowOf(widget.permitUntil)}です。',
        if (_kindNote != null) _kindNote!,
      ];

  Future<void> _onCheck() async {
    FocusScope.of(context).unfocus();
    // 前の知らせ（送れなかった時の枠と「閉じる」だけの形）を消す。届いたか分からなかった回の覚えは消さない。
    setState(() {
      _notice = null;
      _closeOnly = false;
    });
    if (_loadingRoutes) {
      final goAnyway = await confirmProceedWhileRouting(context,
          message: 'このまま提出すると金額が入りません。', proceedLabel: 'このまま提出する');
      if (!goAnyway) return;
      if (!mounted) return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportConfirmScreen(
          initial: _buildSnapshot(),
          currentOf: _buildSnapshot,
          onSend: _submit,
          heading: 'この内容で提出します',
          sendLabel: '提出する',
          band: _band(),
          notes: _confirmNotes,
          noticeOf: () => _notice,
          closeOnlyOf: () => _closeOnly,
          onClose: _closeAfterRefusal,
        ),
      ),
    );
  }

  // 直しても通らない理由の「閉じる」：確認の画面とこの画面を閉じて closed を返す。
  void _closeAfterRefusal() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.pop(LateReportResult.closed);
  }

  Widget _frame(String text, {String? heading}) => PastDayFrame(
        lineColor: FieldTokens.statusError,
        heading: heading,
        headingColor: heading == null ? null : FieldTokens.statusError,
        body: Text(text, style: kPastDayFrameBody),
      );

  // ── 提出（確認の画面の「提出する」）──────────────────────────────
  //   →再（2026-10-21・便BN・下調べの (D4)）: 返り＝この提出で出せたか（確かめの画面は true の時だけ閉じる＝isDone の口は外した）。
  //   true は _done を立てる2つの道（届いた時と、届いたか分からなかった後の ALREADY_SUBMITTED＝1回目が届いていた時）だけ。
  Future<bool> _submit() async {
    if (_submitting) return false;
    if (_userName.isEmpty) {
      showJsSnackbar(context, '氏名が取得できていません', isError: true);
      return false;
    }
    if (_transports.isEmpty) {
      showJsSnackbar(context, '移動手段を選択してください', isError: true);
      _jumpToStep(2);
      return false;
    }
    setState(() => _submitting = true);
    try {
      // 元: 「車か その他」かつ写真0枚（相乗りで帯が無くても窓が出た）。
      // →再（2026-10-14・便BJ・見本 v1 の ④）: 帯を出す式（reportParkingVisible）と同じ1本＋写真0枚。
      if (reportParkingVisible(_transports, _carType) &&
          _parkingPhotoPaths.isEmpty) {
        final proceed = await confirmNoParkingPhoto(context,
            question: 'このまま提出しますか？', proceedLabel: 'このまま提出');
        if (!proceed) {
          if (mounted) setState(() => _submitting = false);
          _jumpToStep(2);
          return false;
        }
      }
      // ホームの _submit と同じ値の関数で組む。
      //   ★（元）「その他」の字（otherText）の欄はフォームに無い（ホームの _otherCtrl も画面に出していない）＝空の字。
      //     →再（2026-10-14・便BJ・見本 v1 の ⑦）: otherText を値の関数から撤去した（ホームの _otherCtrl も撤去）。
      //   ★日付・時刻・場所は送らない（permittedReportBodyFor が除く）＝gpsAddress・gpsLat・gpsLon・timestamp は渡さない。
      final contentPrefix = reportWorkContentPrefix(
        transports: _transports,
        memoText: _transportMemoCtrl.text,
      );
      final exp = reportExpenseSnapshot(_transports, _routeComparisons);
      // 駐車料金と駐車場の写真は、帯が出ている時だけ出す（便BK・CC の見つけた事＝隠れた欄の値を出さない・数えない）。
      final parkingShown = reportParkingVisible(_transports, _carType);
      final item = WorkerReportItem(
        name: _userName,
        transport: _transport,
        transportTypes: _transports.map((t) => t.name).toList(),
        workContent: contentPrefix + _workCtrl.text.trim(),
        parkingFee: parkingShown ? reportParkingFeeValue(_parkingCtrl.text) : null,
        workPhotoPaths: _workPhotoPaths,
        parkingPhotoPaths: parkingShown ? _parkingPhotoPaths : const <String>[],
        originType: _originType,
        siteId: _siteId,
        shiftType: _shiftType,
        transportDistanceKm: exp.distanceKm,
        transportFuelCost: exp.fuelCost,
        transportFare: exp.fare,
        transportToll: exp.toll,
        transportBreakdown: exp.breakdown.isEmpty ? null : exp.breakdown,
        carpoolCompany: reportCarpoolValue(
            transports: _transports, carType: _carType, text: _carpoolCompanyCtrl.text),
        carpoolName: reportCarpoolValue(
            transports: _transports, carType: _carType, text: _carpoolNameCtrl.text),
      );
      // ★読めない写真を黙って落とさない（今日の日報は飛ばして送る＝ここでは送らずに知らせる）。
      final photos = await reportPhotosFor(item);
      if (!mounted) return false;
      // 数えるのは出す写真だけ（item の並び・便BK＝隠れた帯の写真は数えない）。
      if (photos.length < item.workPhotoPaths.length + item.parkingPhotoPaths.length) {
        setState(() {
          _notice = _frame(kPhotoUnreadableText,
              heading: '提出できません');
          _closeOnly = false;
        });
        return false;
      }
      final body = permittedReportBodyFor(item, confirmationId: widget.confirmationId);
      // この回に送る内容（写真を足す前の本文の字と、写真のパスの並び）。届いたか分からなかった回と比べる。
      //   →再（2026-10-14・便BK）: 写真の並びは出す物（item の並び＝隠れた帯の写真を入れない）。
      final sent = jsonEncode([
        jsonEncode(body),
        item.workPhotoPaths,
        item.parkingPhotoPaths,
      ]);
      if (photos.isNotEmpty) body['photos'] = photos;
      final res = await _api.submitPermittedReport(body);
      if (!mounted) return false;
      return _applyAnswer(res, sent);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // 答えで分ける（見本 H6）。
  //   →再（2026-10-21・便BN・(D4)）: 返り＝出せたか（_done を立てた時だけ true＝確かめの画面はその時だけ閉じる）。
  bool _applyAnswer(ApiResult<Map<String, dynamic>> res, String sent) {
    if (res.ok) {
      // ★確認の画面を閉じるのは ReportConfirmScreen の道（_submit の返りの true・ここでは閉じない＝二重に閉じない）。
      setState(() => _done = true);
      return true;
    }
    // 届いたか分からない回＝サーバまで届かなかった（0）／本文が JSON でない 500 以上（中継の 502・503・504 など。
    //   サーバが書き終えた後に返る事もある）／200 台なのに本文を読めなかった（runApiCall の「応答の解析に失敗しました」）。
    final unknown = res.statusCode == 0 ||
        (res.statusCode >= 500 && res.errorDetails == null) ||
        (res.statusCode >= 200 && res.statusCode < 300);
    if (unknown) {
      _unknownSent.add(sent);
      setState(() {
        _notice = _frame('通信エラーが発生しました');
        _closeOnly = false;
      });
      return false;
    }
    final code = res.errorCode;
    // もう出している：届いたか分からなかった回が在り、その全部が今の内容と同じ＝1回目が届いていた（今の内容が出ている）。
    //   1つでも違えば、どの回が届いたか分からない（サーバの答えに無い）＝下の「提出できません」と「閉じる」だけ。
    if (code == 'ALREADY_SUBMITTED' &&
        _unknownSent.isNotEmpty &&
        _unknownSent.every((s) => s == sent)) {
      setState(() => _done = true);
      return true;
    }
    if (code == 'PERMIT_NOT_FOUND' ||
        code == 'PERMIT_DEADLINE_PASSED' ||
        code == 'ALREADY_SUBMITTED') {
      setState(() {
        _notice = _frame(res.errorMessage ?? '', heading: '提出できません');
        _closeOnly = true;
      });
      return false;
    }
    // ほかの失敗（直せば通る物が在る＝ボタンはそのまま）。文はサーバが JSON で返した時だけ。
    final err = res.errorDetails?['error'];
    final text = (err is String && err.isNotEmpty)
        ? (res.errorMessage ?? err)
        : 'できませんでした。時間をおいて、もう一度お試しください。';
    setState(() {
      _notice = _frame(text, heading: '提出できません');
      _closeOnly = false;
    });
    return false;
  }

  // ── 閉じ方（見本 H1 の※・H5）──────────────────────────────────
  Future<void> _onPopInvoked(bool didPop) async {
    if (didPop) return;
    if (_done) {
      Navigator.pop(context, LateReportResult.submitted);
      return;
    }
    if (_isPristine) {
      Navigator.pop(context);
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: null,
      message: '入力した内容は保存されません。閉じますか？',
      confirmText: '閉じる',
      cancelText: '入力を続ける',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
        child: Scaffold(
          backgroundColor: FieldTokens.bgBase,
          // ★形はホームの日報のページ（_pushReportForm）と同じ。
          appBar: AppBar(
            backgroundColor: FieldTokens.bgBase,
            elevation: 0,
            iconTheme: const IconThemeData(color: FieldTokens.textSupport),
            title: const Text('日報',
                style: TextStyle(
                    color: FieldTokens.brand, fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          body: SafeArea(child: _done ? _doneBody() : _formBody()),
        ),
      );

  // ── 提出完了（見本 H5）─────────────────────────────────────────
  Widget _doneBody() {
    final note = _kindNote;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('提出完了',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('$_shiftLabel $_slashMonthDay分を提出しました',
                textAlign: TextAlign.center,
                style: const TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
            const SizedBox(height: 10),
            // ※が無い種類（confirm_type が表に無い）は、※もその下の空きも置かない。
            if (note != null) ...[
              Text(note,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12, height: 1.6)),
              const SizedBox(height: 8),
            ],
            SizedBox(
              height: 56,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, LateReportResult.submitted),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FieldTokens.textBody,
                  side: const BorderSide(color: FieldTokens.textBody, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('閉じる',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── フォーム（器はホームの _buildHomeTabContent と同じ）────────────────
  Widget _formBody() => Container(
        color: FieldTokens.bgBase,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _band(),
                    const SizedBox(height: 12),
                    ReportStepIndicator(current: _step),
                    const SizedBox(height: 18),
                    if (_step == 1) ...[
                      Text('${widget.dateText}・$_shiftLabel',
                          style: const TextStyle(
                              color: FieldTokens.textSupport, fontSize: 12)),
                      const SizedBox(height: 3),
                      const Text('この日の報告',
                          style: TextStyle(
                              color: FieldTokens.textBody,
                              fontSize: 19,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 18),
                      ReportShiftChoice(
                        shiftType: _shiftType,
                        onChanged: (v) => setState(() => _shiftType = v),
                        nightNote: '※夜勤は、${jpMonthDay(widget.workDate)}の夜に始まった勤務です',
                      ),
                      const SizedBox(height: 18),
                      ReportStepSite(
                        siteName: _siteName,
                        onTap: _showSitePicker,
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_step == 2) ...[
                      // 押した時の中身はホームと同じ式から、端末の保存に書く行を除いた物。
                      ReportStepMove(
                        originType: _originType,
                        onOriginChanged: (type) async {
                          setState(() => _originType = type);
                          await _calculateRoutes();
                        },
                        transports: _transports,
                        onTransportTap: (t) {
                          final newSet = transportsAfterTap(_transports, t);
                          if (!newSet.contains(TransportType.car)) {
                            _parkingCtrl.clear();
                            _parkingPhotoPaths = [];
                          }
                          setState(() => _transports = newSet);
                        },
                        onTransportDoubleTap: (t) async {
                          final newSet = Set<TransportType>.from(_transports);
                          if (!newSet.contains(t)) {
                            newSet.add(t);
                            if (newSet.length >= 2) {
                              if (!context.mounted) return;
                              final ok = await confirmAddTransport(context);
                              if (!ok) return;
                            }
                            if (!newSet.contains(TransportType.car)) {
                              _parkingCtrl.clear();
                              if (mounted) setState(() => _parkingPhotoPaths = []);
                            }
                            if (mounted) setState(() => _transports = newSet);
                          }
                        },
                        transportMemoController: _transportMemoCtrl,
                        carType: _carType,
                        onCarTypeOwn: () => setState(() => _carType = 'own'),
                        onCarTypeCarpool: () {
                          setState(() {
                            _carType = 'carpool';
                            _parkingCtrl.clear();
                            _parkingPhotoPaths = [];
                          });
                          _ensureColleaguesLoaded();
                        },
                        routeTransport: _transport,
                        routeComparisons: _routeComparisons,
                        loadingRoutes: _loadingRoutes,
                        routeFailed: _routeFailed,
                        routeFromCache: false,
                        onRouteRetry: _calculateRoutes,
                        routeNote: _homeAddressMissing ? kHomeAddressMissingNote : null,
                        carpoolCompanyController: _carpoolCompanyCtrl,
                        carpoolCompanyCandidatesOf: () =>
                            carpoolCompanyNamesOf(_carpoolCompanyResults),
                        onCarpoolCompanyChanged: _onCarpoolCompanyChanged,
                        carpoolNameController: _carpoolNameCtrl,
                        carpoolNameCandidatesOf: () => carpoolNameCandidatesFor(
                          companyText: _carpoolCompanyCtrl.text,
                          ownCompanyName: _companyName,
                          colleagues: _carpoolColleagues,
                        ),
                        onCarpoolNameChanged: (_) {},
                        parkingFeeController: _parkingCtrl,
                        onParkingFeeChanged: (_) {},
                        parkingPhotoPaths: _parkingPhotoPaths,
                        onParkingPhotosChanged: (v) =>
                            setState(() => _parkingPhotoPaths = v),
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_step == 3)
                      ReportStepWork(
                        workController: _workCtrl,
                        isListening: _isListening,
                        onMicTap: _startVoice,
                        workPhotoPaths: _workPhotoPaths,
                        onWorkPhotosChanged: (v) => setState(() => _workPhotoPaths = v),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              color: FieldTokens.bgBase,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ReportStepButtons(
                step: _step,
                onGoStep: _goStep,
                checkBusy: _submitting,
                onCheck: _onCheck,
                checkNote: '※次の画面で見直してから提出します',
              ),
            ),
          ],
        ),
      );
}
