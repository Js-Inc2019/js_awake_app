// lib/widgets/report_form_parts.dart
// 日報のフォームの部品（今日の日報のフォームから動かした物）。
//
// ★何か：今日の日報のフォームと確認の画面が使う部品17個（画面の部品16個と、確認の画面の材料の入れ物 ReportSnapshot）と、目安の字・経費を組む関数3つ。
//   便F8b-1（2026-10-08）で、lib/screens/home_screen.dart から、ここへ動かした。コードの直しは、本の頭の読み込みのほかに3つだけ
//   （名前を替えた＝部品と関数は公開の名・State の3つは非公開のまま新しい名／画面の部品16個の作り口に任意の key を足した／
//   確認の画面の差の見張りの区切りの1字を目に見える書き方にした）。説明文は、事実と違った所を直した（直した所に、日付と便の名を書いてある）。
// ★誰が使うか：lib/screens/home_screen.dart（今日の日報のフォーム・確認の画面・休憩の短縮のシート）と、
//   lib/widgets/report_form_steps.dart（段の部品）。次の便で、過去の日の日報を出す画面も使う。
// ★この本には、動かした物のほかにコードを足さない（新しく書く物は lib/widgets/report_form_steps.dart へ）。

import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import '../main.dart' show TransportType, SpeechManager, showJsSnackbar;
import '../services/routes_service.dart';
import '../services/site_service.dart';
import 'search_suggest_field.dart';

