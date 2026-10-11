/// Cadangan cloud per toko.
///
/// Satu berkas utuh per toko (transaksi, barang, stok, kontak) — bukan
/// sinkron per baris — supaya pemulihan di HP baru selalu lengkap dan
/// konsisten: tidak mungkin ada transaksi pulih tanpa barang atau stoknya.
///
/// Isi cadangan tetap melewati [SyncPayloadBuilder], jadi field identitas
/// tidak pernah ikut keluar perangkat. Pencadangan hanya berjalan bila
/// pengguna menyalakannya sendiri, dan hanya saat aplikasi dibuka.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/db/app_database.dart';
import '../../core/db/dao/settings_dao.dart';
import '../../core/db/migrations.dart';
import '../../core/sync/sync_payload_builder.dart';

const String backupBucket = 'backups';
const String backupFormat = 'smarttoko-backup';
const int backupFormatVersion = 1;

/// Tabel milik satu toko, dalam urutan yang aman untuk FK saat dipulihkan.
const List<String> _tables = [
  'products',
  'contacts',
  'transactions',
  'transaction_items',
  'stock_movements',
  'debt_payments',
];

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => message;
}

/// Tempat berkas cadangan disimpan. Dipisah supaya layanan bisa diuji tanpa
/// jaringan.
abstract class BackupStorage {
  Future<void> upload(String ownerUid, String storeId, Uint8List bytes);

  /// null bila belum pernah ada cadangan.
  Future<Uint8List?> download(String ownerUid, String storeId);

  /// Waktu cadangan terakhir di server, null bila belum ada.
  Future<DateTime?> lastModified(String ownerUid, String storeId);

  /// Menghapus semua cadangan milik [ownerUid].
  Future<void> deleteAll(String ownerUid);
}

class SupabaseBackupStorage implements BackupStorage {
  final SupabaseClient client;

  SupabaseBackupStorage(this.client);

  StorageFileApi get _bucket => client.storage.from(backupBucket);

  static String _path(String ownerUid, String storeId) =>
      '$ownerUid/$storeId.json.gz';

  @override
  Future<void> upload(String ownerUid, String storeId, Uint8List bytes) async {
    await _bucket.uploadBinary(
      _path(ownerUid, storeId),
      bytes,
      fileOptions: const FileOptions(
        contentType: 'application/gzip',
        upsert: true,
      ),
    );
  }

  @override
  Future<Uint8List?> download(String ownerUid, String storeId) async {
    if (await lastModified(ownerUid, storeId) == null) return null;
    return _bucket.download(_path(ownerUid, storeId));
  }

  @override
  Future<DateTime?> lastModified(String ownerUid, String storeId) async {
    final files = await _bucket.list(
      path: ownerUid,
      searchOptions: SearchOptions(search: storeId, limit: 10),
    );
    for (final file in files) {
      if (file.name == '$storeId.json.gz') {
        final stamp = file.updatedAt ?? file.createdAt;
        return stamp == null ? DateTime.now() : DateTime.parse(stamp).toLocal();
      }
    }
    return null;
  }

  @override
  Future<void> deleteAll(String ownerUid) async {
    // Storage membatasi satu halaman. Ambil semua halaman sebelum menghapus,
    // agar offset tidak melompati objek setelah daftar menyusut.
    final paths = <String>[];
    const pageSize = 100;
    for (var offset = 0; ; offset += pageSize) {
      final files = await _bucket.list(
        path: ownerUid,
        searchOptions: SearchOptions(limit: pageSize, offset: offset),
      );
      paths.addAll([
        for (final file in files)
          if (file.id != null) '$ownerUid/${file.name}',
      ]);
      if (files.length < pageSize) break;
    }
    if (paths.isNotEmpty) await _bucket.remove(paths);
  }
}

class BackupService {
  final AppDatabase database;
  final BackupStorage storage;
  final SyncPayloadBuilder payloadBuilder;

  /// Jarak minimum antar cadangan otomatis saat aplikasi dibuka ulang.
  final Duration autoInterval;

  BackupService({
    required this.database,
    required this.storage,
    this.payloadBuilder = const SyncPayloadBuilder(),
    this.autoInterval = const Duration(minutes: 10),
  });

  Database get _db => database.db;
  SettingsDao get _settings => SettingsDao(_db);

  /// Isi cadangan toko [storeId] sebagai peta yang siap dijadikan JSON.
  Future<Map<String, Object?>> snapshot(String storeId) =>
      _db.transaction((txn) => _snapshot(txn, storeId));

