// lib/widgets/report_form_steps.dart
// 日報のフォームの「段の部品」と「値の関数」。
//
// ★何か：今日の日報のフォーム（lib/screens/home_screen.dart のシェル）が、3つの段（現場／移動／作業）と
//   下のボタンを組む時に使う部品と、送る値・確認の画面の材料を組む関数。
//   便F8b-1（2026-10-08）で、シェルの中に直に書いてあった並びと式を、字のまま（シェルの欄の名前を引数の名前に
//   替えるだけで）ここへ出した。本の頭の読み込みのほかに足したのは、段をまとめる外の器・押した時の中身と候補を受ける引数・確かめの窓を
//   包む関数・値の関数の入口と return の行だけ（相乗りの会社名と氏名の、同じ形の2つの式は、1つの関数にした）。字・色・大きさ・空き・出る条件は、1つも変えていない。
// ★決まり：ここの物は、状態を持たない。時計も、端末の保存も、通信も読まない（渡された値だけで決まる。
//   confirmAddTransport だけは、確かめの窓を出して、利用者の答えを返す）。
//   押した時の中身（状態を変える・端末へ保存する・目安を取り直す・同僚を読む）は、呼び手の側に書いて渡す。
// ★なぜ出したか：事務の許可が出た過去の日の日報を出す画面（次の便）が、同じ並びと同じ式を使うため
//   （同じ決まりを2通りに書かない）。動かした部品は lib/widgets/report_form_parts.dart。

import 'package:flutter/material.dart';
import '../core/theme/field_tokens.dart';
import '../main.dart' show TransportType, showConfirmDialog;
import 'photo_strip_field.dart';
import 'report_form_parts.dart';
import 'search_suggest_field.dart';

// ─────────────────────────────────────────────
// 段1「現場」：見出しと、現場の欄
//   現在地の行（今日の日報だけが出す）と、段の下の空きは、呼び手の側に置く。
// ─────────────────────────────────────────────
class ReportStepSite extends StatelessWidget {
  const ReportStepSite({super.key, required this.siteName, required this.onTap});

  /// 選んだ現場の名前。null は「該当現場なし」という選び。
  final String? siteName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const ReportSectionHeader('現場'),
          ReportSiteSelectField(
            siteName: siteName,
            onTap: onTap,
          ),
        ],
      );
}

// ─────────────────────────────────────────────
// 段2「移動」：見出しと、カードの中の並び
//   条件つきの4つ（補足の欄／車の種類の2択／相乗りの2欄／駐車料金と写真）の出る条件は、
//   シェルに書いてあった式のまま。押した時の中身は、どれも呼び手が渡す。
//   相乗りの候補の2つは「欄を出す時にだけ呼ぶ関数」で受ける（欄が出ていない時には計算しない＝今までと同じ）。
// ─────────────────────────────────────────────
class ReportStepMove extends StatelessWidget {
  const ReportStepMove({
    super.key,
    required this.originType,
    required this.onOriginChanged,
    required this.transports,
    required this.onTransportTap,
    required this.onTransportDoubleTap,
    required this.transportMemoController,
    required this.carType,
    required this.onCarTypeOwn,
    required this.onCarTypeCarpool,
    required this.routeTransport,
    required this.routeComparisons,
    required this.loadingRoutes,
    required this.routeFailed,
    required this.routeFromCache,
    required this.onRouteRetry,
    required this.carpoolCompanyController,
    required this.carpoolCompanyCandidatesOf,
    required this.onCarpoolCompanyChanged,
    required this.carpoolNameController,
    required this.carpoolNameCandidatesOf,
    required this.onCarpoolNameChanged,
    required this.parkingFeeController,
    required this.onParkingFeeChanged,
    required this.parkingPhotoPaths,
    required this.onParkingPhotosChanged,
  });

  /// 出発地（'home'＝自宅／'office'＝会社）。
  final String originType;
  final ValueChanged<String> onOriginChanged;

