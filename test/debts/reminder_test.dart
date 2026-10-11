/// Pesan pengingat dan tautan WhatsApp.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:smart_toko/features/debts/reminder.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('normalizeIndonesianPhone', () {
    test('nomor lokal berawalan 0 diubah ke 62', () {
      expect(normalizeIndonesianPhone('0812-3456-789'), '628123456789');
      expect(normalizeIndonesianPhone('0812 3456 7890'), '6281234567890');
    });

    test('format internasional dipertahankan', () {
      expect(normalizeIndonesianPhone('+62 812 3456 789'), '628123456789');
      expect(normalizeIndonesianPhone('628123456789'), '628123456789');
    });

    test('nomor tanpa 0 di depan dilengkapi', () {
      expect(normalizeIndonesianPhone('8123456789'), '628123456789');
    });

    test('bukan nomor yang masuk akal menghasilkan null', () {
      expect(normalizeIndonesianPhone(null), isNull);
      expect(normalizeIndonesianPhone(''), isNull);
      expect(normalizeIndonesianPhone('abc'), isNull);
      expect(normalizeIndonesianPhone('0812'), isNull);
      expect(normalizeIndonesianPhone('+1 415 555 0100'), isNull);
    });
  });

  group('pesan', () {
    test('menyebut nama, toko, jumlah, dan sejak kapan', () {
      final message = buildReminderMessage(
        contactName: 'Bu Sari',
        storeName: 'Warung Bahari',
        outstanding: 40000,
        openCount: 1,
        since: DateTime(2026, 10, 1),
      );

      expect(message, contains('Bu Sari'));
      expect(message, contains('Warung Bahari'));
      expect(message, contains('Rp40.000'));
      expect(message, contains('1 Okt 2026'));
      expect(message, isNot(contains('transaksi)')));
    });

    test('menyebut jumlah transaksi bila lebih dari satu', () {
      final message = buildReminderMessage(
        contactName: 'Bu Sari',
        storeName: 'Warung Bahari',
        outstanding: 40000,
        openCount: 3,
        since: DateTime(2026, 10, 1),
      );

      expect(message, contains('(3 transaksi)'));
    });
  });

  group('whatsappLink', () {
    test('memuat nomor dan pesan yang di-encode', () {
      final link = whatsappLink('0812-3456-789', 'Halo & terima kasih')!;

      expect(link.host, 'wa.me');
      expect(link.path, '/628123456789');
      expect(link.queryParameters['text'], 'Halo & terima kasih');
    });

    test('tanpa nomor valid tidak ada tautan', () {
      expect(whatsappLink(null, 'x'), isNull);
      expect(whatsappLink('12', 'x'), isNull);
    });
  });
}
