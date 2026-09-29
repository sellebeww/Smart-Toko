/// Korpus regresi parser.
///
/// Setiap ucapan yang pernah salah diurai di lapangan sebaiknya ditambahkan ke
/// sini sebelum aturannya diperbaiki, supaya perbaikan terbukti dan tidak
/// diam-diam merusak kasus lain.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_toko/core/confidence.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/voice_parser/rules/rule_parser.dart';

class Expected {
  final TxDirection? direction;
  final String? name;
  final int? qty;
  final int? price;

  const Expected({this.direction, this.name, this.qty, this.price});
}

void main() {
  const parser = RuleBasedParser();

  const corpus = <String, Expected>{
    'jual indomie dua bungkus lima ribu': Expected(
      direction: TxDirection.masuk,
      name: 'indomie',
      qty: 2,
      price: 5000,
    ),
    'jual indomie dua lima ribu': Expected(
      direction: TxDirection.masuk,
      name: 'indomie',
      qty: 2,
      price: 5000,
    ),
    'jual es teh dua ribu': Expected(
      direction: TxDirection.masuk,
      name: 'es teh',
      qty: 1,
      price: 2000,
    ),
    'jual gorengan sepuluh biji seribu': Expected(
      direction: TxDirection.masuk,
      name: 'gorengan',
      qty: 10,
      price: 1000,
    ),
    'jual rokok sampoerna satu bungkus dua puluh delapan ribu': Expected(
      direction: TxDirection.masuk,
      name: 'rokok sampoerna',
      qty: 1,
      price: 28000,
    ),
    'terjual air mineral 5 botol harga 3000': Expected(
      direction: TxDirection.masuk,
      name: 'air mineral',
      qty: 5,
      price: 3000,
    ),
    'beli gula tiga kilo dua puluh empat ribu': Expected(
      direction: TxDirection.keluar,
      name: 'gula',
      qty: 3,
      price: 24000,
    ),
    'beli minyak goreng dua liter tiga puluh dua ribu': Expected(
      direction: TxDirection.keluar,
      name: 'minyak goreng',
      qty: 2,
      price: 32000,
    ),
    'kulakan beras sepuluh kilo seratus lima puluh ribu': Expected(
      direction: TxDirection.keluar,
      name: 'beras',
      qty: 10,
      price: 150000,
    ),
    'bayar listrik seratus ribu': Expected(
      direction: TxDirection.keluar,
      name: 'listrik',
      qty: 1,
      price: 100000,
    ),
    'masuk lima puluh ribu': Expected(
      direction: TxDirection.masuk,
      name: null,
      qty: 1,
      price: 50000,
    ),
    // Tanpa kata arah: nama tetap terbaca, arah sengaja dibiarkan kosong.
    'teh botol 3 15rb': Expected(
      direction: null,
      name: 'teh botol',
      qty: 3,
      price: 15000,
    ),
  };

  group('korpus', () {
    corpus.forEach((utterance, want) {
      test('"$utterance"', () {
        final result = parser.parse(utterance);
        final item = result.items.isEmpty ? null : result.items.first;

        expect(result.direction.value, want.direction, reason: 'arah');
        expect(item?.name.value, want.name, reason: 'nama');
        expect(item?.qty.value, want.qty, reason: 'jumlah');
        expect(item?.unitPrice.value, want.price, reason: 'harga');
      });
    });
  });

  group('beberapa barang dalam satu ucapan', () {
    test('dipisah kata "dan"', () {
      final result = parser.parse(
        'jual indomie dua bungkus lima ribu dan teh botol tiga 15rb',
      );

      expect(result.items, hasLength(2));
      expect(result.items[0].name.value, 'indomie');
      expect(result.items[1].name.value, 'teh botol');
      expect(result.computedTotal, 10000 + 45000);
    });

    test('dipisah koma', () {
      final result = parser.parse(
        'jual pulsa 10rb, rokok satu bungkus 28 ribu',
      );

      expect(result.items, hasLength(2));
      expect(result.items[0].unitPrice.value, 10000);
      expect(result.items[1].unitPrice.value, 28000);
    });
  });

  group('arah transaksi tidak pernah ditebak', () {
    test('tanpa kata arah, field arah kosong dan wajib ditinjau', () {
      final result = parser.parse('teh botol 3 15rb');

      expect(result.direction.isPresent, isFalse);
      expect(result.needsReview, isTrue);
    });
  });

  group('keyakinan', () {
    test('ucapan jelas menghasilkan pita good', () {
      final result = parser.parse('jual indomie dua bungkus lima ribu');

      expect(result.overall.band, ConfidenceBand.good);
      expect(result.needsReview, isFalse);
    });

    test('angka telanjang tanpa satuan menurunkan keyakinan kuantitas', () {
      final result = parser.parse('jual indomie dua lima ribu');
      final qty = result.items.first.qty;

      expect(qty.value, 2);
      expect(qty.confidence.value, lessThan(Confidence.goodThreshold));
    });

    test('engine STT yang melaporkan 0.0 sebagai "tidak diketahui" '
        'tidak membuat semua field jatuh ke poor', () {
      final result = parser.parse(
        'jual indomie dua bungkus lima ribu',
        sttConfidence: const Confidence.unknown(),
      );

      expect(result.overall.isUnknown, isTrue);
      expect(result.overall.band, ConfidenceBand.check);
      expect(result.overall.band, isNot(ConfidenceBand.poor));
    });
  });
}
