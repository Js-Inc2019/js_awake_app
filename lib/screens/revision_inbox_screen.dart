// lib/screens/revision_inbox_screen.dart - 是正依頼受信画面
import 'package:flutter/material.dart';
import '../main.dart' show showJsSnackbar;
import '../core/theme/field_tokens.dart';
import 'revision_edit_screen.dart';
// 作業3: 移動手段の複数対応。既存の transportNamesOf を再利用する（新設しない）。
import '../utils/revision_parser.dart' show transportNamesOf;
import '../widgets/report_photos.dart';
import '../services/auth_service.dart';
import '../services/reports_service.dart';
// 「今日やる仕事」に載せる条件は lib/utils/report_cancel_gate.dart の1本だけを使う。
import '../utils/report_cancel_gate.dart'
    show isRevisionRequested, reportStatusOf;
// 状態→色も1本だけを使う。この画面に色の割り当てを手書きしない
// （手書きだったせいで、同じ差戻しが月間履歴では赤・ここでは橙になっていた）。
import '../utils/report_status_style.dart' show reportStatusStyleForState;

class RevisionInboxScreen extends StatefulWidget {
  const RevisionInboxScreen({super.key});
  @override
  State<RevisionInboxScreen> createState() => _RevisionInboxScreenState();
}

class _RevisionInboxScreenState extends State<RevisionInboxScreen> {
  final GlobalKey<RevisionInboxBodyState> _bodyKey =
      GlobalKey<RevisionInboxBodyState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('是正依頼'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _bodyKey.currentState?.reload()),
        ],
      ),
      body: RevisionInboxBody(key: _bodyKey),
    );
  }
}

// タブ埋め込み用: Scaffold/AppBar を持たない本体（S2で承認・是正タブに束ねる）
class RevisionInboxBody extends StatefulWidget {
  // isForeman は呼び出し元（home_screen.dart の ForemanHomeScreen は true / RevisionInboxScreen は既定 false）
  // との互換のため構造上残すが、タップ分岐は「提出者本人か」の判定に切替済みで参照しない。
  //   本人（rev['user_id']==自分）→ RevisionEditScreen（編集・再提出）
  //   本人以外（職長が他人の差戻しを見る等）→ ReportDetailSheet（閲覧）
  const RevisionInboxBody({super.key, this.isForeman = false});
  final bool isForeman;
  @override
  State<RevisionInboxBody> createState() => RevisionInboxBodyState();
}

class RevisionInboxBodyState extends State<RevisionInboxBody> {
  List<Map<String, dynamic>> _revisions = [];
  bool _loading = true;
  bool _hasError = false;
  // 本人判定用の現在ユーザーID（prefs 'user_id' = 提出者 reports.user_id と同一体系）。
  // 取得失敗/未取得(null)時は「本人でない」に倒す＝編集を誤開放しない（フェイルセーフ）。
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _loadMyUserId();
    _load();
  }

  Future<void> _loadMyUserId() async {
    final uid = await AuthService().getUserId();
    if (!mounted) return;
    setState(() => _myUserId = uid);
  }

  // 外部（AppBar等）からの再読込用に公開
  void reload() => _load();

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    // 既定 10 秒＝移設前と同じ。home_screen の件数バッジは同じメソッドを
    // _withRetry（60秒起点）で包んで呼ぶ（ReportsService.getRevisionRequested）。
    final r = await ReportsService().getRevisionRequested();
    if (!mounted) return;
    if (r.ok) {
      setState(() {
        // ★取消済は載せない。BE の GET /reports?revision_requested=true は
        //   取消済を除外せず（js-office-api routes/reports.js の GET '/' は
        //   revision_requested の条件しか足さない）、取消は revision_requested を
        //   落とさない（同 PATCH /cancel は status だけを書く）。
        //   除外しないと、取り消した日報が是正依頼として残り、開いても
        //   BE が「この日報は取消済みです」と断るだけの空振りになる。
        // ★取り消した日報そのものは消えていない。履歴の「取消」で選べば
        //   一覧に出るし、カレンダーの日を選べば「日報を確認」から見られる
        //   （行き止まりを作らない）。
        _revisions = (r.data ?? const [])
            .map((e) => e as Map<String, dynamic>)
            .where(isRevisionRequested)
            .toList();
        _loading = false;
      });
    } else if (r.statusCode == 0) {
      // 通信不成立＝移設前の catch 相当（スナックバーを出す経路）。
      showJsSnackbar(context, '差し戻し一覧の取得に失敗しました。再度お試しください。', isError: true);
      setState(() { _loading = false; _hasError = true; });
    } else {
      // 非200＝移設前の else 相当（スナックバーは出さずエラー表示のみ）。
      setState(() { _loading = false; _hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator(color: FieldTokens.accent))
        : _hasError
            ? _errorView()
            : _revisions.isEmpty
                ? _emptyView()
                : RefreshIndicator(
                onRefresh: _load,
                color: FieldTokens.accent,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _revisions.length,
                  itemBuilder: (ctx, i) {
                    final rev = _revisions[i];
                    // 本人判定: 提出者(user_id)==自分 のときのみ編集へ。
                    // _myUserId が null（取得失敗/未取得）や不一致は「本人でない」＝閲覧側へ倒す
                    // （編集画面へは本人のみ＝フェイルセーフ。職長が他人の差戻しを見る場合も閲覧）。
                    final isMine =
                        _myUserId != null && rev['user_id'] == _myUserId;
                    return RevisionCard(
                      revision: rev,
                      isMine: isMine,
                      onResubmit: () async {
                        if (!isMine) {
                          // 本人以外 → 読み取り専用の詳細（現状維持）。
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: FieldTokens.surfaceCard,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            builder: (_) => ReportDetailSheet(report: rev),
                          );
                          return;
                        }
                        // 本人 → 編集・再提出（職長本人でも到達＝袋小路解消）。
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RevisionEditScreen(revision: rev),
                          ),
                        );
                        if (result == true) _load();
                      },
                    );
                  },
                ),
              );
  }

  Widget _emptyView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, color: FieldTokens.textSupport, size: 64),
          SizedBox(height: 16),
          Text('差し戻しはありません',
              style: TextStyle(color: FieldTokens.textSupport, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: FieldTokens.statusError, size: 64),
          const SizedBox(height: 16),
          const Text('取得に失敗しました',
              style: TextStyle(color: FieldTokens.statusError, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _load,
            // 生成り抜き（画面内の主ボタン）
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: FieldTokens.textBody,
              side: const BorderSide(
                  color: FieldTokens.textBody, width: 1.5),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('再試行'),
          ),
        ],
      ),
    );
  }
}

