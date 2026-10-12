/// Foto barang: tersimpan di HP ini saja.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/product_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/features/backup/backup_service.dart';
import 'package:smart_toko/features/catalog/product_photo_store.dart';
import 'package:smart_toko/features/sync/sync_engine.dart';
import 'package:smart_toko/features/sync/sync_remote.dart';

class RecordingRemote implements SyncRemote {
  final pushed = <OutgoingRow>[];
  List<RemoteRow> toPull = [];

  @override
  Future<void> push(String storeId, List<OutgoingRow> rows) async =>
      pushed.addAll(rows);

  @override
  Future<List<RemoteRow>> pull(
    String storeId, {
    required int after,
    int limit = 500,
  }) async {
    final rows = toPull.where((r) => r.version > after).toList();
    return rows;
  }
}

class NoStorage implements BackupStorage {
  @override
  Future<void> deleteAll(String ownerUid) async {}
  @override
  Future<Uint8List?> download(String ownerUid, String storeId) async => null;
  @override
  Future<DateTime?> lastModified(String ownerUid, String storeId) async => null;
  @override
  Future<void> upload(String ownerUid, String storeId, Uint8List bytes) async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late AppDatabase database;
  late ProductDao products;
  late ProductRecord ayam;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('smarttoko_photo');
    addTearDown(() => dir.delete(recursive: true));
    database = AppDatabase();
    await database.open(overridePath: '${dir.path}/app.db');
    addTearDown(database.close);
    await StoreDao(database.db).ensureExists('s1', 'Warung');
    products = ProductDao(database.db);
    ayam = await products.findOrCreate(
      storeId: 's1',
      kind: ProductKind.menu,
      name: 'Ayam Geprek',
      now: DateTime(2026, 10, 1),
    );
  });

  group('ProductPhotoStore', () {
    late ProductPhotoStore store;

    setUp(() => store = ProductPhotoStore(baseDir: () async => dir));

    test('memindahkan foto dari cache ke folder aplikasi', () async {
      final picked = File('${dir.path}/cache.jpg')..writeAsBytesSync([1, 2, 3]);

      final path = await store.adopt(picked, ayam.id);

      expect(File(path).readAsBytesSync(), [1, 2, 3]);
      expect(path, contains('product_photos'));
      expect(picked.existsSync(), isFalse);
    });

    test('menghapus foto lama, tapi tidak berkas di luar foldernya', () async {
      final path = await store.adopt(
        File('${dir.path}/a.jpg')..writeAsBytesSync([1]),
        ayam.id,
      );
      final outside = File('${dir.path}/jangan.jpg')..writeAsBytesSync([9]);

      await store.delete(path);
      await store.delete(outside.path);
      await store.delete(null);

      expect(File(path).existsSync(), isFalse);
      expect(outside.existsSync(), isTrue);
    });
  });

  test('menyimpan foto tidak mengubah updated_at', () async {
    final before = (await products.findById(ayam.id))!.updatedAt;

    await products.setPhoto(ayam.id, '/foto/ayam.jpg');

    final after = (await products.findById(ayam.id))!;
    expect(after.photoPath, '/foto/ayam.jpg');
    expect(after.updatedAt, before);
  });

  test('path foto tidak ikut dikirim sinkron', () async {
    await products.setPhoto(ayam.id, '/foto/ayam.jpg');
    final remote = RecordingRemote();

    await SyncEngine(
      database: database,
      remote: remote,
    ).enable('s1', firstDevice: true);

    final sent = remote.pushed.firstWhere((r) => r.table == 'products');
    expect(sent.data!.containsKey('photo_path'), isFalse);
  });

  test('data dari HP lain tidak menimpa foto di HP ini', () async {
    await products.setPhoto(ayam.id, '/foto/punyaku.jpg');
    final remote = RecordingRemote()
      ..toPull = [
        RemoteRow(
          table: 'products',
          id: ayam.id,
          data: {
            'id': ayam.id,
            'store_id': 's1',
            'kind': 'menu',
            'name': 'Ayam Geprek',
            'name_key': 'ayam geprek',
            'default_price': 16000,
            'archived': 0,
            'created_at': 0,
            'updated_at': 1,
            'photo_path': '/foto/punya-orang-lain.jpg',
          },
          deleted: false,
          version: 1,
        ),
      ];

    await SyncEngine(
      database: database,
      remote: remote,
    ).enable('s1', firstDevice: false);

    final after = (await products.findById(ayam.id))!;
    expect(after.defaultPrice, 16000);
    expect(after.photoPath, '/foto/punyaku.jpg');
  });

  test('cadangan tidak memuat path foto', () async {
    await products.setPhoto(ayam.id, '/foto/ayam.jpg');

    final snapshot = await BackupService(
      database: database,
      storage: NoStorage(),
    ).snapshot('s1');

    final rows =
        (snapshot['tables']! as Map<String, Object?>)['products']! as List;
    expect((rows.single as Map).containsKey('photo_path'), isFalse);
  });
}
