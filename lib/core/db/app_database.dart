/// Pembuka dan pemilik skema basis data lokal.
///
/// Basis data lokal adalah SUMBER KEBENARAN aplikasi ini. Cloud (bila
/// diaktifkan) hanyalah cermin dari isi tabel-tabel di sini, bukan sebaliknya.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

class AppDatabase {
  static const String fileName = 'smart_toko.db';

  Database? _db;

  Database get db {
    final instance = _db;
    if (instance == null) {
      throw StateError('AppDatabase.open() belum dipanggil');
    }
    return instance;
  }

  bool get isOpen => _db != null;

  Future<Database> open({String? overridePath}) async {
    if (_db != null) return _db!;
    final path = overridePath ?? p.join(await getDatabasesPath(), fileName);
    _db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        // Wajib dinyalakan per koneksi: tanpa ini ON DELETE CASCADE pada
        // transaction_items diam-diam tidak berlaku dan menyisakan baris yatim.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final migration in migrations) {
          await migration.apply(db);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        for (final migration in migrations) {
          if (migration.version > oldVersion &&
              migration.version <= newVersion) {
            await migration.apply(db);
          }
        }
      },
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
