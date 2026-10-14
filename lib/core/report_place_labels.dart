// lib/core/report_place_labels.dart
// 日報の報告場所の出し方を1か所に集めた表と関数（便BJ・見本 claude/field_report_fix_mock_v1.html の A）。
//
// ★何か：日報の行（サーバの答えの Map）から、報告場所の住所と「測れなかった」の字を読み分ける。
//   場所を測れなかった日報は、住所の欄（gps_address）が空で、理由が gps_fail_reason に符号で入る
//   （サーバ js-office-api の routes/reports.js の GPS_FAIL_REASONS と1対1・便BI・migration v94）。
//   便BJ より前のこのアプリは、測れなかった時に理由の文を住所の欄へそのまま入れていた。前の日報の行は
//   書き換えない決まりなので、その文もここで読み替える（下の kLegacyGpsFailTexts）。
// ★字は事務アプリ（js_office_admin_app の lib/core/report_place_labels.dart）と1文字も同じ。
//   同じ日報の場所を、職長と事務とで別の言葉で出さない。
// ★住所として使う所（現場の束の見出し・現場の登録の初めの字）は address だけを使う。
//   「測れませんでした（…）」の字を住所として使わない（座標にしない）。

/// 測れなかった時に、このアプリの fetchGpsAddress（lib/main.dart）が返す字（ホームの現在地の帯に出す）。
///   ★字の真実はここ1か所。fetchGpsAddress も、前の日報の読み替え（kLegacyGpsFailTexts）も、この3つを使う。
const String kGpsFailTextNoPermission = '位置情報の権限がありません';
const String kGpsFailTextDisabled = 'GPS が無効です';
const String kGpsFailTextError = 'GPS取得失敗';

/// サーバの reports.gps_fail_reason の符号 → 出す字（事務アプリと同じ字）。
const Map<String, String> kGpsFailReasonLabels = {
  'no_permission': '位置情報の権限なし',
  'gps_disabled': 'GPS が無効',
  'gps_error': 'GPS の取得に失敗',
};

/// 便BJ より前のこのアプリが、測れなかった時に住所の欄へ入れていた字 → 符号。
const Map<String, String> kLegacyGpsFailTexts = {
  kGpsFailTextNoPermission: 'no_permission',
  kGpsFailTextDisabled: 'gps_disabled',
  kGpsFailTextError: 'gps_error',
};

/// 符号から「測れませんでした（…）」の字を作る。表に無い符号は「理由不明」（黙って空にしない）。
String _failTextOf(String code) =>
    '測れませんでした（${kGpsFailReasonLabels[code] ?? '理由不明'}）';

/// 日報の行の報告場所。address＝住所の字（前後の空白を除く）・failText＝測れなかった時の字。
///   決める順：(1) gps_fail_reason が空でない字なら failText（住所の字より先に見る＝本人の編集で後から
///   場所の字が書かれた行も、出した時に測れなかった事を先に出す）。(2) gps_address が空なら両方 null。
///   (3) 前の字（kLegacyGpsFailTexts）なら failText。(4) ほかは address。
({String? address, String? failText}) reportPlaceOf(Map<String, dynamic> r) {
  final reason = r['gps_fail_reason'];
  if (reason is String && reason.trim().isNotEmpty) {
    return (address: null, failText: _failTextOf(reason.trim()));
  }
  final raw = r['gps_address'];
  final addr = raw is String ? raw.trim() : '';
  if (addr.isEmpty) return (address: null, failText: null);
  final legacy = kLegacyGpsFailTexts[addr];
  if (legacy != null) return (address: null, failText: _failTextOf(legacy));
  return (address: addr, failText: null);
}

/// 出す字（住所か「測れませんでした（…）」）。どちらも無ければ null。
String? reportPlaceText(Map<String, dynamic> r) {
  final p = reportPlaceOf(r);
  return p.address ?? p.failText;
}
