/// Tes utang/piutang: kasbon, pembayaran bertahap, saldo per kontak, dan
/// ketahanannya terhadap koreksi transaksi.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/core/db/dao/contact_dao.dart';
import 'package:smart_toko/core/db/dao/store_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/debts/data/debt_repository.dart';
import 'package:smart_toko/features/transactions/data/transaction_repository.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';

TransactionDraft draft({
  TxDirection direction = TxDirection.masuk,
  TxCategory? category,
  int qty = 2,
  int unitPrice = 5000,
  String? contactId,
  bool onCredit = false,
  DateTime? occurredAt,
}) => TransactionDraft(
  direction: DraftField<TxDirection>.entered(direction),
  category: category == null
      ? const DraftField<TxCategory>.empty()
      : DraftField<TxCategory>.entered(category),
  items: [
    DraftItem(
      name: const DraftField<String>.entered('nasi goreng'),
      qty: DraftField<int>.entered(qty),
      unitPrice: DraftField<int>.entered(unitPrice),
    ),
  ],
  occurredAt: occurredAt ?? DateTime(2026, 10, 1, 10),
  source: TxSource.manual,
  contactId: contactId,
  onCredit: onCredit,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late TransactionRepository transactions;
  late DebtRepository debts;
  late String storeId;
  late String sari;
  late String budi;
  late String supplier;

  Future<String> contact(String name, ContactKind kind) async =>
      (await ContactDao(database.db).create(
        storeId: storeId,
        kind: kind,
        name: name,
        now: DateTime.now(),
      )).id;

  Future<String> save(TransactionDraft d) async {
    final confirmed = confirmDraftByUser(draft: d, editedFields: const {})!;
    return (await transactions.save(confirmed, storeId: storeId)).id;
  }

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    transactions = TransactionRepository(database: database);
    debts = DebtRepository(database: database);
    storeId = (await StoreDao(database.db).create(name: 'Warung Uji')).id;
    sari = await contact('Bu Sari', ContactKind.pelanggan);
    budi = await contact('Pak Budi', ContactKind.pelanggan);
    supplier = await contact('Toko Maju', ContactKind.supplier);
  });

  tearDown(() async => database.close());

  group('draf kasbon', () {
    test('kasbon tanpa nama tidak bisa dikonfirmasi', () {
      final d = draft(onCredit: true);

      expect(d.isComplete, isFalse);
      expect(confirmDraftByUser(draft: d, editedFields: const {}), isNull);
    });

    test('kasbon dengan nama bisa dikonfirmasi', () {
      final d = draft(onCredit: true, contactId: sari);

      expect(confirmDraftByUser(draft: d, editedFields: const {}), isNotNull);
    });

    test('pemasukan lain dan pengeluaran operasional selalu tunai', () {
      for (final category in [TxCategory.pemasukanLain]) {
        expect(
          draft(category: category, onCredit: true).isCredit,
          isFalse,
          reason: '${category.label} tidak boleh dikasbon',
        );
      }
      expect(
        draft(
          direction: TxDirection.keluar,
          category: TxCategory.pengeluaran,
          onCredit: true,
        ).isCredit,
        isFalse,
      );
    });

    test('pembelian bahan boleh dikasbon', () {
      expect(
        draft(direction: TxDirection.keluar, onCredit: true).isCredit,
        isTrue,
      );
    });

    test('beralih ke kategori tunai tidak mewajibkan kontak', () {
      final d = draft(category: TxCategory.pemasukanLain, onCredit: true);

      expect(d.isComplete, isTrue);
    });
  });

  group('menyimpan kasbon', () {
    test('transaksi tunai tidak punya sisa', () async {
      final id = await save(draft());

      final record = (await transactions.findById(id))!;
      expect(record.onCredit, isFalse);
      expect(record.outstanding, 0);
      expect(await debts.totals(storeId), isA<DebtTotals>());
      expect((await debts.totals(storeId)).isEmpty, isTrue);
    });

    test('kasbon penjualan menjadi piutang sebesar totalnya', () async {
      final id = await save(draft(onCredit: true, contactId: sari));

      final record = (await transactions.findById(id))!;
      expect(record.onCredit, isTrue);
      expect(record.outstanding, 10000);
      expect(record.isUnpaid, isTrue);
      expect((await debts.totals(storeId)).receivable, 10000);
      expect((await debts.totals(storeId)).payable, 0);
    });

    test('kasbon pembelian menjadi utang ke supplier', () async {
      await save(
        draft(
          direction: TxDirection.keluar,
          onCredit: true,
          contactId: supplier,
        ),
      );

      final totals = await debts.totals(storeId);
      expect(totals.payable, 10000);
      expect(totals.receivable, 0);
    });

    test('kasbon tetap terhitung sebagai omzet pada tanggalnya', () async {
      await save(draft(onCredit: true, contactId: sari));

      final omzet = await transactions.totalBetween(
        storeId: storeId,
        direction: TxDirection.masuk,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 2),
      );
      expect(omzet, 10000);
    });
  });

  group('pembayaran', () {
    late String txId;

    setUp(() async {
      txId = await save(draft(onCredit: true, contactId: sari));
    });

    test('pembayaran sebagian mengurangi sisa', () async {
      await debts.addPayment(
        storeId: storeId,
        transactionId: txId,
        amount: 4000,
      );

      final record = (await transactions.findById(txId))!;
      expect(record.paidAmount, 4000);
      expect(record.outstanding, 6000);
      expect((await debts.totals(storeId)).receivable, 6000);
    });

    test('pelunasan membuat sisa nol dan kontak hilang dari daftar', () async {
      await debts.addPayment(
        storeId: storeId,
        transactionId: txId,
        amount: 10000,
      );

      final record = (await transactions.findById(txId))!;
      expect(record.outstanding, 0);
      expect(record.isUnpaid, isFalse);
      expect(await debts.balances(storeId), isEmpty);
    });

    test('pembayaran melebihi sisa ditolak', () async {
      await expectLater(
        debts.addPayment(storeId: storeId, transactionId: txId, amount: 10001),
        throwsA(isA<DebtException>()),
      );
      expect(await debts.paymentsFor(txId), isEmpty);
    });

    test('jumlah nol atau negatif ditolak', () async {
      for (final amount in [0, -500]) {
        await expectLater(
          debts.addPayment(
            storeId: storeId,
            transactionId: txId,
            amount: amount,
          ),
          throwsA(isA<DebtException>()),
        );
      }
    });

    test('transaksi yang sudah lunas tidak menerima pembayaran lagi', () async {
      await debts.addPayment(
        storeId: storeId,
        transactionId: txId,
        amount: 10000,
      );

      await expectLater(
        debts.addPayment(storeId: storeId, transactionId: txId, amount: 1),
        throwsA(isA<DebtException>()),
      );
    });

    test('transaksi tunai tidak bisa dibayar', () async {
      final cash = await save(draft());

      await expectLater(
        debts.addPayment(storeId: storeId, transactionId: cash, amount: 1000),
        throwsA(isA<DebtException>()),
      );
    });

    test('pembayaran tidak bisa dicatat di toko lain', () async {
      final other = (await StoreDao(database.db).create(name: 'Toko Lain')).id;

      await expectLater(
        debts.addPayment(storeId: other, transactionId: txId, amount: 1000),
        throwsA(isA<DebtException>()),
      );
    });

    test('menghapus pembayaran mengembalikan sisa', () async {
      final payment = await debts.addPayment(
        storeId: storeId,
        transactionId: txId,
        amount: 10000,
      );

      await debts.deletePayment(payment.id);

      expect((await transactions.findById(txId))!.outstanding, 10000);
    });

    test('menghapus transaksi ikut menghapus pembayarannya', () async {
      await debts.addPayment(
        storeId: storeId,
        transactionId: txId,
        amount: 3000,
      );

      await transactions.delete(txId);

      expect(await database.db.query('debt_payments'), isEmpty);
      expect((await debts.totals(storeId)).isEmpty, isTrue);
    });
  });

  group('saldo per kontak', () {
    test(
      'menjumlahkan beberapa kasbon dan mengurutkan terbesar dulu',
      () async {
        await save(draft(onCredit: true, contactId: sari));
        await save(
          draft(
            onCredit: true,
            contactId: sari,
            unitPrice: 2000,
            occurredAt: DateTime(2026, 9, 20),
          ),
        );
        await save(draft(onCredit: true, contactId: budi, qty: 10));

        final balances = await debts.balances(storeId);

        expect(balances.map((b) => b.name), ['Pak Budi', 'Bu Sari']);
        final sariBalance = balances.last;
        expect(sariBalance.outstanding, 14000);
        expect(sariBalance.openCount, 2);
        expect(sariBalance.oldest, DateTime(2026, 9, 20));
        expect(await debts.outstandingFor(storeId, sari), 14000);
      },
    );

    test('utang dan piutang dipisah menurut arah', () async {
      await save(draft(onCredit: true, contactId: sari));
      await save(
        draft(
          direction: TxDirection.keluar,
          onCredit: true,
          contactId: supplier,
        ),
      );

      final balances = await debts.balances(storeId);
      expect(
        {for (final b in balances) b.name: b.direction},
        {'Bu Sari': TxDirection.masuk, 'Toko Maju': TxDirection.keluar},
      );
    });

    test('data toko lain tidak ikut terhitung', () async {
      final other = (await StoreDao(database.db).create(name: 'Toko Lain')).id;
      final foreign = confirmDraftByUser(
        draft: draft(onCredit: true, contactId: sari),
        editedFields: const {},
      )!;
      await transactions.save(foreign, storeId: other);

      expect((await debts.totals(storeId)).isEmpty, isTrue);
      expect(await debts.balances(storeId), isEmpty);
    });
  });

  group('koreksi transaksi', () {
    test('riwayat pembayaran dipertahankan saat transaksi dikoreksi', () async {
      final id = await save(draft(onCredit: true, contactId: sari));
      await debts.addPayment(storeId: storeId, transactionId: id, amount: 4000);

      final corrected = confirmDraftByUser(
        draft: draft(onCredit: true, contactId: sari, qty: 3),
        editedFields: const {},
      )!;
      final replaced = await transactions.replace(
        id,
        corrected,
        storeId: storeId,
      );

      expect(replaced.id, isNot(id));
      expect(replaced.totalAmount, 15000);
      expect(replaced.paidAmount, 4000);
      expect(replaced.outstanding, 11000);
      expect(await debts.paymentsFor(replaced.id), hasLength(1));
    });

    test('diubah menjadi tunai: pembayaran tidak lagi relevan', () async {
      final id = await save(draft(onCredit: true, contactId: sari));
      await debts.addPayment(storeId: storeId, transactionId: id, amount: 4000);

      final corrected = confirmDraftByUser(
        draft: draft(),
        editedFields: const {},
      )!;
      final replaced = await transactions.replace(
        id,
        corrected,
        storeId: storeId,
      );

      expect(replaced.onCredit, isFalse);
      expect(replaced.outstanding, 0);
      expect(await database.db.query('debt_payments'), isEmpty);
    });

    test(
      'total dikoreksi lebih kecil dari yang sudah dibayar: sisa nol',
      () async {
        final id = await save(draft(onCredit: true, contactId: sari));
        await debts.addPayment(
          storeId: storeId,
          transactionId: id,
          amount: 9000,
        );

        final corrected = confirmDraftByUser(
          draft: draft(onCredit: true, contactId: sari, qty: 1),
          editedFields: const {},
        )!;
        final replaced = await transactions.replace(
          id,
          corrected,
          storeId: storeId,
        );

        expect(replaced.outstanding, 0);
        expect((await debts.totals(storeId)).isEmpty, isTrue);
      },
    );
  });
}