  /// 選んでいる移動手段（選んだ順）。
  final Set<TransportType> transports;
  final Function(TransportType) onTransportTap;
  final Function(TransportType) onTransportDoubleTap;
  final TextEditingController transportMemoController;

  /// 車の種類（'own'＝社用車・自家用車／'carpool'＝相乗り）。
  final String carType;
  final VoidCallback onCarTypeOwn;
  final VoidCallback onCarTypeCarpool;

  /// 目安の帯へ渡す物（手段は、呼び手が決めて渡す。今日の日報は、選んだ中の先頭・何も選んでいなければ none）。
  final TransportType routeTransport;
  final Map<String, dynamic> routeComparisons;
  final bool loadingRoutes;
  final bool routeFailed;
  final bool routeFromCache;
  final Future<void> Function() onRouteRetry;

  final TextEditingController carpoolCompanyController;
  final List<String> Function() carpoolCompanyCandidatesOf;
  final ValueChanged<String> onCarpoolCompanyChanged;
  final TextEditingController carpoolNameController;
  final List<String> Function() carpoolNameCandidatesOf;
  final ValueChanged<String> onCarpoolNameChanged;

  final TextEditingController parkingFeeController;
  final ValueChanged<String> onParkingFeeChanged;
  final List<String> parkingPhotoPaths;
  final ValueChanged<List<String>> onParkingPhotosChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const ReportSectionHeader('移動'),
          ReportFormCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ReportFieldLabel('出発地'),
                const SizedBox(height: 8),
                ReportOriginSelector(
                  selected: originType,
                  onChanged: onOriginChanged,
                ),
                const SizedBox(height: 16),
                const ReportFieldLabel('移動手段'),
                const SizedBox(height: 8),

