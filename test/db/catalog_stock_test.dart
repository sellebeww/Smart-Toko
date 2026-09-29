/// Katalog yang tumbuh dari transaksi, stok bahan, dan migrasi skema v2.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/contact_dao.dart';
import 'package:smart_toko/core/db/dao/product_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/db/migrations.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';

ConfirmedDraft confirmed({
  required TxCategory category,
  String name = 'ayam',
  int qty = 5,
  int price = 200000,
  PriceMode mode = PriceMode.perUnit,
  String? unit,
  String? contactId,
}) => confirmDraftByUser(
  draft: TransactionDraft(
    direction: DraftField<TxDirection>.entered(category.direction),
    category: DraftField<TxCategory>.entered(category),
    items: [
      DraftItem(
        name: DraftField<String>.entered(name),
        qty: DraftField<int>.entered(qty),
        unitPrice: DraftField<int>.entered(price),
        unit: unit,
        priceMode: DraftField<PriceMode>.entered(mode),
      ),
    ],
    occurredAt: DateTime(2026, 9, 1, 10),
    source: TxSource.manual,
    contactId: contactId,
  ),
  editedFields: const {},
)!;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late TransactionRepository repository;
  late ProductDao products;
  late String storeId;

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    repository = TransactionRepository(database: database);
    products = ProductDao(database.db);
    storeId = (await StoreDao(database.db).create(name: 'Warteg Uji')).id;
  });

  tearDown(() async => database.close());

  group('harga total', () {
    test('total disimpan persis, harga satuan dibulatkan', () async {
      final record = await repository.save(
        confirmed(
          category: TxCategory.pembelian,
          name: 'cabai',
          qty: 3,
          price: 25000,
          mode: PriceMode.total,
          unit: 'kg',
        ),
        storeId: storeId,
      );

      expect(record.totalAmount, 25000);
      expect(record.items.single.lineTotal, 25000);
      expect(record.items.single.unitPrice, 8333);
      expect(record.items.single.unit, 'kg');
    });
  });

  group('katalog tumbuh sendiri', () {
    test('penjualan mencatat menu, pembelian mencatat bahan', () async {
      await repository.save(
        confirmed(
          category: TxCategory.penjualan,
          name: 'Ayam Geprek',
          qty: 2,
          price: 15000,
        ),
        storeId: storeId,
      );
      await repository.save(
        confirmed(category: TxCategory.pembelian, name: 'ayam', unit: 'kg'),
        storeId: storeId,
      );

      final menu = await products.list(
        storeId: storeId,
        kind: ProductKind.menu,
      );
      final bahan = await products.list(
        storeId: storeId,
        kind: ProductKind.bahan,
      );
      expect(menu.single.name, 'Ayam Geprek');
      expect(menu.single.defaultPrice, 15000);
      expect(bahan.single.name, 'ayam');
      expect(bahan.single.unit, 'kg');
    });

    test('nama beda huruf/spasi tetap produk yang sama', () async {
      await repository.save(
        confirmed(
          category: TxCategory.penjualan,
          name: 'Es Teh',
          qty: 1,
          price: 3000,
        ),
        storeId: storeId,
      );
      await repository.save(
        confirmed(
          category: TxCategory.penjualan,
          name: '  es   teh ',
          qty: 2,
          price: 4000,
        ),
        storeId: storeId,
      );

      final menu = await products.list(
        storeId: storeId,
        kind: ProductKind.menu,
      );
      expect(menu, hasLength(1));
      // Harga terakhir yang tercatat dipakai sebagai harga produk.
      expect(menu.single.defaultPrice, 4000);
    });

    test('pengeluaran operasional tidak masuk katalog', () async {
      await repository.save(
        confirmed(
          category: TxCategory.pengeluaran,
          name: 'listrik',
          qty: 1,
          price: 100000,
        ),
        storeId: storeId,
      );

      expect(await products.list(storeId: storeId), isEmpty);
    });
  });

  group('stok bahan', () {
    Future<int> stockOf(String name) async {
      final bahan = await products.list(
        storeId: storeId,
        kind: ProductKind.bahan,
      );
      final product = bahan.firstWhere((p) => p.name == name);
      return (await products.stockLevels(storeId))[product.id] ?? 0;
    }

    test('pembelian menambah stok sebanyak jumlahnya', () async {
      await repository.save(
        confirmed(category: TxCategory.pembelian, qty: 5, unit: 'kg'),
        storeId: storeId,
      );
      await repository.save(
        confirmed(category: TxCategory.pembelian, qty: 3, unit: 'kg'),
        storeId: storeId,
      );

      expect(await stockOf('ayam'), 8);
    });

    test('pemakaian manual mengurangi stok', () async {
      await repository.save(
        confirmed(category: TxCategory.pembelian, qty: 5, unit: 'kg'),
        storeId: storeId,
      );
      final ayam = (await products.list(
        storeId: storeId,
        kind: ProductKind.bahan,
      )).single;
      await products.addMovement(
        storeId: storeId,
        productId: ayam.id,
        qtyDelta: -2,
        reason: StockReason.pemakaian,
        occurredAt: DateTime(2026, 9, 1, 12),
        now: DateTime(2026, 9, 1, 12),
      );

      expect(await stockOf('ayam'), 3);
    });

    test('menghapus transaksi pembelian membatalkan stoknya', () async {
      final record = await repository.save(
        confirmed(category: TxCategory.pembelian, qty: 5, unit: 'kg'),
        storeId: storeId,
      );

      await repository.delete(record.id);

      expect(await stockOf('ayam'), 0);
    });

    test('koreksi transaksi tidak menghitung stok dua kali', () async {
      final original = await repository.save(
        confirmed(category: TxCategory.pembelian, qty: 5, unit: 'kg'),
        storeId: storeId,
      );

      await repository.replace(
        original.id,
        confirmed(category: TxCategory.pembelian, qty: 4, unit: 'kg'),
        storeId: storeId,
      );

      expect(await stockOf('ayam'), 4);
      expect(await database.db.query('transactions'), hasLength(1));
    });
  });

  group('kontak', () {
    test('menghapus kontak tidak menghapus transaksinya', () async {
      final supplier = await ContactDao(database.db).create(
        storeId: storeId,
        kind: ContactKind.supplier,
        name: 'Pak Budi',
        location: 'Pasar Minggu',
        now: DateTime(2026, 9, 1),
      );
      final record = await repository.save(
        confirmed(category: TxCategory.pembelian, contactId: supplier.id),
        storeId: storeId,
      );

      await ContactDao(database.db).delete(supplier.id);

      final kept = await repository.findById(record.id);
      expect(kept, isNotNull);
      expect(kept!.contactId, isNull);
    });
  });

  group('migrasi dari v1', () {
    test('transaksi lama mendapat kategori sesuai arahnya', () async {
      final path = '${await getDatabasesPath()}/migrasi_uji.db';
      await deleteDatabase(path);

      final old = await openDatabase(
        path,
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => migrations.first.apply(db),
      );
      await old.insert('stores', {
        'id': 's1',
        'name': 'Lama',
        'verification_status': 'unverified',
        'created_at': 0,
      });
      for (final (id, direction) in [('t1', 'masuk'), ('t2', 'keluar')]) {
        await old.insert('transactions', {
          'id': id,
          'store_id': 's1',
          'direction': direction,
          'occurred_at': 0,
          'source': 'manual',
          'total_amount': 1000,
          'created_at': 0,
          'updated_at': 0,
        });
      }
      await old.close();

      final upgraded = AppDatabase();
      await upgraded.open(overridePath: path);
      final rows = await upgraded.db.query(
        'transactions',
        columns: ['id', 'category', 'recorded_by'],
        orderBy: 'id',
      );
      await upgraded.close();
      await deleteDatabase(path);

      // Naik langsung dari v1 ke versi terbaru melewati semua migrasi.
      expect(schemaVersion, 3);
      expect(rows[0]['category'], 'penjualan');
      expect(rows[1]['category'], 'pengeluaran');
      expect(rows[0]['recorded_by'], isNull);
    });
  });
}
