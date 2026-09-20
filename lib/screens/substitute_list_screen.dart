// ============================================================
// lib/screens/substitute_list_screen.dart - 振替休日の一覧
//
// 承認済みモック field_substitute_flow_mock_v4.html の A2。
// ホームの要対応「振替休日」と、通知・カレンダーの「振替休日を開く」から来る。
//
// ★この便は【見る側だけ】。同意する・休む日を変える・申し出を取り下げる・取り消す、の
//   操作は次の便で足す。操作が無くても状態と記録は全部出す。
//   ★「近く使えます」の類の空約束は書かない。押しても何も起きない行も作らない
//     （行を押すと1件の画面へ必ず進む）。
//
// ★出どころは GET /rest-days/my/substitutes ただ1本。月は渡さない。
//   BE が返すのは (a) 本人が動く番（同意待ち・成立できない）と
//   (b) これからの成立済み だけ。取消済と過去の成立済みは【BE が返さない】ので、
//   この画面で落とす細工は1つも要らない。
//
// ★節の分け方は BE が返した action_needed ただ1つで決める。
//   上＝「あなたの番」（action_needed が true）／下＝「これからの振替」（残り）。
//   ★端末で reason や日付から組み立て直さない。並びも BE が返した順のまま
//     （BE は rest_date 昇順・id 昇順で返す）。端末で並べ替えない。
//
// 色は FieldTokens のみ（直書き禁止・新しい色を作らない）。
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../services/api_result.dart';
import '../services/reports_service.dart';
import 'substitute_detail_screen.dart';

/// 'YYYY-MM-DD' → 'M月D日'。★Date を経由しない（切って先頭のゼロを落とすだけ）。
///   形式が違うものは黙って化けさせず、そのまま返す。
String jpMonthDay(String? ymd) {
  if (ymd == null || ymd.isEmpty) return '—';
  final p = ymd.split('-');
  if (p.length != 3) return ymd;
  final m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  if (m == null || d == null) return ymd;
  return '$m月$d日';
}

/// ISO の日時 → 'M月D日'（JST）。パース不能は '—'。
String jpMonthDayOfIso(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '—';
  final jst = dt.toUtc().add(const Duration(hours: 9));
  return '${jst.month}月${jst.day}日';
}

/// 行の状態。★BE が返した印だけで決める（3つのどれか）。
///   ・同意待ち       … pending_agreement
///   ・成立できません … change_blocked（BE が返す真偽）
///   ・成立           … 残り
///
/// ★change_blocked を読む形に直した（2026-09-20）。それまでは
///   「action_needed が true かつ pending_agreement でない」という【差集合】で
///   導いていた。答えは同じでも、それは BE が持っている判定を端末でも組み立て直す形で、
///   片方だけ直せる二重真実になる（BE が action_needed の意味を広げた日に、この画面だけ
///   黙って嘘をつく）。印はサーバが1本で出し、端末は読むだけにする。
/// ★change_blocked を返さない回（BE の別便が入る前の古いサーバー）は
///   キーが無く null になる＝この式は false になり「成立できません」を出さない。
///   端末で change_deadline と今日を比べて作り直さない（作った瞬間に判定が2箇所になる）。
String substituteStateLabel(Map<String, dynamic> r) {
  if (r['pending_agreement'] == true) return '同意待ち';
  if (r['change_blocked'] == true) return '成立できません';
  return '成立';
}

/// 状態の色。★意味の色だけを使う（FieldTokens の外に作らない）。
///   ★語（substituteStateLabel）と同じ条件を同じ順で見る。片方だけ直すと
///     「成立できません」が緑で出るような食い違いが起きる。
Color substituteStateColor(Map<String, dynamic> r) {
  if (r['pending_agreement'] == true) return FieldTokens.statusWarning;
  if (r['change_blocked'] == true) return FieldTokens.statusError;
  return FieldTokens.statusSuccess;
}

/// 「誰がいつ登録したか」の1行。
///   ・事務が持ちかけた行 … proposed_at が在る。氏名は BE の proposed_by_name。
///     ★proposed_by_name が無い回（BE の別便が入る前）は名前なしで出す。
///       端末で名前を作らない・行ごと落とさない。
///   ・本人が自分で立てた行 … proposed_at が null。BE が返す created_at（登録の日時）で
///     「M月D日 に自分で登録」と出す（2026-09-20）。それまでは日付を出せる列が
///     応答に1つも無く、持ちかけの行だけ日付が出る＝同じ一覧に2通りの書き方があった。
///     ★created_at が無い回（古いサーバー）や日時として読めない回は、日付を書かず
///       「自分で登録」とだけ出す。端末で今日から作ると【嘘の日付】になる。
String substituteRegisteredLine(Map<String, dynamic> r) {
  final at = r['proposed_at'];
  if (at == null) {
    final created = r['created_at'];
    // jpMonthDayOfIso は読めないものを '—' で返す。'—' は日付ではないので出さない。
    final day = created == null ? '—' : jpMonthDayOfIso('$created');
    return day == '—' ? '自分で登録' : '$day に自分で登録';
  }
  final name = r['proposed_by_name'];
  final who = (name == null || '$name'.isEmpty) ? '事務' : '事務 $name さん';
  return '${who}が ${jpMonthDayOfIso('$at')} に登録';
}