                // ④ 移動手段 4択（1タップ排他・ダブルタップで複数追加）（押した時の中身は呼び手）
                ReportTransportRow(
                  selectedSet: transports,
                  onTap: onTransportTap,
                  onDoubleTap: onTransportDoubleTap,
                ),
                // 作業5: 複数選択の操作方法を明示（ダブルタップは発見されにくいため）
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('※タップで選択　／　2つ以上使うときはダブルタップで追加',
                      style: TextStyle(color: FieldTokens.textFaint, fontSize: 11)),
                ),
                // 補足テキスト（その他 or 複数選択時）— 注意書き直下・トグルより前へ移設
                if (transports.contains(TransportType.other) || transports.length >= 2) ...[
                  const SizedBox(height: 10),
                  ReportFormInputShell(
                    icon: Icons.edit_note,
                    child: TextField(
                      controller: transportMemoController,
                      decoration: const InputDecoration(
                        hintText: '移動手段の補足（任意）例：バイクで駅まで → 電車 → 徒歩',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                            color: FieldTokens.textFaint, fontSize: 12),
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                          color: FieldTokens.textBody, fontSize: 13),
                    ),
                  ),
                ],
                // 車選択時: 社用車/相乗り 2択 → 各入力欄
                if (transports.contains(TransportType.car)) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onCarTypeOwn,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: carType == 'own'
                                ? FieldTokens.outlineStrong
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: carType == 'own'
                                    ? FieldTokens.textSupport
                                    : FieldTokens.outline),
                          ),
                          child: Center(child: Text('社用車・自家用車',
                            style: TextStyle(
                              color: carType == 'own'
                                  ? FieldTokens.textBody
                                  : FieldTokens.textSupport,
                              fontSize: 12,
                              fontWeight: carType == 'own' ? FontWeight.bold : FontWeight.normal,
                            ))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: onCarTypeCarpool,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: carType == 'carpool'
                                ? FieldTokens.outlineStrong
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: carType == 'carpool'
                                    ? FieldTokens.textSupport
                                    : FieldTokens.outline),
                          ),
                          child: Center(child: Text('相乗り',
                            style: TextStyle(
                              color: carType == 'carpool'
                                  ? FieldTokens.textBody
                                  : FieldTokens.textSupport,
                              fontSize: 12,
                              fontWeight: carType == 'carpool' ? FontWeight.bold : FontWeight.normal,
                            ))),
                        ),
                      ),
                    ),
                  ]),
                ],
                // ルート情報バー（距離・時間・金額）。
                // 位置: 車のときは「社用車・自家用車/相乗り」2択の直下＝駐車料金入力の上。
                //       他の手段のときは手段チップの直下（上の car ブロックが出ないため自然にそうなる）。
                // 表示条件は従来どおり無条件（transports に依存しない）。
                const SizedBox(height: 12),
                ReportRouteInfoBar(
                  transport: routeTransport,
                  comparisons: routeComparisons,
                  loading: loadingRoutes,
                  failed: routeFailed,
                  fromCache: routeFromCache,
                  onRetry: onRouteRetry,
                ),
                // 車選択かつ相乗り時: 相乗り相手（会社名サジェスト＋氏名の2欄）。
                //   駐車料金は出さない＝現行仕様のまま。work_content には連結しない（二重真実の禁止）。
                if (transports.contains(TransportType.car) &&
                    carType == 'carpool') ...[
                  const SizedBox(height: 10),
                  // 作業3: 会社名はサジェスト付き（searchCompanies・300msデバウンス・共通部品）
                  SearchSuggestField(
                    controller: carpoolCompanyController,
                    candidates: carpoolCompanyCandidatesOf(),
                    hintText: '相乗り相手の会社名（任意）',
                    onChanged: onCarpoolCompanyChanged,
                    onSelected: onCarpoolCompanyChanged,
                    // 候補はサーバ(/companies/search)が正規化検索で絞り済み。
                    // 生テキスト部分一致の再フィルタでサーバ候補を捨てない。
                    serverFiltered: true,
                  ),
                  // 作業2: 会社名欄の下に補足（既存の ※ 補足と同じ textFaint / fontSize 11）
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('※自社なら空欄のままでOK',
                        style: TextStyle(color: FieldTokens.textFaint, fontSize: 11)),
                  ),
                  const SizedBox(height: 10),
                  // 氏名の欄もサジェスト付き。候補は呼び手が決めて渡す（会社名が空か自社の時だけ自社の同僚）。
                  //   serverFiltered:false＝候補は全件渡るので、欄の側で部分一致の絞り込みをする。
                  SearchSuggestField(
                    controller: carpoolNameController,
                    candidates: carpoolNameCandidatesOf(),
                    hintText: '相乗り相手の氏名（任意）',
                    onChanged: onCarpoolNameChanged,
                    serverFiltered: false,
                  ),
                ],
                // 駐車料金 + 駐車場写真（1組だけ描画する）
                // ★車(社用車・自家用車)の時と「その他」の時を OR で1本にしてある＝両方を選んでも、
                //   同じ持ち物を使う入力欄と写真帯が2組並ばない。
                if ((transports.contains(TransportType.car) && carType == 'own') ||
                    transports.contains(TransportType.other)) ...[
                  const SizedBox(height: 10),
                  ReportFormInputShell(
                    icon: Icons.local_parking,
                    child: TextField(
                      controller: parkingFeeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '駐車料金（円）',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                            color: FieldTokens.textFaint, fontSize: 12),
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                          color: FieldTokens.textBody, fontSize: 13),
                      onChanged: onParkingFeeChanged,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 駐車場写真（複数・横スクロール帯）
                  PhotoStripField(
                    label: '駐車場写真（看板・領収書）',
                    paths: parkingPhotoPaths,
                    onChanged: onParkingPhotosChanged,
                  ),
                ],
              ],
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────
// 段3「作業」：見出しと、カード（作業内容・写真）
// ─────────────────────────────────────────────
class ReportStepWork extends StatelessWidget {
  const ReportStepWork({
    super.key,
    required this.workController,
    required this.isListening,
    required this.onMicTap,
    required this.workPhotoPaths,
    required this.onWorkPhotosChanged,
  });

