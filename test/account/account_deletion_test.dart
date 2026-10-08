/// Tes penghapusan akun: urutan langkahnya dan perilaku saat gagal di tengah.
///
/// Server dipalsukan di tingkat HTTP, jadi yang diuji adalah permintaan
/// sungguhan yang dikirim SDK Supabase.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/settings_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/features/account/account_deletion_service.dart';
import 'package:smart_toko/features/backup/backup_service.dart';
import 'package:smart_toko/features/stores/data/store_cache.dart';

class FakeBackupStorage implements BackupStorage {
  final List<String> calls;
  FakeBackupStorage(this.calls);

  @override
  Future<void> deleteAll(String ownerUid) async =>
      calls.add('backups.deleteAll($ownerUid)');

  @override
  Future<Uint8List?> download(String ownerUid, String storeId) async => null;

  @override
  Future<DateTime?> lastModified(String ownerUid, String storeId) async => null;

  @override
  Future<void> upload(String ownerUid, String storeId, Uint8List bytes) async {}
}

/// SDK Postgrest membaca `response.request`, jadi harus ikut diisi.
http.Response reply(http.Request request, Object? body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late List<String> calls;
  late AccountDeletionService service;
  late bool failFileRemoval;

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    calls = [];
    failFileRemoval = false;

    final client = SupabaseClient(
      'https://contoh.supabase.co',
      'sb_publishable_tes',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path == '/rest/v1/stores' && request.method == 'GET') {
          calls.add('select stores');
          return reply(request, [
            {'id': 's1'},
          ]);
        }
        if (path == '/storage/v1/object/list/verifications') {
          calls.add('list ${jsonDecode(request.body)['prefix']}');
          return reply(request, [
            {'id': 'f1', 'name': 'ktp.jpg'},
            {'id': 'f2', 'name': 'selfie.jpg'},
          ]);
        }
        if (path == '/storage/v1/object/verifications' &&
            request.method == 'DELETE') {
          if (failFileRemoval) {
            return reply(request, {'message': 'gagal'}, 500);
          }
          calls.add('remove ${jsonDecode(request.body)['prefixes']}');
          return reply(request, []);
        }
        if (path == '/rest/v1/rpc/delete_my_account') {
          calls.add('rpc delete_my_account');
          return http.Response('', 204, request: request);
        }
        return reply(request, {'message': 'tak terduga: $path'}, 404);
      }),
    );

    service = AccountDeletionService(
      client: client,
      backups: FakeBackupStorage(calls),
      cache: StoreCache(database.db),
      settings: SettingsDao(database.db),
    );

    await StoreDao(database.db).ensureExists('s1', 'Warung Satu');
    await database.db.update('stores', {'owner_uid': 'u1'});
  });

  tearDown(() async => database.close());

  test('berkas dan cadangan dihapus sebelum akun di server', () async {
    await service.deleteAccount('u1');

    expect(calls, [
      'select stores',
      'list u1/s1',
      'remove [u1/s1/ktp.jpg, u1/s1/selfie.jpg]',
      'backups.deleteAll(u1)',
      'rpc delete_my_account',
    ]);
  });

  test('data toko di HP ikut terhapus', () async {
    await service.deleteAccount('u1');

    expect(await database.db.query('stores'), isEmpty);
  });

  test('akun tidak dihapus bila berkas gagal dihapus', () async {
    failFileRemoval = true;

    await expectLater(service.deleteAccount('u1'), throwsA(anything));

    expect(calls, isNot(contains('rpc delete_my_account')));
    expect(
      await database.db.query('stores'),
      hasLength(1),
      reason: 'data lokal harus tetap ada supaya pengguna bisa mencoba lagi',
    );
  });
}
