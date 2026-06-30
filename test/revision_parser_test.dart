import 'package:flutter_test/flutter_test.dart';
import 'package:js_awake_app/utils/revision_parser.dart';

void main() {
  group('parseRevision 接頭辞逆変換', () {
    test('1: 相乗り(car) → carType=carpool/carpool抽出/本文', () {
      final r = parseRevision({
        'work_content': '[相乗り:田中] 配線工事',
        'transport_types_json': ['car'],
      });
      expect(r.carType, 'carpool');
      expect(r.carpoolText, '田中');
      expect(r.workContent, '配線工事');
      expect(r.parkingText, '');
    });

    test('2: 駐車料金(car/own) → parkingは列が真実/prefix剥がす', () {
      final r = parseRevision({
        'work_content': '[駐車料金:500円] 点検',
        'transport_types_json': ['car'],
        'parking_fee': 500,
      });
      expect(r.carType, 'own');
      expect(r.parkingText, '500');
      expect(r.workContent, '点検');
      expect(r.carpoolText, '');
    });

    test('3: その他(other) → other抽出/本文', () {
      final r = parseRevision({
        'work_content': '[その他:タクシー] 撤去',
        'transport_types_json': ['other'],
      });
      expect(r.otherText, 'タクシー');
      expect(r.workContent, '撤去');
    });

    test('4: 残業接尾辞は退避され本文から除去', () {
      final r = parseRevision({
        'work_content': '作業 【残業1時間30分】',
        'transport_types_json': ['train'],
      });
      expect(r.workContent, '作業');
      expect(r.overtimeSuffix.contains('残業1時間30分'), true);
    });

    test('5: 複合(駐車+その他+残業) を全部分解', () {
      final r = parseRevision({
        'work_content': '[駐車料金:300円] [その他:電車遅延] 補修 【残業0時間45分】',
        'transport_types_json': ['car', 'other'],
        'parking_fee': 300,
      });
      expect(r.carType, 'own');
      expect(r.parkingText, '300');
      expect(r.otherText, '電車遅延');
      expect(r.workContent, '補修');
      expect(r.overtimeSuffix.contains('残業0時間45分'), true);
      expect(r.transportNames.contains('car'), true);
      expect(r.transportNames.contains('other'), true);
    });

    test('6: prefix無し → 本文そのまま/他は空', () {
      final r = parseRevision({
        'work_content': '普通の作業',
        'transport_types_json': ['walk'],
      });
      expect(r.workContent, '普通の作業');
      expect(r.carpoolText, '');
      expect(r.parkingText, '');
      expect(r.otherText, '');
      expect(r.overtimeSuffix, '');
    });

    test('7: ★狙い撃ち=carを選んでない時は駐車prefixを剥がさない(誤爆防止)', () {
      final r = parseRevision({
        'work_content': '[駐車料金:999円] 工事',
        'transport_types_json': ['train'],
        'parking_fee': 999,
      });
      // car非選択 → 駐車prefixは本文の一部として温存される
      expect(r.workContent, '[駐車料金:999円] 工事');
      expect(r.parkingText, '');
    });

    test('8: transport_types_json が JSON文字列でも動く', () {
      final r = parseRevision({
        'work_content': '[その他:バイク] 配線',
        'transport_types_json': '["other"]',
      });
      expect(r.otherText, 'バイク');
      expect(r.workContent, '配線');
    });

    test('9: transport_types_json 無し→ transport_type 単一にフォールバック', () {
      final r = parseRevision({
        'work_content': '[相乗り:佐藤] 据付',
        'transport_type': 'car',
      });
      expect(r.carType, 'carpool');
      expect(r.carpoolText, '佐藤');
      expect(r.workContent, '据付');
    });

    test('10: work_content 空 → 全部空で落ちない', () {
      final r = parseRevision({});
      expect(r.workContent, '');
      expect(r.transportNames.isEmpty, true);
    });
  });
}
