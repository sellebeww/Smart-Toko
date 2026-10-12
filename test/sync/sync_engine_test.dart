/// Sinkronisasi dua HP lewat server tiruan yang meniru sync_push/sync_pull.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/contact_dao.dart';
import 'package:smart_toko/core/db/dao/product_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/debts/data/debt_repository.dart';
import 'package:smart_toko/features/sync/sync_engine.dart';
import 'package:smart_toko/features/sync/sync_remote.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';

/// Server tiruan: versi naik berurutan, tombstone, dan hapus transaksi ikut
/// menghapus barang/pembayaran/stoknya — seperti setup.sql.
class FakeServer implements SyncRemote {
  final rows = <String, RemoteRow>{};
  var _version = 0;
  bool failPush = false;
  bool accessLost = false;
  final pushed = <OutgoingRow>[];

  void _put(String table, String id, Map<String, Object?>? data) {
    rows['$table/$id'] = RemoteRow(
      table: table,
      id: id,
      data: data,
      deleted: data == null,
      version: ++_version,
    );
  }

  @override
  Future<void> push(String storeId, List<OutgoingRow> batch) async {
    if (accessLost) throw const SyncAccessLost();
    if (failPush) throw const SocketException('offline');
    for (final r in batch) {
      pushed.add(r);
      _put(r.table, r.id, r.data);
      if (r.deleted && r.table == 'transactions') {
        final items = [
          for (final row in rows.values)
            if (row.table == 'transaction_items' &&
                !row.deleted &&
                row.data!['transaction_id'] == r.id)
              row.id,
        ];
        for (final row in rows.values.toList()) {
          if (row.deleted) continue;
          final d = row.data!;
          if ((row.table == 'transaction_items' && items.contains(row.id)) ||
              (row.table == 'stock_movements' &&
                  items.contains(d['transaction_item_id'])) ||
              (row.table == 'debt_payments' && d['transaction_id'] == r.id)) {
            _put(row.table, row.id, null);
          }
        }
      }
    }
  }

  @override
  Future<List<RemoteRow>> pull(
    String storeId, {
    required int after,
    int limit = 500,
  }) async {
    if (accessLost) throw const SyncAccessLost();
    final list = rows.values.where((r) => r.version > after).toList()
      ..sort((a, b) => a.version.compareTo(b.version));
    return list.take(limit).toList();
  }

  int live(String table) =>
      rows.values.where((r) => r.table == table && !r.deleted).length;
}

const storeId = 'toko-1';

class Device {
  final AppDatabase db;
  final SyncEngine engine;
  final TransactionRepository transactions;

  Device(this.db, FakeServer server)
    : engine = SyncEngine(database: db, remote: server),
      transactions = TransactionRepository(database: db);

  Future<String> sell(
    String item, {
    int qty = 1,
    int price = 10000,
    TxCategory category = TxCategory.penjualan,
    String? recordedBy,
    bool credit = false,
    String? contactId,
  }) async => (await transactions.save(
    confirmDraftByUser(
      draft: TransactionDraft(
        direction: DraftField<TxDirection>.entered(category.direction),
        category: DraftField<TxCategory>.entered(category),
        items: [
          DraftItem(
            name: DraftField<String>.entered(item),
            qty: DraftField<int>.entered(qty),
            unitPrice: DraftField<int>.entered(price),
          ),
        ],
        occurredAt: DateTime(2026, 10, 12, 10),
        source: TxSource.manual,
        onCredit: credit,
        contactId: contactId,
      ),
      editedFields: const {},
    )!,
    storeId: storeId,
    recordedBy: recordedBy,
  )).id;

  Future<int> count(String table) async => (await db.db.query(table)).length;

  Future<int> pending() async => (await db.db.query('sync_changes')).length;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late FakeServer server;
  late Device a;
  late Device b;

  Future<Device> device(String name) async {
    final dir = await Directory.systemTemp.createTemp('smarttoko_sync_$name');
    addTearDown(() => dir.delete(recursive: true));
    final db = AppDatabase();
    await db.open(overridePath: '${dir.path}/app.db');
    addTearDown(db.close);
    await StoreDao(db.db).ensureExists(storeId, 'Warung');
    return Device(db, server);
  }

  setUp(() async {
    server = FakeServer();
    a = await device('a');
    b = await device('b');
  });

  test('perubahan tidak dicatat selama sinkronisasi belum menyala', () async {
    await a.sell('nasi');

    expect(await a.pending(), 0);
  });

