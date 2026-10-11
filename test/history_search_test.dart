/// Pencarian dan filter "belum lunas" pada riwayat.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/transactions/domain/history_filter.dart';
import 'package:smart_toko/features/transactions/domain/transaction_record.dart';

TxRecord tx(
  String id, {
  required String item,
  String? note,
  String? contactId,
  TxCategory category = TxCategory.penjualan,
  bool onCredit = false,
  int paid = 0,
}) => TxRecord(
  id: id,
  storeId: 's1',
  direction: category.direction,
  category: category,
  occurredAt: DateTime(2026, 10, 12),
  source: TxSource.manual,
  totalAmount: 20000,
  createdAt: DateTime(2026, 10, 12),
  updatedAt: DateTime(2026, 10, 12),
  note: note,
  contactId: contactId,
  onCredit: onCredit,
  paidAmount: paid,
  items: [
    TxItemRecord(
      id: 'i$id',
      transactionId: id,
      name: item,
      qty: 1,
      unitPrice: 20000,
      lineTotal: 20000,
    ),
  ],
);

void main() {
  final records = [
    tx('1', item: 'Nasi Goreng', contactId: 'sari'),
    tx('2', item: 'Ayam Potong', category: TxCategory.pembelian),
    tx('3', item: 'Es Teh', note: 'untuk acara RT'),
    tx('4', item: 'Mie Ayam', onCredit: true, contactId: 'budi'),
    tx('5', item: 'Kopi', onCredit: true, paid: 20000, contactId: 'budi'),
  ];
  const names = {'sari': 'Bu Sari', 'budi': 'Pak Budi'};

  List<String> ids(HistoryFilter f) => [
    for (final r in f.applyLocal(records, contactNames: names)) r.id,
  ];

  test('tanpa kata kunci dan filter, semua lolos', () {
    expect(ids(const HistoryFilter()), ['1', '2', '3', '4', '5']);
    expect(const HistoryFilter().isNarrowed, isFalse);
  });

  test('cocok dengan nama barang tanpa peduli huruf besar', () {
    expect(ids(const HistoryFilter(query: 'AYAM')), ['2', '4']);
  });

  test('cocok dengan catatan', () {
    expect(ids(const HistoryFilter(query: 'acara rt')), ['3']);
  });

  test('cocok dengan nama pelanggan', () {
    expect(ids(const HistoryFilter(query: 'sari')), ['1']);
    expect(ids(const HistoryFilter(query: 'budi')), ['4', '5']);
  });

  test('cocok dengan nama kategori', () {
    expect(ids(const HistoryFilter(query: 'pembelian')), ['2']);
  });

  test('spasi di tepi diabaikan, kata tak ada menghasilkan kosong', () {
    expect(ids(const HistoryFilter(query: '  kopi ')), ['5']);
    expect(ids(const HistoryFilter(query: 'tidak ada')), isEmpty);
  });

  test('belum lunas hanya memuat kasbon yang masih bersisa', () {
    expect(ids(const HistoryFilter(onlyUnpaid: true)), ['4']);
  });

  test('kata kunci dan belum lunas digabung', () {
    expect(ids(const HistoryFilter(onlyUnpaid: true, query: 'budi')), ['4']);
    expect(ids(const HistoryFilter(onlyUnpaid: true, query: 'sari')), isEmpty);
  });

  test('pencarian dan belum lunas dihitung sebagai filter aktif', () {
    expect(const HistoryFilter(query: 'a').isNarrowed, isTrue);
    expect(const HistoryFilter(onlyUnpaid: true).isNarrowed, isTrue);
    expect(const HistoryFilter(query: '   ').isNarrowed, isFalse);
  });

  test('copyWith mempertahankan pencarian saat rentang diganti', () {
    final filter = const HistoryFilter(
      query: 'ayam',
      onlyUnpaid: true,
    ).copyWith(range: HistoryRange.hariIni);

    expect(filter.query, 'ayam');
    expect(filter.onlyUnpaid, isTrue);
  });
}
