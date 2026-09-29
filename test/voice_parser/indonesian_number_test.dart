import 'package:flutter_test/flutter_test.dart';
import 'package:smart_toko/features/voice_parser/rules/indonesian_number.dart';

int? _read(String input) {
  final tokens = normalizeNumericText(input).split(RegExp(r'\s+'));
  return readNumberAt(tokens, 0)?.asRupiah;
}

void main() {
  group('sebutan angka Bahasa Indonesia', () {
    const cases = <String, int>{
      'seribu': 1000,
      'sepuluh ribu': 10000,
      'sebelas ribu': 11000,
      'dua belas ribu': 12000,
      'sembilan belas ribu': 19000,
      'lima ribu': 5000,
      'dua puluh lima ribu': 25000,
      'empat puluh dua ribu': 42000,
      'delapan puluh ribu': 80000,
      'seratus ribu': 100000,
      'seratus lima puluh ribu': 150000,
      'tujuh ratus lima puluh ribu': 750000,
      'satu juta': 1000000,
      'dua juta lima ratus ribu': 2500000,
      'setengah juta': 500000,
      'dua setengah juta': 2500000,
      'tiga ratus': 300,
      'lima puluh': 50,
      'dua ribu lima ratus': 2500,
    };

    cases.forEach((input, expected) {
      test('"$input" -> $expected', () => expect(_read(input), expected));
    });
  });

  group('ragam tulisan informal', () {
    const cases = <String, int>{
      '25rb': 25000,
      '25k': 25000,
      '15 ribu': 15000,
      '25.000': 25000,
      '1.250.000': 1250000,
      '2,5jt': 2500000,
    };

    cases.forEach((input, expected) {
      test('"$input" -> $expected', () => expect(_read(input), expected));
    });
  });

  group('pemisahan beberapa angka dalam satu kalimat', () {
    test('kuantitas dan harga terbaca terpisah', () {
      final tokens = normalizeNumericText('jual indomie dua lima ribu')
          .split(RegExp(r'\s+'));
      final numbers = readAllNumbers(tokens);

      expect(numbers.map((n) => n.asRupiah), [2, 5000]);
    });

    test('satuan di antara angka tidak menggabungkan keduanya', () {
      final tokens = normalizeNumericText(
        'beli gula tiga kilo dua puluh empat ribu',
      ).split(RegExp(r'\s+'));
      final numbers = readAllNumbers(tokens);

      expect(numbers.map((n) => n.asRupiah), [3, 24000]);
    });
  });

  group('bukan angka', () {
    test('kata biasa mengembalikan null', () {
      expect(_read('indomie'), isNull);
    });

    test('"setengah" tanpa skala sesudahnya bukan angka', () {
      expect(_read('setengah'), isNull);
    });
  });
}
