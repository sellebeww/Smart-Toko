/// Toko tempat bekerja di HP karyawan, peran, dan kode undangan.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/app/main_shell.dart';
import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/stores/data/store_cache.dart';
import 'package:smart_toko/features/stores/domain/store_profile.dart';
import 'package:smart_toko/features/sync/sync_providers.dart';
import 'package:smart_toko/features/sync/team_repository.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';

StoreProfile store(String id, String owner, {bool sync = true}) => StoreProfile(
  id: id,
  ownerUid: owner,
  name: 'Toko $id',
  category: StoreCategory.warteg,
  address: '',
  createdAt: DateTime(2026, 10, 1),
  syncEnabled: sync,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('kode undangan', () {
    test('dinormalkan dari ketikan apa pun', () {
      expect(normalizeInviteCode(' abcde-12345 '), 'ABCDE12345');
      expect(normalizeInviteCode('AB CDE 123 45'), 'ABCDE12345');
    });

    test('ditampilkan dengan tanda hubung di tengah', () {
      expect(formatInviteCode('abcde12345'), 'ABCDE-12345');
    });
  });

  group('hak mengoreksi', () {
    test('pemilik boleh mengoreksi semua catatan', () {
      expect(
        canEditRecord(staff: false, email: 'a@x.com', recordedBy: 'b@x.com'),
        isTrue,
      );
    });

    test('karyawan hanya catatannya sendiri', () {
      expect(
        canEditRecord(staff: true, email: 'k@x.com', recordedBy: 'k@x.com'),
        isTrue,
      );
      expect(
        canEditRecord(staff: true, email: 'k@x.com', recordedBy: 'p@x.com'),
        isFalse,
      );
      expect(
        canEditRecord(staff: true, email: 'k@x.com', recordedBy: null),
        isFalse,
      );
      expect(
        canEditRecord(staff: true, email: null, recordedBy: null),
        isFalse,
      );
    });
  });

  test('peran ditentukan dari pemilik toko', () {
    final s = store('s1', 'pemilik');
    expect(s.isOwnedBy('pemilik'), isTrue);
    expect(s.isOwnedBy('karyawan'), isFalse);
    expect(s.isOwnedBy(null), isFalse);
  });

  group('salinan toko di HP karyawan', () {
    late AppDatabase database;
    late StoreCache cache;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('smarttoko_team');
      addTearDown(() => dir.delete(recursive: true));
      database = AppDatabase();
      await database.open(overridePath: '${dir.path}/app.db');
      addTearDown(database.close);
      cache = StoreCache(database.db);
    });

    Future<void> addSale(String storeId) =>
        TransactionRepository(database: database).save(
          confirmDraftByUser(
            draft: TransactionDraft(
              direction: const DraftField<TxDirection>.entered(
                TxDirection.masuk,
              ),
              items: const [
                DraftItem(
                  name: DraftField<String>.entered('nasi'),
                  qty: DraftField<int>.entered(1),
                  unitPrice: DraftField<int>.entered(10000),
                ),
              ],
              occurredAt: DateTime(2026, 10, 12),
              source: TxSource.manual,
            ),
            editedFields: const {},
          )!,
          storeId: storeId,
        );

    test('toko tempat bekerja ikut tersimpan dan terbaca luring', () async {
      await cache.saveAll([
        store('milik', 'saya'),
        store('kerja', 'bos'),
      ], viewerUid: 'saya');

      final stored = await cache.forOwner('saya');

      expect(stored.map((s) => s.id), containsAll(['milik', 'kerja']));
      expect(stored.firstWhere((s) => s.id == 'kerja').syncEnabled, isTrue);
    });

    test(
      'dikeluarkan: salinan tokonya dihapus tanpa masuk antrean kirim',
      () async {
        await cache.saveAll([store('kerja', 'bos')], viewerUid: 'saya');
        await database.db.insert('sync_stores', {'store_id': 'kerja'});
        await addSale('kerja');
        expect(await database.db.query('sync_changes'), isNotEmpty);
        await database.db.delete('sync_changes');

        await cache.saveAll([], viewerUid: 'saya');

        expect(await cache.forOwner('saya'), isEmpty);
        expect(await database.db.query('transactions'), isEmpty);
        expect(await database.db.query('sync_changes'), isEmpty);
        expect(await database.db.query('sync_stores'), isEmpty);
      },
    );

    test('toko milik sendiri tidak pernah dibersihkan otomatis', () async {
      await cache.saveAll([store('milik', 'saya')], viewerUid: 'saya');
      await addSale('milik');

      await cache.saveAll([], viewerUid: 'saya');

      expect(await database.db.query('transactions'), hasLength(1));
    });

    test('hapus akun membersihkan toko milik dan tempat kerja', () async {
      await cache.saveAll([
        store('milik', 'saya'),
        store('kerja', 'bos'),
      ], viewerUid: 'saya');
      await database.db.insert('sync_stores', {'store_id': 'milik'});
      await addSale('milik');
      await addSale('kerja');
      await database.db.delete('sync_changes');

      await cache.deleteForOwner('saya');

      expect(await database.db.query('stores'), isEmpty);
      expect(
        await database.db.query('sync_changes'),
        isEmpty,
        reason: 'penghapusan lokal tidak boleh terkirim ke server',
      );
    });

    test('toko lama (sebelum fitur ini) tetap terbaca', () async {
      await StoreDao(database.db).ensureExists('lama', 'Lama');
      await database.db.update('stores', {'owner_uid': 'saya'});

      expect((await cache.forOwner('saya')).single.syncEnabled, isFalse);
    });
  });

  testWidgets('karyawan tidak melihat menu Laporan', (tester) async {
    Future<int> count({required bool showReports}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: SmartTokoNavigationBar(
              selectedIndex: 0,
              showReports: showReports,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      return tester.widgetList(find.byType(NavigationDestination)).length;
    }

    expect(await count(showReports: true), 5);
    expect(await count(showReports: false), 4);
    expect(find.text('Laporan'), findsNothing);
  });
}
