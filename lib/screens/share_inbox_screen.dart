// ============================================================
// lib/screens/share_inbox_screen.dart — 受信トレイ（FIELD）
//
// 導線: 共有タブ（share_hub_screen.dart）の「受信トレイ」タイル。
//
// BE: GET /bundles/receipts（BundlesService.getReceipts）。
//   ・1階層・日報ごと1行・時系列。並びは BE が
//     sent_at DESC → report_date DESC → worker_name ASC で確定させている
//     （routes/bundles.js の GET /bundles/receipts の ORDER BY）ので FE で並べ替え直さない。
//   ・会社絞りは sender_company_id（会社IDで絞る＝同名会社を文字列一致で
//     混ぜないための裁定Q11。表示名は sender_company_name）。
//
// 行の印（ボス裁定＝3段階）:
//   ① 改ざん … receipt_status == 'tampered'（改ざん検知）
//               または is_updated == true（送信後に原本が変更された）
//   ② 既読   … read_at != null
//   ③ 未読   … 上のどちらでもない
//   ★①の2つは同じ枠・同じ色・同じ優先順（＝3段階のまま）だが、言葉は分ける。
//     'tampered' を「原本変更」と呼ぶのも、単なる更新を「改ざん」と呼ぶのも
//     どちらも嘘になるため（BE も 'tampered' と 'updated' を別の値として持つ・
//     routes/bundles.js の PATCH /bundles/receipts/:receipt_id/read）。
//
// 確認済みにする: 各行の印の【直下】に置く（POST /bundles/:bundle_id/confirm）。
//   ★確認は【束単位・人単位】。1回押すと同じ束に属する行が全て確認済みになるので、
//     成功後は一覧を取り直して全行へ反映する。
//   ★確認済みかどうかは受信明細（GET /receipts）に無い（日報単位の confirmed は
//     存在しない＝裁定Q10）。GET /bundles/inbox の my_confirmed_at を bundle_id で
//     引いて出す。取得は一覧本体と切り離す（fail-soft＝落ちても一覧は出す）。
//   ★処理鍵が無い人にもボタンは出し、タップ時に案内する（袋小路にしない）。
//     束詳細（share_bundle_detail_screen.dart）の「確認済みにする」は温存＝そちらは
//     束の全体を見ながら押す口として残す。
//
// 現場紐付け: 各行に置く（PATCH /bundles/receipts/:id/site）。
//   未設定→「現場を紐付け」／設定済→「変更」＋「解除」（解除は確認1回）。
//   ★処理鍵（can_share_manage）が無い人がタップしたら案内を出す＝袋小路にしない。
//     最終門番は BE（bundles.js の blockShareManager）。
// ============================================================

import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import '../services/bundles_service.dart';
import '../services/site_service.dart';
import '../main.dart' show showJsSnackbar;
import 'share_receipt_detail_screen.dart';

/// 処理鍵が無い人へ出す文言。共有の「処理できない」はこの1文だけで言う
/// （同じ事象を2つの言い方で説明しない）。share_receipt_detail_screen も参照する。
const String kShareManageDeniedMessage =
    '共有を処理する権限がありません（『共有処理』が必要）';

/// 日付（YYYY-MM-DD / ISO）→「MM/DD」。解析できなければ元の文字列をそのまま出す。
String fmtShareDate(Object? raw) {
  final s = (raw ?? '').toString();
  if (s.isEmpty) return '-';
  final dt = DateTime.tryParse(s);
  if (dt == null) return s;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(dt.month)}/${p(dt.day)}';
}

/// 日時（ISO）→ JST「MM/DD HH:mm」（端末TZ=Asia/Tokyo前提）。
/// tamper_incident_detail_screen.dart の _fmtJst と同じ整形。
String fmtShareDateTime(Object? raw) {
  final s = (raw ?? '').toString();
  if (s.isEmpty) return '-';
  final dt = DateTime.tryParse(s)?.toLocal();
  if (dt == null) return s;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(dt.month)}/${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
}

/// 行の印。3段階（改ざん / 既読 / 未読）。
enum ReceiptMark { tampered, read, unread }

ReceiptMark receiptMarkOf(Map<String, dynamic> r) {
  if (r['receipt_status'] == 'tampered' || r['is_updated'] == true) {
    return ReceiptMark.tampered;
  }
  return r['read_at'] == null ? ReceiptMark.unread : ReceiptMark.read;
}

