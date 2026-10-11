/// PIN disimpan sebagai hash; PIN lemah ditolak.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_toko/features/app_lock/pin_hasher.dart';

void main() {
  group('isValidPin', () {
    test('4 sampai 6 angka', () {
      for (final pin in ['1357', '24680', '864209']) {
        expect(isValidPin(pin), isTrue, reason: pin);
      }
    });

    test('selain itu ditolak', () {
      for (final pin in ['', '123', '1234567', '12a4', '12 34', '１２３４']) {
        expect(isValidPin(pin), isFalse, reason: pin);
      }
    });
  });

  group('isWeakPin', () {
    test('angka sama dan berurutan lemah', () {
      for (final pin in ['0000', '1111', '123456', '1234', '4321', '987654']) {
        expect(isWeakPin(pin), isTrue, reason: pin);
      }
    });

    test('PIN acak tidak lemah', () {
      for (final pin in ['1357', '2580', '8642', '135790']) {
        expect(isWeakPin(pin), isFalse, reason: pin);
      }
    });
  });

  group('hash', () {
    test('PIN benar lolos, salah ditolak', () {
      final salt = newSalt();
      final hash = hashPin('2580', salt);

      expect(verifyPin('2580', salt: salt, expected: hash), isTrue);
      expect(verifyPin('2581', salt: salt, expected: hash), isFalse);
      expect(verifyPin('', salt: salt, expected: hash), isFalse);
    });

    test('hash tidak memuat PIN dan bergantung pada garam', () {
      final a = hashPin('2580', newSalt());
      final b = hashPin('2580', newSalt());

      expect(a, isNot(contains('2580')));
      expect(a, isNot(b), reason: 'garam berbeda → hash berbeda');
    });

    test('deterministik untuk PIN dan garam yang sama', () {
      final salt = newSalt();

      expect(hashPin('2580', salt), hashPin('2580', salt));
    });

    test('garam acak dan cukup panjang', () {
      final salts = {for (var i = 0; i < 50; i++) newSalt()};

      expect(salts, hasLength(50));
      expect(salts.first.length, greaterThanOrEqualTo(20));
    });

    test('cocok dengan vektor uji PBKDF2-HMAC-SHA256 yang dipublikasikan', () {
      // password="password", salt="salt", dkLen=32 (blok pertama saja).
      final salt = base64Url.encode(utf8.encode('salt'));
      String hex(String hash) => [
        for (final b in base64Url.decode(hash))
          b.toRadixString(16).padLeft(2, '0'),
      ].join();

      expect(
        hex(hashPin('password', salt, iterations: 1)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
      expect(
        hex(hashPin('password', salt, iterations: 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
      expect(
        hex(hashPin('password', salt, iterations: 4096)),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });
  });
}