  test('HP pertama mengirim semua; HP kedua menerima semuanya', () async {
    final sari = await ContactDao(a.db.db).create(
      storeId: storeId,
      kind: ContactKind.pelanggan,
      name: 'Bu Sari',
      now: DateTime(2026, 10, 1),
    );
    final tx = await a.sell(
      'nasi goreng',
      qty: 2,
      credit: true,
      contactId: sari.id,
    );
    await DebtRepository(database: a.db)
        .addPayment(storeId: storeId, transactionId: tx, amount: 5000);
    await a.sell('ayam', category: TxCategory.pembelian);

    final first = await a.engine.enable(storeId, firstDevice: true);
    expect(first.pushed, greaterThan(0));
    expect(await a.pending(), 0);

    await b.engine.enable(storeId, firstDevice: false);

    for (final table in syncTables) {
      expect(await b.count(table), await a.count(table), reason: table);
    }
    final record = (await b.transactions.findById(tx))!;
    expect(record.paidAmount, 5000);
    expect(record.outstanding, 15000);
    expect(
      await b.pending(),
      0,
      reason: 'data dari server tidak dikirim balik',
    );
  });

  test('transaksi baru di satu HP muncul di HP lain', () async {
    await a.engine.enable(storeId, firstDevice: true);
    await b.engine.enable(storeId, firstDevice: false);

    final id = await a.sell('es teh');
    expect(await a.pending(), greaterThan(0));
    await a.engine.sync(storeId);
    final result = await b.engine.sync(storeId);

    expect(result.changedLocalData, isTrue);
    expect(await b.transactions.findById(id), isNotNull);
  });

  test(
    'hapus di satu HP ikut terhapus di HP lain, berikut barangnya',
    () async {
      final id = await a.sell('es teh');
      await a.engine.enable(storeId, firstDevice: true);
      await b.engine.enable(storeId, firstDevice: false);
      expect(await b.count('transaction_items'), 1);

      await a.transactions.delete(id);
      await a.engine.sync(storeId);
      await b.engine.sync(storeId);

      expect(await b.transactions.findById(id), isNull);
      expect(await b.count('transaction_items'), 0);
      expect(server.live('transaction_items'), 0);
    },
  );

  test('koreksi di HP kedua menggantikan transaksi di HP pertama', () async {
    final id = await a.sell('es teh', qty: 1);
    await a.engine.enable(storeId, firstDevice: true);
    await b.engine.enable(storeId, firstDevice: false);

    final record = (await b.transactions.findById(id))!;
    final corrected = await b.transactions.replace(
      id,
      confirmDraftByUser(
        draft: TransactionDraft.fromRecord(record).copyWith(
          items: [
            const DraftItem(
              name: DraftField<String>.entered('es teh'),
              qty: DraftField<int>.entered(3),
              unitPrice: DraftField<int>.entered(5000),
            ),
          ],
        ),
        editedFields: const {},
      )!,
      storeId: storeId,
    );
    await b.engine.sync(storeId);
    await a.engine.sync(storeId);

    expect(await a.transactions.findById(id), isNull);
    expect((await a.transactions.findById(corrected.id))!.totalAmount, 15000);
    expect(await a.count('transaction_items'), 1);
  });

  test('barang yang sama dicatat di dua HP saat luring menjadi satu', () async {
    await a.engine.enable(storeId, firstDevice: true);
    await b.engine.enable(storeId, firstDevice: false);

    await a.sell('Ayam Geprek');
    await b.sell('ayam geprek ');
    await a.engine.sync(storeId);
    await b.engine.sync(storeId);
    await a.engine.sync(storeId);

    expect(await a.count('products'), 1);
    expect(await b.count('products'), 1);
    expect(await a.count('transactions'), 2);
    expect(await b.count('transactions'), 2);
  });

  test('nama barang bentrok dengan id berbeda: keduanya disimpan', () async {
    await a.engine.enable(storeId, firstDevice: true);
    await b.engine.enable(storeId, firstDevice: false);

    // Di A, barang lama diganti namanya menjadi "ayam"; di B, "ayam" dibuat
    // baru. Id keduanya berbeda.
    await a.sell('ayam kampung');
    await b.sell('ayam');
    final products = ProductDao(a.db.db);
    final kampung = (await products.list(storeId: storeId)).single;
    await products.update(
      kampung,
      name: 'ayam',
      unit: null,
      defaultPrice: 10000,
      lowStockThreshold: null,
      now: DateTime.now(),
    );

    await b.engine.sync(storeId);
    await a.engine.sync(storeId);
    await b.engine.sync(storeId);

    expect(await a.count('products'), 2);
    expect(await b.count('products'), 2);
    expect(await a.count('transaction_items'), 2);
  });