/// 2つの節へ分ける。★分け方は BE が返した action_needed ただ1つ。
///   ・yours    … あなたの番（action_needed が true）
///   ・upcoming … これからの振替（残り）
///   ★どちらも BE が返した【順のまま】。端末で並べ替えない。
///   ★純関数にしてあるのは、画面を立てずに検査できるようにするため
///     （この本の家風＝画面は実HTTPへ行くので立てない）。
({List<Map<String, dynamic>> yours, List<Map<String, dynamic>> upcoming})
    splitSubstituteRows(List<Map<String, dynamic>> rows) => (
      yours: rows.where((r) => r['action_needed'] == true).toList(),
      upcoming: rows.where((r) => r['action_needed'] != true).toList(),
    );

class SubstituteListScreen extends StatefulWidget {
  const SubstituteListScreen({super.key, this.service});

  /// 口の差し替え（検査だけが渡す）。
  ///   ★なぜ要るか【Q70】: この画面は initState から実 HTTP へ行くので、
  ///     渡す口が無いと「0件の文が出るか」「取れなかった回に理由が出るか」を
  ///     1つも測れない。測れないまま出すのは、直したつもりで直っていない形。
  ///   ★形は ReportsService が既に持っている差し替えの入口
  ///     （@visibleForTesting ReportsService.forTest()）に乗せるだけ。
  ///     新しい仕組みは作らない。
  ///   ★既定は null＝今までどおり ReportsService() を使う。だから呼び出し側
  ///     （home_screen.dart の const SubstituteListScreen()）は1文字も変わらない。
  ///     ★const のまま置けるよう、ここでは既定値を作らずに null を持つ
  ///       （コンストラクタで ReportsService() を呼ぶと const が外れ、呼び出し側が壊れる）。
  final ReportsService? service;

  @override
  State<SubstituteListScreen> createState() => _SubstituteListScreenState();
}

class _SubstituteListScreenState extends State<SubstituteListScreen> {
  bool _loading = true;
  String? _error;                 // null = 失敗していない
  List<Map<String, dynamic>> _rows = const [];
  bool _truncated = false;

  /// 実際に叩く口。★本番は今までどおり ReportsService()。
  late final ReportsService _api = widget.service ?? ReportsService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final ApiResult<Map<String, dynamic>> res = await _api.getMySubstitutes();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!res.ok) {
        // ★0件に倒さない。取れなかったことを取れなかったと言う。
        //   文言は BE が返したものを優先（規約2＝サーバの言い分を丸めない）。
        _error = res.errorMessage ?? '振替休日を取得できませんでした';
        _rows = const [];
        _truncated = false;
        return;
      }
      final d = res.data ?? const <String, dynamic>{};
      _rows = ((d['rows'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _truncated = d['truncated'] == true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        title: const Text('振替休日'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final err = _error;
    if (err != null) {
      // 取れなかった回は理由と「もう一度」（黙って空にしない）。
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(err,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FieldTokens.textSupport)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('もう一度')),
            ],
          ),
        ),
      );
    }

    if (_rows.isEmpty) {
      // 0件は黙らない（「無い」と「取れていない」を読み分けられるようにする）。
      return const Center(
        child: Text('いまは振替休日はありません',
            style: TextStyle(color: FieldTokens.textSupport)),
      );
    }

    // ★節の分けは action_needed ただ1つ。並びは BE が返した順のまま。
    final parts = splitSubstituteRows(_rows);
    final yours = parts.yours;
    final upcoming = parts.upcoming;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (yours.isNotEmpty) ...[
          const _SectionHeader('あなたの番'),
          for (final r in yours) _SubstituteRow(row: r, onTap: () => _open(r)),
        ],
        if (upcoming.isNotEmpty) ...[
          const _SectionHeader('これからの振替'),
          for (final r in upcoming) _SubstituteRow(row: r, onTap: () => _open(r)),
        ],
        // ★天井で切れた回は黙らない（「これで全部」と言い切らない）。
        if (_truncated)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('※件数が多いため、ここに出ているのは一部です。',
                style: TextStyle(color: FieldTokens.textFaint, fontSize: 12)),
          ),
      ],
    );
  }

  Future<void> _open(Map<String, dynamic> r) async {
    final id = '${r['id'] ?? ''}';
    if (id.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      // ★印（成立できません）は渡さない。1件の口が同じ真偽を返すようになったので、
      //   一覧から開いても通知・カレンダーから開いても同じ状態に見える。
      //   差し替え口だけは下ろす（検査が一覧→1件の道をそのまま辿れるように）。
      builder: (_) => SubstituteDetailScreen(
        restDayId: id,
        service: widget.service,
      ),
    ));
    if (!mounted) return;
    await _load(); // 戻ったら BE の真実へ追随
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Text(label,
            style: const TextStyle(
                color: FieldTokens.textSupport,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      );
}

class _SubstituteRow extends StatelessWidget {
  const _SubstituteRow({required this.row, required this.onTap});
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = substituteStateColor(row);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: FieldTokens.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(substituteStateLabel(row),
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('休む日　　${jpMonthDay('${row['rest_date'] ?? ''}')}',
                      style: const TextStyle(
                          color: FieldTokens.textBody, fontSize: 15)),
                  Text('出勤する日　${jpMonthDay('${row['paired_work_date'] ?? ''}')}',
                      style: const TextStyle(
                          color: FieldTokens.textBody, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(substituteRegisteredLine(row),
                      style: const TextStyle(
                          color: FieldTokens.textFaint, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: FieldTokens.textFaint, size: 20),
          ],
        ),
      ),
    );
  }
}
