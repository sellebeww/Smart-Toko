import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/settings_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';

TransactionDraft completeDraft({
  TxDirection direction = TxDirection.masuk,
  String name = 'indomie',
  int qty = 2,
  int unitPrice = 5000,
  DateTime? occurredAt,
}) => TransactionDraft(
  direction: DraftField<TxDirection>.entered(direction),
  items: [
    DraftItem(
      name: DraftField<String>.entered(name),
      qty: DraftField<int>.entered(qty),
      unitPrice: DraftField<int>.entered(unitPrice),
    ),
  ],
  occurredAt: occurredAt ?? DateTime.utc(2026, 1, 15, 10),
  source: TxSource.voice,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late TransactionRepository repository;
  late String storeId;

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    repository = TransactionRepository(database: database);
    final store = await StoreDao(database.db).create(name: 'Warung Uji');
    storeId = store.id;
  });

  tearDown(() async => database.close());

  group('penyimpanan transaksi', () {
    test('menulis transaksi beserta barangnya', () async {
      final confirmed = confirmDraftByUser(
        draft: completeDraft(),
        editedFields: const {},
      )!;

      final record = await repository.save(confirmed, storeId: storeId);

      expect(record.totalAmount, 10000);
      expect(record.items, hasLength(1));

      final rows = await database.db.query('transactions');
      final itemRows = await database.db.query('transaction_items');
      expect(rows, hasLength(1));
      expect(itemRows, hasLength(1));
      expect(itemRows.first['line_total'], 10000);
    });

    test('menghapus transaksi ikut menghapus barangnya', () async {
      final confirmed = confirmDraftByUser(
        draft: completeDraft(),
        editedFields: const {},
      )!;
      final record = await repository.save(confirmed, storeId: storeId);

      await repository.delete(record.id);

      expect(await database.db.query('transaction_items'), isEmpty);
    });
  });

  group('sinkronisasi bersifat gagal-tertutup', () {
    test('tanpa baris setelan apa pun, tidak ada yang diantrekan', () async {
      final confirmed = confirmDraftByUser(
        draft: completeDraft(),
        editedFields: const {},
      )!;

      await repository.save(confirmed, storeId: storeId);

      expect(await database.db.query('pending_sync'), isEmpty);
    });

    test(
      'sinkronisasi dimatikan secara eksplisit juga tidak mengantre',
      () async {
        await SettingsDao(database.db)
            .setFlag(SettingsKeys.syncEnabled, value: false);
        final confirmed = confirmDraftByUser(
          draft: completeDraft(),
          editedFields: const {},
        )!;

        await repository.save(confirmed, storeId: storeId);

        expect(await database.db.query('pending_sync'), isEmpty);
      },
    );

    test('hanya mengantre setelah pengguna menyalakannya', () async {
      await SettingsDao(database.db)
          .setFlag(SettingsKeys.syncEnabled, value: true);
      final confirmed = confirmDraftByUser(
        draft: completeDraft(),
        editedFields: const {},
      )!;

      final record = await repository.save(confirmed, storeId: storeId);

      final queued = await database.db.query('pending_sync');
      expect(queued, hasLength(1));
      expect(queued.first['entity_id'], record.id);
      expect(queued.first['status'], 'pending');
    });

    test(
      'antrean dan transaksi tertulis dalam satu transaksi basis data',
      () async {
        await SettingsDao(database.db)
            .setFlag(SettingsKeys.syncEnabled, value: true);
        final confirmed = confirmDraftByUser(
          draft: completeDraft(),
          editedFields: const {},
        )!;

        await repository.save(confirmed, storeId: storeId);

        final transactions = await database.db.query('transactions');
        final queued = await database.db.query('pending_sync');
        expect(transactions, hasLength(1));
        expect(queued, hasLength(1));
      },
    );
  });

  group('gerbang konfirmasi', () {
    test('draft tanpa arah tidak bisa dikonfirmasi', () {
      final draft = completeDraft().copyWith(
        direction: const DraftField<TxDirection>.empty(),
      );

      expect(confirmDraftByUser(draft: draft, editedFields: const {}), isNull);
    });

    test('draft tanpa harga tidak bisa dikonfirmasi', () {
      final draft = completeDraft().copyWith(
        items: [
          DraftItem(
            name: const DraftField<String>.entered('indomie'),
            qty: const DraftField<int>.entered(1),
            unitPrice: const DraftField<int>.empty(),
          ),
        ],
      );

      expect(confirmDraftByUser(draft: draft, editedFields: const {}), isNull);
    });

    test('draft lengkap menghasilkan ConfirmedDraft', () {
      final confirmed = confirmDraftByUser(
        draft: completeDraft(),
        editedFields: const {'harga'},
      );

      expect(confirmed, isNotNull);
      expect(confirmed!.editedFields, contains('harga'));
    });
  });

  group('agregasi laporan', () {
    test('menjumlahkan hanya arah yang diminta dalam rentang waktu', () async {
      Future<void> save(TxDirection direction, int price) async {
        final confirmed = confirmDraftByUser(
          draft: completeDraft(direction: direction, qty: 1, unitPrice: price),
          editedFields: const {},
        )!;
        await repository.save(confirmed, storeId: storeId);
      }

      await save(TxDirection.masuk, 10000);
      await save(TxDirection.masuk, 5000);
      await save(TxDirection.keluar, 3000);

      final masuk = await repository.totalBetween(
        storeId: storeId,
        direction: TxDirection.masuk,
        from: DateTime.utc(2026, 1, 15),
        to: DateTime.utc(2026, 1, 16),
      );
      final keluar = await repository.totalBetween(
        storeId: storeId,
        direction: TxDirection.keluar,
        from: DateTime.utc(2026, 1, 15),
        to: DateTime.utc(2026, 1, 16),
      );

      expect(masuk, 15000);
      expect(keluar, 3000);
    });
  });
}