  test(
    'barang yang versinya lebih tua dari transaksinya tetap diterapkan',
    () async {
      final id = await a.sell('nasi');
      await a.engine.enable(storeId, firstDevice: true);
      // Transaksi diperbarui belakangan: versinya kini lebih baru dari
      // barangnya.
      await DebtRepository(database: a.db)
          .setDueDate(id, null)
          .catchError((_) {});
      await a.db.db.update(
        'transactions',
        {'note': 'diubah', 'updated_at': 99},
        where: 'id = ?',
        whereArgs: [id],
      );
      await a.engine.sync(storeId);

      await b.engine.enable(storeId, firstDevice: false);

      expect(await b.count('transaction_items'), 1);
      expect((await b.transactions.findById(id))!.note, 'diubah');
    },
  );

  test(
    'HP kedua dengan salinan lama tidak menimpa data terbaru di server',
    () async {
      final id = await a.sell('nasi');
      // B punya salinan lama transaksi yang sama (mis. dari cadangan lama).
      final old = (await a.db.db.query('transactions')).single;
      final oldItem = (await a.db.db.query('transaction_items')).single;
      final oldProduct = (await a.db.db.query('products')).single;
      await b.db.db.insert('products', oldProduct);
      await b.db.db.insert('transactions', {...old, 'note': 'versi lama'});
      await b.db.db.insert('transaction_items', oldItem);
      // B juga punya catatan yang belum pernah ada di server.
      final onlyOnB = await b.sell('kopi');

      await a.db.db.update(
        'transactions',
        {'note': 'versi baru'},
        where: 'id = ?',
        whereArgs: [id],
      );
      await a.engine.enable(storeId, firstDevice: true);
      await b.engine.enable(storeId, firstDevice: false);
      await a.engine.sync(storeId);

      expect((await b.transactions.findById(id))!.note, 'versi baru');
      expect((await a.transactions.findById(id))!.note, 'versi baru');
      expect(
        await a.transactions.findById(onlyOnB),
        isNotNull,
        reason: 'catatan yang hanya ada di B tetap terkirim',
      );
    },
  );

  test('gagal kirim: antrean tetap ada dan terkirim berikutnya', () async {
    await a.engine.enable(storeId, firstDevice: true);
    await a.sell('nasi');
    server.failPush = true;

    await expectLater(a.engine.sync(storeId), throwsA(isA<SocketException>()));
    expect(await a.pending(), greaterThan(0));

    server.failPush = false;
    await a.engine.sync(storeId);
    expect(await a.pending(), 0);
    expect(server.live('transactions'), 1);
  });

  test('akses dicabut diteruskan sebagai SyncAccessLost', () async {
    await a.engine.enable(storeId, firstDevice: true);
    server.accessLost = true;

    await expectLater(a.engine.sync(storeId), throwsA(isA<SyncAccessLost>()));
  });

  test('menghapus toko dari HP tidak mengirim penghapusan ke server', () async {
    await a.sell('nasi');
    await a.engine.enable(storeId, firstDevice: true);

    await a.engine.removeLocalStore(storeId);

    expect(await a.count('transactions'), 0);
    expect(await a.pending(), 0);
    expect(server.live('transactions'), 1);
  });

  test('mematikan di HP ini berhenti mencatat perubahan', () async {
    await a.engine.enable(storeId, firstDevice: true);
    await a.engine.disableLocal(storeId);

    await a.sell('nasi');

    expect(await a.pending(), 0);
    expect(await a.engine.isEnabled(storeId), isFalse);
  });

  test('nama pencatat ikut terkirim, data identitas lain tidak', () async {
    await a.db.db.execute(
      'ALTER TABLE transactions ADD COLUMN ktp_number TEXT',
    );
    final id = await a.sell('nasi', recordedBy: 'karyawan@contoh.com');
    await a.db.db.update(
      'transactions',
      {'ktp_number': '3201'},
      where: 'id = ?',
      whereArgs: [id],
    );

    await a.engine.enable(storeId, firstDevice: true);

    final sent = server.pushed.firstWhere(
      (r) => r.table == 'transactions' && r.id == id,
    );
    expect(sent.data!['recorded_by'], 'karyawan@contoh.com');
    expect(sent.data!.containsKey('ktp_number'), isFalse);
  });

  test('sinkron bersamaan untuk toko yang sama digabung', () async {
    await a.engine.enable(storeId, firstDevice: true);
    await a.sell('nasi');

    final results = await Future.wait([
      a.engine.sync(storeId),
      a.engine.sync(storeId),
    ]);

    expect(identical(results[0], results[1]), isTrue);
    expect(server.pushed.where((r) => r.table == 'transactions').length, 1);
  });
}