class ShareInboxScreen extends StatefulWidget {
  const ShareInboxScreen({super.key, required this.canManage});

  /// 処理鍵（can_share_manage 相当）。共有タブが GET /profile から判定して渡す
  /// ＝この画面で鍵を取り直さない（同じ事実を2箇所で取らない）。
  final bool canManage;

  @override
  State<ShareInboxScreen> createState() => _ShareInboxScreenState();
}

class _ShareInboxScreenState extends State<ShareInboxScreen> {
  final BundlesService _svc = BundlesService();
  final SiteService _sites = SiteService();

  List<Map<String, dynamic>> _receipts = const [];
  bool _loading = true;
  String? _error;
  String? _companyFilter;      // null＝すべて。値は sender_company_id
  String? _busyReceiptId;      // 紐付け処理中の行（連打を止める）

  // 束ごとの確認状態（bundle_id -> my_confirmed_at）。
  //   ★受信明細（GET /receipts）の18キーに confirmed は【無い】
  //     （bundles_service.dart の「日報単位の confirmed は存在しない＝裁定Q10」）。
  //     確認は束単位・人単位の事実なので、GET /bundles/inbox の my_confirmed_at
  //     （同ファイルの「confirmed_count / my_confirmed_at だけは【人数・人単位】」）を
  //     bundle_id で引く。門番は受信箱と同じ blockShareViewer＝新たな鍵は要らない。
  //   ★取れなかった場合は空のまま＝未確認扱いでボタンを出す。確認は冪等
  //     （同ファイルの「二度押しても値は動かない」）なので害が無く、隠す方が袋小路になる。
  Map<String, String?> _confirmedByBundle = const {};
  String? _confirmingBundleId; // 確認処理中の束（連打よけ・行の出し分けにも使う）

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final r = await _svc.getReceipts();
    // 束の確認状態を併せて取る（_confirmedByBundle のコメント参照）。
    //   ★一覧の成否とは切り離す（fail-soft）。こちらが落ちても受信トレイは出す
    //     ＝確認状態だけが分からなくなる。一覧ごと消える方がはるかに困る。
    final inbox = await _svc.getInbox();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _confirmedByBundle = {
        for (final b in (inbox.ok ? (inbox.data ?? const []) : const []))
          (b['bundle_id'] ?? '').toString(): b['my_confirmed_at'] as String?,
      };
      if (r.ok) {
        _receipts = r.data ?? const [];
        _error = null;
        // 絞り込み中の会社が消えていたら「すべて」へ戻す（存在しない絞りを残さない）。
        if (_companyFilter != null &&
            !_receipts.any((e) => e['sender_company_id'] == _companyFilter)) {
          _companyFilter = null;
        }
      } else {
        _receipts = const [];
        // 権限・通信断・その他を混ぜない（規約6＝statusCode と errorCode で言い切る）。
        _error = r.statusCode == 403
            ? (r.errorMessage ?? '共有を見る権限がありません')
            : r.statusCode == 0
                ? '通信できませんでした'
                : (r.errorMessage ?? '受信トレイを取得できませんでした');
      }
    });
  }

  // ── 会社絞り（sender_company_id）─────────────────────────────
  // 選択肢は取得済みの受信明細から作る（会社一覧APIは叩かない＝届いていない会社を
  // 選べる形にしない）。並びは会社名昇順で安定させる。
  List<({String id, String name})> get _companies {
    final map = <String, String>{};
    for (final r in _receipts) {
      final id = (r['sender_company_id'] ?? '').toString();
      if (id.isEmpty) continue;
      map[id] = (r['sender_company_name'] ?? '(会社名なし)').toString();
    }
    final list = map.entries.map((e) => (id: e.key, name: e.value)).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  List<Map<String, dynamic>> get _visible => _companyFilter == null
      ? _receipts
      : _receipts.where((e) => e['sender_company_id'] == _companyFilter).toList();

  // ── 確認済みにする（束単位・行カードから直接押す）────────────────
  // ★確認は【束単位・人単位】（bundles_service.dart の confirmBundle）。同じ束に属する行が
  //   複数あれば1回押すと全行が確認済みになる。だから成功後は _load() で取り直し、
  //   bundle_id で引き直す（行ごとに別々の確認状態を持たせない）。
  // ★鍵が無い人はボタンを隠さずタップ時に案内する（_onTapLink と同じ流儀＝
  //   袋小路にしない。最終門番は BE の blockShareManager）。
  Future<void> _onTapConfirm(Map<String, dynamic> r) async {
    if (!widget.canManage) {
      showJsSnackbar(context, kShareManageDeniedMessage, isError: true);
      return;
    }
    final bundleId = (r['bundle_id'] ?? '').toString();
    if (bundleId.isEmpty || _confirmingBundleId != null) return;

    // 押し間違いで相手に伝わらないよう確認を1回挟む（_confirmUnlink と同じ型）。
    final yes = await _confirmSend((r['sender_company_name'] ?? '').toString());
    if (yes != true || !mounted) return;

    setState(() => _confirmingBundleId = bundleId);
    final res = await _svc.confirmBundle(bundleId);
    if (!mounted) return;
    setState(() => _confirmingBundleId = null);

    if (res.ok) {
      showJsSnackbar(context, '確認済みにしました');
      // 束単位＝同じ束の全行が確認済みになる。取り直して全行へ反映する。
      await _load();
      return;
    }
    // 非200を握り潰さない（規約6＝statusCode と errorCode で言い切る）。
    //   分岐は share_bundle_detail_screen.dart（同じ confirm の呼び手）と同型。
    final String msg;
    if (res.statusCode == 403) {
      msg = res.errorMessage ?? kShareManageDeniedMessage;
    } else if (res.statusCode == 404) {
      msg = 'この共有は自社宛ではないため確認できません';
    } else if (res.statusCode == 0) {
      msg = '通信できませんでした';
    } else {
      msg = res.errorMessage ?? '確認済みにできませんでした';
    }
    showJsSnackbar(context, msg, isError: true);
  }

  Future<bool?> _confirmSend(String companyName) => showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: FieldTokens.surfaceCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: const Text('確認済みにしますか？',
              style: TextStyle(
                  color: FieldTokens.textBody, fontWeight: FontWeight.bold)),
          content: Text(
            companyName.trim().isEmpty
                ? '送信元に「確認済」と表示されます。この共有に含まれる日報すべてが確認済みになります。'
                : '「${companyName.trim()}」に「確認済」と表示されます。'
                    'この共有に含まれる日報すべてが確認済みになります。',
            style: const TextStyle(
                color: FieldTokens.textSupport, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
              child: const Text('キャンセル',
                  style: TextStyle(color: FieldTokens.textSupport)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dctx).pop(true),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(112, 44),
                backgroundColor: FieldTokens.accent,
                foregroundColor: FieldTokens.onAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('確認済みにする'),
            ),
          ],
        ),
      );

  // ── 現場紐付け ───────────────────────────────────────────
  Future<void> _onTapLink(Map<String, dynamic> r) async {
    if (!widget.canManage) {
      showJsSnackbar(context, kShareManageDeniedMessage, isError: true);
      return;
    }
    final receiptId = (r['receipt_id'] ?? '').toString();
    if (receiptId.isEmpty || _busyReceiptId != null) return;

    final linked = (r['link_site_id'] ?? '').toString().isNotEmpty;
    final choice = await _pickSite(r, alreadyLinked: linked);
    if (choice == null || !mounted) return;   // キャンセル

    // 解除は確認1回（付け間違いを戻せる口だが、黙って外さない）。
    if (choice.unlink) {
      final ok = await _confirmUnlink(
          (r['link_site_name'] ?? '').toString());
      if (ok != true || !mounted) return;
    }

    setState(() => _busyReceiptId = receiptId);
    final res = await _svc.linkReceiptSite(
      receiptId: receiptId,
      siteId: choice.unlink ? null : choice.siteId,
    );
    if (!mounted) return;
    setState(() => _busyReceiptId = null);

    if (res.ok) {
      // 応答の receipt / site_name を信じて手元の行だけ差し替える（全件再取得しない）。
      final receipt = res.data?['receipt'];
      setState(() {
        r['link_site_id'] =
            receipt is Map ? receipt['site_id'] : (choice.unlink ? null : choice.siteId);
        r['link_site_name'] = res.data?['site_name'];
      });
      showJsSnackbar(context,
          (res.data?['message'] ?? (choice.unlink ? '現場の紐付けを解除しました' : '現場を紐づけました'))
              .toString());
      return;
    }
    // 非200を握り潰さない。
    final String msg;
    if (res.statusCode == 403) {
      msg = res.errorMessage ?? kShareManageDeniedMessage;
    } else if (res.statusCode == 404) {
      msg = '対象の現場または受信明細が見つかりません';
    } else if (res.statusCode == 0) {
      msg = '通信できませんでした';
    } else {
      msg = res.errorMessage ?? '現場を紐付けできませんでした';
    }
    showJsSnackbar(context, msg, isError: true);
  }

  /// 現場選択シート。戻り値 null＝キャンセル。
  Future<({String? siteId, bool unlink})?> _pickSite(
      Map<String, dynamic> r, {required bool alreadyLinked}) async {
    final sr = await _sites.getSites();
    if (!mounted) return null;
    if (!sr.ok) {
      showJsSnackbar(
          context,
          sr.statusCode == 0
              ? '通信できませんでした'
              : (sr.errorMessage ?? '現場一覧を取得できませんでした'),
          isError: true);
      return null;
    }
    final sites = (sr.data ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return showModalBottomSheet<({String? siteId, bool unlink})>(
      context: context,
      backgroundColor: FieldTokens.surfaceCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (bctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(children: [
                Icon(Icons.place, color: FieldTokens.accent, size: 18),
                SizedBox(width: 8),
                Text('自社の現場を選ぶ',
                    style: TextStyle(
                        color: FieldTokens.textBody,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
            // 送信社が書いた現場名・報告場所を「候補を選ぶ材料」として出す
            // （BE が gps_address を応答に載せている理由・裁定Q9）。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '送信社の現場名: ${_s(r['site_name'])}\n報告場所: ${_s(r['gps_address'])}',
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12, height: 1.5),
                ),
              ),
            ),
            const Divider(height: 1, color: FieldTokens.outline),
            if (sites.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('自社の現場が登録されていません',
                    style: TextStyle(
                        color: FieldTokens.textSupport, fontSize: 13)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sites.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: FieldTokens.outline),
                  itemBuilder: (_, i) {
                    final s = sites[i];
                    final id = (s['site_id'] ?? '').toString();
                    final selected = id == (r['link_site_id'] ?? '').toString();
                    return ListTile(
                      title: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(_s(s['site_name']),
                            style: const TextStyle(
                                color: FieldTokens.textBody, fontSize: 14)),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check,
                              color: FieldTokens.accent, size: 18)
                          : null,
                      onTap: () => Navigator.of(bctx)
                          .pop((siteId: id, unlink: false)),
                    );
                  },
                ),
              ),
            if (alreadyLinked) ...[
              const Divider(height: 1, color: FieldTokens.outline),
              ListTile(
                leading: const Icon(Icons.link_off,
                    color: FieldTokens.statusWarning, size: 20),
                title: const Text('紐付けを解除する',
                    style: TextStyle(
                        color: FieldTokens.statusWarning, fontSize: 14)),
                onTap: () =>
                    Navigator.of(bctx).pop((siteId: null, unlink: true)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmUnlink(String siteName) => showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: FieldTokens.surfaceCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: const Text('紐付けを解除',
              style: TextStyle(
                  color: FieldTokens.textBody, fontWeight: FontWeight.bold)),
          content: Text(
            siteName.isEmpty
                ? 'この日報の現場の紐付けを解除します。'
                : '「$siteName」との紐付けを解除します。',
            style: const TextStyle(
                color: FieldTokens.textSupport, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
              child: const Text('キャンセル',
                  style: TextStyle(color: FieldTokens.textSupport)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dctx).pop(true),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(112, 44),
                backgroundColor: FieldTokens.statusWarning,
                foregroundColor: FieldTokens.onStatusWarning,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('解除する'),
            ),
          ],
        ),
      );

  // ── 日報を開く（開いた瞬間に自動既読は詳細画面側が行う）──────────
  Future<void> _openReceipt(Map<String, dynamic> r) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShareReceiptDetailScreen(
        receipt: Map<String, dynamic>.from(r),
        canManage: widget.canManage,
      ),
    ));
    if (!mounted) return;
    // ★戻ったら必ず取り直す（結果を pop の戻り値で受け取らない）。
    //   詳細画面は開いた瞬間に既読を打つので、ほぼ必ず状態が変わっている。
    //   「変わったか」を戻り値で運ぶ形にすると、端末の戻るジェスチャ（値を返せない）
    //   で戻ったときだけ一覧が古いまま残る＝印が嘘になる経路が生まれる。
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        foregroundColor: FieldTokens.accent,
        title: const Text('受信トレイ'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: FieldTokens.accent))
          : _error != null
              ? _errorView()
              : Column(children: [
                  if (_companies.length > 1) _filterBar(),
                  Expanded(child: _list()),
                ]),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: FieldTokens.statusError),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 15)),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('再試行'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FieldTokens.accent,
                    side: const BorderSide(color: FieldTokens.accent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  // 会社絞り。2社以上届いているときだけ出す（1社しか無い画面に絞りを置かない）。
  Widget _filterBar() => Container(
        width: double.infinity,
        color: FieldTokens.surfaceCard,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _chip('すべて', _companyFilter == null,
                () => setState(() => _companyFilter = null)),
            for (final c in _companies) ...[
              const SizedBox(width: 8),
              _chip(c.name, _companyFilter == c.id,
                  () => setState(() => _companyFilter = c.id)),
            ],
          ]),
        ),
      );

  Widget _chip(String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            // 選択中の面は outlineStrong（accent 面は上の textBody が 1.37:1 で読めない
            // ＝field_tokens.dart の outlineStrong の実測理由に従う）。
            color: active ? FieldTokens.outlineStrong : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: active ? FieldTokens.accent : FieldTokens.outline),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? FieldTokens.textBody : FieldTokens.textSupport,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal)),
        ),
      );

  Widget _list() {
    final rows = _visible;
    if (rows.isEmpty) {
      return RefreshIndicator(
        color: FieldTokens.accent,
        backgroundColor: FieldTokens.surfaceCard,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 320,
              child: Center(
                child: Text(
                  _companyFilter == null
                      ? '届いている日報はありません'
                      : 'この会社から届いている日報はありません',
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: FieldTokens.accent,
      backgroundColor: FieldTokens.surfaceCard,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: rows.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: FieldTokens.outline),
        itemBuilder: (_, i) => _ReceiptRow(
          receipt: rows[i],
          busy: _busyReceiptId == (rows[i]['receipt_id'] ?? '').toString(),
          // 確認状態は束単位。行ではなく bundle_id で引く。
          confirmedAt:
              _confirmedByBundle[(rows[i]['bundle_id'] ?? '').toString()],
          confirming: _confirmingBundleId ==
              (rows[i]['bundle_id'] ?? '').toString(),
          onTap: () => _openReceipt(rows[i]),
          onTapLink: () => _onTapLink(rows[i]),
          onTapConfirm: () => _onTapConfirm(rows[i]),
        ),
      ),
    );
  }
}

