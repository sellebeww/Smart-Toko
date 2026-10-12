/// Tes salinan lokal profil toko.
///
/// Yang dijaga: aplikasi tetap bisa dibuka saat luring, dan memperbarui
/// salinan profil toko tidak pernah menghapus transaksinya (SQLite REPLACE
/// akan memicu ON DELETE CASCADE).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/features/stores/data/store_cache.dart';
import 'package:smart_toko/features/stores/domain/store_profile.dart';
import 'package:smart_toko/features/stores/stores_providers.dart';
import 'package:smart_toko/features/verification/domain/verification_status.dart';

StoreProfile profile(
  String id, {
  String name = 'Warteg Bahari',
  StoreVerificationStatus status = StoreVerificationStatus.unverified,
}) => StoreProfile(
  id: id,
  ownerUid: 'owner-1',
  name: name,
  category: StoreCategory.warteg,
  address: 'Jl. Melati 1',
  createdAt: DateTime(2026, 9, 1),
  verificationStatus: status,
);

/// SQLite (ffi) berjalan di isolate lain, jadi pumpEventQueue saja tidak
/// cukup untuk menunggunya; tunggu sampai kondisinya terpenuhi.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late StoreCache cache;

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    cache = StoreCache(database.db);
  });

  tearDown(() async => database.close());

  test('memperbarui profil tidak menghapus transaksi toko', () async {
    await StoreDao(database.db).ensureExists('s1', 'Lama');
    await database.db.insert('transactions', {
      'id': 't1',
      'store_id': 's1',
      'direction': 'masuk',
      'occurred_at': 0,
      'source': 'manual',
      'total_amount': 1000,
      'created_at': 0,
      'updated_at': 0,
    });

    await cache.saveAll([
      profile('s1', name: 'Baru', status: StoreVerificationStatus.verified),
    ]);

    expect(await database.db.query('transactions'), hasLength(1));
    final stored = await cache.forOwner('owner-1');
    expect(stored.single.name, 'Baru');
    expect(stored.single.verificationStatus, StoreVerificationStatus.verified);
  });

  test('salinan lokal tampil dulu, lalu digantikan data server', () async {
    await cache.saveAll([profile('s1', name: 'Tersimpan')]);
    final remote = StreamController<List<StoreProfile>>();

    final events = <List<StoreProfile>>[];
    final sub = cachedStores(
      remote: remote.stream,
      cache: cache,
      ownerUid: 'owner-1',
    ).listen(events.add);
    await until(() => events.isNotEmpty);
    expect(events.single.single.name, 'Tersimpan');

    remote.add([profile('s1', name: 'Dari server')]);
    await until(() => events.length > 1);
    expect(events.last.single.name, 'Dari server');
    expect((await cache.forOwner('owner-1')).single.name, 'Dari server');

    // Riverpod tidak menunggu pembatalan; menunggunya di sini akan
    // menggantung karena StreamController uji tidak punya onCancel.
    unawaited(sub.cancel());
    await remote.close();
  });

  test('saat luring, salinan lokal tetap dipakai', () async {
    await cache.saveAll([profile('s1')]);
    final result = await cachedStores(
      remote: Stream.error(Exception('offline')),
      cache: cache,
      ownerUid: 'owner-1',
    ).toList();
    expect(result.single.single.id, 's1');
  });

  test('tanpa salinan lokal, galat server diteruskan', () async {
    expect(
      cachedStores(
        remote: Stream.error(Exception('offline')),
        cache: cache,
        ownerUid: 'owner-1',
      ).toList(),
      throwsException,
    );
  });

  test('toko milik akun lain tidak ikut tampil', () async {
    await cache.saveAll([profile('s1')]);
    expect(await cache.forOwner('owner-2'), isEmpty);
  });
}