// 公開化（承認タブの日付一覧画面から同一実体を呼ぶため）。中身は1行も変更していない。
class RevisionCard extends StatelessWidget {
  const RevisionCard({super.key, required this.revision, required this.onResubmit, this.isMine = false});
  final Map<String, dynamic> revision;
  final VoidCallback onResubmit;
  final bool isMine; // 提出者本人か（本人=編集導線／他人=閲覧導線）

  @override
  Widget build(BuildContext context) {
    final reportDate  = revision['report_date'] as String? ?? '';
    final workContent = revision['work_content'] as String? ?? '';
    final bossNote    = revision['boss_note'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: FieldTokens.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FieldTokens.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('日報: $reportDate',
                style: const TextStyle(color: FieldTokens.textBody, fontWeight: FontWeight.bold)),
            if (workContent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                workContent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: FieldTokens.textBody, fontSize: 12),
              ),
            ],
            if (bossNote.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FieldTokens.statusWarning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.comment_outlined, size: 14, color: FieldTokens.accent),
                      SizedBox(width: 6),
                      Text('差戻し理由',
                          style: TextStyle(color: FieldTokens.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 6),
                    Text(bossNote, style: const TextStyle(color: FieldTokens.textBody, fontSize: 13)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onResubmit,
                icon: Icon(isMine ? Icons.send : Icons.visibility, size: 16),
                label: Text(isMine ? '直して再提出' : '詳細を見る'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FieldTokens.accent,
                  side: const BorderSide(color: FieldTokens.accent),
                  minimumSize: const Size(0, 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 読み取り専用 日報詳細ボトムシート（承認待ち／差戻し・職長文脈で共用）
//   作業内容全文 / メモ / 現場住所・移動手段・駐車料金 / 承認状態・承認時刻(JST) /
//   提出時刻(JST) / 差戻し履歴(boss_note＝事務の修正依頼・worker_revision_note＝職人の再提出メモ) /
//   写真(ReportPhotos)。操作ボタンは持たない（承認/修正依頼は既存カードのボタンで行う）。
//   ※ worker_revision_note は一覧API(LIST_COLS)に含まれないため、応答に存在する時のみ表示。
// ─────────────────────────────────────────────
class ReportDetailSheet extends StatelessWidget {
  const ReportDetailSheet({super.key, required this.report});
  final Map<String, dynamic> report;

  // JST「MM/DD HH:mm」整形（端末TZ=Asia/Tokyo前提・生ISO禁止）。null/不正は null。
  static String? _jst(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(dt.month)}/${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    final date     = r['report_date'] as String? ?? '';
    // ★状態は report_cancel_gate の判定1本で決める。ここに条件を手書きすると
    //   同じ式の4本目になり、取消済の扱いだけがこの画面に届かない形が残る。
    // ★色も report_status_style の対応表1本から採る。ここに switch を書かない。
    //   直す前はこの画面だけが独自の割り当てを持っていて、
    //     ・差戻し … statusWarning（橙）。月間履歴の JsReportTile は statusError（赤）。
    //     ・取消済 … textSupport（温グレー）。既定の未承認と同じ色で見分けが付かない。
    //   となっており、同じ状態が画面によって違う色で出ていた。
    //   対応表へ寄せた結果、この画面では差戻しが橙から赤へ、取消済が温グレーから
    //   藤へ、未承認が温グレーから橙へ変わる。見た目が変わるのは承知の裁定。
    // ★語（'取消済' '承認済' '差戻し' '未承認'）はこの場のものをそのまま残す。
    //   4語とも対応表と同じ文字列だが、語を対応表から採るかどうかは今回の対象外
    //   なので、色だけを寄せる（monthly_history_screen.dart の _DateRow と同じやり方）。
    final status = reportStatusOf(r);
    const Map<String, String> labels = <String, String>{
      'cancelled': '取消済',
      'approved':  '承認済',
      'rejected':  '差戻し',
      'pending':   '未承認',
    };
    final Color sc = reportStatusStyleForState(status).color;
    final String sl = labels[status] ?? '未承認';

    // ★これは状態の判定ではなく「承認時刻の行を出すか」の判定。
    //   取消は approved を落とさないので、取消済でも承認された事実と時刻は残る。
    //   記録として残す裁定どおり、ここは取消済でも出したままにする。
    final approved   = r['approved'] == true;
    final reportId   = r['report_id'] as String? ?? r['id'] as String? ?? '';
    final submitted  = _jst(r['created_at'] as String?);
    final approvedAt = _jst(r['approved_at'] as String?);
    final approvedBy = (r['approved_by'] as String?)?.trim() ?? '';
    final work       = (r['work_content'] as String?)?.trim() ?? '';
    final memo       = (r['memo'] as String?)?.trim() ?? '';
    final gps        = (r['gps_address'] as String?)?.trim() ?? '';
    // 作業3: 複数選択に対応（'・' 区切り）
    final trans      = transportNamesOf(r).join('・');
    final parking    = r['parking_fee'];
    final bossNote   = (r['boss_note'] as String?)?.trim() ?? '';
    final workerNote = (r['worker_revision_note'] as String?)?.trim() ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: FieldTokens.outline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(date, style: const TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: sc),
                  ),
                  child: Text(sl,
                      style: TextStyle(color: sc, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            // ★開いた詳細にも取消済の印を出す。右上のバッジだけだと文字が小さく、
            //   取り消された日報が普通の日報に見える＝これも嘘の記号になる。
            //   文言・アイコン・色は一覧の行（monthly_history_screen.dart の
            //   JsReportTile）と同じものを使う（画面ごとに言い換えない）。
            // ★この画面には押せる操作が1つも無い（下は読み取り専用の行と写真だけ）。
            //   操作を足すときは day_reports_screen.dart の先例
            //   （取消済のときだけボタンを引っ込める）に従うこと。
            if (status == 'cancelled') ...[
              const SizedBox(height: 10),
              const Row(children: [
                Icon(Icons.cancel_outlined,
                    color: FieldTokens.textSupport, size: 14),
                SizedBox(width: 6),
                Expanded(
                  child: Text('取消済（日報は残ります）',
                      style: TextStyle(
                          color: FieldTokens.textSupport,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
            ],
            const SizedBox(height: 14),
            if (submitted != null) _row(Icons.schedule, '提出時刻', submitted),
            if (approved && approvedAt != null)
              _row(Icons.event_available, '承認時刻',
                  approvedBy.isNotEmpty ? '$approvedAt（$approvedBy）' : approvedAt),
            _row(Icons.work_outline, '作業内容', work.isEmpty ? '（未入力）' : work),
            if (memo.isNotEmpty) _row(Icons.sticky_note_2_outlined, 'メモ', memo),
            if (gps.isNotEmpty) _row(Icons.location_on_outlined, '現場住所', gps),
            if (trans.isNotEmpty) _row(Icons.directions_car_outlined, '移動手段', trans),
            if (parking != null && parking.toString().isNotEmpty)
              _row(Icons.local_parking, '駐車料金', '¥$parking'),
            // 差戻し履歴
            if (bossNote.isNotEmpty)
              _noteBox('事務からの修正依頼', bossNote, FieldTokens.accent, Icons.feedback_outlined),
            if (workerNote.isNotEmpty)
              _noteBox('職人の再提出メモ', workerNote, FieldTokens.textSupport, Icons.reply),
            const SizedBox(height: 12),
            const Text('写真', style: TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
            const SizedBox(height: 6),
            ReportPhotos(reportId: reportId, report: r),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: FieldTokens.accent, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: FieldTokens.textSupport, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(color: FieldTokens.textBody, fontSize: 14, height: 1.4)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _noteBox(String title, String body, Color color, IconData icon) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: FieldTokens.textBody, fontSize: 13, height: 1.5)),
      ],
    ),
  );
}
