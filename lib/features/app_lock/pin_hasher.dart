/// Penyimpanan PIN sebagai hash berkunci garam, bukan teks asli.
///
/// PIN pendek memang tidak tahan serangan luring bila basis datanya dicopot
/// dari HP, jadi kunci ini melindungi dari orang yang memegang HP yang
/// sedang menyala — bukan dari penyerang yang mengambil berkas data. Hash
/// berulang (PBKDF2-HMAC-SHA256) hanya memperlambat tebakan seperlunya.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int minPinLength = 4;
const int maxPinLength = 6;

/// 4 sampai 6 angka.
bool isValidPin(String pin) =>
    RegExp('^\\d{$minPinLength,$maxPinLength}\$').hasMatch(pin);

/// PIN yang terlalu mudah ditebak: semua angka sama (0000) atau berurutan
/// (1234, 4321).
bool isWeakPin(String pin) {
  if (pin.isEmpty) return true;
  if (pin.split('').every((c) => c == pin[0])) return true;
  final digits = pin.codeUnits;
  var up = true;
  var down = true;
  for (var i = 1; i < digits.length; i++) {
    if (digits[i] != digits[i - 1] + 1) up = false;
    if (digits[i] != digits[i - 1] - 1) down = false;
  }
  return up || down;
}

String newSalt([Random? random]) {
  final rng = random ?? Random.secure();
  return base64Url.encode([for (var i = 0; i < 16; i++) rng.nextInt(256)]);
}

/// PBKDF2-HMAC-SHA256, satu blok keluaran (32 byte).
String hashPin(String pin, String salt, {int iterations = 20000}) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  final saltBytes = [...base64Url.decode(salt), 0, 0, 0, 1];
  var u = hmac.convert(saltBytes).bytes;
  final result = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return base64Url.encode(result);
}

/// Perbandingan waktu-tetap supaya lama pemeriksaan tidak membocorkan
/// seberapa mirip tebakannya.
bool verifyPin(String pin, {required String salt, required String expected}) {
  final actual = hashPin(pin, salt);
  if (actual.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return diff == 0;
}

/// Versi yang berjalan di isolate terpisah. Hash berulang memakan puluhan
/// milidetik di HP cepat dan jauh lebih lama di HP murah; di thread UI itu
/// terasa sebagai layar kunci yang tersendat.
Future<String> hashPinAsync(String pin, String salt) =>
    Isolate.run(() => hashPin(pin, salt));

Future<bool> verifyPinAsync(
  String pin, {
  required String salt,
  required String expected,
}) => Isolate.run(() => verifyPin(pin, salt: salt, expected: expected));
