import 'dart:convert';

/// 差戻し日報の work_content/列 を編集欄の値へ分解した結果(副作用なし)。
class RevisionParseResult {
  RevisionParseResult({
    required this.workContent,
    required this.carpoolText,
    required this.parkingText,
    required this.otherText,
    required this.overtimeSuffix,
    required this.carType,
    required this.transportNames,
  });
  final String workContent;
  final String carpoolText;
  final String parkingText;
  final String otherText;
  final String overtimeSuffix;
  final String carType; // 'own' | 'carpool'
  final Set<String> transportNames;
}

/// transport_types_json(List or JSON文字列) か transport_type から手段名集合を得る。
Set<String> transportNamesOf(Map<String, dynamic> r) {
  final names = <String>{};
  final raw = r['transport_types_json'];
  if (raw is List) {
    for (final e in raw) {
      names.add(e.toString());
    }
  } else if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final e in decoded) {
          names.add(e.toString());
        }
      }
    } catch (_) {}
  }
  if (names.isEmpty) {
    final single = (r['transport_type'] as String?)?.trim() ?? '';
    if (single.isNotEmpty) names.add(single);
  }
  return names;
}

/// 保存済み work_content から接頭辞/接尾辞を剥がし各欄の値へ分解する。
/// 方針: parking_fee と残業は「列が真実」。相乗り/その他は列に無いので regex 抽出。
RevisionParseResult parseRevision(Map<String, dynamic> r) {
  var content = (r['work_content'] as String?)?.trim() ?? '';
  final names = transportNamesOf(r);

  var carpoolText = '';
  var parkingText = '';
  var otherText = '';
  var overtimeSuffix = '';
  var carType = 'own';

  final ot = RegExp(r'\s*【残業[^】]*】\s*$').firstMatch(content);
  if (ot != null) {
    overtimeSuffix = ot.group(0)!.replaceFirst(RegExp(r'^\s*'), ' ').trimRight();
    content = content.substring(0, ot.start).trimRight();
  }

  if (names.contains('car')) {
    final carpool = RegExp(r'^\[相乗り:([^\]]*)\]\s*').firstMatch(content);
    if (carpool != null) {
      carType = 'carpool';
      carpoolText = carpool.group(1)!.trim();
      content = content.substring(carpool.end);
    } else {
      carType = 'own';
      content = content.replaceFirst(RegExp(r'^\[駐車料金:[^\]]*\]\s*'), '');
      final fee = r['parking_fee'];
      if (fee != null) {
        parkingText = (fee is num) ? fee.toInt().toString() : fee.toString().trim();
      }
    }
  }

  if (names.contains('other')) {
    final other = RegExp(r'^\[その他:([^\]]*)\]\s*').firstMatch(content);
    if (other != null) {
      otherText = other.group(1)!.trim();
      content = content.substring(other.end);
    }
  }

  return RevisionParseResult(
    workContent: content.trim(),
    carpoolText: carpoolText,
    parkingText: parkingText,
    otherText: otherText,
    overtimeSuffix: overtimeSuffix,
    carType: carType,
    transportNames: names,
  );
}
