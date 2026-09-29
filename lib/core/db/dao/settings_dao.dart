/// Akses setelan aplikasi.
///
/// Semua sakelar privasi di sini bersifat GAGAL-TERTUTUP: bila barisnya tidak
/// ada, nilainya false. Dengan begitu basis data yang baru dibuat, rusak
/// sebagian, atau gagal dimigrasi tidak akan pernah berakhir dengan
/// sinkronisasi atau pengiriman transkrip yang menyala tanpa sepengetahuan
/// pengguna.
library;

import 'package:sqflite/sqflite.dart';

class SettingsKeys {
  static const String syncEnabled = 'sync_enabled';
  static const String llmEnabled = 'llm_enabled';
  static const String qrisEnabled = 'qris_enabled';
  static const String onboardingDone = 'onboarding_done';
  static const String activeStoreId = 'active_store_id';
}

class SettingsDao {
  final DatabaseExecutor db;

  const SettingsDao(this.db);

  Future<String?> getString(String key) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setString(String key, String value) async {
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> getFlag(String key) async => await getString(key) == 'true';

  Future<void> setFlag(String key, {required bool value}) =>
      setString(key, value ? 'true' : 'false');

  Future<bool> syncEnabled() => getFlag(SettingsKeys.syncEnabled);

  Future<bool> llmEnabled() => getFlag(SettingsKeys.llmEnabled);

  Future<bool> qrisEnabled() => getFlag(SettingsKeys.qrisEnabled);
}