  final TextEditingController workController;
  final bool isListening;
  final VoidCallback onMicTap;
  final List<String> workPhotoPaths;
  final ValueChanged<List<String>> onWorkPhotosChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ReportSectionHeader('作業'),
          ReportFormCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ⑤ 作業内容テキスト（音声入力）
                ReportWorkContentSection(
                  controller: workController,
                  showMediaButtons: true,
                  isListening: isListening,
                  onMicTap: onMicTap,
                ),
                const SizedBox(height: 14),
                // 作業写真（複数・横スクロール帯）
                PhotoStripField(
                  label: '写真',
                  note: '※なくても報告できます',
                  paths: workPhotoPaths,
                  onChanged: onWorkPhotosChanged,
                ),
              ],
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────
// 下のボタン：段ごとの並び
//   段1＝「次へ」／段2＝「戻る」「次へ」／段3＝「戻る」「内容を確認する」と※。
//   外の器（地の色と周りの空き）は、呼び手の側に置く。
//   ★この縦の並びには「横いっぱい」を付けない（今のまま＝※の字は横の真ん中に出る）。
// ─────────────────────────────────────────────
class ReportStepButtons extends StatelessWidget {
  const ReportStepButtons({
    super.key,
    required this.step,
    required this.onGoStep,
    required this.checkBusy,
    required this.onCheck,
  });

  /// 今の段（1＝現場／2＝移動／3＝作業）。
  final int step;

  /// 段を移る時に呼ぶ（行き先の段の番号を渡す）。
  final void Function(int step) onGoStep;
  final bool checkBusy;
  final Future<void> Function() onCheck;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ステップ1: 「次へ」だけ（ブロックなし＝バリデーションは足さない）
          if (step == 1)
            ReportOutlineActionButton(
              label: '次へ',
              onTap: () async => onGoStep(2),
            ),
          // ステップ2: 「戻る」＋「次へ」
          if (step == 2)
            Row(
              children: [
                Expanded(child: ReportStepBackButton(onTap: () => onGoStep(1))),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ReportOutlineActionButton(
                    label: '次へ',
                    onTap: () async => onGoStep(3),
                  ),
                ),
              ],
            ),
          // ステップ3: 「戻る」＋既存の「内容を確認する」（押した時の中身は呼び手）
          if (step == 3) ...[
            Row(
              children: [
                Expanded(child: ReportStepBackButton(onTap: () => onGoStep(2))),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ReportOutlineActionButton(
                    label: '内容を確認する',
                    busy:  checkBusy,
                    onTap: onCheck,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            const Text('※次の画面で見直してから送信します',
                style: TextStyle(
                    color: FieldTokens.textFaint, fontSize: 11)),
          ],
        ],
      );
}

// ─────────────────────────────────────────────
// 値の関数（状態を持たない・渡された値だけで決まる。confirmAddTransport だけは、窓を出して利用者の答えを返す）
// ─────────────────────────────────────────────

/// 移動手段を1回押した時の、新しい選び。
///   まだ選んでいない手段 → それ1つだけにする。選んである手段 → 2つ以上選んでいる時だけ外す（1つの時はそのまま）。
///   渡した集まりは書き換えず、新しい集まりを返す。
Set<TransportType> transportsAfterTap(Set<TransportType> current, TransportType t) {
  final newSet = Set<TransportType>.from(current);
  if (!newSet.contains(t)) {
    newSet.clear();
    newSet.add(t);
  } else if (newSet.length > 1) {
    newSet.remove(t);
  }
  return newSet;
}

/// 移動手段の2つ目を足す前の、確かめの窓。「OK」で true。
Future<bool> confirmAddTransport(BuildContext context) => showConfirmDialog(
      context,
      title: '移動手段を追加',
      message: '2つ以上の移動手段を記録します。よろしいですか？',
      confirmText: 'OK', cancelText: 'キャンセル',
    );

