// lib/screens/device_error_log_screen.dart
// 端末の中の失敗の控えの一覧（便BK・見本 claude/field_report_fix_mock_v3.html の ⑰④「エラー記録」・ボスの裁定【Q145】＝１）。
//   開く所は設定の「端末｜エラー記録」の行（lib/screens/profile_screen.dart）だけ。
//   1件＝題（何が止まったか）と「M/D HH:MM・代わりにした事」。字の名簿は lib/utils/device_error_log.dart の
//   kDeviceErrorKinds ただ1つ（ここに写しを作らない）。読むだけ（消す・送る道は作らない）。
import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../utils/device_error_log.dart';

/// 一覧の画面の題と、設定の行の字（見本 v3 の ⑰④・lib/screens/profile_screen.dart も、この1つを読む）。
const String kDeviceErrorLogTitle = 'エラー記録';

/// 一覧の下の※（見本 v3 の ⑰④）。
const String kDeviceErrorLogNote = '※新しい順に50件まで残します。';

/// 設定の「端末｜エラー記録」の行の下の※（見本 v3 の ⑰④・lib/screens/profile_screen.dart が出す）。
const String kDeviceErrorTileNote = '※不具合の問い合わせの時にお伝えください。';

/// 控えが1件も無い時の字。
const String kDeviceErrorLogEmpty = 'エラー記録はありません';

/// 控えそのものを読めなかった時の字（便BK・検分 a260 の N9＝「ありません」と事実と違う字を出さない）。
const String kDeviceErrorLogReadFailed = 'エラー記録を読み込めませんでした';

/// 「M/D HH:MM」（端末の時刻）。
String deviceErrorTimeLabel(DateTime at) {
  final t = at.toLocal();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.month}/${t.day} $hh:$mm';
}

class DeviceErrorLogScreen extends StatefulWidget {
  const DeviceErrorLogScreen({super.key});

  @override
  State<DeviceErrorLogScreen> createState() => _DeviceErrorLogScreenState();
}

class _DeviceErrorLogScreenState extends State<DeviceErrorLogScreen> {
  bool _loaded = false;
  List<DeviceErrorEntry>? _entries;   // 読み終えて null＝控えを読めなかった

  @override
  void initState() {
    super.initState();
    readDeviceErrors().then((v) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _entries = v;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries ?? const <DeviceErrorEntry>[];
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(
        backgroundColor: FieldTokens.bgBase,
        title: const Text(kDeviceErrorLogTitle),
      ),
      body: SafeArea(
        child: !_loaded
            ? const Center(
                child: CircularProgressIndicator(color: FieldTokens.accent))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_entries == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(kDeviceErrorLogReadFailed,
                          style: TextStyle(
                              color: FieldTokens.statusWarning, fontSize: 13)),
                    )
                  else if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(kDeviceErrorLogEmpty,
                          style: TextStyle(
                              color: FieldTokens.textSupport, fontSize: 13)),
                    ),
                  for (final e in entries)
                    Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 2),
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: FieldTokens.outline)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title,
                              style: const TextStyle(
                                  color: FieldTokens.textBody,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${deviceErrorTimeLabel(e.at)}・${e.fallback}',
                              style: const TextStyle(
                                  color: FieldTokens.textSupport,
                                  fontSize: 11.5)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(kDeviceErrorLogNote,
                      style: TextStyle(
                          color: FieldTokens.textSupport, fontSize: 11.5)),
                ],
              ),
      ),
    );
  }
}
