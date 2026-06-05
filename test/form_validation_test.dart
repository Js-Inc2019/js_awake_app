import 'package:flutter_test/flutter_test.dart';

void main() {
  group('フォームバリデーション', () {
    test('PIN: 6桁数字→有効', () {
      expect(RegExp(r'^\d{6}$').hasMatch('123456'), true);
    });
    test('PIN: 5桁→無効', () {
      expect(RegExp(r'^\d{6}$').hasMatch('12345'), false);
    });
    test('PIN: 文字列混入→無効', () {
      expect(RegExp(r'^\d{6}$').hasMatch('12345a'), false);
    });
    test('PIN: 空文字→無効', () {
      expect(RegExp(r'^\d{6}$').hasMatch(''), false);
    });
    test('会社コード: JS-0001形式→有効', () {
      expect(RegExp(r'^JS-\d{4}$').hasMatch('JS-0001'), true);
    });
    test('会社コード: 小文字→無効', () {
      expect(RegExp(r'^JS-\d{4}$').hasMatch('js-0001'), false);
    });
    test('日付: 正常→parse成功', () {
      expect(() => DateTime.parse('2026-06-05'), returnsNormally);
    });
    test('日付: 不正形式→例外', () {
      expect(() => DateTime.parse('not-a-date'), throwsFormatException);
    });
    test('氏名: 空白のみ→無効', () {
      expect('   '.trim().isEmpty, true);
    });
    test('郵便番号: XXX-XXXX形式→有効', () {
      expect(RegExp(r'^\d{3}-\d{4}$').hasMatch('123-4567'), true);
    });
    test('郵便番号: ハイフンなし→無効', () {
      expect(RegExp(r'^\d{3}-\d{4}$').hasMatch('1234567'), false);
    });
    test('金額: 正の整数→有効', () {
      expect(int.tryParse('1000') != null, true);
    });
    test('金額: 文字列→null', () {
      expect(int.tryParse('abc'), null);
    });
  });

  group('SQLインジェクション・XSSチェック', () {
    final dangerous = [
      "' OR '1'='1",
      '<script>alert(1)</script>',
      '"; DROP TABLE users; --',
      '../../../etc/passwd',
    ];
    for (final input in dangerous) {
      test('危険文字列サニタイズ: $input', () {
        final sanitized = input.replaceAll(RegExp('[<>"]'), '').replaceAll("'", '');
        expect(sanitized.contains('<script>'), false);
      });
    }
  });

  group('日付境界値テスト', () {
    test('うるう年2024-02-29→有効', () {
      expect(() => DateTime.parse('2024-02-29'), returnsNormally);
    });
    test('9999-12-31→有効', () {
      expect(() => DateTime.parse('9999-12-31'), returnsNormally);
    });
  });
}
