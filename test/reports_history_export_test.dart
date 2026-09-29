/// Riwayat (filter & grup harian), laporan & wawasan, koreksi, dan ekspor
/// Excel.
library;

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/pending_sync_dao.dart';
import 'package:smart_toko/core/db/dao/settings_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/export/excel_exporter.dart';
import 'package:smart_toko/features/reports/data/report_repository.dart';
import 'package:smart_toko/features/reports/domain/insights.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/history_filter.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';
import 'package:smart_toko/features/transactions/history_providers.dart';

ConfirmedDraft tx(
  TxCategory category,
  DateTime at, {
  List<(String, int, int, PriceMode, String?)> items = const [
    ('nasi ayam', 2, 15000, PriceMode.perUnit, 'porsi'),
  ],
  TxSource source = TxSource.manual,
}) => confirmDraftByUser(
  draft: TransactionDraft(
    direction: DraftField<TxDirection>.entered(category.direction),
    category: DraftField<TxCategory>.entered(category),
    items: [
      for (final (name, qty, price, mode, unit) in items)
        DraftItem(
          name: DraftField<String>.entered(name),
          qty: DraftField<int>.entered(qty),
          unitPrice: DraftField<int>.entered(price),
          unit: unit,
          priceMode: DraftField<PriceMode>.entered(mode),
        ),
    ],
    occurredAt: at,
    source: source,
  ),
  editedFields: const {},
)!;

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('id_ID');
  });

  group('filter riwayat', () {
    // Selasa, 29 September 2026.
    final now = DateTime(2026, 9, 29, 14, 30);

    test('minggu ini dimulai Senin dan mencakup hari ini', () {
      final r = const HistoryFilter(range: HistoryRange.mingguIni).resolve(now);
      expect(r.from, DateTime(2026, 9, 28));
      expect(r.to, DateTime(2026, 9, 30));
    });

    test('bulan ini dari tanggal 1', () {
      final r = const HistoryFilter(range: HistoryRange.bulanIni).resolve(now);
      expect(r.from, DateTime(2026, 9, 1));
      expect(r.to, DateTime(2026, 9, 30));
    });

    test('rentang pilihan inklusif sampai akhir hari terakhir', () {
      final r = HistoryFilter(
        range: HistoryRange.pilihTanggal,
        customFrom: DateTime(2026, 9, 10, 18),
        customTo: DateTime(2026, 9, 12),
      ).resolve(now);
      expect(r.from, DateTime(2026, 9, 10));
      expect(r.to, DateTime(2026, 9, 13));
    });

    test('copyWith bisa mengosongkan sumber', () {
      const f = HistoryFilter(source: TxSource.voice);
      expect(f.copyWith(source: null).source, isNull);
      expect(f.copyWith(range: HistoryRange.hariIni).source, TxSource.voice);
    });
  });

  group('database', () {
    late AppDatabase database;
    late TransactionRepository repository;
    late String storeId;

    setUp(() async {
      database = AppDatabase();
      await database.open(overridePath: inMemoryDatabasePath);
      repository = TransactionRepository(database: database);
      storeId = (await StoreDao(database.db).create(name: 'Warteg Uji')).id;
    });

    tearDown(() async => database.close());

    test('grup per hari dengan subtotal masuk/keluar', () async {
      await repository.save(
        tx(TxCategory.penjualan, DateTime(2026, 9, 28, 9)),
        storeId: storeId,
      );
      await repository.save(
        tx(TxCategory.penjualan, DateTime(2026, 9, 29, 9)),
        storeId: storeId,
      );
      await repository.save(
        tx(
          TxCategory.pengeluaran,
          DateTime(2026, 9, 29, 12),
          items: [('gas', 1, 22000, PriceMode.perUnit, null)],
        ),
        storeId: storeId,
      );

      final records = await repository.listBetween(
        storeId: storeId,
        from: DateTime(2026, 9, 28),
        to: DateTime(2026, 9, 30),
      );
      final groups = groupByDay(records);

      expect(groups.map((g) => g.day), [
        DateTime(2026, 9, 29),
        DateTime(2026, 9, 28),
      ]);
      expect(groups.first.masuk, 30000);
      expect(groups.first.keluar, 22000);
      expect(groups.first.net, 8000);
      expect(groups.last.records, hasLength(1));
    });

    test('filter kategori dan sumber', () async {
      await repository.save(
        tx(
          TxCategory.penjualan,
          DateTime(2026, 9, 29, 9),
          source: TxSource.voice,
        ),
        storeId: storeId,
      );
      await repository.save(
        tx(TxCategory.pembelian, DateTime(2026, 9, 29, 10)),
        storeId: storeId,
      );
      final range = (from: DateTime(2026, 9, 29), to: DateTime(2026, 9, 30));

      final purchases = await repository.listBetween(
        storeId: storeId,
        from: range.from,
        to: range.to,
        categories: {TxCategory.pembelian},
      );
      final voice = await repository.listBetween(
        storeId: storeId,
        from: range.from,
        to: range.to,
        source: TxSource.voice,
      );

      expect(purchases.single.category, TxCategory.pembelian);
      expect(voice.single.category, TxCategory.penjualan);
    });

    test('pencatat tersimpan', () async {
      final saved = await repository.save(
        tx(TxCategory.penjualan, DateTime(2026, 9, 29, 9)),
        storeId: storeId,
        recordedBy: 'bu.ani@contoh.com',
      );
      final loaded = await repository.findById(saved.id);
      expect(loaded!.recordedBy, 'bu.ani@contoh.com');
    });

    test('koreksi lewat fromRecord mempertahankan harga total', () async {
      final original = await repository.save(
        tx(
          TxCategory.pembelian,
          DateTime(2026, 9, 29, 9),
          items: [('cabai', 3, 25000, PriceMode.total, 'kg')],
        ),
        storeId: storeId,
      );

      final draft = TransactionDraft.fromRecord(original);
      expect(draft.needsAttention, isFalse);
      expect(draft.items.single.priceIsTotal, isTrue);
      expect(draft.total, 25000);
      expect(draft.effectiveCategory, TxCategory.pembelian);

      final edited = draft.copyWith(
        items: [
          draft.items.single.copyWith(
            unitPrice: const DraftField<int>.entered(30000),
          ),
        ],
      );
      final replaced = await repository.replace(
        original.id,
        confirmDraftByUser(draft: edited, editedFields: const {'price'})!,
        storeId: storeId,
      );

      expect(await repository.findById(original.id), isNull);
      expect(replaced.totalAmount, 30000);
      expect(replaced.occurredAt, original.occurredAt);
    });

    test('lencana sinkron hanya untuk transaksi yang masih antre', () async {
      await SettingsDao(database.db)
          .setFlag(SettingsKeys.syncEnabled, value: true);
      final saved = await repository.save(
        tx(TxCategory.penjualan, DateTime(2026, 9, 29, 9)),
        storeId: storeId,
      );
      final ids = await PendingSyncDao(database.db)
          .pendingEntityIds('transaction');
      expect(ids, {saved.id});
    });

    test('laporan: total per kategori, menu terlaris, pengeluaran', () async {
      final at = DateTime(2026, 9, 29, 9);
      await repository.save(
        tx(
          TxCategory.penjualan,
          at,
          items: [
            ('Nasi Ayam', 3, 15000, PriceMode.perUnit, 'porsi'),
            ('es teh', 4, 3000, PriceMode.perUnit, 'gelas'),
          ],
        ),
        storeId: storeId,
      );
      await repository.save(
        tx(
          TxCategory.penjualan,
          at,
          items: [('nasi ayam', 2, 15000, PriceMode.perUnit, 'porsi')],
        ),
        storeId: storeId,
      );
      await repository.save(
        tx(
          TxCategory.pembelian,
          at,
          items: [('ayam', 5, 200000, PriceMode.total, 'kg')],
        ),
        storeId: storeId,
      );
      await repository.save(
        tx(
          TxCategory.pengeluaran,
          at,
          items: [('listrik', 1, 50000, PriceMode.perUnit, null)],
        ),
        storeId: storeId,
      );

      final reports = ReportRepository(database.db);
      final from = DateTime(2026, 9, 29);
      final to = DateTime(2026, 9, 30);
      final totals = await reports.totals(storeId: storeId, from: from, to: to);
      expect(totals.omzet, 87000);
      expect(totals.pengeluaran, 250000);
      expect(totals.keuntungan, -163000);
      expect(totals.count, 4);

      final top = await reports.topItems(
        storeId: storeId,
        from: from,
        to: to,
        categories: {TxCategory.penjualan},
      );
      // "Nasi Ayam" dan "nasi ayam" satu menu di katalog.
      expect(top.first.qty, 5);
      expect(top.first.amount, 75000);
      expect(top, hasLength(2));

      final spend = await reports.topItems(
        storeId: storeId,
        from: from,
        to: to,
        categories: {TxCategory.pembelian, TxCategory.pengeluaran},
        byQty: false,
      );
      expect(spend.first.name, 'ayam');
      expect(spend.first.amount, 200000);
    });

    test('Excel: dua sheet, satu baris per barang, ringkasan harian', () async {
      await repository.save(
        tx(
          TxCategory.penjualan,
          DateTime(2026, 9, 28, 9),
          items: [
            ('nasi ayam', 2, 15000, PriceMode.perUnit, 'porsi'),
            ('es teh', 2, 3000, PriceMode.perUnit, 'gelas'),
          ],
        ),
        storeId: storeId,
        recordedBy: 'budi@contoh.com',
      );
      await repository.save(
        tx(
          TxCategory.pembelian,
          DateTime(2026, 9, 29, 7),
          items: [('ayam', 5, 200000, PriceMode.total, 'kg')],
        ),
        storeId: storeId,
      );
      final records = await repository.listBetween(
        storeId: storeId,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 10, 1),
      );

      final book = Excel.decodeBytes(buildTransactionsWorkbook(records));
      expect(
        book.tables.keys,
        containsAll([transactionsSheetName, dailySummarySheetName]),
      );
      expect(book.tables.keys, hasLength(2));

      final sheet = book.tables[transactionsSheetName]!;
      String cell(int r, int c) => '${sheet.rows[r][c]?.value}';
      expect(
        [for (var c = 0; c < 8; c++) cell(0, c)],
        [
          'Tanggal',
          'Jam',
          'Nama Item',
          'Jumlah',
          'Harga Satuan',
          'Total',
          'Sumber',
          'Dicatat Oleh',
        ],
      );
      expect(sheet.rows[0][0]?.cellStyle?.isBold, isTrue);
      // Terlama dulu; transaksi dua barang jadi dua baris.
      expect(sheet.maxRows, 4);
      expect(cell(1, 0), '2026-09-28');
      expect(cell(1, 2), 'nasi ayam');
      expect(cell(1, 7), 'budi@contoh.com');
      expect(cell(3, 2), 'ayam');
      expect(cell(3, 4), '40000');
      expect(cell(3, 5), '200000');

      final summary = book.tables[dailySummarySheetName]!;
      String s(int r, int c) => '${summary.rows[r][c]?.value}';
      expect(s(1, 0), '2026-09-28');
      expect(s(1, 2), '36000');
      expect(s(2, 3), '200000');
      expect(s(3, 0), 'TOTAL');
      expect(s(3, 4), '-164000');
    });
  });

  group('nama berkas', () {
    test('mengikuti pola SmartToko_[Toko]_[Mulai]_[Akhir]', () {
      expect(
        exportFileName(
          storeName: "Warteg Bu Ani's",
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 9, 29),
        ),
        'SmartToko_Warteg_Bu_Ani_s_2026-09-01_2026-09-29.xlsx',
      );
    });
  });

  group('wawasan', () {
    CategoryTotals totals({int jual = 0, int beli = 0, int count = 1}) =>
        CategoryTotals(
          amounts: {TxCategory.penjualan: jual, TxCategory.pembelian: beli},
          count: count,
        );

    test('periode pembanding minggu ini adalah hari yang sama minggu lalu', () {
      final r = ReportPeriod.mingguIni.ranges(DateTime(2026, 9, 29, 10));
      expect(r.prevFrom, DateTime(2026, 9, 21));
      expect(r.prevTo, DateTime(2026, 9, 23));
    });

    test('bulan ini tanggal 31 dibandingkan dengan akhir bulan lalu', () {
      final r = ReportPeriod.bulanIni.ranges(DateTime(2026, 10, 31, 10));
      expect(r.prevFrom, DateTime(2026, 9, 1));
      expect(r.prevTo, DateTime(2026, 10, 1));
    });

    test('menu terlaris dan kenaikan pengeluaran disebut', () {
      final insights = buildInsights(
        period: ReportPeriod.mingguIni,
        current: totals(jual: 500000, beli: 300000),
        previous: totals(jual: 500000, beli: 200000),
        topMenu: const [
          ItemAggregate(
            name: 'nasi ayam',
            qty: 24,
            amount: 360000,
            unit: 'porsi',
          ),
        ],
        topSpending: const [
          ItemAggregate(name: 'ayam', qty: 5, amount: 200000),
        ],
        lowStock: const [LowStock(name: 'beras', qty: 2, unit: 'kg')],
      );
      expect(insights.first, contains('nasi ayam'));
      expect(insights.first, contains('24 porsi'));
      expect(insights, contains(contains('Omzet sama dengan minggu lalu')));
      expect(
        insights,
        contains(contains('Pengeluaran naik 50% dibanding minggu lalu')),
      );
      expect(insights, contains(contains('beras (2 kg)')));
    });

    test('tanpa data pembanding tidak mengarang persentase', () {
      final insights = buildInsights(
        period: ReportPeriod.hariIni,
        current: totals(jual: 100000),
        previous: CategoryTotals.empty,
        topMenu: const [],
        topSpending: const [],
        lowStock: const [],
      );
      expect(insights.where((s) => s.contains('%')), isEmpty);
    });

    test('motivasi harian', () {
      expect(
        dailyMotivation(
          today: CategoryTotals.empty,
          yesterday: CategoryTotals.empty,
          hour: 8,
        ),
        contains('Selamat pagi'),
      );
      expect(
        dailyMotivation(
          today: totals(jual: 600000),
          yesterday: totals(jual: 500000),
          hour: 20,
        ),
        allOf(contains('Mantap'), contains('20%')),
      );
    });
  });
}
