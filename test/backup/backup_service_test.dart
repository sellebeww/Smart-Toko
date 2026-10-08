/// Tes cadangan cloud.
///
/// Yang dijaga: cadangan tidak pernah jalan tanpa sakelar, tidak mengunggah
/// ulang data yang sama, tidak menimpa cadangan lama dengan toko kosong, dan
/// pemulihan di HP baru menghasilkan data yang utuh (termasuk stok).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/contact_dao.dart';
import 'package:smart_toko/core/db/dao/product_dao.dart';
import 'package:smart_toko/core/db/dao/settings_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/db/migrations.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/backup/backup_service.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';

class MemoryBackupStorage implements BackupStorage {
  final files = <String, Uint8List>{};
  final modified = <String, DateTime>{};
  int uploads = 0;
  bool failUploads = false;

  @override
  Future<void> upload(String ownerUid, String storeId, Uint8List bytes) async {
    if (failUploads) throw const SocketException('offline');
    uploads++;
    files['$ownerUid/$storeId'] = bytes;
    modified['$ownerUid/$storeId'] = DateTime.now();
  }

  @override
  Future<Uint8List?> download(String ownerUid, String storeId) async =>
      files['$ownerUid/$storeId'];

  @override
  Future<DateTime?> lastModified(String ownerUid, String storeId) async =>
      modified['$ownerUid/$storeId'];

  @override
  Future<void> deleteAll(String ownerUid) async {
    files.removeWhere((key, _) => key.startsWith('$ownerUid/'));
    modified.removeWhere((key, _) => key.startsWith('$ownerUid/'));
  }
}

ConfirmedDraft draft(TxCategory category, String name, int qty, int price) =>
    confirmDraftByUser(
      draft: TransactionDraft(
        direction: DraftField<TxDirection>.entered(category.direction),
        category: DraftField<TxCategory>.entered(category),
        items: [
          DraftItem(
            name: DraftField<String>.entered(name),
            qty: DraftField<int>.entered(qty),
            unitPrice: DraftField<int>.entered(price),
            unit: 'kg',
          ),
        ],
        occurredAt: DateTime(2026, 10, 1, 9),
        source: TxSource.manual,
      ),
      editedFields: const {},
    )!;

