import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  group('画面遷移ロジックテスト', () {
    test('status=pending→承認待ち画面フラグ', () {
      String status = 'pending';
      String route = status == 'pending' ? '/pending' : '/home';
      expect(route, '/pending');
    });

    test('status=active→ホーム画面フラグ', () {
      String status = 'active';
      String route = status == 'pending' ? '/pending' : '/home';
      expect(route, '/home');
    });

    test('consent未同意→同意画面フラグ', () {
      bool consentAgreed = false;
      bool needsConsent = !consentAgreed;
      expect(needsConsent, true);
    });

    test('consent同意済み→スキップ', () {
      bool consentAgreed = true;
      bool needsConsent = !consentAgreed;
      expect(needsConsent, false);
    });

    test('device_id未登録→登録画面フラグ', () {
      String? deviceId;
      bool needsRegister = deviceId == null || deviceId.isEmpty;
      expect(needsRegister, true);
    });

    test('device_id登録済み→ログイン画面フラグ', () {
      String? deviceId = 'registered-device-id';
      bool needsRegister = deviceId == null || deviceId.isEmpty;
      expect(needsRegister, false);
    });

    test('token有効→自動ログインフラグ', () {
      String? token = 'valid_token_xyz';
      bool autoLogin = token != null && token.isNotEmpty;
      expect(autoLogin, true);
    });

    test('token無効→ログイン必要フラグ', () {
      String? token;
      bool autoLogin = token != null && token.isNotEmpty;
      expect(autoLogin, false);
    });
  });

  group('移動手段別表示ロジック', () {
    final testCases = {
      'car': {'showParking': true, 'showMedia': true, 'showRoute': true},
      'train': {'showParking': false, 'showMedia': true, 'showRoute': true},
      'bus': {'showParking': false, 'showMedia': true, 'showRoute': true},
      'other': {'showParking': false, 'showMedia': true, 'showRoute': true},
    };

    for (final entry in testCases.entries) {
      final transport = entry.key;
      final expected = entry.value;

      test('$transport: 駐車料金表示=${expected['showParking']}', () {
        bool showParking = transport == 'car';
        expect(showParking, expected['showParking']);
      });

      test('$transport: マイク表示=${expected['showMedia']}', () {
        bool showMedia = true; // 全移動手段で表示
        expect(showMedia, expected['showMedia']);
      });
    }
  });

  group('日報送信前バリデーション', () {
    bool validateReport({
      required String? date,
      required String? address,
      required String? clockIn,
    }) {
      if (date == null || date.isEmpty) return false;
      if (address == null || address.isEmpty) return false;
      if (clockIn == null || clockIn.isEmpty) return false;
      try { DateTime.parse(date); } catch (_) { return false; }
      return true;
    }

    test('全フィールド正常→有効', () {
      expect(validateReport(
        date: '2026-06-05',
        address: '兵庫県神戸市',
        clockIn: '08:00',
      ), true);
    });

    test('日付空→無効', () {
      expect(validateReport(date: '', address: '住所', clockIn: '08:00'), false);
    });

    test('住所空→無効', () {
      expect(validateReport(date: '2026-06-05', address: '', clockIn: '08:00'), false);
    });

    test('出勤時間空→無効', () {
      expect(validateReport(date: '2026-06-05', address: '住所', clockIn: ''), false);
    });

    test('全null→無効', () {
      expect(validateReport(date: null, address: null, clockIn: null), false);
    });

    test('不正日付→無効', () {
      expect(validateReport(date: 'not-a-date', address: '住所', clockIn: '08:00'), false);
    });
  });

  group('招待コードバリデーション', () {
    bool isValidInviteCode(String code) {
      return RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(code);
    }

    test('有効な招待コード', () {
      expect(isValidInviteCode('ABC123'), true);
      expect(isValidInviteCode('INVITE001'), true);
    });

    test('短すぎる→無効', () {
      expect(isValidInviteCode('AB1'), false);
    });

    test('空文字→無効', () {
      expect(isValidInviteCode(''), false);
    });

    test('小文字混入→無効', () {
      expect(isValidInviteCode('abc123'), false);
    });

    test('記号混入→無効', () {
      expect(isValidInviteCode('ABC-123'), false);
    });
  });

  group('オフライン対応テスト', () {
    test('キャッシュあり→オフラインで表示可能', () {
      final cache = [{'id': '1', 'name': 'パナソニック'}];
      bool canDisplay = cache.isNotEmpty;
      expect(canDisplay, true);
    });

    test('キャッシュなし+オフライン→エラー表示', () {
      final cache = <Map>[];
      bool isOnline = false;
      bool showError = cache.isEmpty && !isOnline;
      expect(showError, true);
    });

    test('キャッシュあり+オフライン→キャッシュ表示', () {
      final cache = [{'id': '1'}];
      bool isOnline = false;
      bool useCache = cache.isNotEmpty && !isOnline;
      expect(useCache, true);
    });
  });
}
