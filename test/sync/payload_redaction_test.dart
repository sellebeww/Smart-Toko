/// Penjaga janji privasi.
///
/// Bila salah satu tes di berkas ini gagal, artinya ada jalur yang bisa
/// mengirim data identitas keluar perangkat tanpa persetujuan terpisah. Jangan
/// melonggarkan tesnya — perbaiki jalurnya.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_toko/core/sync/sync_payload_builder.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/transactions/domain/transaction_record.dart';

void main() {
  const builder = SyncPayloadBuilder();

  Map<String, Object?> sampleWithIdentity() => {
    'id': 'store-1',
    'name': 'Warung Bu Sri',
    'ktp_number': '3201234567890001',
    'ktp_image_path': '/data/ktp.enc',
    'nib': '1234567890',
    'owner_name': 'Sri Wahyuni',
    'owner_address': 'Jl. Melati 12',
  };

  group('tanpa persetujuan identitas', () {
    test('seluruh field identitas dibuang', () {
      final payload = builder.build(
        sampleWithIdentity(),
        identityConsent: false,
      );

      for (final field in identityFieldNames) {
        expect(
          payload.containsKey(field),
          isFalse,
          reason: '$field tidak boleh ikut terkirim',
        );
      }
    });

    test('field non-identitas tetap utuh', () {
      final payload = builder.build(
        sampleWithIdentity(),
        identityConsent: false,
      );

      expect(payload['id'], 'store-1');
      expect(payload['name'], 'Warung Bu Sri');
    });

    test('field identitas yang bersarang ikut dibuang', () {
      final payload = builder.build({
        'id': 'store-1',
        'pemilik': {'owner_name': 'Sri', 'kota': 'Yogyakarta'},
      }, identityConsent: false);

      final nested = payload['pemilik']! as Map<String, Object?>;
      expect(nested.containsKey('owner_name'), isFalse);
      expect(nested['kota'], 'Yogyakarta');
    });

    test('field identitas di dalam daftar ikut dibuang', () {
      final payload = builder.build({
        'dokumen': [
          {'ktp_number': '320123', 'jenis': 'ktp'},
          {'jenis': 'nib'},
        ],
      }, identityConsent: false);

      final list = payload['dokumen']! as List;
      final first = list.first as Map<String, Object?>;
      expect(first.containsKey('ktp_number'), isFalse);
      expect(first['jenis'], 'ktp');
    });
  });

  group('dengan persetujuan identitas eksplisit', () {
    test('field identitas boleh ikut', () {
      final payload = builder.build(
        sampleWithIdentity(),
        identityConsent: true,
      );

      expect(payload['ktp_number'], '3201234567890001');
      expect(payload['owner_name'], 'Sri Wahyuni');
    });
  });

  group('payload transaksi', () {
    TxRecord record() => TxRecord(
      id: 'tx-1',
      storeId: 'store-1',
      direction: TxDirection.masuk,
      category: TxCategory.penjualan,
      occurredAt: DateTime.utc(2026, 1, 1),
      source: TxSource.voice,
      totalAmount: 10000,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      items: const [
        TxItemRecord(
          id: 'item-1',
          transactionId: 'tx-1',
          name: 'indomie',
          qty: 2,
          unitPrice: 5000,
          lineTotal: 10000,
        ),
      ],
    );

    test('memuat data transaksi apa adanya', () {
      final payload = builder.buildTransaction(
        record(),
        identityConsent: false,
      );

      expect(payload['id'], 'tx-1');
      expect(payload['total_amount'], 10000);
      expect(payload['items'], hasLength(1));
    });

    test('tidak pernah memuat satu pun field identitas', () {
      final payload = builder.buildTransaction(
        record(),
        identityConsent: false,
      );

      for (final field in identityFieldNames) {
        expect(payload.containsKey(field), isFalse);
      }
    });
  });

  test('payload yang dihasilkan tidak bisa diubah setelah dibentuk', () {
    final payload = builder.build({'id': 'x'}, identityConsent: false);

    expect(() => payload['ktp_number'] = 'bocor', throwsUnsupportedError);
  });
}
