/// Penyimpan rahasia di Keystore/Keychain perangkat.
///
/// Kunci API TIDAK PERNAH ditulis di kode sumber maupun ikut dibundel ke APK.
/// Pengguna memasukkannya sendiri di Pengaturan, dan nilainya hanya hidup di
/// penyimpanan aman milik sistem operasi.
///
/// Untuk rilis publik, memanggil API pihak ketiga langsung dari aplikasi tetap
/// bukan pilihan terbaik — kunci di perangkat yang sudah di-root masih bisa
/// digali. Jalur produksinya adalah proxy backend, dan itu dicatat di
/// DESIGN_DECISIONS.md.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class KeyStore {
  Future<String?> readLlmApiKey();

  Future<void> writeLlmApiKey(String value);

  Future<void> deleteLlmApiKey();

  Future<bool> hasLlmApiKey();
}

class SecureKeyStore implements KeyStore {
  static const String _llmApiKey = 'llm_api_key';

  final FlutterSecureStorage _storage;

  /// Nilai bawaan flutter_secure_storage 11 sudah memakai AES-GCM dengan
  /// pembungkusan kunci RSA-OAEP, jadi tidak ada opsi yang perlu disetel.
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> readLlmApiKey() => _storage.read(key: _llmApiKey);

  @override
  Future<void> writeLlmApiKey(String value) =>
      _storage.write(key: _llmApiKey, value: value);

  @override
  Future<void> deleteLlmApiKey() => _storage.delete(key: _llmApiKey);

  @override
  Future<bool> hasLlmApiKey() async {
    final value = await readLlmApiKey();
    return value != null && value.isNotEmpty;
  }
}

class InMemoryKeyStore implements KeyStore {
  String? _key;

  InMemoryKeyStore([this._key]);

  @override
  Future<String?> readLlmApiKey() async => _key;

  @override
  Future<void> writeLlmApiKey(String value) async => _key = value;

  @override
  Future<void> deleteLlmApiKey() async => _key = null;

  @override
  Future<bool> hasLlmApiKey() async => (_key ?? '').isNotEmpty;
}
