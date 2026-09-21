// ============================================================
// lib/screens/rest_day_screen.dart - 本日休み（登録・修正 兼用）
// 色は必ず field_tokens.dart のトークン（FieldTokens）を使う。
// Color(0x 直書き・Colors.* は使わない。
// ============================================================

import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import '../services/reports_service.dart';
import '../main.dart' show showJsSnackbar;
import '../widgets/comp_off_dialog.dart';
import 'rest_day_done_screen.dart';
import 'substitute_detail_screen.dart' show showSubstituteNotice;
import 'substitute_register_screen.dart';

// 理由4値（null=未選択）。表示ラベルと BE キーの対応。
const List<Map<String, String>> _kReasons = [
  {'key': 'paid_leave',     'label': '有給'},
  {'key': 'absence',        'label': '欠勤'},
  {'key': 'company_closed', 'label': '会社休業'},
  {'key': 'personal',       'label': '私用'},
];

// 区分3値（既定=full）。単一選択・解除不可（必ずどれか1つ）。
const List<Map<String, String>> _kPortions = [
  {'key': 'full',    'label': '終日'},
  {'key': 'am_half', 'label': '午前休'},
  {'key': 'pm_half', 'label': '午後休'},
];

const List<String> _kWeekdayJa = ['月', '火', '水', '木', '金', '土', '日'];

class RestDayScreen extends StatefulWidget {
  const RestDayScreen({
    super.key,
    this.editMode = false,
    this.initialReason,
    this.initialPortion = 'full',
    this.service,
  });

  final bool editMode;          // false=新規登録 / true=修正
  final String? initialReason;  // 修正モードの初期 reason（null許容）
  final String initialPortion;  // 修正モードの初期 portion（full/am_half/pm_half）

  /// 口の差し替え（検査だけが渡す）。既定は null＝今までどおり ReportsService()。
  ///   ★形も理由も substitute_list_screen.dart の同じ引数の★と同じ【Q70】。
  ///   ★呼び出し側は editMode / initialReason / initialPortion しか渡しておらず、
  ///     1文字も変わらない。
  final ReportsService? service;

  @override
  State<RestDayScreen> createState() => _RestDayScreenState();
}

class _RestDayScreenState extends State<RestDayScreen> {
  // ★本番は今までどおり ReportsService()。差し替えを渡すのは検査だけ。
  late final ReportsService _svc = widget.service ?? ReportsService();

