/// Cadangan harus ikut membawa kasbon dan pembayarannya, dan cadangan lama
/// (sebelum fitur ini) tetap bisa dipulihkan.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/contact_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/backup/backup_service.dart';
import 'package:smart_toko/features/debts/data/debt_repository.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';

import 'backup_service_test.dart' show MemoryBackupStorage, owner;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late MemoryBackupStorage storage;
  late BackupService service;
  late DebtRepository debts;
  late String storeId;
  late String txId;

  Future<AppDatabase> freshDevice() async {
    final dir = await Directory.systemTemp.createTemp('smarttoko_debt');
    addTearDown(() => dir.delete(recursive: true));
    final db = AppDatabase();
    await db.open(overridePath: '${dir.path}/fresh.db');
    addTearDown(db.close);
    return db;
  }

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    storage = MemoryBackupStorage();
    service = BackupService(database: database, storage: storage);
    debts = DebtRepository(database: database);
    storeId = (await StoreDao(database.db).create(name: 'Warung Uji')).id;

    final sari = await ContactDao(database.db).create(
      storeId: storeId,
      kind: ContactKind.pelanggan,
      name: 'Bu Sari',
      now: DateTime(2026, 10, 1),
    );
    final confirmed = confirmDraftByUser(
      draft: TransactionDraft(
        direction: const DraftField<TxDirection>.entered(TxDirection.masuk),
        items: const [
          DraftItem(
            name: DraftField<String>.entered('nasi goreng'),
            qty: DraftField<int>.entered(2),
            unitPrice: DraftField<int>.entered(15000),
          ),
        ],
        occurredAt: DateTime(2026, 10, 1, 9),
        source: TxSource.manual,
        contactId: sari.id,
        onCredit: true,
      ),
      editedFields: const {},
    )!;
    txId = (await TransactionRepository(
      database: database,
    ).save(confirmed, storeId: storeId)).id;
    await debts.addPayment(
      storeId: storeId,
      transactionId: txId,
      amount: 10000,
      note: 'DP',
    );
  });

  tearDown(() async => database.close());

  test('kasbon dan pembayarannya ikut pulih di HP baru', () async {
    await service.backupNow(ownerUid: owner, storeId: storeId);

    final fresh = await freshDevice();
    await StoreDao(fresh.db).ensureExists(storeId, 'Warung Uji');
    await BackupService(
      database: fresh,
      storage: storage,
    ).restore(ownerUid: owner, storeId: storeId);

    final freshDebts = DebtRepository(database: fresh);
    expect((await freshDebts.totals(storeId)).receivable, 20000);
    final payments = await freshDebts.paymentsFor(txId);
    expect(payments.single.amount, 10000);
    expect(payments.single.note, 'DP');
  });

  test(
    'pembayaran baru mengubah sidik sehingga cadangan diunggah ulang',
    () async {
      final before = await service.fingerprint(storeId);

      await debts.addPayment(
        storeId: storeId,
        transactionId: txId,
        amount: 5000,
      );

      expect(await service.fingerprint(storeId), isNot(before));
    },
  );

  test('cadangan lama tanpa tabel pembayaran masih bisa dipulihkan', () async {
    // Cadangan dibuat aplikasi sebelum fitur utang/piutang: skema 4, tanpa
    // tabel debt_payments, dan baris transaksi tanpa kolom on_credit.
    final snapshot = await service.snapshot(storeId);
    final tables = Map<String, Object?>.of(
      snapshot['tables']! as Map<String, Object?>,
    )..remove('debt_payments');
    final transactions = [
      for (final row in tables['transactions']! as List)
        Map<String, Object?>.of(row as Map<String, Object?>)
          ..remove('on_credit'),
    ];
    final legacy = {
      ...snapshot,
      'schema_version': 4,
      'tables': {...tables, 'transactions': transactions},
    };
    final bytes = Uint8List.fromList(
      gzip.encode(utf8.encode(jsonEncode(legacy))),
    );

    final fresh = await freshDevice();
    await StoreDao(fresh.db).ensureExists(storeId, 'Warung Uji');
    final restored = await BackupService(
      database: fresh,
      storage: storage,
    ).restoreFromBytes(storeId, bytes);

    expect(restored, 1);
    final row = (await fresh.db.query('transactions')).single;
    expect(row['on_credit'], 0, reason: 'cadangan lama dianggap tunai');
    expect(await fresh.db.query('debt_payments'), isEmpty);
  });

  test('pembayaran yang menunjuk transaksi tak dikenal ditolak', () async {
    final snapshot = await service.snapshot(storeId);
    final tables = Map<String, Object?>.of(
      snapshot['tables']! as Map<String, Object?>,
    );
    tables['debt_payments'] = [
      {
        'id': 'p-palsu',
        'store_id': storeId,
        'transaction_id': 'tidak-ada',
        'amount': 1000,
        'paid_at': 0,
        'created_at': 0,
      },
    ];
    final bytes = Uint8List.fromList(
      gzip.encode(utf8.encode(jsonEncode({...snapshot, 'tables': tables}))),
    );

    await expectLater(
      service.restoreFromBytes(storeId, bytes),
      throwsA(isA<BackupException>()),
    );
    expect(
      await debts.paymentsFor(txId),
      hasLength(1),
      reason: 'data lokal tidak boleh berubah bila cadangan ditolak',
    );
  });
}
