/// Akses setelan aplikasi.
///
/// Semua sakelar privasi di sini bersifat GAGAL-TERTUTUP: bila barisnya tidak
/// ada, nilainya false. Dengan begitu basis data yang baru dibuat, rusak
/// sebagian, atau gagal dimigrasi tidak akan pernah berakhir dengan
/// pencadangan atau pengiriman transkrip yang menyala tanpa sepengetahuan
/// pengguna.
library;

import 'package:sqflite/sqflite.dart';

class SettingsKeys {
  static const String backupEnabled = 'backup_enabled';
  static const String llmEnabled = 'llm_enabled';
  static const String errorReportsEnabled = 'error_reports_enabled';

  /// Pengingat terjadwal. Waktu disimpan sebagai "HH:mm".
  static const String reminderDaily = 'reminder_daily';
  static const String reminderTime = 'reminder_time';
  static const String reminderDue = 'reminder_due';

  /// Tawaran menyalakan pengingat di beranda sudah dijawab.
  static const String reminderOfferAnswered = 'reminder_offer_answered';

  /// Kunci PIN: hash + garam PIN, dan penghitung percobaan salah.
  static const String appLockHash = 'app_lock_hash';
  static const String appLockSalt = 'app_lock_salt';
  static const String appLockFailed = 'app_lock_failed';
  static const String appLockBlockedUntil = 'app_lock_blocked_until';
  static const String appLockBiometric = 'app_lock_biometric';
  static const String onboardingDone = 'onboarding_done';
  static const String activeStoreId = 'active_store_id';

  /// Per toko: waktu cadangan terakhir yang berhasil (milidetik epoch).
  static String lastBackupAt(String storeId) => 'last_backup_at:$storeId';

  /// Per toko: sidik isi data saat cadangan terakhir, supaya cadangan
  /// otomatis tidak mengunggah ulang data yang tidak berubah.
  static String lastBackupFingerprint(String storeId) =>
      'last_backup_fingerprint:$storeId';
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

  Future<void> remove(String key) async {
    await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<bool> backupEnabled() => getFlag(SettingsKeys.backupEnabled);

  Future<bool> llmEnabled() => getFlag(SettingsKeys.llmEnabled);

  Future<bool> errorReportsEnabled() =>
      getFlag(SettingsKeys.errorReportsEnabled);
}
