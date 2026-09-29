import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_toko/core/sync/backoff.dart';

void main() {
  group('backoff eksponensial', () {
    // Tanpa jitter agar kurvanya bisa diperiksa persis.
    final backoff = SyncBackoff(jitterRatio: 0);

    test('menggandakan tiap percobaan', () {
      expect(backoff.delayFor(0), const Duration(seconds: 5));
      expect(backoff.delayFor(1), const Duration(seconds: 10));
      expect(backoff.delayFor(2), const Duration(seconds: 20));
      expect(backoff.delayFor(3), const Duration(seconds: 40));
    });

    test('berhenti naik di batas atas', () {
      expect(backoff.delayFor(20), const Duration(hours: 6));
      expect(backoff.delayFor(30), const Duration(hours: 6));
    });

    test('percobaan sangat besar tidak meluap menjadi negatif', () {
      expect(backoff.delayFor(999).isNegative, isFalse);
      expect(backoff.delayFor(999), const Duration(hours: 6));
    });
  });

  group('jitter', () {
    test('tetap berada dalam rentang rasio yang ditentukan', () {
      final backoff = SyncBackoff(jitterRatio: 0.2, random: Random(42));

      for (var i = 0; i < 200; i++) {
        final delay = backoff.delayFor(3).inMilliseconds;
        expect(delay, greaterThanOrEqualTo(32000));
        expect(delay, lessThanOrEqualTo(48000));
      }
    });

    test('menghasilkan nilai yang berbeda-beda', () {
      final backoff = SyncBackoff(jitterRatio: 0.2, random: Random(7));
      final values = {
        for (var i = 0; i < 20; i++) backoff.delayFor(5).inMilliseconds,
      };

      expect(values.length, greaterThan(1));
    });
  });

  group('batas percobaan', () {
    final backoff = SyncBackoff(maxAttempts: 10);

    test('belum menyerah sebelum batas', () {
      expect(backoff.isExhausted(9), isFalse);
    });

    test('menyerah tepat di batas', () {
      expect(backoff.isExhausted(10), isTrue);
    });
  });

  test('nextAttemptAt menambahkan jeda ke waktu sekarang', () {
    final backoff = SyncBackoff(jitterRatio: 0);
    final now = DateTime.utc(2026, 1, 1, 12);

    expect(backoff.nextAttemptAt(now, 0), now.add(const Duration(seconds: 5)));
  });
}