String _s(Object? v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? '-' : s;
}

// ─── 受信明細1行 ──────────────────────────────────────────
class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.receipt,
    required this.busy,
    required this.confirmedAt,
    required this.confirming,
    required this.onTap,
    required this.onTapLink,
    required this.onTapConfirm,
  });

  final Map<String, dynamic> receipt;
  final bool busy;

  /// この行が属する束の確認時刻（null＝未確認）。束単位・人単位の事実。
  final String? confirmedAt;

  /// この行が属する束が確認処理中か。
  final bool confirming;
  final VoidCallback onTap;
  final VoidCallback onTapLink;
  final VoidCallback onTapConfirm;

  @override
  Widget build(BuildContext context) {
    final mark = receiptMarkOf(receipt);
    final linkedName = (receipt['link_site_name'] ?? '').toString().trim();
    final linked = (receipt['link_site_id'] ?? '').toString().isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: mark == ReceiptMark.unread
            ? FieldTokens.surfaceCard
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1段目: 送信元会社 ＋ 印
            Row(children: [
              const Icon(Icons.business,
                  size: 13, color: FieldTokens.externalBlue),
              const SizedBox(width: 5),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_s(receipt['sender_company_name']),
                      style: const TextStyle(
                          color: FieldTokens.externalBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              // 印（3段階・裁定は不変）と、その【直下】に確認の導線を置く。
              //   ★印を4段階にするものではない（印は _MarkBadge のまま）。
              //     確認は束単位・人単位の別の事実なので、段を分けて出す。
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MarkBadge(mark: mark, receipt: receipt),
                  const SizedBox(height: 8),
                  _ConfirmCell(
                    confirmedAt: confirmedAt,
                    confirming: confirming,
                    onTap: onTapConfirm,
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 6),
            // 2段目: 日付・職人
            Row(children: [
              Text(fmtShareDate(receipt['report_date']),
                  style: const TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_s(receipt['worker_name']),
                      style: const TextStyle(
                          color: FieldTokens.textBody, fontSize: 13)),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            // 3段目: 送信社が書いた現場名
            Row(children: [
              const Icon(Icons.place_outlined,
                  size: 12, color: FieldTokens.textSupport),
              const SizedBox(width: 4),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_s(receipt['site_name']),
                      style: const TextStyle(
                          color: FieldTokens.textSupport, fontSize: 12)),
                ),
              ),
            ]),
            // 4段目: 提出時刻（report_created_at＝日報の提出時刻。束の作成時刻ではない）
            const SizedBox(height: 4),
            Text('提出 ${fmtShareDateTime(receipt['report_created_at'])}',
                style: const TextStyle(
                    color: FieldTokens.textFaint, fontSize: 11)),
            const SizedBox(height: 8),
            // 5段目: 自社の現場紐付け（各行に置く）
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onTapLink,
                icon: Icon(linked ? Icons.link : Icons.add_link, size: 15),
                label: Text(
                  busy
                      ? '処理中…'
                      : linked
                          ? '自社現場: ${linkedName.isEmpty ? "設定済み" : linkedName}（変更）'
                          : '現場を紐付け',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      linked ? FieldTokens.accent : FieldTokens.textSupport,
                  side: BorderSide(
                      color:
                          linked ? FieldTokens.accent : FieldTokens.outline),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 確認済みにする／確認済み（束単位・印の直下）───────────────────
// 未確認の束 → ボタン／確認済みの束 → 印（_MarkBadge と同じ枠の流儀）。
//   ★確認は【人単位】（my_confirmed_at）。既読が会社単位なのと粒度が違うため、
//     印（既読/未読）と同じ段には並べず、下の段に分けている。
class _ConfirmCell extends StatelessWidget {
  const _ConfirmCell({
    required this.confirmedAt,
    required this.confirming,
    required this.onTap,
  });

  final String? confirmedAt;
  final bool confirming;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = (confirmedAt ?? '').isNotEmpty;
    if (done) {
      // 確認済みの印。_MarkBadge と同じ枠・同じ作り（淡い地＋枠＋文字）。
      const c = FieldTokens.statusSuccess;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('確認済 ${fmtShareDateTime(confirmedAt)}',
              style: const TextStyle(
                  color: c, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      );
    }
    return SizedBox(
      height: 44, // タッチターゲット44pt以上
      child: OutlinedButton.icon(
        onPressed: confirming ? null : onTap,
        icon: confirming
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: FieldTokens.accent))
            : const Icon(Icons.check_circle_outline, size: 15),
        label: Text(confirming ? '処理中…' : '確認済みにする',
            style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: FieldTokens.accent,
          side: const BorderSide(color: FieldTokens.accent),
          // ★横の最小幅をゼロ起点へ明示的に戻す。app_theme.dart の elevatedButtonTheme / outlinedButtonTheme が
          //   minimumSize: Size(double.infinity, 52) を課しており、Row/Column の
          //   横方向に無制約な文脈へ置くと「幅＝無限」を要求して
          //   BoxConstraints forces an infinite width で落ちる（bba77ef の実害と同じ罠）。
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

// ─── 行の印（3段階）───────────────────────────────────────
class _MarkBadge extends StatelessWidget {
  const _MarkBadge({required this.mark, required this.receipt});

  final ReceiptMark mark;
  final Map<String, dynamic> receipt;

  @override
  Widget build(BuildContext context) {
    late final Color c;
    late final String label;
    switch (mark) {
      case ReceiptMark.tampered:
        c = FieldTokens.statusError;
        // 同じ枠でも言葉は分ける（'tampered' と 'updated' は別の事実）。
        label = receipt['receipt_status'] == 'tampered' ? '改ざん' : '原本変更';
      case ReceiptMark.unread:
        c = FieldTokens.statusWarning;
        label = '未読';
      case ReceiptMark.read:
        c = FieldTokens.textFaint;
        label = '既読';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c),
      ),
      child: Text(label,
          style: TextStyle(
              color: c, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
