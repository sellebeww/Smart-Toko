/// Pembacaan harga per-satuan vs total, satuan, dan kategori transaksi.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_toko/core/confidence.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/voice_parser/rules/rule_parser.dart';

void main() {
  const parser = RuleBasedParser();

  group('harga per satuan atau total', () {
    test('contoh pitch deck: "beli ayam 5 kg 200 ribu" = total 200 ribu', () {
      final result = parser.parse('beli ayam 5 kg dua ratus ribu');
      final item = result.items.single;

      expect(item.name.value, 'ayam');
      expect(item.qty.value, 5);
      expect(item.unit, 'kg');
      expect(item.unitPrice.value, 200000);
      expect(item.priceMode.value, PriceMode.total);
      expect(item.lineTotal, 200000);
      expect(result.computedTotal, 200000);
    });

    test('tebakan total tanpa penanda tetap disorot untuk dicek', () {
      final item = parser.parse('beli ayam 5 kg 200 ribu').items.single;

      expect(item.priceMode.band, ConfidenceBand.check);
    });

    test('barang satuan hitung dibaca per satuan', () {
      final item = parser
          .parse('jual gorengan sepuluh biji seribu')
          .items
          .single;

      expect(item.priceMode.value, PriceMode.perUnit);
      expect(item.lineTotal, 10000);
    });

    test('"per kilo" memaksa per satuan dan tidak mengotori nama', () {
      final result = parser.parse('beli ayam 5 kilo 40 ribu per kilo');
      final item = result.items.single;

      expect(item.name.value, 'ayam');
      expect(item.priceMode.value, PriceMode.perUnit);
      expect(item.priceMode.band, ConfidenceBand.good);
      expect(item.lineTotal, 200000);
      expect(result.unmatchedTokens, isEmpty);
    });

    test('"semuanya" memaksa total walau satuannya hitungan', () {
      final item = parser
          .parse('jual es teh 4 gelas semuanya 12 ribu')
          .items
          .single;

      expect(item.priceMode.value, PriceMode.total);
      expect(item.lineTotal, 12000);
    });

    test('satu barang: per satuan dan total sama saja', () {
      final item = parser.parse('bayar listrik seratus ribu').items.single;

      expect(item.lineTotal, 100000);
      expect(item.priceMode.band, ConfidenceBand.good);
    });

    test('satuan dinormalisasi', () {
      expect(parser.parse('beli gula 3 kilo 45 ribu').items.single.unit, 'kg');
      expect(
        parser.parse('beli minyak 2 ltr 32 ribu').items.single.unit,
        'liter',
      );
    });
  });

  group('kategori', () {
    test('kata jual = penjualan', () {
      expect(
        parser.parse('jual nasi ayam 2 porsi 30 ribu').category.value,
        TxCategory.penjualan,
      );
    });

    test('kulakan = pembelian bahan', () {
      expect(
        parser.parse('kulakan beras 10 kilo 150 ribu').category.value,
        TxCategory.pembelian,
      );
    });

    test('"beli gas" = pengeluaran operasional, bukan bahan', () {
      final result = parser.parse('beli gas 3 kilo 22 ribu');

      expect(result.direction.value, TxDirection.keluar);
      expect(result.category.value, TxCategory.pengeluaran);
    });

    test('bayar listrik = pengeluaran operasional', () {
      expect(
        parser.parse('bayar listrik seratus ribu').category.value,
        TxCategory.pengeluaran,
      );
    });

    test('"masuk" tanpa barang = pemasukan lain', () {
      expect(
        parser.parse('masuk lima puluh ribu').category.value,
        TxCategory.pemasukanLain,
      );
    });

    test('tanpa kata arah, kategori juga kosong', () {
      expect(parser.parse('teh botol 3 15rb').category.isPresent, isFalse);
    });
  });
}