const owner = 'owner-1';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late MemoryBackupStorage storage;
  late BackupService service;
  late String storeId;

  /// [path] null = basis data di memori. "HP baru" butuh berkas terpisah:
  /// sqflite mengembalikan instans yang sama untuk path memori yang sama.
  Future<AppDatabase> openDb([String? path]) async {
    final db = AppDatabase();
    await db.open(overridePath: path ?? inMemoryDatabasePath);
    return db;
  }

  Future<AppDatabase> openFreshDevice() async {
    final dir = await Directory.systemTemp.createTemp('smarttoko_test');
    addTearDown(() => dir.delete(recursive: true));
    return openDb('${dir.path}/fresh.db');
  }

  Future<void> seed() async {
    final repo = TransactionRepository(database: database);
    final contact = await ContactDao(database.db).create(
      storeId: storeId,
      kind: ContactKind.supplier,
      name: 'Pak Budi',
      phone: '0812',
      now: DateTime(2026, 10, 1),
    );
    await repo.save(
      draft(TxCategory.pembelian, 'ayam', 5, 30000),
      storeId: storeId,
      recordedBy: 'pemilik@contoh.com',
    );
    await repo.save(
      draft(TxCategory.penjualan, 'nasi ayam', 3, 15000),
      storeId: storeId,
    );
    expect(contact.id, isNotEmpty);
  }

  Future<void> enableBackup(AppDatabase db) =>
      SettingsDao(db.db).setFlag(SettingsKeys.backupEnabled, value: true);

  setUp(() async {
    database = await openDb();
    storage = MemoryBackupStorage();
    service = BackupService(database: database, storage: storage);
    storeId = (await StoreDao(database.db).create(name: 'Warteg Uji')).id;
  });

  tearDown(() async => database.close());

  test('tidak mencadangkan apa pun sebelum sakelar dinyalakan', () async {
    await seed();
    expect(
      await service.backupIfNeeded(ownerUid: owner, storeId: storeId),
      isFalse,
    );
    expect(storage.uploads, 0);
  });

  test('tidak mengunggah ulang bila data tidak berubah', () async {
    await seed();
    await enableBackup(database);

    expect(
      await service.backupIfNeeded(ownerUid: owner, storeId: storeId),
      isTrue,
    );
    expect(
      await service.backupIfNeeded(
        ownerUid: owner,
        storeId: storeId,
        force: true,
      ),
      isFalse,
    );
    expect(storage.uploads, 1);
  });

  test('perubahan dalam jeda minimum menunggu, kecuali dipaksa', () async {
    await seed();
    await enableBackup(database);
    await service.backupIfNeeded(ownerUid: owner, storeId: storeId);

    await TransactionRepository(database: database)
        .save(draft(TxCategory.penjualan, 'es teh', 2, 5000), storeId: storeId);
    expect(
      await service.backupIfNeeded(ownerUid: owner, storeId: storeId),
      isFalse,
    );
    expect(
      await service.backupIfNeeded(
        ownerUid: owner,
        storeId: storeId,
        force: true,
      ),
      isTrue,
    );
    expect(storage.uploads, 2);
  });

  test('toko kosong di HP baru tidak menimpa cadangan lama', () async {
    await enableBackup(database);
    storage.modified['$owner/$storeId'] = DateTime(2026, 9, 1);
    expect(
      await service.backupIfNeeded(
        ownerUid: owner,
        storeId: storeId,
        force: true,
      ),
      isFalse,
    );
    expect(storage.uploads, 0);
  });

  test('kegagalan jaringan tidak melempar dan dicoba lagi nanti', () async {
    await seed();
    await enableBackup(database);
    storage.failUploads = true;
    expect(
      await service.backupIfNeeded(ownerUid: owner, storeId: storeId),
      isFalse,
    );
    storage.failUploads = false;
    expect(
      await service.backupIfNeeded(ownerUid: owner, storeId: storeId),
      isTrue,
    );
  });

  test('isi cadangan tidak memuat field identitas', () async {
    await seed();
    final snapshot = await service.snapshot(storeId);
    final text = jsonEncode(snapshot);
    expect(text, isNot(contains('pemilik@contoh.com')));
    expect(text, isNot(contains('recorded_by')));
  });

  test('pemulihan di HP baru menghasilkan data yang utuh', () async {
    await seed();
    await service.backupNow(ownerUid: owner, storeId: storeId);
    final originalStock = await ProductDao(database.db).stockLevels(storeId);

    final fresh = await openFreshDevice();
    addTearDown(fresh.close);
    await StoreDao(fresh.db).ensureExists(storeId, 'Warteg Uji');
    final freshService = BackupService(database: fresh, storage: storage);
    expect(await freshService.hasLocalData(storeId), isFalse);

    final restored = await freshService.restore(
      ownerUid: owner,
      storeId: storeId,
    );

    expect(restored, 2);
    expect(await fresh.db.query('transaction_items'), hasLength(2));
    expect(await fresh.db.query('contacts'), hasLength(1));
    expect(await ProductDao(fresh.db).stockLevels(storeId), originalStock);
    expect(
      await freshService.fingerprint(storeId),
      await service.fingerprint(storeId),
    );
    // Setelah pulih, cadangan otomatis tidak perlu mengunggah ulang.
    await enableBackup(fresh);
    expect(
      await freshService.backupIfNeeded(
        ownerUid: owner,
        storeId: storeId,
        force: true,
      ),
      isFalse,
    );
  });

  test('pemulihan mengganti data lokal, bukan menambah ganda', () async {
    await seed();
    await service.backupNow(ownerUid: owner, storeId: storeId);
    await service.restore(ownerUid: owner, storeId: storeId);
    await service.restore(ownerUid: owner, storeId: storeId);
    expect(await database.db.query('transactions'), hasLength(2));
    expect(await database.db.query('stock_movements'), hasLength(1));
  });

  test('menolak cadangan milik toko lain', () async {
    await seed();
    final bytes = BackupService.encode(await service.snapshot(storeId));
    await expectLater(
      service.restoreFromBytes('toko-lain', bytes),
      throwsA(isA<BackupException>()),
    );
  });

  test('menolak cadangan dari versi aplikasi yang lebih baru', () async {
    final snapshot = Map<String, Object?>.of(await service.snapshot(storeId))
      ..['schema_version'] = schemaVersion + 1;
    await expectLater(
      service.restoreFromBytes(storeId, BackupService.encode(snapshot)),
      throwsA(isA<BackupException>()),
    );
  });

  test('menolak berkas yang bukan cadangan', () async {
    await expectLater(
      service.restoreFromBytes(storeId, Uint8List.fromList([1, 2, 3])),
      throwsA(isA<BackupException>()),
    );
  });

  test(
    'tabel hilang dan baris rusak ditolak tanpa menghapus data lokal',
    () async {
      await seed();
      final before = await service.fingerprint(storeId);
      for (final corrupt in <void Function(Map<String, dynamic>)>[
        (data) => (data['tables'] as Map).remove('products'),
        (data) => (data['tables'] as Map)['transactions'] = 'rusak',
        (data) => ((data['tables'] as Map)['contacts'] as List).add(null),
        (data) => data['format_version'] = 99,
        (data) => data['schema_version'] = '4',
        (data) =>
            ((data['tables'] as Map)['products'] as List).first['store_id'] =
                'toko-lain',
      ]) {
        final data = jsonDecode(
          jsonEncode(await service.snapshot(storeId)),
        ) as Map<String, dynamic>;
        corrupt(data);
        await expectLater(
          service.restoreFromBytes(storeId, BackupService.encode(data)),
          throwsA(isA<BackupException>()),
        );
        expect(await service.fingerprint(storeId), before);
        expect(await database.db.query('transactions'), hasLength(2));
      }
    },
  );

  test(
    'relasi ke transaksi toko lain ditolak dan data keduanya tetap utuh',
    () async {
      await seed();
      final other = (await StoreDao(database.db).create(name: 'Toko kedua')).id;
      final tx = await TransactionRepository(database: database)
          .save(draft(TxCategory.penjualan, 'kopi', 1, 8000), storeId: other);
      final before = await service.fingerprint(storeId);
      final data = jsonDecode(
        jsonEncode(await service.snapshot(storeId)),
      ) as Map<String, dynamic>;
      ((data['tables'] as Map)['transaction_items'] as List)
              .first['transaction_id'] =
          tx.id;
      await expectLater(
        service.restoreFromBytes(storeId, BackupService.encode(data)),
        throwsA(isA<BackupException>()),
      );
      expect(await service.fingerprint(storeId), before);
      expect(await database.db.query('transactions'), hasLength(3));
    },
  );
}