/// 作業内容の頭に付ける字（送る時に、作業内容の欄の字の前へつなぐ）。
///   「その他」を選んでいて otherText が空でない時は「[その他:字] 」、
///   memoText（移動手段の補足）が空でない時は「【移動】字 」。この順でつなぐ。
String reportWorkContentPrefix({
  required Set<TransportType> transports,
  required String otherText,
  required String memoText,
}) {
  final otherPrefix = (transports.contains(TransportType.other) && otherText.trim().isNotEmpty)
      ? '[その他:${otherText.trim()}] '
      : '';
  // D-1: 移動手段の補足テキスト。従来 UI にはあるが payload に載らず消えていた。
  //      other prefix と同じ流儀で work_content へ連結する。空なら付けない。
  final memoPrefix = memoText.trim().isEmpty
      ? ''
      : '【移動】${memoText.trim()} ';
  return otherPrefix + memoPrefix;
}

/// 駐車料金として送る値（欄の字から）。
String? reportParkingFeeValue(String text) {
  // D-2: 駐車料金を実値で送る。未入力/パース不能/負数は null、0以上はその値をそのまま渡す
  //      （0を空に丸めない＝BE側 POST /reports の `parking_fee || null` は別途BEで是正予定）。
  final parkingRaw    = text.trim();
  final parkingParsed = parkingRaw.isEmpty ? null : double.tryParse(parkingRaw);
  return (parkingParsed != null && parkingParsed >= 0) ? parkingRaw : null;
}

/// 相乗りの1欄ぶん（会社名・氏名のどちらにも使う）の送る値。
String? reportCarpoolValue({
  required Set<TransportType> transports,
  required String carType,
  required String text,
}) {
  // 作業2: 相乗り2欄（相乗り時のみ・空欄は null）。
  final isCarpool = transports.contains(TransportType.car) && carType == 'carpool';
  return isCarpool && text.trim().isNotEmpty ? text.trim() : null;
}

/// 確認の画面の材料（表示と、差の見張りの鍵）を組む。読むだけ。
///   日付の字と勤務の字は、呼び手が作って渡す（ここでは時計を読まない）。
ReportSnapshot reportSnapshotFrom({
  required String dateLabel,
  required String shiftLabel,
  required String? siteId,
  required String? siteName,
  required String originType,
  required Set<TransportType> transports,
  required String carType,
  required Map<String, dynamic> routeComparisons,
  required String parkingText,
  required String carpoolCompanyText,
  required String carpoolNameText,
  required String workText,
  required int workPhotoCount,
  required int parkingPhotoCount,
}) {
  // 作業2: 先頭1件ではなく選択中の全手段から内訳を作る。
  final routeRows  = reportRouteBreakdown(transports, routeComparisons);
  final parkingRaw = parkingText.trim();
  return ReportSnapshot(
    dateLabel:         dateLabel,
    shiftLabel:        shiftLabel,
    siteId:            siteId,
    siteName:          siteName ?? '該当現場なし',
    originLabel:       originType == 'office' ? '会社' : '自宅',
    transportKey:      (transports.map((t) => t.name).toList()..sort()).join(','),
    transportLabel:    transports.isEmpty
        ? '未選択'
        : transports.map((t) => t.label).join('・'),
    routeRows:         routeRows,
    parkingFeeRaw:     parkingRaw,
    // 作業4: 相乗り2項目（相乗り時のみ・空欄は空文字）。表示・差異検知に使う。
    carpoolCompany:    (transports.contains(TransportType.car) && carType == 'carpool')
        ? carpoolCompanyText.trim() : '',
    carpoolName:       (transports.contains(TransportType.car) && carType == 'carpool')
        ? carpoolNameText.trim() : '',
    workContent:       workText.trim(),
    workPhotoCount:    workPhotoCount,
    parkingPhotoCount: parkingPhotoCount,
  );
}