/// セクション見出し。
/// ※ 旧 alert 引数（琥珀の「必須」バッジ）は作業内容の必須化撤回に伴い削除した。
///   元: 現場カード側の「必須」バッジは ReportSiteSelectField が自前で持っている。
///   →再（2026-10-08・便F8b-1）: その印も撤去済み（ReportSiteSelectField の★の説明）。この本の部品に、自前で「必須」の印を持つ物は無い。
class ReportSectionHeader extends StatelessWidget {
  const ReportSectionHeader(this.title, {super.key});
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

/// カード内の小ラベル（例：「出発地」「移動手段」。元の説明の「どこから」「なにで」は前の字＝2026-10-08・便F8b-1 で今の字に直した）
class ReportFieldLabel extends StatelessWidget {
  const ReportFieldLabel(this.text, {super.key});
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
class ReportFormCard extends StatelessWidget {
  const ReportFormCard({super.key, required this.child});
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

/// カード内の入力欄の外装（アイコン+高さ46の帯。元の説明の「高さ44」は実物と違った＝2026-10-08・便F8b-1 で実物の値に直した）
class ReportFormInputShell extends StatelessWidget {
  const ReportFormInputShell({super.key, required this.icon, required this.child});
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
class ReportOutlineActionButton extends StatelessWidget {
  const ReportOutlineActionButton({
    super.key,
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
//   ・「確認」(4) は別画面 ReportConfirmScreen。フォーム内で current=4 にはならない。
// ─────────────────────────────────────────────
class ReportStepIndicator extends StatelessWidget {
  const ReportStepIndicator({super.key, required this.current});

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
/// 主ボタン(ReportOutlineActionButton)と高さ56を揃え、面は塗らない＝序列を枠と色だけで示す。
class ReportStepBackButton extends StatelessWidget {
  const ReportStepBackButton({super.key, required this.onTap});
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
class ReportSnapshot {
  const ReportSnapshot({
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

  /// 相乗り相手のラベル。会社名・氏名のどちらか一方でもあれば「会社名　氏名」。
  /// 両方空なら空文字（＝相乗りを選んでいない or 未入力）。
  String get carpoolLabel =>
      [carpoolCompany, carpoolName].where((s) => s.isNotEmpty).join('　');

  // 差の見張りの鍵。7つの値＝現場ID・移動手段・作業内容・ルート金額・駐車料金・相乗りの会社名・相乗りの氏名。
  //   元: 「差異検知は4項目に限定: 現場ID・移動手段・作業内容・金額（ルート金額+駐車料金）」（carpoolLabel の説明の上に書いてあった）
  //   →再（2026-10-08・便F8b-1）: 作業4 で相乗りの2つを足してあり、実物は7つ。区切りは、目に見えない1字（U+0001）。
  // 作業4: 差異検知に相乗り2項目を追加（金額・移動に加えて相乗りの変更も検知する）。
  String get diffKey => [
        siteId ?? '',
        transportKey,
        workContent,
        routeCostKey,
        parkingFeeRaw,
        carpoolCompany,
        carpoolName,
      ].join('\u0001');
}

// ─────────────────────────────────────────────
// 確認画面（2段タップの2段目）
// ─────────────────────────────────────────────
class ReportConfirmScreen extends StatefulWidget {
  const ReportConfirmScreen({
    super.key,
    required this.initial,
    required this.currentOf,
    required this.onSend,
    required this.isDone,
  });

  /// 「内容を確認する」を押した時点の静止画（元の説明は前の字「内容を確かめる」＝2026-10-08・便F8b-1 で直した）
  final ReportSnapshot initial;
  /// 現在stateから作り直すための取得口（送信直前の差異検知に使う）
  final ReportSnapshot Function() currentOf;
  /// 実送信。従来どおり現在stateを読む _submit をそのまま呼ぶ
  final Future<void> Function() onSend;
  /// 送信が成立したか（_todayReportDone）。成立時のみ画面を閉じる
  final bool Function() isDone;

  @override
  State<ReportConfirmScreen> createState() => _ReportConfirmScreenState();
}

class _ReportConfirmScreenState extends State<ReportConfirmScreen> {
  late ReportSnapshot _snap = widget.initial;
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
    // _submit が途中で止めた時は _todayReportDone が立たない＝ここでは閉じない。
    //   元: 「（移動手段未選択・駐車写真ダイアログで戻る等）は…閉じずにこの画面へ留まる」
    //   →再（2026-10-08・便F8b-1）: その2つの道は、呼び手の _jumpToStep が先にこの画面を閉じる（移動の段へ戻す）。
    //   この画面に留まるのは、氏名が取れていない時と、_submit の中で例外が出た時（_submit にも、ここにも catch が無い＝例外は、この行まで来ずに外へ抜ける）。どの道でも、ここで二重に閉じる事は無い。
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
                    ReportFormCard(
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
                  ReportOutlineActionButton(
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

// ─────────────────────────────────────────────
// ①' 作業現場 選択欄
//   元: （GPS住所の直下・金枠強調・選択必須バッジ）
//   →再（2026-10-08・便F8b-1）: 今は、枠なし・「必須」の印なし。置く場所は呼び手が決める（今日の日報では、現在地の行の上）。
// ─────────────────────────────────────────────
class ReportSiteSelectField extends StatelessWidget {
  const ReportSiteSelectField({
    super.key,
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
class ReportSitePickerSheet extends StatefulWidget {
  const ReportSitePickerSheet(
      {super.key, required this.selectedSiteId, required this.onSelected});
  final String? selectedSiteId;
  final void Function(String? id, String? name) onSelected;
  @override
  State<ReportSitePickerSheet> createState() => _ReportSitePickerSheetState();
}

class _ReportSitePickerSheetState extends State<ReportSitePickerSheet> {
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

// ─────────────────────────────────────────────
// ③.5 起点選択（自宅 / 会社）
// ─────────────────────────────────────────────
class ReportOriginSelector extends StatelessWidget {
  const ReportOriginSelector({super.key, required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  // v2: 出発地のチップ（元の説明の「どこから」は前の字＝2026-10-08・便F8b-1 で今の字に直した）。onChanged の中身は呼び出し側のまま（await _calculateRoutes() 維持）。
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
class ReportTransportRow extends StatelessWidget {
  const ReportTransportRow({
    super.key,
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

  // v2: 移動手段のチップ（元の説明の「なにで」は前の字＝2026-10-08・便F8b-1 で今の字に直した）。onTap/onDoubleTap の中身（駐車情報リセット・
  // _saveWorkStatus('moving')・_saveDraft）は呼び出し側にそのまま残してある。
  //   →再（2026-10-08・便F8b-1）: 1回押した時の選びの式（排他判定）だけは、呼び出し側から
  //   transportsAfterTap（lib/widgets/report_form_steps.dart）へ出した。
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
// ⑤ 作業内容セクション（マイク / テキスト。元の説明に在った「カメラ」のボタンは、今は無い＝2026-10-08・便F8b-1 で直した）
// ─────────────────────────────────────────────
class ReportWorkContentSection extends StatelessWidget {
  const ReportWorkContentSection({
    super.key,
    required this.controller,
    this.showMediaButtons = false,
    this.isListening = false,
    this.onMicTap,
  });
  final TextEditingController controller;
  final bool showMediaButtons;
  final bool isListening;
  final VoidCallback? onMicTap;

  // v2: カード内に置かれる前提。外枠は ReportFormCard 側が持つので自前の枠は張らない。
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
              ReportSmallMediaButton(
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
// メディアボタン（今の使い手は、マイクの1か所だけ。元の説明は「マイク / カメラ」＝2026-10-08・便F8b-1 で直した）
// ─────────────────────────────────────────────
class ReportSmallMediaButton extends StatelessWidget {
  const ReportSmallMediaButton({
    super.key,
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
class ReportVoiceInputDialog extends StatefulWidget {
  const ReportVoiceInputDialog(
      {super.key,
      required this.manager,
      required this.onConfirm,
      required this.onCancel});
  final SpeechManager manager;
  final void Function(String) onConfirm;
  final VoidCallback onCancel;

  @override
  State<ReportVoiceInputDialog> createState() => _ReportVoiceInputDialogState();
}

class _ReportVoiceInputDialogState extends State<ReportVoiceInputDialog>
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
class ReportRouteInfoBar extends StatelessWidget {
  const ReportRouteInfoBar({
    super.key,
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

    // 表示文言の組み立ては reportRouteParts に一本化（確認画面のスナップショットと同じ値になる）
    final parts = reportRouteParts(transport, comparisons);
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

// ルート表示文言の組み立て。元 ReportRouteInfoBar.build 内の分岐をそのまま関数へ出したもの。
// 判定順・条件・書式は1文字も変えていない（確認画面と表示バーで同じ値を使うため共有化）。
({String? time, String? cost, String? dist}) reportRouteParts(
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
// 判定順・条件・書式を二重に書かないため、要素ごとに上の reportRouteParts をそのまま呼ぶ。
//
// ★train と bus の重複回避（理由）:
//   reportRouteParts は train も bus も同じ comparisons['transit'] を参照する。
//   BE の POST /routes/compare が返すのは route_transit 1本だけで、バス単独の経路検索は
//   存在しない（js-office-api/routes/routes-calc.js は transit と car の2種のみ算出）。
//   したがって train と bus を同時に選ぶと「同一ルートの運賃・所要時間」が2行に
//   重複計上されてしまう。transit を参照する手段は最初の1件だけを残す。
//
// 値が取れない手段も行は残す（dist/cost が null＝表示側で '—'）。
// 「選んだのに行が消える」ほうが利用者には不可解なため。
List<({String label, String? dist, String? cost})> reportRouteBreakdown(
    Set<TransportType> transports, Map<String, dynamic> comparisons) {
  final rows = <({String label, String? dist, String? cost})>[];
  var transitUsed = false;
  for (final t in transports) {
    final usesTransit = t == TransportType.train || t == TransportType.bus;
    if (usesTransit) {
      if (transitUsed) continue;   // 同一 transit ルートの二重計上を防ぐ
      transitUsed = true;
    }
    final p = reportRouteParts(t, comparisons);
    rows.add((label: t.label, dist: p.dist, cost: p.cost));
  }
  return rows;
}

// 作業1: ルート検索結果(_routeComparisons)から【提出時点の経費スナップショット】を作る。
//   ★これは提出した瞬間の値の写し。後から燃費単価や運賃が変わっても、この報告の
//     過去の値は書き換わらない（BE側で reports 列に保存＝不変のスナップショット）。
//   ・4列（distance_km / fuel_cost / fare / toll）は選択中の全手段の【合計】。
//   ・breakdown は手段ごとの【内訳】配列（例: [{mode:'car',distance_km:12.3,...},{mode:'train',fare:620}]）。
//   ・train と bus は同一 transit ルートのため 1件だけ計上（reportRouteBreakdown の transitUsed と同判定）。
//     car と other も同一 comparisons['car'] を指すため 1件だけ計上する
//     （同一ルートの toll/fuel を二重計上しない＝例の内訳が car 1件なのと整合）。
//   ・値が取れない場合は null（0 で埋めない）。合計はどの手段も寄与しなければ null のまま。
({double? distanceKm, int? fuelCost, int? fare, int? toll,
  List<Map<String, dynamic>> breakdown}) reportExpenseSnapshot(
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
