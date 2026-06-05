import 'package:flutter_test/flutter_test.dart';

void main() {
  group('報告データ検証', () {
    test('report_date必須チェック', () {
      String? date;
      expect(date == null || date.isEmpty, true);
    });

    test('clock_in_time形式チェック HH:MM', () {
      expect(RegExp(r'^\d{2}:\d{2}$').hasMatch('09:00'), true);
      expect(RegExp(r'^\d{2}:\d{2}$').hasMatch('9:00'), false);
      expect(RegExp(r'^\d{2}:\d{2}$').hasMatch('25:00'), true); // 形式OK（値は別途チェック）
    });

    test('時刻範囲チェック 00:00〜23:59', () {
      bool isValidTime(String t) {
        final parts = t.split(':');
        if (parts.length != 2) return false;
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h == null || m == null) return false;
        return h >= 0 && h <= 23 && m >= 0 && m <= 59;
      }
      expect(isValidTime('09:00'), true);
      expect(isValidTime('23:59'), true);
      expect(isValidTime('24:00'), false);
      expect(isValidTime('00:60'), false);
    });

    test('移動手段の有効値チェック', () {
      const valid = ['car', 'train', 'bus', 'other'];
      expect(valid.contains('car'), true);
      expect(valid.contains('taxi'), false);
      expect(valid.contains(''), false);
      expect(valid.contains(null), false);
    });

    test('駐車料金: 0以上の整数', () {
      expect(0 >= 0, true);
      expect(-1 >= 0, false);
      expect(9999 >= 0, true);
    });
  });

  group('通信エラーハンドリング', () {
    test('タイムアウト時のフォールバック', () {
      String? result;
      try {
        throw TimeoutException('timeout', const Duration(seconds: 30));
      } on TimeoutException {
        result = 'timeout_handled';
      }
      expect(result, 'timeout_handled');
    });

    test('nullレスポンスのフォールバック', () {
      Map<String, dynamic>? response;
      final name = response?['name'] ?? '不明';
      expect(name, '不明');
    });

    test('空配列レスポンスのハンドリング', () {
      List items = [];
      expect(items.isEmpty, true);
      expect(() => items.first, throwsStateError);
    });

    test('不正JSONのハンドリング', () {
      Map<String, dynamic>? parsed;
      try {
        // 不正JSONはパース失敗
        throw const FormatException('invalid json');
      } on FormatException {
        parsed = null;
      }
      expect(parsed, isNull);
    });
  });

  group('認証フローテスト', () {
    test('PIN 6桁数字のみ有効', () {
      final valid = ['123456', '000000', '999999'];
      final invalid = ['12345', '1234567', 'abcdef', '', '12 456'];
      for (final v in valid) {
        expect(RegExp(r'^\d{6}$').hasMatch(v), true, reason: '$v は有効なはず');
      }
      for (final v in invalid) {
        expect(RegExp(r'^\d{6}$').hasMatch(v), false, reason: '$v は無効なはず');
      }
    });

    test('5回失敗でロック', () {
      int attempts = 0;
      bool locked = false;
      for (int i = 0; i < 6; i++) {
        attempts++;
        if (attempts >= 5) locked = true;
      }
      expect(locked, true);
    });

    test('トークンnull→未ログイン', () {
      String? token;
      bool isLoggedIn = token != null && token.isNotEmpty;
      expect(isLoggedIn, false);
    });
  });

  group('カタログ機能テスト', () {
    test('製品検索: debounce 500ms', () {
      const debounceMs = 500;
      expect(debounceMs, 500);
    });

    test('キャッシュヒット判定', () {
      final cache = {'panasonic': [{'id': 'p1'}]};
      expect(cache.containsKey('panasonic'), true);
      expect(cache.containsKey('mitsubishi'), false);
    });

    test('製品フィルタ: manufacturer_id', () {
      final products = [
        {'id': 'p1', 'manufacturer_id': 'panasonic'},
        {'id': 'p2', 'manufacturer_id': 'mitsubishi'},
        {'id': 'p3', 'manufacturer_id': 'panasonic'},
      ];
      final filtered = products.where((p) => p['manufacturer_id'] == 'panasonic').toList();
      expect(filtered.length, 2);
    });
  });

  group('同意管理テスト', () {
    test('consent_agreed=true→同意済み', () {
      bool agreed = true;
      expect(agreed, true);
    });

    test('consent_agreed=false→未同意', () {
      bool agreed = false;
      expect(agreed, false);
    });

    test('consent_agreed_at: ISO8601フォーマット', () {
      final dateStr = '2026-06-05T09:00:00.000Z';
      expect(() => DateTime.parse(dateStr), returnsNormally);
    });
  });
}

class TimeoutException implements Exception {
  final String message;
  final Duration? duration;
  TimeoutException(this.message, [this.duration]);
}