  String? _selectedReason;
  String _selectedPortion = 'full';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 新規=未選択 / 修正=現在のreason
    _selectedReason = widget.editMode ? widget.initialReason : null;
    // 区分: 新規=終日(full) / 修正=現在のportion
    _selectedPortion = widget.editMode ? widget.initialPortion : 'full';
  }

  String _dateLabel() {
    final d = DateTime.now(); // 端末JST（表示用）
    final w = _kWeekdayJa[d.weekday - 1]; // weekday: 1=月..7=日
    return '${d.month}月${d.day}日（$w）';
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = widget.editMode
          ? await _svc.updateRestDay(reason: _selectedReason, portion: _selectedPortion)
          : await _svc.createRestDay(reason: _selectedReason, portion: _selectedPortion);

      final ok = res.ok;
      // 新規登録で 409 ALREADY_RESTED は「既に休み」なので成功扱い（ねぎらい画面へ）。
      final alreadyRested = !widget.editMode &&
          (res.statusCode == 409 || res.errorCode == 'ALREADY_RESTED');

      if (ok || alreadyRested) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => RestDayDoneScreen(
              reason: _selectedReason,
              portion: _selectedPortion,
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      // ★statusCode:0 ＝ サーバまで届かなかった。統一前は例外時に statusCode を
      //   積んでいなかったため「（N）」が付かなかった。同じ見た目を保つため 0 は出さない。
      showJsSnackbar(
        context,
        '${res.errorMessage ?? '休みの登録に失敗しました'}'
        '${res.statusCode != 0 ? '（${res.statusCode}）' : ''}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 代休（入口①）が持つ「休む日」──────────────────────────
  //  ★この画面が唯一の持ち主。部品（showCompOffFlow）は受け取るだけで、
  //    自分では日を決めない（同じ日付を2箇所で決めない）。
  //  ★既定は今日。上の「本日休み」と同じ日から始めるのが自然で、
  //    別の日を取りたいときだけ人が選び直す。
  DateTime _compOffDate = DateTime.now();

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _compOffDateLabel() {
    final w = _kWeekdayJa[_compOffDate.weekday - 1];
    return '${_compOffDate.month}月${_compOffDate.day}日（$w）';
  }

  // 別の日を選ぶ。★showDatePicker は FIELD の既存3箇所（profile_screen /
  //   share_send_screen ×2）と同じ使い方。新しい日付部品は作らない。
  //   先の日を選べるのは、代休が「これから取る休み」だから
  //   （BE の代休の口は当日・前日の制限を持たない）。
  Future<void> _pickCompOffDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _compOffDate,
      // 過去は前日まで（BE は実在日なら受けるが、遡って休みを作る運用は
      // 「本日休み」と同じく事務の仕事なのでここでは開けない）。
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (picked == null || !mounted) return;
    setState(() => _compOffDate = picked);
  }

  // ★_busy は立てない。この画面の _busy は「この画面から通信を出している最中」の印で、
  //   立てると本体の主ボタンが回るスピナーに変わる。代休の受け皿はモーダルで
  //   画面全体を覆うため二度押しは起きず、立てる意味が無いうえに
  //   「休みを登録する」を押したときと同じ見た目になって取り違える。
  Future<void> _openCompOff() async {
    final took = await showCompOffFlow(context, restDate: _ymd(_compOffDate));
    if (!mounted || !took) return;
    // 取れたらホームへ戻す（ホームが休みの状態を取り直す）。
    // ★「本日休み」の登録が done 画面へ進むのとは道を分ける。代休は
    //   今日とは限らないので、今日のねぎらい画面へ入れると嘘になる。
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ── 振替の日（入口②が持つ）────────────────────────────────
  //  ★代休の日（_compOffDate）とは別に持つ。同じ変数を使い回すと、代休の日を
  //    選び直したつもりで振替の日まで動く（1つの値に2つの意味を持たせない）。
  DateTime _substituteDate = DateTime.now();

  String _substituteDateLabel() {
    final w = _kWeekdayJa[_substituteDate.weekday - 1];
    return '${_substituteDate.month}月${_substituteDate.day}日（$w）';
  }

  // 別の日を選ぶ。★日付部品の使い方も選べる範囲も代休の _pickCompOffDate と
  //   同じに揃える（同じ画面に2通りの日の選び方を作らない）。
  Future<void> _pickSubstituteDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _substituteDate,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (picked == null || !mounted) return;
    setState(() => _substituteDate = picked);
  }

  // 振替で休む。★手前に注意書き（B2）を挟む。使うのは1件の画面が既に持っている
  //   showSubstituteNotice ただ1本で、同じ注意書きの写しをここに作らない。
  Future<void> _openSubstitute() async {
    if (!await showSubstituteNotice(context)) return;
    if (!mounted) return;
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SubstituteRegisterScreen(
        restDate: _ymd(_substituteDate),
        service: widget.service,
      ),
    ));
    if (!mounted || done != true) return;
    // 登録できたらホームへ戻す。★ホームが休みの状態・カレンダー・要対応の件数を
    //   取り直す道（代休の _openCompOff とまったく同じ＝数が古いまま残らない）。
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _cancelRest() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        title: const Text('本日の休み登録を取り消しますか？',
            style: TextStyle(color: FieldTokens.textBody, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('戻る', style: TextStyle(color: FieldTokens.textSupport)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('取消する',
                style: TextStyle(color: FieldTokens.statusWarning)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final res = await _svc.deleteRestDay();
      if (res.ok) {
        if (!mounted) return;
        Navigator.of(context).popUntil((r) => r.isFirst); // ホームへ（スタックを畳む）
        return;
      }
      if (!mounted) return;
      showJsSnackbar(
        context,
        '${res.errorMessage ?? '取り消しに失敗しました'}'
        '${res.statusCode != 0 ? '（${res.statusCode}）' : ''}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 代休／振替の主ボタン（横に2つ並べる）────────────────────
  //  ★中は2行。上＝種類名（代休／振替・太字）、下＝その日付。
  //    種類名をいちばん目立たせるのは、賃金の扱いが違う2つを取り違えないため。
  //  ★半分の幅に「代休で休む（12月31日（水））」は1行に入らないので、
  //    種類名と日付を縦に分けた（文字を削らずに幅へ収める）。
  Widget _entryButton({
    required IconData icon,
    required String kind,
    required String date,
    required VoidCallback? onPressed,
  }) =>
      SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: FieldTokens.textBody,
            side: const BorderSide(color: FieldTokens.textBody, width: 1.5),
            // ★半分の幅しか無いので、左右の余白は既定より詰める。
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(date, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      );

  // ── 「別の日」（横に2つ並べる）──────────────────────────────
  //  ★見た目の文字は2つとも「別の日」。どちらの日かは上のボタンの真下という
  //    位置で分かる。目で見えない読み上げには label で手がかりを渡す。
  Widget _anotherDayButton({
    required String semanticsLabel,
    required VoidCallback? onPressed,
  }) =>
      SizedBox(
        height: 44, // 押せる部品は 44pt 以上
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(minimumSize: Size.zero),
          child: Semantics(
            label: semanticsLabel,
            excludeSemantics: true,
            child: const Text('別の日',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.surfaceCard,
        foregroundColor: FieldTokens.textBody,
        elevation: 0,
        title: const Text('本日休み'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          // ★上下を 24 → 16 に詰める。左右 20 はそのまま（1画面に収めるため）。
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 日付表示（端末JST・表示用）
              Text(
                _dateLabel(),
                style: const TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // 区分チップ3択（単一選択・解除不可＝必ずどれか1つ。既定=終日）
              const Text('区分',
                  style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _kPortions.map((p) {
                  final selected = _selectedPortion == p['key'];
                  return ChoiceChip(
                    label: Text(p['label']!),
                    selected: selected,
                    showCheckmark: false,
                    backgroundColor: FieldTokens.surfaceCard,
                    selectedColor: FieldTokens.outlineStrong,
                    side: BorderSide(
                        color: selected
                            ? FieldTokens.outlineStrong
                            : FieldTokens.outline),
                    labelStyle: TextStyle(
                      color: selected ? FieldTokens.textBody : FieldTokens.textSupport,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    // 解除不可: 常に選択キーを設定（再タップでも維持）
                    onSelected: (_) => setState(() => _selectedPortion = p['key']!),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              const Text('理由（任意）',
                  style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
              const SizedBox(height: 8),

              // 理由チップ4択（単一選択・再タップで解除）
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _kReasons.map((r) {
                  final selected = _selectedReason == r['key'];
                  return ChoiceChip(
                    label: Text(r['label']!),
                    selected: selected,
                    showCheckmark: false,
                    backgroundColor: FieldTokens.surfaceCard,
                    selectedColor: FieldTokens.outlineStrong,
                    side: BorderSide(
                        color: selected
                            ? FieldTokens.outlineStrong
                            : FieldTokens.outline),
                    labelStyle: TextStyle(
                      color: selected ? FieldTokens.textBody : FieldTokens.textSupport,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() {
                      // 再タップで解除（未選択に戻る）
                      _selectedReason = selected ? null : r['key'];
                    }),
                  );
                }).toList(),
              ),

              const SizedBox(height: 8),
              // ★同じ意味のまま1行に収まる長さにした（1画面に収めるため）。
              const Text(
                '※理由は任意。有給は事務の確認後に記録へ反映',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 12),
              ),

              // ── 代休・振替（この画面の本体とは別の休み）──────────
              //  ★この画面の本体（今日・区分3値・理由4値・「休みを登録する」）には
              //    1つも手を入れていない。下に増設しただけ＝従来の道はそのまま通る。
              //  ★なぜ本体に混ぜないか: この画面は「本日」固定で、理由も
              //    有給/欠勤/会社休業/私用 の4値に固定されている（_kReasons）。
              //    代休は理由が comp_off で4値に無く、休む日も今日とは限らない。
              //    振替も同じで、BE の口（POST /rest-days/substitute）は
              //    まるごと1日しか受け付けず reason は 'substitute' 固定。
              //    同じチップの列に並べると「今日の私用」と同じ操作に見えるのに
              //    送り先も規則も違う、という嘘になる。
              //  ★2つを【横に並べて1つの節】にまとめた。以前は縦に2節あり、
              //    実機でスクロールしないと「休みを登録する」まで届かなかった。
              //    賃金の扱いが違う2つなので、種類名（代休／振替）をいちばん
              //    目立たせて取り違えを防ぐ。日付はその下に小さく添える。
              //  ★日はそれぞれの入口が持つ（既定＝今日／別の日も選べる）。
              //  ★修正モード（既に休みが登録されている日を開いている）では出さない。
              //    その日は既に休みなので、代休も振替も BE が ALREADY_RESTED で
              //    断るだけ＝押せるのに必ず失敗するボタンを置かない。
              if (!widget.editMode) ...[
                const SizedBox(height: 16),
                const Divider(color: FieldTokens.outline, height: 1),
                const SizedBox(height: 12),
                const Text('代休・振替',
                    style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
                const SizedBox(height: 8),

                // 1行目＝主ボタンを横に2つ。左＝代休・右＝振替。
                Row(
                  children: [
                    Expanded(
                      child: _entryButton(
                        icon: Icons.event_repeat,
                        kind: '代休',
                        date: _compOffDateLabel(),
                        onPressed: _busy ? null : _openCompOff,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _entryButton(
                        icon: Icons.swap_horiz,
                        kind: '振替',
                        date: _substituteDateLabel(),
                        onPressed: _busy ? null : _openSubstitute,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 2行目＝「別の日」を横に2つ。左＝代休・右＝振替（上の行と同じ並び）。
                Row(
                  children: [
                    Expanded(
                      child: _anotherDayButton(
                        // ★見た目は「別の日」だけ。同じ文字のボタンが2つ並ぶので、
                        //   読み上げにはどちらの日かが分かる手がかりを残す。
                        semanticsLabel: '代休を別の日にする',
                        onPressed: _busy ? null : _pickCompOffDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _anotherDayButton(
                        semanticsLabel: '振替を別の日にする',
                        onPressed: _busy ? null : _pickSubstituteDate,
                      ),
                    ),
                  ],
                ),
              ],

              // ★「別の日」の行（または修正モードでは※）と主ボタンの間。
              const SizedBox(height: 24),

              // 主ボタン（accent面・onAccent文字・高さ52）
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  // 生成り抜き（画面内の主ボタン）
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: FieldTokens.textBody,
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor:
                        FieldTokens.textFaint,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ).copyWith(
                    side: WidgetStateProperty.resolveWith((states) =>
                        BorderSide(
                          color: states.contains(WidgetState.disabled)
                              ? FieldTokens.textFaint
                              : FieldTokens.textBody,
                          width: 1.5,
                        )),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          // 面が透明になったのでスピナーも枠色（生成り）へ
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: FieldTokens.textFaint))
                      : Text(
                          widget.editMode ? '変更を保存' : '休みを登録する',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              // 修正モードのみ：休みを取り消す
              if (widget.editMode) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _cancelRest,
                  child: const Text('休みを取り消す',
                      style: TextStyle(color: FieldTokens.statusWarning)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
