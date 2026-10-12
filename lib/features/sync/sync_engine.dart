/// Mesin sinkronisasi antar-HP.
///
/// Prinsip:
/// - Semua perubahan lokal tercatat otomatis oleh trigger SQLite ke
///   `sync_changes` (lihat migrasi 8), termasuk penghapusan berantai.
/// - Kirim dulu, baru tarik. Server memberi nomor versi berurutan; yang
///   terakhir sampai di server yang berlaku.
/// - Data dari server diterapkan dengan `sync_meta.applying = 1` supaya tidak
///   terkirim balik, dan diurutkan induk → anak (hapus: anak → induk) supaya
///   relasi selalu terpenuhi.
library;

import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/sync/sync_payload_builder.dart';
import 'sync_remote.dart';

/// Tabel yang disinkronkan, urut dari induk ke anak.
const List<String> syncTables = [
  'products',
  'contacts',
  'transactions',
  'transaction_items',
  'stock_movements',
  'debt_payments',
];

/// Kolom yang hanya bermakna di HP ini (mis. path berkas foto). Tidak
/// dikirim, dan nilai dari server tidak menimpanya.
const Set<String> localOnlyColumns = {'photo_path'};

const int _pushBatch = 200;
const int _pullPage = 500;

/// Batas baris per sekali tarik; sisanya diambil pada sinkron berikutnya.
const int _pullCap = 50000;

class SyncResult {
  final int pushed;
  final int applied;
  final int skipped;

  const SyncResult({this.pushed = 0, this.applied = 0, this.skipped = 0});

  bool get changedLocalData => applied > 0;
}

class SyncEngine {
  final AppDatabase database;
  final SyncRemote remote;
  final SyncPayloadBuilder payloadBuilder;

  final Map<String, Future<SyncResult>> _running = {};
  final Map<String, Set<String>> _columns = {};

  SyncEngine({
    required this.database,
    required this.remote,
    this.payloadBuilder = const SyncPayloadBuilder(),
  });

  Database get _db => database.db;

  Future<bool> isEnabled(String storeId) async => (await _db.query(
    'sync_stores',
    where: 'store_id = ?',
    whereArgs: [storeId],
  )).isNotEmpty;

