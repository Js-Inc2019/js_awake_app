// ============================================================
// lib/screens/share_send_screen.dart — 日報を他社へ送る（FIELD・条件先行型）
//
// 導線: 共有タブ（share_hub_screen.dart）の「送信」タイル。
//
// ★業務仕様は OFFICE の完成形（js_office_admin_app 2028773 の
//   lib/screens/bundle_send_screen.dart）と同じものを、FIELD の流儀
//   （ApiResult<T> + runApiCall / FieldTokens = Asphalt Dawn）で実装したもの。
//   OFFICE との対応:
//     ・フェーズ制（_showList）            … OFFICE の _showList
//     ・条件カード3枚（現場/職人/期間）     … OFFICE の _conditionCard
//     ・活性条件 _canSearch（片側以上）     … OFFICE の _canSearch
//     ・擬似行「現場未設定」= site_ids none … OFFICE の _kSiteNone
//     ・条件要約バー＋「条件を変更」         … OFFICE の _buildListPhase
//     ・truncated の注意文（文言同一）       … OFFICE の _buildListPhase の _truncated 注意文
//     ・全選択＝取得済み全件                … OFFICE の _toggleSelectAll
//     ・送信設定（宛先/まとめ方/写真/題名）  … OFFICE の _SendSettingsSheet
//     ・確認画面 → sendBundle              … OFFICE の _doSend
//   OFFICE にあって FIELD で作らないもの:
//     ・テキスト／PDF の出口（OFFICE の _openExitChoice の出口3択）。裁定6により
//       FIELD の出口は「アプリで送る」一本＝帳票は OFFICE の資産。
//
// ★role 差（BE routes/reports.js の GET /reports の scopeClause が最終権威）:
//   worker は GET /reports のスコープが `r.user_id = 自分` に固定されるため、
//   職人セレクタを出しても効かない（他人を指定しても交差して0件）。
//   さらに職人候補 API（GET /workers）は requireRole('boss','admin_office',
//   'admin_exec')（routes/workers.js の GET /workers）で worker は 403。
//   よって【worker には職人カードを出さない】。出せない・効かない選択肢を
//   置くのは嘘の記号になる。boss は会社軸なので出す。
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/field_tokens.dart';
import '../services/bundles_service.dart';
import '../services/company_service.dart';
import '../services/reports_service.dart';
import '../services/site_service.dart';
import '../services/worker_service.dart';
import '../main.dart' show showJsSnackbar;
// 状態の判定は report_cancel_gate の1本だけを使う（この画面に条件を手書きしない）。
// 状態→色・語は report_status_style の対応表1本だけを使う。
// ★この画面が状態を出す必要がある根拠は BE 側にある。POST /bundles/send は
//   「approved = true かつ status <> 'cancelled'」でないと 403 REPORT_NOT_APPROVED を返す
//   （js-office-api routes/bundles.js の承認ゲート）。候補に印が無いと、
//   送れない日報を選んで送信ボタンまで進み、そこで初めて断られる袋小路になる。
import '../utils/report_cancel_gate.dart' show reportStatusOf;
import '../utils/report_status_style.dart'
    show reportStatusStyleForState, reportStatusStyleOf;
import 'revision_inbox_screen.dart' show ReportDetailSheet;
import 'share_send_confirm_screen.dart';

/// 現場条件の擬似行「現場未設定」。BE の site_ids=none（r.site_id IS NULL・
/// routes/reports.js の GET /reports の 'none' 判定）に対応する。sites マスタには無い値なので、
/// ID 空間を汚さないようここ1箇所で定義する（OFFICE の _kSiteNone と同じ扱い）。
const String kSiteNone = 'none';

class ShareSendScreen extends StatefulWidget {
  const ShareSendScreen({super.key, required this.role});

  /// GET /profile の role をそのまま受ける。判定を2つに分けるため文字列で持つ:
  ///   ・職人カードを出すか       … role != 'worker'
  ///     （BE routes/reports.js の GET /reports の scopeClause＝worker は `r.user_id = 自分` に固定され、
  ///       他の顔は `r.company_id = 自社`。worker に出しても効かない）
  ///   ・職人候補 API を叩くか     … boss / admin_office / admin_exec のみ
  ///     （BE routes/workers.js の GET /workers の requireRole がこの3値。master は 403）
  /// ★この2つは集合が違う（master は会社軸だが職人候補を取れない）ので
  ///   1つの bool にまとめない。
  final String role;

  /// 会社軸の顔か（職人カードを出すかの判定）。
  bool get isCompanyScope => role != 'worker';

  /// 職人候補（GET /workers）を取得できる顔か。
  bool get canListWorkers =>
      role == 'boss' || role == 'admin_office' || role == 'admin_exec';

  @override
  State<ShareSendScreen> createState() => _ShareSendScreenState();
}

class _ShareSendScreenState extends State<ShareSendScreen> {
  final ReportsService _reports = ReportsService();
  final SiteService _sites = SiteService();
  final WorkerService _workers = WorkerService();
  final CompanyService _companies = CompanyService();
  final BundlesService _bundles = BundlesService();

  // ── フェーズ ──
  // false = 条件を選ぶ画面（開いた直後・一覧は出さない）／true = 一覧
  bool _showList = false;

  // ── 条件 ──
  final Set<String> _siteIds = <String>{};  // 空＝全部（現場未設定を含む）
  final Set<String> _userIds = <String>{};  // 空＝全員。値は person_id
  DateTime? _startDate;
  DateTime? _endDate;

  // ── 候補マスタ ──
  List<MapEntry<String, String>> _siteOptions = const [];
  List<MapEntry<String, String>> _workerOptions = const [];
  bool _mastersLoading = false;
  String? _mastersError;

