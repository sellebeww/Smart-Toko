/// Modal (HPP) dan laba per menu.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/product_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/reports/data/report_repository.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late TransactionRepository transactions;
  late ProductDao products;
  late ReportRepository reports;
  late String storeId;
  final day = DateTime(2026, 10, 12);

  Future<void> sell(
    String name,
    int qty,
    int price, {
    TxCategory category = TxCategory.penjualan,
    DateTime? at,
  }) => transactions.save(
    confirmDraftByUser(
      draft: TransactionDraft(
        direction: DraftField<TxDirection>.entered(category.direction),
        category: DraftField<TxCategory>.entered(category),
        items: [
          DraftItem(
            name: DraftField<String>.entered(name),
            qty: DraftField<int>.entered(qty),
            unitPrice: DraftField<int>.entered(price),
          ),
        ],
        occurredAt: at ?? day.add(const Duration(hours: 10)),
        source: TxSource.manual,
      ),
      editedFields: const {},
    )!,
    storeId: storeId,
  );

  Future<ProductRecord> menu(String name) async => (await products.list(
    storeId: storeId,
    kind: ProductKind.menu,
  )).firstWhere((p) => p.name == name);

  Future<void> setCost(String name, int? cost) async {
    final p = await menu(name);
    await products.update(
      p,
      name: p.name,
      unit: p.unit,
      defaultPrice: p.defaultPrice,
      lowStockThreshold: null,
      now: DateTime.now(),
      costPrice: cost,
    );
  }

  Future<GrossProfit> profit() => reports.grossProfit(
    storeId: storeId,
    from: day,
    to: day.add(const Duration(days: 1)),
  );

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    transactions = TransactionRepository(database: database);
    products = ProductDao(database.db);
    reports = ReportRepository(database.db);
    storeId = (await StoreDao(database.db).create(name: 'Warung')).id;
  });

  tearDown(() async => database.close());

  group('ProductRecord', () {
    test('untung dan margin per satuan', () async {
      await sell('ayam geprek', 1, 15000);
      await setCost('ayam geprek', 9000);

      final p = await menu('ayam geprek');
      expect(p.costPrice, 9000);
      expect(p.unitProfit, 6000);
      expect(p.marginPercent, 40);
    });

    test('tanpa modal, untung tidak dikarang', () async {
      await sell('es teh', 1, 5000);

      final p = await menu('es teh');
      expect(p.unitProfit, isNull);
      expect(p.marginPercent, isNull);
    });

    test('mengubah produk tanpa menyentuh modal mempertahankannya', () async {
      await sell('ayam geprek', 1, 15000);
      await setCost('ayam geprek', 9000);
      final p = await menu('ayam geprek');

      await products.update(
        p,
        name: 'Ayam Geprek Spesial',
        unit: p.unit,
        defaultPrice: 16000,
        lowStockThreshold: null,
        now: DateTime.now(),
      );

      expect((await menu('Ayam Geprek Spesial')).costPrice, 9000);
    });
  });

  group('laba kotor', () {
    test('omzet dikurangi modal, per menu', () async {
      await sell('ayam geprek', 4, 15000);
      await sell('es teh', 10, 5000);
      await setCost('ayam geprek', 9000);
      await setCost('es teh', 1500);

      final result = await profit();

      expect(result.revenue, 110000);
      expect(result.cost, 4 * 9000 + 10 * 1500);
      expect(result.profit, 110000 - 51000);
      expect(result.coveragePercent, 100);
      expect(result.missingCost, isEmpty);
      // Untung terbesar dulu: es teh 35.000, ayam 24.000.
      expect(result.menus.map((m) => m.name), ['es teh', 'ayam geprek']);
      expect(result.menus.last.marginPercent, 40);
    });

    test('mengisi modal pertama kali ikut menghitung penjualan lama', () async {
      await sell('ayam geprek', 2, 15000);

      expect((await profit()).costedRevenue, 0);

      await setCost('ayam geprek', 9000);
      expect((await profit()).profit, 12000);
    });

    test('mengubah modal tidak mengubah laba penjualan lama', () async {
      await sell('ayam geprek', 2, 15000);
      await setCost('ayam geprek', 9000);
      await setCost('ayam geprek', 12000);
      await sell('ayam geprek', 1, 15000);

      final m = (await profit()).menus.single;
      // 2 porsi lama dengan modal 9.000, 1 porsi baru dengan modal 12.000.
      expect(m.cost, 2 * 9000 + 12000);
      expect(m.profit, 45000 - 30000);
    });

    test(
      'menu tanpa modal disebut, dan tidak dihitung sebagai untung',
      () async {
        await sell('ayam geprek', 2, 15000);
        await sell('es teh', 2, 5000);
        await setCost('ayam geprek', 9000);

        final result = await profit();

        expect(result.profit, 12000);
        expect(result.coveragePercent, 75);
        expect(result.missingCost.map((m) => m.name), ['es teh']);
        expect(
          result.menus.last.profit,
          isNull,
          reason: 'tanpa modal di akhir',
        );
      },
    );

    test('menjual rugi tampil sebagai laba negatif', () async {
      await sell('promo', 1, 5000);
      await setCost('promo', 7000);

      expect((await profit()).profit, -2000);
    });

    test('pembelian bahan tidak dihitung sebagai penjualan menu', () async {
      await sell('ayam', 5, 30000, category: TxCategory.pembelian);

      expect((await profit()).menus, isEmpty);
    });

    test('di luar periode tidak ikut', () async {
      await sell('ayam geprek', 2, 15000, at: DateTime(2026, 10, 1));

      expect((await profit()).menus, isEmpty);
    });
  });
}