  Future<int> pendingCount(String storeId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(DISTINCT table_name || row_id) AS n FROM sync_changes '
      'WHERE store_id = ?',
      [storeId],
    );
    return (rows.first['n']! as num).toInt();
  }

  Future<DateTime?> lastSyncedAt(String storeId) async {
    final rows = await _db.query(
      'sync_stores',
      columns: ['last_synced_at'],
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    final millis = rows.isEmpty ? null : rows.first['last_synced_at'] as int?;
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Menyalakan sinkronisasi toko ini di HP ini.
  ///
  /// [firstDevice]: HP yang menyalakan sinkronisasi untuk pertama kali —
  /// seluruh datanya dikirim. HP lain (pemilik di HP kedua, atau karyawan)
  /// menarik data server dulu, lalu hanya mengirim baris lokal yang belum
  /// ada di server, supaya salinan lama di HP itu tidak menimpa data terbaru.
  Future<SyncResult> enable(String storeId, {required bool firstDevice}) async {
    if (await isEnabled(storeId)) return sync(storeId);
    await _db.insert('sync_stores', {'store_id': storeId, 'cursor': 0});
    if (firstDevice) {
      await _enqueueAll(storeId);
      return sync(storeId);
    }
    final pulled = await _pull(storeId);
    await _enqueueAll(storeId, except: pulled.seen);
    final pushed = await _push(storeId);
    await _markSynced(storeId);
    return SyncResult(
      pushed: pushed,
      applied: pulled.applied,
      skipped: pulled.skipped,
    );
  }

  /// Langkah pertama di HP yang menyalakan sinkronisasi: mendaftarkan toko
  /// dan memasukkan semua barisnya ke antrean, tanpa jaringan. Dipanggil
  /// sebelum server dinyalakan, supaya pemicu otomatis tidak sempat
  /// menganggap HP ini sebagai HP kedua.
  Future<void> prepareFirstDevice(String storeId) async {
    if (await isEnabled(storeId)) return;
    await _db.insert('sync_stores', {'store_id': storeId, 'cursor': 0});
    await _enqueueAll(storeId);
  }

  /// Mematikan sinkronisasi di HP ini. Data lokal tetap ada.
  Future<void> disableLocal(String storeId) => _db.transaction((txn) async {
    await txn.delete(
      'sync_stores',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    await txn.delete(
      'sync_changes',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
  });

  /// Menghapus seluruh data toko dari HP ini tanpa mengirim penghapusan ke
  /// server — untuk karyawan yang dikeluarkan atau keluar dari toko.
  Future<void> removeLocalStore(String storeId) => _db.transaction((txn) async {
    // Dihapus dari sync_stores lebih dulu: trigger hanya mencatat toko yang
    // terdaftar di sana, jadi hapus berantai di bawah tidak masuk antrean.
    await txn.delete(
      'sync_stores',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    await txn.delete(
      'sync_changes',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    await txn.delete('stores', where: 'id = ?', whereArgs: [storeId]);
  });

  /// Kirim lalu tarik. Panggilan bersamaan untuk toko yang sama digabung.
  Future<SyncResult> sync(String storeId) =>
      _running[storeId] ??= _sync(storeId).whenComplete(() {
        // Blok, bukan panah: remove() mengembalikan Future ini sendiri, dan
        // whenComplete akan menunggunya — menunggu dirinya sendiri selamanya.
        _running.remove(storeId);
      });

  Future<SyncResult> _sync(String storeId) async {
    if (!await isEnabled(storeId)) return const SyncResult();
    final pushed = await _push(storeId);
    final pulled = await _pull(storeId);
    await _markSynced(storeId);
    return SyncResult(
      pushed: pushed,
      applied: pulled.applied,
      skipped: pulled.skipped,
    );
  }

  Future<void> _markSynced(String storeId) => _db.update(
    'sync_stores',
    {'last_synced_at': DateTime.now().millisecondsSinceEpoch},
    where: 'store_id = ?',
    whereArgs: [storeId],
  );

  /// Memasukkan semua baris toko ke antrean kirim.
  Future<void> _enqueueAll(String storeId, {Set<String> except = const {}}) =>
      _db.transaction((txn) async {
        for (final table in syncTables) {
          final rows = table == 'transaction_items'
              ? await txn.rawQuery(
                  'SELECT i.id AS id FROM transaction_items i '
                  'JOIN transactions t ON t.id = i.transaction_id '
                  'WHERE t.store_id = ?',
                  [storeId],
                )
              : await txn.query(
                  table,
                  columns: ['id'],
                  where: 'store_id = ?',
                  whereArgs: [storeId],
                );
          for (final row in rows) {
            final id = row['id']! as String;
            if (except.contains(_key(table, id))) continue;
            await txn.insert('sync_changes', {
              'store_id': storeId,
              'table_name': table,
              'row_id': id,
              'op': 'upsert',
            });
          }
        }
      });

  static String _key(String table, String id) => '$table/$id';

  // ------------------------------------------------------------------ kirim

  Future<int> _push(String storeId) async {
    var total = 0;
    // Dibatasi supaya perubahan yang terus berdatangan tidak membuat
    // pengiriman tidak pernah selesai.
    for (var round = 0; round < 50; round++) {
      final changes = await _db.query(
        'sync_changes',
        where: 'store_id = ?',
        whereArgs: [storeId],
        orderBy: 'seq',
        limit: 1000,
      );
      if (changes.isEmpty) break;
      final maxSeq = changes.last['seq']! as int;

      // Hanya perubahan terakhir per baris yang penting.
      final latest = <String, ({String table, String id, String op})>{};
      for (final c in changes) {
        final table = c['table_name']! as String;
        final id = c['row_id']! as String;
        latest.remove(_key(table, id));
        latest[_key(table, id)] = (
          table: table,
          id: id,
          op: c['op']! as String,
        );
      }

      final upserts = <OutgoingRow>[];
      final deletes = <OutgoingRow>[];
      for (final change in latest.values) {
        final row = change.op == 'delete'
            ? null
            : await _readRow(change.table, change.id);
        if (row == null) {
          deletes.add(OutgoingRow.delete(change.table, change.id));
        } else {
          upserts.add(OutgoingRow.upsert(change.table, change.id, row));
        }
      }
      int order(OutgoingRow r) => syncTables.indexOf(r.table);
      upserts.sort((a, b) => order(a).compareTo(order(b)));
      deletes.sort((a, b) => order(b).compareTo(order(a)));
      final rows = [...upserts, ...deletes];

      for (var start = 0; start < rows.length; start += _pushBatch) {
        final end = start + _pushBatch > rows.length
            ? rows.length
            : start + _pushBatch;
        await remote.push(storeId, rows.sublist(start, end));
      }
      // Baru dihapus setelah server menerima semuanya; gagal di tengah =
      // dikirim ulang nanti (server menerima kiriman ulang dengan aman).
      await _db.delete(
        'sync_changes',
        where: 'store_id = ? AND seq <= ?',
        whereArgs: [storeId, maxSeq],
      );
      total += rows.length;
    }
    return total;
  }

  Future<Map<String, Object?>?> _readRow(String table, String id) async {
    final rows = await _db.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Map<String, Object?>.of(
      payloadBuilder.build(
        rows.first,
        identityConsent: false,
        keepRecorder: true,
      ),
    )..removeWhere((key, _) => localOnlyColumns.contains(key));
  }

  // ------------------------------------------------------------------ tarik

  Future<({int applied, int skipped, Set<String> seen})> _pull(
    String storeId,
  ) async {
    final cursorRows = await _db.query(
      'sync_stores',
      columns: ['cursor'],
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    if (cursorRows.isEmpty) return (applied: 0, skipped: 0, seen: <String>{});
    var cursor = cursorRows.first['cursor']! as int;

    // Semua halaman diambil dulu, lalu diterapkan sekaligus dalam urutan
    // induk → anak. Menerapkan per halaman bisa membuat barang transaksi
    // datang sebelum transaksinya (versi barang lebih tua), lalu terbuang.
    final latest = <String, RemoteRow>{};
    var fetched = 0;
    while (fetched < _pullCap) {
      final page = await remote.pull(storeId, after: cursor, limit: _pullPage);
      if (page.isEmpty) break;
      for (final row in page) {
        latest[_key(row.table, row.id)] = row;
        if (row.version > cursor) cursor = row.version;
      }
      fetched += page.length;
      if (page.length < _pullPage) break;
    }
    if (latest.isEmpty) return (applied: 0, skipped: 0, seen: <String>{});

    int order(RemoteRow r) => syncTables.indexOf(r.table);
    final upserts =
        latest.values.where((r) => !r.deleted && r.data != null).toList()
          ..sort((a, b) => order(a).compareTo(order(b)));
    final deletes =
        latest.values.where((r) => r.deleted || r.data == null).toList()
          ..sort((a, b) => order(b).compareTo(order(a)));

    var applied = 0;
    var skipped = 0;
    await _db.transaction((txn) async {
      await txn.update('sync_meta', {'applying': 1}, where: 'id = 1');
      try {
        for (final row in upserts) {
          if (!syncTables.contains(row.table)) continue;
          if (await _applyUpsert(txn, storeId, row)) {
            applied++;
          } else {
            skipped++;
          }
        }
        for (final row in deletes) {
          if (!syncTables.contains(row.table)) continue;
          applied += await txn.delete(
            row.table,
            where: 'id = ?',
            whereArgs: [row.id],
          );
        }
      } finally {
        await txn.update('sync_meta', {'applying': 0}, where: 'id = 1');
      }
      await txn.update(
        'sync_stores',
        {'cursor': cursor},
        where: 'store_id = ?',
        whereArgs: [storeId],
      );
    });
    return (applied: applied, skipped: skipped, seen: latest.keys.toSet());
  }

  Future<Set<String>> _columnsOf(DatabaseExecutor db, String table) async {
    final cached = _columns[table];
    if (cached != null) return cached;
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return _columns[table] = {for (final c in info) c['name']! as String};
  }

  /// Menerapkan satu baris. False bila dilewati (induknya tidak ada).
  Future<bool> _applyUpsert(
    Transaction txn,
    String storeId,
    RemoteRow row,
  ) async {
    final columns = await _columnsOf(txn, row.table);
    final values = <String, Object?>{
      for (final entry in row.data!.entries)
        if (columns.contains(entry.key) &&
            !localOnlyColumns.contains(entry.key))
          entry.key: entry.value,
    };
    values['id'] = row.id;
    // Baris selalu milik toko yang sedang disinkronkan.
    if (columns.contains('store_id')) values['store_id'] = storeId;
    // Kolom yang disembunyikan server (modal untuk karyawan) tidak boleh
    // menimpa nilai lokal dengan kosong — biarkan apa adanya.

    final names = values.keys.toList();
    final updates = [
      for (final n in names)
        if (n != 'id') '$n = excluded.$n',
    ];
    final sql =
        'INSERT INTO ${row.table} (${names.join(', ')}) '
        'VALUES (${List.filled(names.length, '?').join(', ')}) '
        'ON CONFLICT(id) DO '
        '${updates.isEmpty ? 'NOTHING' : 'UPDATE SET ${updates.join(', ')}'}';
    try {
      await txn.rawInsert(sql, [for (final n in names) values[n]]);
      return true;
    } on DatabaseException catch (e) {
      if (row.table == 'products' && e.isUniqueConstraintError()) {
        // Nama sama dengan barang lain yang id-nya berbeda (mis. diganti
        // nama di HP lain). Keduanya disimpan; kuncinya dibuat unik supaya
        // tidak ada data yang hilang.
        values['name_key'] = '${values['name_key']}#${row.id.substring(0, 8)}';
        await txn.rawInsert(sql, [for (final n in names) values[n]]);
        return true;
      }
      // Induknya belum/tidak ada di HP ini (mis. sudah dihapus): lewati.
      return false;
    }
  }
}