  Future<Map<String, Object?>> _snapshot(
    DatabaseExecutor db,
    String storeId,
  ) async {
    final tables = <String, Object?>{};
    for (final table in _tables) {
      final rows = table == 'transaction_items'
          ? await db.rawQuery(
              'SELECT i.* FROM transaction_items i '
              'JOIN transactions t ON t.id = i.transaction_id '
              'WHERE t.store_id = ?',
              [storeId],
            )
          : await db.query(table, where: 'store_id = ?', whereArgs: [storeId]);
      tables[table] = rows;
    }
    return payloadBuilder.build({
      'format': backupFormat,
      'format_version': backupFormatVersion,
      'schema_version': schemaVersion,
      'store_id': storeId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    }, identityConsent: false);
  }

  static Uint8List encode(Map<String, Object?> snapshot) =>
      Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(snapshot))));

  static Map<String, dynamic> decode(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(gzip.decode(bytes)));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Ditangani di bawah.
    }
    throw const BackupException('Berkas cadangan rusak atau tidak dikenali.');
  }

  /// Sidik ringkas isi data toko. Berubah setiap kali ada data yang
  /// ditambah, diubah, atau dihapus.
  Future<String> fingerprint(String storeId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT
        (SELECT COUNT(*) || ':' || COALESCE(MAX(updated_at), 0) || ':' ||
                COALESCE(SUM(total_amount), 0)
           FROM transactions WHERE store_id = ?1) AS t,
        (SELECT COUNT(*) || ':' || COALESCE(MAX(updated_at), 0) || ':' ||
                COALESCE(SUM(archived), 0)
           FROM products WHERE store_id = ?1) AS p,
        (SELECT COUNT(*) || ':' || COALESCE(MAX(updated_at), 0)
           FROM contacts WHERE store_id = ?1) AS c,
        (SELECT COUNT(*) || ':' || COALESCE(MAX(created_at), 0) || ':' ||
                COALESCE(SUM(qty_delta), 0)
           FROM stock_movements WHERE store_id = ?1) AS s,
        (SELECT COUNT(*) || ':' || COALESCE(SUM(amount), 0)
           FROM debt_payments WHERE store_id = ?1) AS d
      ''',
      [storeId],
    );
    final row = rows.first;
    return '${row['t']}|${row['p']}|${row['c']}|${row['s']}|${row['d']}';
  }

  Future<bool> hasLocalData(String storeId) async =>
      await fingerprint(storeId) != '0:0:0|0:0:0|0:0|0:0:0|0:0';

  Future<DateTime?> lastBackupAt(String storeId) async {
    final raw = await _settings.getString(SettingsKeys.lastBackupAt(storeId));
    final millis = raw == null ? null : int.tryParse(raw);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Mengunggah cadangan sekarang juga.
  Future<DateTime> backupNow({
    required String ownerUid,
    required String storeId,
  }) async {
    final stamp = await fingerprint(storeId);
    final bytes = encode(await snapshot(storeId));
    await storage.upload(ownerUid, storeId, bytes);
    final now = DateTime.now();
    await _settings.setString(
      SettingsKeys.lastBackupAt(storeId),
      '${now.millisecondsSinceEpoch}',
    );
    await _settings.setString(
      SettingsKeys.lastBackupFingerprint(storeId),
      stamp,
    );
    return now;
  }

  /// Cadangan otomatis: hanya bila pengguna menyalakannya dan datanya
  /// berubah sejak cadangan terakhir. [force] melewati jeda minimum (dipakai
  /// saat aplikasi ditinggalkan, supaya catatan terakhir ikut tercadang).
  ///
  /// Mengembalikan true bila benar-benar mengunggah. Tidak pernah melempar:
  /// kegagalan cukup dicoba lagi pada kesempatan berikutnya.
  Future<bool> backupIfNeeded({
    required String ownerUid,
    required String storeId,
    bool force = false,
    DateTime? now,
  }) async {
    try {
      if (!await _settings.backupEnabled()) return false;
      final current = await fingerprint(storeId);
      final previous = await _settings.getString(
        SettingsKeys.lastBackupFingerprint(storeId),
      );
      if (current == previous) return false;
      // Toko kosong yang belum pernah dicadangkan: jangan timpa cadangan
      // lama yang mungkin ada di server (misalnya di HP yang baru dipasang).
      if (previous == null && !await hasLocalData(storeId)) return false;
      final last = await lastBackupAt(storeId);
      final clock = now ?? DateTime.now();
      if (!force && last != null && clock.difference(last) < autoInterval) {
        return false;
      }
      await backupNow(ownerUid: ownerUid, storeId: storeId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Mengganti seluruh data toko [storeId] di HP ini dengan isi cadangan
  /// di server. Mengembalikan jumlah transaksi yang dipulihkan.
  Future<int> restore({
    required String ownerUid,
    required String storeId,
  }) async {
    final bytes = await storage.download(ownerUid, storeId);
    if (bytes == null) {
      throw const BackupException('Belum ada cadangan untuk toko ini.');
    }
    return restoreFromBytes(storeId, bytes);
  }

  Future<int> restoreFromBytes(String storeId, Uint8List bytes) async {
    final data = decode(bytes);
    if (data['format'] != backupFormat) {
      throw const BackupException('Berkas ini bukan cadangan SmartToko.');
    }
    if (data['format_version'] != backupFormatVersion) {
      throw const BackupException('Versi format cadangan tidak didukung.');
    }
    final version = data['schema_version'];
    if (version is! int || version < 1) {
      throw const BackupException('Versi skema cadangan tidak valid.');
    }
    if (version > schemaVersion) {
      throw const BackupException(
        'Cadangan dibuat oleh versi aplikasi yang lebih baru. '
        'Perbarui aplikasi dulu.',
      );
    }
    if (data['store_id'] != storeId) {
      throw const BackupException('Cadangan ini milik toko lain.');
    }
    final tables = data['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const BackupException('Berkas cadangan rusak atau tidak dikenali.');
    }
    // Cadangan dari sebelum fitur utang/piutang belum punya tabel ini.
    if (version < 5) tables.putIfAbsent('debt_payments', () => <Object?>[]);
    _validateTables(tables, storeId);

    var restored = 0;
    await _db.transaction((txn) async {
      // Transaksi dihapus dulu: item dan pergerakan stoknya ikut lewat
      // CASCADE. Sisanya dibersihkan per tabel.
      await txn.delete(
        'transactions',
        where: 'store_id = ?',
        whereArgs: [storeId],
      );
      await txn.delete(
        'stock_movements',
        where: 'store_id = ?',
        whereArgs: [storeId],
      );
      await txn.delete('products', where: 'store_id = ?', whereArgs: [storeId]);
      await txn.delete('contacts', where: 'store_id = ?', whereArgs: [storeId]);

      for (final table in _tables) {
        final rows = tables[table];
        // Struktur dan relasi sudah diperiksa sebelum data lokal disentuh.
        final columns = await _columns(txn, table);
        for (final raw in rows as List) {
          final row = <String, Object?>{
            for (final entry in raw.entries)
              if (columns.contains(entry.key)) '${entry.key}': entry.value,
          };
          // Baris selalu dipaksa milik toko yang sedang dipulihkan.
          if (columns.contains('store_id')) row['store_id'] = storeId;
          await txn.insert(table, row);
          if (table == 'transactions') restored++;
        }
      }
    });

    // Data yang baru dipulihkan sama dengan isi server.
    await _settings.setString(
      SettingsKeys.lastBackupFingerprint(storeId),
      await fingerprint(storeId),
    );
    return restored;
  }

  static Future<Set<String>> _columns(DatabaseExecutor db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return {for (final column in info) column['name']! as String};
  }

  static void _validateTables(Map<String, dynamic> tables, String storeId) {
    Never invalid() => throw const BackupException(
      'Isi cadangan tidak lengkap atau relasi datanya rusak. Data lokal tidak diubah.',
    );
    final ids = <String, Set<String>>{};
    for (final table in _tables) {
      final rows = tables[table];
      if (rows is! List) invalid();
      final tableIds = <String>{};
      for (final row in rows) {
        if (row is! Map<String, dynamic>) invalid();
        final id = row['id'];
        if (id is! String || id.isEmpty || !tableIds.add(id)) invalid();
        if (table != 'transaction_items' && row['store_id'] != storeId) {
          invalid();
        }
      }
      ids[table] = tableIds;
    }
    void reference(Map row, String key, String table, {bool required = false}) {
      final id = row[key];
      if (id == null && !required) return;
      if (id is! String || !ids[table]!.contains(id)) invalid();
    }

    for (final row in tables['transactions'] as List) {
      reference(row as Map, 'contact_id', 'contacts');
    }
    for (final row in tables['transaction_items'] as List) {
      reference(row as Map, 'transaction_id', 'transactions', required: true);
      reference(row, 'product_id', 'products');
    }
    for (final row in tables['debt_payments'] as List) {
      reference(row as Map, 'transaction_id', 'transactions', required: true);
    }
    for (final row in tables['stock_movements'] as List) {
      reference(row as Map, 'product_id', 'products', required: true);
      reference(row, 'transaction_item_id', 'transaction_items');
    }
  }
}
