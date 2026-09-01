// lib/utils/report_cancel_gate.dart
// 日報の「取消済かどうか」と、画面が描く4状態の唯一の判定。
//
// ★なぜ1ファイルに集めるか（実際に起きていた事故の形）:
//   BE は取消のとき status を 'cancelled' にするだけで、approved と
//   revision_requested は落とさない（js-office-api routes/reports.js の
//   PATCH /reports/:report_id/cancel は
//   "UPDATE reports SET status = 'cancelled'" ただ1文）。
//   そして一覧の口 GET /reports は取消済を除外しない（同 routes/reports.js の
//   GET '/' は WHERE に status の条件を持たない）。つまり取消済の行は必ず画面へ届く。
//   ところが親の画面3箇所が
//     'status': approved ? 'approved' : revision ? 'rejected' : 'pending'
//   で status を承認の3値へ上書きしていたため、届いた 'cancelled' がそこで消え、
//   取り消した日報が取消前の姿（未承認／承認済）のまま表示されていた。
//   同じ式が3箇所に手書きされていたことが原因なので、式そのものをここへ1本にする。
//   （前例: lib/utils/field_role_gate.dart。判定を各画面に手書きした結果
//     「どこかだけ直し忘れる」形が構造的に残った、という同じ趣旨で作られている。）
//
// ★このファイルは通信も画面も持たない。純粋な関数だけを置く。

/// BE が取消済に立てる値。reports.status はこの1値だけが意味を持つ。
///
/// ★根拠: 新規作成は 'open' で入り
///   （js-office-api routes/reports.js の INSERT INTO reports … VALUES … 'open'）、
///   取消だけが 'cancelled' を書く（同 PATCH /reports/:report_id/cancel）。
///   BE 自身も判定を status === 'cancelled' の一致で行っている
///   （js-office-api lib/reportHash.js computeEffectiveState の1行目）。
///   よって FE も「'cancelled' と一致するか」だけを見る。
///   他の値・null・キー欠落はすべて「取消済ではない」に倒す（値を知らないまま
///   取消済に倒すと、生きている日報が画面から消える方向の嘘になる）。
const String kReportStatusCancelled = 'cancelled';

/// 取消済か。判定はこの1本だけを使い、画面ごとに書かない。
bool isCancelledReport(Map<String, dynamic> r) =>
    r['status']?.toString() == kReportStatusCancelled;

/// 画面が描く状態を1つに決める。返す値は次の4つだけ。
///   'cancelled' 取消済 / 'approved' 承認済 / 'rejected' 差戻し / 'pending' 未承認
///
/// ★取消済を最初に見る。取消は approved も revision_requested も落とさないため、
///   承認から先に見ると取消済が「承認済」に化ける（これが直そうとしている嘘そのもの）。
/// ★2番目以降の並び（approved → revision_requested → 既定）は、上書きしていた
///   3箇所の式と同一にしてある（monthly_history_screen.dart の _load、
///   home_screen.dart の _loadReports、同 ReviewTab の _load）。挙動を変えたのは
///   取消済の1行を先頭へ足したことだけ。
String reportStatusOf(Map<String, dynamic> r) {
  if (isCancelledReport(r)) return kReportStatusCancelled;
  if (r['approved'] == true) return 'approved';
  if (r['revision_requested'] == true) return 'rejected';
  return 'pending';
}

/// 一覧の1行に上の判定結果を載せて返す（元の Map は書き換えない）。
///
/// ★親の画面はこれを `.map(withReportStatus)` で通すだけにする。
///   'status' 以外のキーは1つも触らないので、approved / revision_requested は
///   行に残ったままになる＝この関数を二度通しても答えは変わらない。
Map<String, dynamic> withReportStatus(Map<String, dynamic> r) =>
    <String, dynamic>{...r, 'status': reportStatusOf(r)};

/// 承認待ち＝「今日やる仕事」に載せる行か。
///
/// ★式の後半（is_sent / approved / revision_requested）は移設前から同一で、
///   1文字も変えていない（home_screen.dart の _isPending、
///   approval_day_screen.dart の _isPending、同 _loadPendingApprovalCount）。
///   足したのは先頭の「取消済でないこと」だけ。
///   取消は approved を落とさないので、これが無いと取り消した日報が
///   いつまでも承認待ちに残り、押しても BE が断るだけの空振りになる。
bool isPendingApproval(Map<String, dynamic> r) =>
    !isCancelledReport(r) &&
    r['is_sent'] == true &&
    r['approved'] != true &&
    r['revision_requested'] != true;

/// 差し戻し中＝「今日やる仕事」に載せる行か。
///
/// ★BE の GET /reports?revision_requested=true は取消済を除外しない
///   （js-office-api routes/reports.js の GET '/' は
///     `if (revOnly) query += ' AND r.revision_requested = true'` だけを足す）。
///   取消は revision_requested も落とさないため、除外はここで行う。
bool isRevisionRequested(Map<String, dynamic> r) =>
    !isCancelledReport(r) && r['revision_requested'] == true;