  // ── 取得結果 ──
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  bool _truncated = false;

  // ── 選択 ──
  final Set<String> _selectedIds = <String>{};

  // ── 宛先候補（自社を除いた全社）──
  // ★自社の company_id は _loadCompanies の中でだけ使う（除外に使ったら用済み）。
  //   State に持たない＝使われないフィールドを残さない。
  List<Map<String, dynamic>> _companyOptions = const [];
  String? _companiesError;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // ★開いた直後は日報を取りにいかない（条件を選ぶまで一覧は出さない）。
    _loadMasters();
    _loadCompanies();
  }

  // ── 日付の道具（BE が受ける 'YYYY-MM-DD' と同一形）──
  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  String? get _startStr => _startDate == null ? null : _ymd(_startDate!);
  String? get _endStr => _endDate == null ? null : _ymd(_endDate!);

  /// 期間の見出し文。要約バーと確認画面で同じ1つを使う（表記を二重に持たない）。
  String get _periodLabel {
    final s = _startStr, e = _endStr;
    if (s != null && e != null) return '$s〜$e';
    if (s != null) return '$s以降';
    if (e != null) return '$eまで';
    return '';
  }

  /// 「この条件で日報を表示」は開始日か終了日のどちらか一方を選ぶまで押せない。
  /// ★両方なしで叩くと BE は期間経路に入らず既定50件の一覧に落ちる
  ///   （routes/reports.js の GET /reports の limit 決定）＝「期間指定したつもりで全然違う結果」になる。
  bool get _canSearch => _startDate != null || _endDate != null;

  String get _siteSummary =>
      _siteIds.isEmpty ? '全部（現場未設定を含む）' : '${_siteIds.length}件を指定';
  String get _workerSummary =>
      _userIds.isEmpty ? '全員' : '${_userIds.length}名を指定';

  List<String> _namesOf(Set<String> ids, List<MapEntry<String, String>> opts) {
    if (ids.isEmpty) return const [];
    final byId = {for (final e in opts) e.key: e.value};
    return ids.map((id) => byId[id] ?? id).toList()..sort();
  }

  // ── 候補マスタ（日報に依存しない＝条件を先に選べるようにするため）────────
  Future<void> _loadMasters() async {
    setState(() { _mastersLoading = true; _mastersError = null; });

    final sr = await _sites.getSites();
    // ★職人候補は会社軸の顔だけ取りにいく。worker は GET /workers が 403 なので
    //   そもそも叩かない（取れない API を叩いて 403 をログに積まない）。
    final wr = widget.canListWorkers
        ? await _workers.getWorkers(membershipType: 'employee')
        : null;
    if (!mounted) return;

    // 現場: 先頭に擬似行「現場未設定」。以降は sites マスタ。
    final siteOpts = <MapEntry<String, String>>[
      const MapEntry(kSiteNone, '現場未設定'),
    ];
    if (sr.ok) {
      for (final s in (sr.data ?? const [])) {
        if (s is! Map) continue;
        final id = (s['site_id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final name = (s['site_name'] ?? '').toString().trim();
        siteOpts.add(MapEntry(id, name.isEmpty ? '(名称未設定)' : name));
      }
    }

    // 職人: 自社（is_own）の workers を平坦化（BE routes/workers.js の GET /workers の companies 組み立ての形）。
    final workerOpts = <MapEntry<String, String>>[];
    if (wr != null && wr.ok) {
      for (final c in (wr.data ?? const [])) {
        if (c['is_own'] != true) continue;
        for (final w in ((c['workers'] as List?) ?? const [])) {
          if (w is! Map) continue;
          final id = (w['user_id'] ?? w['person_id'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          final name = (w['name'] ?? '').toString().trim();
          workerOpts.add(MapEntry(id, name.isEmpty ? '不明' : name));
        }
      }
      workerOpts.sort((a, b) => a.value.compareTo(b.value));
    }

    setState(() {
      _siteOptions = siteOpts;
      _workerOptions = workerOpts;
      _mastersLoading = false;
      // 候補が取れなくても条件選択は続けられる（空＝全部/全員で送れる）ので
      // 画面は止めず注意文だけ出す＝袋小路にしない。理由は丸めない。
      final msgs = <String>[];
      if (!sr.ok) {
        msgs.add(sr.statusCode == 0
            ? '現場の候補を取得できませんでした（通信できませんでした）'
            : '現場の候補を取得できませんでした（${sr.errorMessage ?? "理由不明"}）');
      }
      if (wr != null && !wr.ok) {
        msgs.add(wr.statusCode == 403
            ? '職人の候補を取得する権限がありません'
            : wr.statusCode == 0
                ? '職人の候補を取得できませんでした（通信できませんでした）'
                : '職人の候補を取得できませんでした（${wr.errorMessage ?? "理由不明"}）');
      }
      _mastersError = msgs.isEmpty
          ? null
          : '${msgs.join('／')}。全部／全員のままなら検索できます';
    });
  }

  // ── 宛先候補（全社から自社を除く）──────────────────────────────
  //   ★自社の company_id はログイン時に prefs へ保存されている値を使う
  //     （login_screen.dart / recovery_screen.dart / register_screen.dart
  //       が書き、monthly_history_screen.dart 等が既に同じ読み方をしている）。
  //     GET /profile は company_name しか返さないため、会社名の文字列一致で
  //     自社を外す形にはしない（同名会社を取り違える）。
  //   ★自社が混ざったまま送ると BE は 400 SELF_SHARE_NOT_ALLOWED で断る
  //     （bundles.js）。押してから怒られる形にしない。
  Future<void> _loadCompanies() async {
    final prefs = await SharedPreferences.getInstance();
    final myId = prefs.getString('company_id') ?? '';
    final cr = await _companies.getCompanies();
    if (!mounted) return;
    setState(() {
      if (cr.ok) {
        _companyOptions = (cr.data ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((c) => (c['company_id'] ?? '').toString() != myId)
            .toList();
        _companiesError = null;
      } else {
        _companyOptions = const [];
        _companiesError = cr.statusCode == 0
            ? '通信できませんでした'
            : (cr.errorMessage ?? '送信先の候補を取得できませんでした');
      }
    });
  }

  // ── 日報取得 ────────────────────────────────────────────
  Future<void> _loadReports() async {
    setState(() { _loading = true; _error = null; });
    final r = await _reports.getReportsRange(
      startDate: _startStr,
      endDate: _endStr,
      // 空＝条件を送らない（現場は全部／職人は全員）。
      siteIds: _siteIds.isEmpty ? null : _siteIds.toList(),
      userIds: _userIds.isEmpty ? null : _userIds.toList(),
      // limit は送らない＝BE の期間経路既定（1000）に委ねる。
    );
    if (!mounted) return;
    if (r.ok && r.data != null) {
      setState(() {
        _rows = r.data!.reports;
        _truncated = r.data!.truncated;
        _loading = false;
        _showList = true;
        _selectedIds.clear(); // 条件が変われば選択は持ち越さない
      });
      return;
    }
    // ★非200を「0件」に化けさせない。BE が理由を言っているならそれを出す
    //   （400 の文言は BE の error そのまま＝api_result 規約2・丸めない）。
    setState(() {
      _loading = false;
      _error = r.statusCode == 0
          ? '通信できませんでした'
          : r.statusCode == 403
              ? (r.errorMessage ?? '権限がありません')
              : (r.errorMessage ?? '日報を取得できませんでした（HTTP ${r.statusCode}）');
    });
  }

  String _rid(Map<String, dynamic> r) => (r['report_id'] ?? '').toString();

  List<Map<String, dynamic>> _selectedReports() =>
      _rows.where((r) => _selectedIds.contains(_rid(r))).toList();

  void _toggleSelectAll() {
    final allIds = _rows.map(_rid).toSet();
    final allSelected = allIds.isNotEmpty && _selectedIds.containsAll(allIds);
    setState(() {
      if (allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(allIds);
      }
    });
  }

  // ── 条件シート（現場／職人）──────────────────────────────────
  Future<void> _openPicker({
    required String title,
    required List<MapEntry<String, String>> options,
    required Set<String> current,
    required String allLabel,
    required String emptyLabel,
    required String unit,
  }) async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: FieldTokens.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MultiPickSheet(
        title: title,
        options: options,
        initialSelected: current,
        allLabel: allLabel,
        emptyLabel: emptyLabel,
        unit: unit,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      current
        ..clear()
        ..addAll(result);
    });
  }

  // ── 期間（片側可・逆転はUIで防ぐ）───────────────────────────
  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      // 終了日が決まっていれば、それより後は選ばせない（押してから400にしない）。
      lastDate: _endDate ?? DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _endDate = picked);
  }

  // ── 日報プレビュー（FIELD 既存の共通シートを使う）───────────────
  //   ★home_screen.dart / revision_inbox_screen.dart /
  //     approval_day_screen.dart と同じ ReportDetailSheet。
  //     プレビュー専用の別画面は作らない（同じものを2つ持たない）。
  void _preview(Map<String, dynamic> r) {
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

  // ── 送信設定 → 確認画面 → sendBundle ──────────────────────────
  Future<void> _openSendFlow() async {
    final selected = _selectedReports();
    if (selected.isEmpty) return;

    final cfg = await showModalBottomSheet<_SendConfig>(
      context: context,
      backgroundColor: FieldTokens.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SendConfigSheet(
        companies: _companyOptions,
        companiesError: _companiesError,
        onRetryCompanies: _loadCompanies,
      ),
    );
    if (cfg == null || !mounted) return;

    final nameById = {
      for (final c in _companyOptions)
        (c['company_id'] ?? '').toString():
            (c['company_name'] ?? '(名称不明)').toString()
    };

    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ShareSendConfirmScreen(
        reports: selected,
        receiverCompanyNames:
            cfg.receiverIds.map((id) => nameById[id] ?? '(名称不明)').toList(),
        periodLabel: _periodLabel,
        workerSummary: _userIds.isEmpty
            ? _workerSummary
            : '$_workerSummary（${_namesOf(_userIds, _workerOptions).join('・')}）',
        siteSummary: _siteIds.isEmpty
            ? _siteSummary
            : '$_siteSummary（${_namesOf(_siteIds, _siteOptions).join('・')}）',
        includePhotos: cfg.includePhotos,
        onPreview: _preview,
      ),
    ));
    if (ok != true || !mounted) return;

    setState(() => _sending = true);
    final res = await _bundles.sendBundle(
      reportIds: selected.map(_rid).toList(),
      receiverCompanyIds: cfg.receiverIds,
      initialAxis: cfg.axis,
      includePhotos: cfg.includePhotos,
      title: cfg.title.isEmpty ? null : cfg.title,
      memo: cfg.memo.isEmpty ? null : cfg.memo,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (res.ok) {
      showJsSnackbar(context,
          '日報${selected.length}件を${cfg.receiverIds.length}社に共有しました');
      Navigator.of(context).pop(); // 送信画面ごと閉じる
      return;
    }
    // ★BE の理由を丸めない（規約6）。ここで留まる＝袋小路にしない。
    final String msg;
    switch (res.errorCode) {
      case 'REPORT_NOT_OWNED':
        msg = '自社の日報のみ送れます';
      case 'SELF_SHARE_NOT_ALLOWED':
        msg = '自社への送信はできません';
      case 'RECEIVER_NOT_FOUND':
        msg = '送信先の会社が見つかりません';
      default:
        msg = res.statusCode == 403
            ? (res.errorMessage ?? '共有を送る権限がありません（『共有送信』が必要）')
            : res.statusCode == 0
                ? '通信できませんでした'
                : (res.errorMessage ?? '送信できませんでした');
    }
    showJsSnackbar(context, msg, isError: true);
  }

  // ─────────────────────── BUILD ───────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        title: const Text('日報を送る'),
      ),
      body: Stack(children: [
        SafeArea(child: _showList ? _listPhase() : _conditionPhase()),
        if (_sending)
          const ColoredBox(
            color: FieldTokens.scrimStrong,
            child: Center(
                child: CircularProgressIndicator(color: FieldTokens.accent)),
          ),
      ]),
      bottomNavigationBar: _showList ? _bottomBar() : null,
    );
  }

  // ── フェーズ1: 条件 ─────────────────────────────────────
  Widget _conditionPhase() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text('送る日報の条件を選んでください',
              style: TextStyle(
                  color: FieldTokens.textBody,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('条件を決めてから一覧を出します（開いた時点では取得しません）',
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
          const SizedBox(height: 16),

          if (_mastersError != null) ...[
            _notice(_mastersError!, FieldTokens.statusWarning),
            const SizedBox(height: 12),
          ],

          // 1. 現場
          _card(
            icon: Icons.place_outlined,
            label: '現場',
            value: _siteSummary,
            enabled: !_mastersLoading,
            onTap: () => _openPicker(
              title: '現場を選ぶ',
              options: _siteOptions,
              current: _siteIds,
              allLabel: '全部（現場未設定を含む）',
              emptyLabel: '現場がありません',
              unit: '件',
            ),
          ),
          const SizedBox(height: 10),

          // 2. 職人（会社軸の顔だけ。worker には出さない）
          if (widget.isCompanyScope) ...[
            _card(
              icon: Icons.people_outline,
              label: '職人',
              value: _workerSummary,
              enabled: !_mastersLoading,
              onTap: () => _openPicker(
                title: '職人を選ぶ',
                options: _workerOptions,
                current: _userIds,
                allLabel: '全員',
                emptyLabel: '職人がいません',
                unit: '名',
              ),
            ),
            const SizedBox(height: 10),
          ] else ...[
            _notice('職人の指定はできません（自分の日報のみが対象です）',
                FieldTokens.textFaint),
            const SizedBox(height: 10),
          ],

          // 3. 期間
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: FieldTokens.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FieldTokens.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.date_range,
                      size: 16, color: FieldTokens.accent),
                  const SizedBox(width: 8),
                  const Text('期間',
                      style: TextStyle(
                          color: FieldTokens.textBody,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_startDate != null || _endDate != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _startDate = null;
                        _endDate = null;
                      }),
                      style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          visualDensity: VisualDensity.compact),
                      child: const Text('クリア',
                          style: TextStyle(
                              color: FieldTokens.textSupport, fontSize: 12)),
                    ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _dateButton('開始日', _startStr, _pickStart)),
                  const SizedBox(width: 10),
                  Expanded(child: _dateButton('終了日', _endStr, _pickEnd)),
                ]),
                const SizedBox(height: 8),
                const Text('※片方だけの指定もできます',
                    style: TextStyle(
                        color: FieldTokens.textFaint, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 22),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: (_canSearch && !_loading) ? _loadReports : null,
              icon: const Icon(Icons.search, size: 18),
              label: Text(_loading ? '取得中…' : 'この条件で日報を表示'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FieldTokens.accent,
                foregroundColor: FieldTokens.onAccent,
                disabledBackgroundColor: FieldTokens.outlineStrong,
                disabledForegroundColor: FieldTokens.textFaint,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (!_canSearch) ...[
            const SizedBox(height: 8),
            const Text('開始日か終了日のどちらかを選ぶと押せます',
                textAlign: TextAlign.center,
                style: TextStyle(color: FieldTokens.textFaint, fontSize: 11)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            _notice(_error!, FieldTokens.statusError),
          ],
        ],
      );

  Widget _card({
    required IconData icon,
    required String label,
    required String value,
    required bool enabled,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: FieldTokens.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: FieldTokens.outline),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: FieldTokens.accent),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            // 1行に収める必要がある値は FittedBox で縮める（ellipsis / clip 禁止）。
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(value,
                    style: const TextStyle(
                        color: FieldTokens.textSupport, fontSize: 13)),
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: FieldTokens.textSupport),
          ]),
        ),
      );

  Widget _dateButton(String label, String? value, VoidCallback onTap) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor:
              value == null ? FieldTokens.textSupport : FieldTokens.accent,
          side: BorderSide(
              color: value == null ? FieldTokens.outline : FieldTokens.accent),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: const TextStyle(
                    color: FieldTokens.textFaint, fontSize: 10)),
            const SizedBox(height: 2),
            Text(value ?? '未指定',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
        ),
      );

  Widget _notice(String text, Color c) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 12, height: 1.4)),
          ),
        ]),
      );

  // ── フェーズ2: 一覧 ─────────────────────────────────────
  Widget _listPhase() => Column(children: [
        // 条件要約バー＋「条件を変更」
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: const BoxDecoration(
            color: FieldTokens.surfaceCard,
            border:
                Border(bottom: BorderSide(color: FieldTokens.outline)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(_periodLabel,
                        style: const TextStyle(
                            color: FieldTokens.textBody,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                        widget.isCompanyScope
                            ? '現場: $_siteSummary ／ 職人: $_workerSummary'
                            : '現場: $_siteSummary ／ 自分の日報のみ',
                        style: const TextStyle(
                            color: FieldTokens.textSupport, fontSize: 12)),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _showList = false),
              child: const Text('条件を変更',
                  style: TextStyle(color: FieldTokens.accent, fontSize: 13)),
            ),
          ]),
        ),
        // 上限で切れたときだけ出す注意文（BE の truncated）
        if (_truncated)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: FieldTokens.statusWarning.withValues(alpha: 0.14),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded,
                  color: FieldTokens.statusWarning, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '1,000件を超えたため一部のみ表示しています。期間を狭めて絞り直してください',
                  style: TextStyle(
                      color: FieldTokens.textBody, fontSize: 12, height: 1.4),
                ),
              ),
            ]),
          ),
        // 全選択（取得済み一覧の全件が対象）
        if (!_loading && _error == null && _rows.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 6, top: 2),
              child: TextButton.icon(
                onPressed: _toggleSelectAll,
                icon: Icon(
                  _selectedIds.length == _rows.length
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  color: FieldTokens.accent,
                  size: 18,
                ),
                label: Text(
                  _selectedIds.length == _rows.length ? '全解除' : '全選択',
                  style: const TextStyle(
                      color: FieldTokens.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        Expanded(child: _listBody()),
      ]);

  Widget _listBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: FieldTokens.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline,
                size: 48, color: FieldTokens.statusError),
            const SizedBox(height: 12),
            // ★BE が返した理由をそのまま出す（「取得に失敗」で塗り潰さない）。
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: FieldTokens.textSupport, fontSize: 14)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton.icon(
                onPressed: _loadReports,
                icon: const Icon(Icons.refresh,
                    size: 16, color: FieldTokens.accent),
                label: const Text('再試行',
                    style: TextStyle(color: FieldTokens.accent)),
              ),
              TextButton(
                onPressed: () => setState(() => _showList = false),
                child: const Text('条件を変更',
                    style: TextStyle(color: FieldTokens.accent)),
              ),
            ]),
          ]),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('この条件の日報はありません',
              style:
                  TextStyle(color: FieldTokens.textSupport, fontSize: 14)),
          TextButton(
            onPressed: () => setState(() => _showList = false),
            child: const Text('条件を変更',
                style: TextStyle(color: FieldTokens.accent)),
          ),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _pickerRow(_rows[i]),
    );
  }

  // 行の中身は ShareCandidateRow（下の公開部品）へ出してある。
  //   ★出した理由: この画面は ReportsService 等のシングルトンを直接触るため
  //     widget テストで実HTTPを避けられない（test/share_send_confirm_test.dart の
  //     冒頭がその線引きを書いている）。行だけを引数で動く公開部品にすれば、
  //     画面を立てずに「印が出るか」を検査で固定できる。
  //     前例は monthly_history_screen.dart の JsReportTile / JsStatChip で、
  //     どちらも公開部品として test/report_cancel_gate_test.dart が直接組んでいる。
  Widget _pickerRow(Map<String, dynamic> r) {
    final id = _rid(r);
    return ShareCandidateRow(
      report: r,
      checked: _selectedIds.contains(id),
      onChanged: (v) => setState(() {
        if (v == true) {
          _selectedIds.add(id);
        } else {
          _selectedIds.remove(id);
        }
      }),
      onTap: () => _preview(r),
    );
  }

  // ── 下部固定バー（選択件数＋送る）────────────────────────────
  Widget _bottomBar() {
    final n = _selectedIds.length;
    // ★注意帯は下部バーの真上に置く。押す直前に読める位置でなければ、
    //   送信ボタンへ手が伸びたあとに 403 で断られる袋小路が残る。
    //   数えるのは選んだ行だけ（一覧に居るだけの行は関係ない）。
    final blocked = shareSendBlockedCounts(_selectedReports());
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (blocked.total > 0) ShareSendCautionBanner(counts: blocked),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: const BoxDecoration(
            color: FieldTokens.surfaceCard,
            border: Border(top: BorderSide(color: FieldTokens.outline)),
          ),
          child: Row(children: [
            // ★Flexible + FittedBox で縮退させる（省略記号や切り落としは使わない＝
            //   件数は数えた事実であって、丸めたり消したりして良い値ではない）。
            //   流儀は同ファイルの条件サマリと同一。
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('$n件を選択中',
                    style: const TextStyle(
                        color: FieldTokens.textBody,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: (n == 0 || _sending) ? null : _openSendFlow,
                icon: const Icon(Icons.send, size: 16),
                label: const Text('宛先を選んで送る'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FieldTokens.accent,
                  foregroundColor: FieldTokens.onAccent,
                  disabledBackgroundColor: FieldTokens.outlineStrong,
                  disabledForegroundColor: FieldTokens.textFaint,
                  // ★横の最小幅をゼロ起点へ戻す。app_theme.dart の elevatedButtonTheme が
                  //   minimumSize: Size(double.infinity, 52) を課しており、Row の非 flex 子
                  //   として置くと「幅＝無限」を要求して BoxConstraints forces an infinite
                  //   width で落ちる（＝下部バーの Row ごとレイアウト不能。リリース版では
                  //   例外表示が出ないためボタンが消えたように見えた）。
                  //   同じ罠と対処は approval_day_screen.dart / 同ファイルの他の OutlinedButton
                  //   に前例がある。高さ48・角丸10・色は現状のまま。
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 送信候補の1行（公開部品）
//
// ★状態の印を出す理由（BE が最終権威）:
//   POST /bundles/send は選ばれた日報を1件ずつ見て
//   `r.approved !== true || r.status === 'cancelled'` に当たるものが1件でもあれば
//   403 REPORT_NOT_APPROVED を返す（js-office-api routes/bundles.js の承認ゲート）。
//   一方 GET /reports は取消済も未承認も差戻し中も候補として返す
//   （同 routes/reports.js の LIST_COLS は approved と status を載せており、
//     一覧そのものは状態で絞っていない）。印が無ければ、送れない日報と
//   送れる日報が同じ顔で並ぶ＝押してから断られる袋小路になる。
//
// ★印の出し方（裁定＝案2）:
//   ・行の左端に縦帯4px（状態の色）
//   ・2段目の現場名の右に状態の語（太字・状態の色）
//   ・承認済には何も足さない（送れる行に印を足すと、印そのものの意味が薄まる）
//
// ★行は一覧から消さない・タップで開ける・チェックも外さない。
//   消すと「条件に合う日報が一覧に無い」という別の嘘になる。外すかどうかは
//   人が決めることで、画面が勝手に決めてよい値ではない。
// ─────────────────────────────────────────────────────────
class ShareCandidateRow extends StatelessWidget {
  const ShareCandidateRow({
    super.key,
    required this.report,
    required this.checked,
    required this.onChanged,
    required this.onTap,
  });

  final Map<String, dynamic> report;
  final bool checked;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = (report['report_date'] ?? '').toString();
    final worker = (report['worker_name'] ?? '').toString().trim();
    // 現場名は sitesマスタ正式名 > 職人入力 > 未設定 の順（OFFICE 確認画面と同じ優先度）。
    final master = (report['master_site_name'] ?? '').toString().trim();
    final site = (report['site_name'] ?? '').toString().trim();
    final siteLabel =
        master.isNotEmpty ? master : (site.isNotEmpty ? site : '現場未設定');

    // 判定は report_cancel_gate、色と語は report_status_style。ここには書かない。
    final status = reportStatusOf(report);
    final style = reportStatusStyleOf(report);
    final isApproved = status == 'approved';

    return Container(
      decoration: BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: checked ? FieldTokens.accent : FieldTokens.outline),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左端の縦帯。承認済のときは帯そのものを置かない。
            //   幅と角丸は monthly_history_screen.dart の JsReportTile の
            //   自社／他社の帯と同じ寸法に揃える（同じアプリで帯の太さを変えない）。
            if (!isApproved)
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: style.color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(9),
                    bottomLeft: Radius.circular(9),
                  ),
                ),
              ),
            Checkbox(
              value: checked,
              activeColor: FieldTokens.accent,
              checkColor: FieldTokens.onAccent,
              side: const BorderSide(color: FieldTokens.textSupport),
              onChanged: onChanged,
            ),
            // 行タップ＝プレビュー（チェックはチェックボックスで行う＝誤爆させない）。
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(date,
                                style: const TextStyle(
                                    color: FieldTokens.textBody,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                    worker.isEmpty ? '不明' : worker,
                                    style: const TextStyle(
                                        color: FieldTokens.textBody,
                                        fontSize: 13)),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 3),
                          // 2段目。現場名の右に状態の語を置く。
                          //   現場名を Expanded にして語の場所を先に確保する
                          //   （長い現場名に押し出されて語が消えると印にならない）。
                          Row(children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(siteLabel,
                                    style: const TextStyle(
                                        color: FieldTokens.textSupport,
                                        fontSize: 11)),
                              ),
                            ),
                            if (!isApproved) ...[
                              const SizedBox(width: 8),
                              Text(style.label,
                                  style: TextStyle(
                                      color: style.color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ]),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 18, color: FieldTokens.textSupport),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 送れない日報が選択に何件混じっているかの数え。
//
// ★数える条件は BE の承認ゲートと同じ集合にする
//   （js-office-api routes/bundles.js: `r.approved !== true || r.status === 'cancelled'`）。
//   ＝取消済・差戻し中・未承認の3つ。承認済だけが送れる。
// ★差戻し中も数える。裁定で名指しされたのは取消済と未承認だが、差戻し中も
//   approved=false のまま（BE は request-revision で approved を false へ落とす）
//   なので、数えないとその行だけが黙って 403 の材料として残り、
//   注意帯が「0件」と言っているのに送ると断られる形になる。
//   状態を1つでも数え落とすと注意帯そのものが嘘になるため、3つとも数える。
// ─────────────────────────────────────────────────────────
@immutable
class ShareSendBlockedCounts {
  const ShareSendBlockedCounts({
    required this.cancelled,
    required this.rejected,
    required this.pending,
  });

  final int cancelled;
  final int rejected;
  final int pending;

  int get total => cancelled + rejected + pending;
}

/// 選ばれた日報から、送れない件数を状態ごとに数える。
///
/// ★判定は report_cancel_gate の reportStatusOf 1本。ここで
///   approved や status を直接読まない（読み方を2つに増やさない）。
ShareSendBlockedCounts shareSendBlockedCounts(
    List<Map<String, dynamic>> selected) {
  var cancelled = 0, rejected = 0, pending = 0;
  for (final r in selected) {
    switch (reportStatusOf(r)) {
      case 'cancelled':
        cancelled++;
      case 'rejected':
        rejected++;
      case 'approved':
        break;
      default:
        pending++;
    }
  }
  return ShareSendBlockedCounts(
      cancelled: cancelled, rejected: rejected, pending: pending);
}

// ─────────────────────────────────────────────────────────
// 下部バーの真上に出す注意帯（公開部品）。
//
// ★帯の色は statusWarning。状態の色（藤・赤・橙）のどれかを使うと
//   「この帯は取消済のこと」と読めてしまうが、実際は複数の状態をまとめて
//   知らせる帯である。同じ画面の上限超過の注意帯（_listPhase の truncated）が
//   既に statusWarning なので、注意を促す帯の色はそれに揃える。
// ★2行目の文は BE が 403 で返す文そのままにしてある
//   （js-office-api routes/bundles.js の REPORT_NOT_APPROVED の error）。
//   送る前と断られた後で言うことが違うと、どちらが本当か人が判断できなくなる。
// ─────────────────────────────────────────────────────────
class ShareSendCautionBanner extends StatelessWidget {
  const ShareSendCautionBanner({super.key, required this.counts});

  final ShareSendBlockedCounts counts;

  /// 「取消済2件・未承認1件」のような、数えた事実だけの並び。
  /// 0件の状態は書かない（0を並べると読む手間だけが増える）。
  String get countsLine {
    final parts = <String>[];
    if (counts.cancelled > 0) {
      parts.add(
          '${reportStatusStyleForState('cancelled').label}${counts.cancelled}件');
    }
    if (counts.rejected > 0) {
      parts.add(
          '${reportStatusStyleForState('rejected').label}${counts.rejected}件');
    }
    if (counts.pending > 0) {
      parts.add(
          '${reportStatusStyleForState('pending').label}${counts.pending}件');
    }
    return '選択中に ${parts.join('・')} が含まれています';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: FieldTokens.surfaceCard,
        border: Border(top: BorderSide(color: FieldTokens.outline)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded,
            color: FieldTokens.statusWarning, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(countsLine,
                  style: const TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              const Text(
                '承認済みの日報のみ送信できます。'
                '未承認・差戻し中の日報は承認を受けてから、'
                '取消済みの日報は選択から外してから送信してください',
                style: TextStyle(
                    color: FieldTokens.textSupport,
                    fontSize: 12,
                    height: 1.4),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 複数選択シート（現場／職人で共用＝中身が同じものを2つ作らない）
//   OFFICE の _MultiPickSheet（bundle_send_screen.dart）と同じ役割。
// ─────────────────────────────────────────────────────────
class _MultiPickSheet extends StatefulWidget {
  const _MultiPickSheet({
    required this.title,
    required this.options,
    required this.initialSelected,
    required this.allLabel,
    required this.emptyLabel,
    required this.unit,
  });

  final String title;
  final List<MapEntry<String, String>> options;
  final Set<String> initialSelected;

  /// 選択0件のときの意味（'全部（現場未設定を含む）' / '全員'）。
  final String allLabel;
  final String emptyLabel;
  final String unit;

  @override
  State<_MultiPickSheet> createState() => _MultiPickSheetState();
}

class _MultiPickSheetState extends State<_MultiPickSheet> {
  late final Set<String> _sel = {...widget.initialSelected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim();
    final shown = q.isEmpty
        ? widget.options
        : widget.options.where((e) => e.value.contains(q)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: FieldTokens.textFaint,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 12),
        Text(widget.title,
            style: const TextStyle(
                color: FieldTokens.textBody,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          _sel.isEmpty ? widget.allLabel : '${_sel.length}${widget.unit}を選択中',
          style: const TextStyle(color: FieldTokens.textSupport, fontSize: 12),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            style: const TextStyle(color: FieldTokens.textBody, fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '名前で絞り込む',
              hintStyle: TextStyle(color: FieldTokens.textHint, fontSize: 13),
              prefixIcon:
                  Icon(Icons.search, size: 18, color: FieldTokens.textSupport),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: FieldTokens.outline)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: FieldTokens.accent)),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        const Divider(height: 1, color: FieldTokens.outline),
        Expanded(
          child: widget.options.isEmpty
              ? Center(
                  child: Text(widget.emptyLabel,
                      style: const TextStyle(
                          color: FieldTokens.textSupport, fontSize: 13)),
                )
              : ListView.separated(
                  controller: scrollCtrl,
                  itemCount: shown.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: FieldTokens.outline),
                  itemBuilder: (_, i) {
                    final e = shown[i];
                    final on = _sel.contains(e.key);
                    return CheckboxListTile(
                      value: on,
                      activeColor: FieldTokens.accent,
                      checkColor: FieldTokens.onAccent,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(e.value,
                            style: const TextStyle(
                                color: FieldTokens.textBody, fontSize: 14)),
                      ),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _sel.add(e.key);
                        } else {
                          _sel.remove(e.key);
                        }
                      }),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(_sel.clear),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: FieldTokens.textSupport,
                    side: const BorderSide(color: FieldTokens.outline),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(widget.allLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(_sel),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: FieldTokens.accent,
                    foregroundColor: FieldTokens.onAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('決定'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 送信設定（宛先／まとめ方／写真／タイトル・メモ）
//   OFFICE の _SendSettingsSheet（bundle_send_screen.dart）と同じ項目。
//   ★写真の既定は false（BE bundles.js の include_photos === true と同じ側）。
//     ここを省くと常に写真なしで送ることになり、受信側に
//     「この束は写真を含めずに送られています」が出続ける＝送り手が選べない。
// ─────────────────────────────────────────────────────────
class _SendConfig {
  const _SendConfig({
    required this.receiverIds,
    required this.axis,
    required this.includePhotos,
    required this.title,
    required this.memo,
  });
  final List<String> receiverIds;
  final String axis;
  final bool includePhotos;
  final String title;
  final String memo;
}

class _SendConfigSheet extends StatefulWidget {
  const _SendConfigSheet({
    required this.companies,
    required this.companiesError,
    required this.onRetryCompanies,
  });

  /// 自社を除いた会社候補（company_id / company_name）。
  final List<Map<String, dynamic>> companies;
  final String? companiesError;
  final Future<void> Function() onRetryCompanies;

  @override
  State<_SendConfigSheet> createState() => _SendConfigSheetState();
}

class _SendConfigSheetState extends State<_SendConfigSheet> {
  final Set<String> _receiverIds = <String>{};
  String _axis = 'date';
  bool _includePhotos = false;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _memoCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  String _nameOf(String id) => widget.companies
      .firstWhere((c) => (c['company_id'] ?? '').toString() == id,
          orElse: () => const {})['company_name']
      ?.toString() ??
      '(名称不明)';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim();
    final shown = q.isEmpty
        ? widget.companies
        : widget.companies
            .where((c) => (c['company_name'] ?? '').toString().contains(q))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: FieldTokens.textFaint,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 12),
        const Text('送信設定',
            style: TextStyle(
                color: FieldTokens.textBody,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        Expanded(
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              // (a) 送信先
              const Text('送信先',
                  style: TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (widget.companiesError != null) ...[
                Row(children: [
                  Expanded(
                    child: Text(
                        '送信先の候補を取得できませんでした（${widget.companiesError}）',
                        style: const TextStyle(
                            color: FieldTokens.statusError, fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () async {
                      await widget.onRetryCompanies();
                      if (context.mounted) setState(() {});
                    },
                    child: const Text('再試行',
                        style: TextStyle(color: FieldTokens.accent)),
                  ),
                ]),
              ] else if (_receiverIds.isEmpty)
                const Text('送信先を1社以上選んでください',
                    style: TextStyle(
                        color: FieldTokens.textSupport, fontSize: 12))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _receiverIds
                      .map((id) => Chip(
                            backgroundColor: FieldTokens.surfaceRaised,
                            side: const BorderSide(color: FieldTokens.accent),
                            label: Text(_nameOf(id),
                                style: const TextStyle(
                                    color: FieldTokens.textBody,
                                    fontSize: 12)),
                            deleteIcon: const Icon(Icons.close,
                                size: 16, color: FieldTokens.textSupport),
                            onDeleted: () =>
                                setState(() => _receiverIds.remove(id)),
                          ))
                      .toList(),
                ),
              const SizedBox(height: 10),
              TextField(
                style:
                    const TextStyle(color: FieldTokens.textBody, fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '会社名で絞り込む',
                  hintStyle:
                      TextStyle(color: FieldTokens.textHint, fontSize: 13),
                  prefixIcon: Icon(Icons.search,
                      size: 18, color: FieldTokens.textSupport),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: FieldTokens.outline)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: FieldTokens.accent)),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 4),
              if (widget.companies.isEmpty && widget.companiesError == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('送信できる会社がありません',
                      style: TextStyle(
                          color: FieldTokens.textSupport, fontSize: 13)),
                )
              else
                for (final c in shown)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _receiverIds
                        .contains((c['company_id'] ?? '').toString()),
                    activeColor: FieldTokens.accent,
                    checkColor: FieldTokens.onAccent,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text((c['company_name'] ?? '(名称不明)').toString(),
                          style: const TextStyle(
                              color: FieldTokens.textBody, fontSize: 14)),
                    ),
                    onChanged: (v) => setState(() {
                      final id = (c['company_id'] ?? '').toString();
                      if (v == true) {
                        _receiverIds.add(id);
                      } else {
                        _receiverIds.remove(id);
                      }
                    }),
                  ),
              const Divider(height: 24, color: FieldTokens.outline),

              // (b) まとめ方（BE bundles.js の VALID_AXES の3値）
              const Text('まとめ方',
                  style: TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'date', label: Text('時系列')),
                  ButtonSegment(value: 'site', label: Text('現場別')),
                  ButtonSegment(value: 'worker', label: Text('職人別')),
                ],
                selected: {_axis},
                onSelectionChanged: (s) => setState(() => _axis = s.first),
              ),
              const Divider(height: 24, color: FieldTokens.outline),

              // (c) 写真
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: FieldTokens.accent,
                title: const Text('写真も含める',
                    style: TextStyle(
                        color: FieldTokens.textBody, fontSize: 14)),
                subtitle: const Text('送信先も写真を閲覧できます',
                    style: TextStyle(
                        color: FieldTokens.textSupport, fontSize: 12)),
                value: _includePhotos,
                onChanged: (v) => setState(() => _includePhotos = v),
              ),
              const Divider(height: 24, color: FieldTokens.outline),

              // (d) タイトル / メモ（任意）
              TextField(
                controller: _titleCtrl,
                style:
                    const TextStyle(color: FieldTokens.textBody, fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'タイトル（任意）',
                  labelStyle:
                      TextStyle(color: FieldTokens.textSupport, fontSize: 13),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: FieldTokens.outline)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: FieldTokens.accent)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _memoCtrl,
                maxLines: 3,
                style:
                    const TextStyle(color: FieldTokens.textBody, fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'メモ（任意）',
                  labelStyle:
                      TextStyle(color: FieldTokens.textSupport, fontSize: 13),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: FieldTokens.outline)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: FieldTokens.accent)),
                ),
              ),
            ],
          ),
        ),
        // (e) 次へ（宛先0件で無効）
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _receiverIds.isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop(_SendConfig(
                          receiverIds: _receiverIds.toList(),
                          axis: _axis,
                          includePhotos: _includePhotos,
                          title: _titleCtrl.text.trim(),
                          memo: _memoCtrl.text.trim(),
                        )),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('送信内容を確認する'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FieldTokens.accent,
                  foregroundColor: FieldTokens.onAccent,
                  disabledBackgroundColor: FieldTokens.outlineStrong,
                  disabledForegroundColor: FieldTokens.textFaint,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
