/// Nota teks: isinya benar dan tidak membocorkan data internal.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/transactions/domain/receipt.dart';
import 'package:smart_toko/features/transactions/domain/transaction_record.dart';

TxRecord record({
  bool onCredit = false,
  int paid = 0,
  List<TxItemRecord>? items,
}) => TxRecord(
  id: 't1',
  storeId: 's1',
  direction: TxDirection.masuk,
  category: TxCategory.penjualan,
  occurredAt: DateTime(2026, 10, 12, 14, 30),
  source: TxSource.manual,
  totalAmount: 35000,
  createdAt: DateTime(2026, 10, 12),
  updatedAt: DateTime(2026, 10, 12),
  onCredit: onCredit,
  paidAmount: paid,
  recordedBy: 'rahasia@contoh.com',
  items:
      items ??
      const [
        TxItemRecord(
          id: 'i1',
          transactionId: 't1',
          name: 'Nasi goreng',
          qty: 2,
          unitPrice: 15000,
          lineTotal: 30000,
        ),
        TxItemRecord(
          id: 'i2',
          transactionId: 't1',
          name: 'Es teh',
          qty: 1,
          unitPrice: 5000,
          lineTotal: 5000,
        ),
      ],
);

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test('memuat toko, tanggal, barang, dan total', () {
    final text = buildReceiptText(record(), storeName: 'Warung Bahari');

    expect(text, contains('Warung Bahari'));
    expect(text, contains('12 Okt 2026 14:30'));
    expect(text, contains('Nasi goreng 2'));
    expect(text, contains('2 x Rp15.000 = Rp30.000'));
    expect(text, contains('TOTAL: Rp35.000'));
    expect(text, isNot(contains('LUNAS')));
  });

  test('tidak memuat email pencatat', () {
    expect(
      buildReceiptText(record(), storeName: 'Warung'),
      isNot(contains('rahasia@contoh.com')),
    );
  });

  test('menyebut nama pelanggan bila ada', () {
    expect(
      buildReceiptText(record(), storeName: 'Warung', contactName: 'Bu Sari'),
      contains('Untuk: Bu Sari'),
    );
  });

  test(
    'harga total yang tidak habis dibagi tidak memajang harga satuan palsu',
    () {
      final text = buildReceiptText(
        record(
          items: const [
            TxItemRecord(
              id: 'i1',
              transactionId: 't1',
              name: 'Ayam',
              qty: 3,
              unitPrice: 8333,
              lineTotal: 25000,
            ),
          ],
        ),
        storeName: 'Warung',
      );

      expect(text, isNot(contains('8.333')));
      expect(text, contains('Rp25.000'));
    },
  );

  test('kasbon belum lunas menampilkan dibayar dan sisa', () {
    final text = buildReceiptText(
      record(onCredit: true, paid: 10000),
      storeName: 'Warung',
    );

    expect(text, contains('Dibayar: Rp10.000'));
    expect(text, contains('Sisa belum dibayar: Rp25.000'));
  });

  test('kasbon yang sudah lunas ditandai LUNAS', () {
    final text = buildReceiptText(
      record(onCredit: true, paid: 35000),
      storeName: 'Warung',
    );

    expect(text, contains('LUNAS'));
    expect(text, isNot(contains('Sisa belum dibayar')));
  });
}
