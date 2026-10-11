/// Tampilan kasbon: sakelar di layar konfirmasi dan layar Utang & Piutang.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/contact_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/debts/ui/debts_screen.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';
import 'package:smart_toko/features/transactions/ui/confirmation_sheet.dart';

TransactionDraft sale({bool onCredit = false, String? contactId}) =>
    TransactionDraft(
      direction: const DraftField<TxDirection>.entered(TxDirection.masuk),
      items: const [
        DraftItem(
          name: DraftField<String>.entered('nasi goreng'),
          qty: DraftField<int>.entered(2),
          unitPrice: DraftField<int>.entered(15000),
        ),
      ],
      occurredAt: DateTime(2026, 10, 1, 10),
      source: TxSource.manual,
      onCredit: onCredit,
      contactId: contactId,
    );

Future<void> pumpSheet(
  WidgetTester tester,
  TransactionDraft draft, {
  required List<ConfirmedDraft> saved,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConfirmationSheet(
          draft: draft,
          onConfirm: (confirmed) async => saved.add(confirmed),
          pickContact: (kind) async => (id: 'sari', name: 'Bu Sari'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// FilledButton.icon adalah subkelas privat, jadi dicari lewat predikat.
Finder get saveButton => find.byWidgetPredicate((w) => w is FilledButton);

/// Toko aktif tetap, tanpa gerbang toko dan akun.
class _FixedStore extends ActiveStoreId {
  final String id;
  _FixedStore(this.id);

  @override
  String? build() => id;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('id_ID');
  });

  group('layar konfirmasi', () {
    testWidgets('sakelar belum dibayar tersedia untuk penjualan', (
      tester,
    ) async {
      await pumpSheet(tester, sale(), saved: []);

      expect(find.text('Belum dibayar (kasbon pelanggan)'), findsOneWidget);
    });

    testWidgets('kasbon tanpa pelanggan tidak bisa disimpan', (tester) async {
      await pumpSheet(tester, sale(), saved: []);

      await tester.tap(find.text('Belum dibayar (kasbon pelanggan)'));
      await tester.pumpAndSettle();

      expect(
        find.text('Pilih pelanggan dulu supaya bisa ditagih.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    });

    testWidgets('memilih pelanggan membuat kasbon bisa disimpan', (
      tester,
    ) async {
      final saved = <ConfirmedDraft>[];
      await pumpSheet(tester, sale(), saved: saved);

      await tester.tap(find.text('Belum dibayar (kasbon pelanggan)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pilih pelanggan'));
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single.draft.isCredit, isTrue);
      expect(saved.single.draft.contactId, 'sari');
      expect(saved.single.editedFields, contains('credit'));
    });

    testWidgets('draf dari suara "ngutang" tiba dengan sakelar menyala', (
      tester,
    ) async {
      await pumpSheet(tester, sale(onCredit: true), saved: []);

      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    });

    testWidgets('pengeluaran operasional tidak menawarkan kasbon', (
      tester,
    ) async {
      final draft = sale().copyWith(
        direction: const DraftField<TxDirection>.entered(TxDirection.keluar),
        category: const DraftField<TxCategory>.entered(TxCategory.pengeluaran),
      );
      await pumpSheet(tester, draft, saved: []);

      expect(find.byType(SwitchListTile), findsNothing);
    });
  });

  group('layar Utang & Piutang', () {
    late AppDatabase database;
    late String storeId;

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            activeStoreIdProvider.overrideWith(() => _FixedStore(storeId)),
          ],
          child: const MaterialApp(home: DebtsScreen()),
        ),
      );
      // sqflite berjalan di luar jam palsu widget test.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
    }

    setUp(() async {
      database = AppDatabase();
      await database.open(overridePath: inMemoryDatabasePath);
      storeId = (await StoreDao(database.db).create(name: 'Warung Uji')).id;
    });

    tearDown(() async => database.close());

    Future<void> addCredit(
      WidgetTester tester, {
      required String name,
      required ContactKind kind,
      required TxDirection direction,
      required int unitPrice,
    }) => tester.runAsync(() async {
      final contact = await ContactDao(
        database.db,
      ).create(storeId: storeId, kind: kind, name: name, now: DateTime.now());
      final confirmed = confirmDraftByUser(
        draft: sale(onCredit: true, contactId: contact.id).copyWith(
          direction: DraftField<TxDirection>.entered(direction),
          items: [
            DraftItem(
              name: const DraftField<String>.entered('barang'),
              qty: const DraftField<int>.entered(1),
              unitPrice: DraftField<int>.entered(unitPrice),
            ),
          ],
        ),
        editedFields: const {},
      )!;
      await TransactionRepository(database: database)
          .save(confirmed, storeId: storeId);
    });

    testWidgets('kosong menjelaskan cara memakainya', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Tidak ada utang atau piutang'), findsOneWidget);
    });

    testWidgets('menampilkan nama, sisa, dan total per jenis', (tester) async {
      await addCredit(
        tester,
        name: 'Bu Sari',
        kind: ContactKind.pelanggan,
        direction: TxDirection.masuk,
        unitPrice: 40000,
      );
      await addCredit(
        tester,
        name: 'Toko Maju',
        kind: ContactKind.supplier,
        direction: TxDirection.keluar,
        unitPrice: 250000,
      );

      await pumpScreen(tester);

      expect(find.text('Bu Sari'), findsOneWidget);
      expect(find.text('Toko Maju'), findsOneWidget);
      expect(find.text('Belum dibayar pelanggan'), findsOneWidget);
      expect(find.text('Utang ke supplier'), findsOneWidget);
      // Muncul di tile dan di ringkasan atas.
      expect(find.text('Rp40.000'), findsNWidgets(2));
      expect(find.text('Rp250.000'), findsNWidgets(2));
      expect(find.text('Harus ditagih'), findsOneWidget);
      expect(find.text('Harus dibayar'), findsOneWidget);
    });
  });

  group('ageLabel', () {
    final now = DateTime(2026, 10, 12, 9);

    test('hari, minggu, bulan', () {
      expect(ageLabel(DateTime(2026, 10, 12, 1), now), 'hari ini');
      expect(ageLabel(DateTime(2026, 10, 9), now), '3 hari');
      expect(ageLabel(DateTime(2026, 9, 28), now), '2 minggu');
      expect(ageLabel(DateTime(2026, 7, 1), now), '3 bulan');
    });
  });
}
