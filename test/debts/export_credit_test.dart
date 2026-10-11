/// Ekspor Excel memuat status bayar dan sisa kasbon.
library;

import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/export/excel_exporter.dart';
import 'package:smart_toko/features/transactions/domain/transaction_record.dart';

TxRecord tx(String id, {bool onCredit = false, int paid = 0}) => TxRecord(
  id: id,
  storeId: 's1',
  direction: TxDirection.masuk,
  category: TxCategory.penjualan,
  occurredAt: DateTime(2026, 10, 12, 9),
  source: TxSource.manual,
  totalAmount: 30000,
  createdAt: DateTime(2026, 10, 12),
  updatedAt: DateTime(2026, 10, 12),
  onCredit: onCredit,
  paidAmount: paid,
  items: [
    for (final n in ['a', 'b'])
      TxItemRecord(
        id: '$id$n',
        transactionId: id,
        name: 'barang $n',
        qty: 1,
        unitPrice: 15000,
        lineTotal: 15000,
      ),
  ],
);

void main() {
  List<List<Object?>> readRows(List<TxRecord> records) {
    final excel = Excel.decodeBytes(
      Uint8List.fromList(buildTransactionsWorkbook(records)),
    );
    return [
      for (final row in excel[transactionsSheetName].rows)
        [for (final cell in row) cell?.value?.toString()],
    ];
  }

  final statusCol = transactionsHeader.indexOf('Status Bayar');
  final remainingCol = transactionsHeader.indexOf('Sisa Belum Dibayar');

  test('kolom status dan sisa ada di header', () {
    expect(statusCol, greaterThanOrEqualTo(0));
    expect(remainingCol, greaterThan(statusCol));
  });

  test('transaksi tunai ditandai Tunai tanpa sisa', () {
    final rows = readRows([tx('t1')]);

    expect(rows[1][statusCol], 'Tunai');
    expect(rows[1][remainingCol] ?? '', isEmpty);
  });

  test('kasbon belum lunas: sisa hanya di baris pertama transaksi', () {
    final rows = readRows([tx('t1', onCredit: true, paid: 10000)]);

    expect(rows[1][statusCol], 'Belum lunas');
    expect(rows[1][remainingCol], '20000');
    expect(rows[2][statusCol], 'Belum lunas');
    expect(
      rows[2][remainingCol] ?? '',
      isEmpty,
      reason: 'jangan dihitung dua kali',
    );
  });

  test('kasbon lunas ditandai Lunas tanpa sisa', () {
    final rows = readRows([tx('t1', onCredit: true, paid: 30000)]);

    expect(rows[1][statusCol], 'Lunas');
    expect(rows[1][remainingCol] ?? '', isEmpty);
  });
}
