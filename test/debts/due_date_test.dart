/// Jatuh tempo kasbon: penyimpanan, telat bayar, dan rekam jejak pelanggan.
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
import 'package:smart_toko/features/voice_parser/rules/rule_parser.dart';

TransactionDraft credit({
  required String contactId,
  DateTime? dueAt,
  DateTime? occurredAt,
  int price = 20000,
  bool onCredit = true,
}) => TransactionDraft(
  direction: const DraftField<TxDirection>.entered(TxDirection.masuk),
  items: [
    DraftItem(
      name: const DraftField<String>.entered('nasi'),
      qty: const DraftField<int>.entered(1),
      unitPrice: DraftField<int>.entered(price),
    ),
  ],
  occurredAt: occurredAt ?? DateTime(2026, 10, 1, 10),
  source: TxSource.manual,
  contactId: contactId,
  onCredit: onCredit,
  dueAt: dueAt,
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
  final today = DateTime(2026, 10, 12, 15);

  Future<String> save(TransactionDraft d) async => (await transactions.save(
    confirmDraftByUser(draft: d, editedFields: const {})!,
    storeId: storeId,
  )).id;

  Future<String> contact(String name) async =>
      (await ContactDao(database.db).create(
        storeId: storeId,
        kind: ContactKind.pelanggan,
        name: name,
        now: DateTime.now(),
      )).id;

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    transactions = TransactionRepository(database: database);
    debts = DebtRepository(database: database);
    storeId = (await StoreDao(database.db).create(name: 'Warung')).id;
    sari = await contact('Bu Sari');
    budi = await contact('Pak Budi');
  });

  tearDown(() async => database.close());

  group('menyimpan jatuh tempo', () {
    test('disimpan sebagai awal hari', () async {
      final id = await save(
        credit(contactId: sari, dueAt: DateTime(2026, 10, 20, 17, 45)),
      );

      expect((await transactions.findById(id))!.dueAt, DateTime(2026, 10, 20));
    });

    test('transaksi tunai tidak menyimpan jatuh tempo', () async {
      final id = await save(
        credit(contactId: sari, dueAt: DateTime(2026, 10, 20), onCredit: false),
      );

      expect((await transactions.findById(id))!.dueAt, isNull);
    });

    test('koreksi mempertahankan jatuh tempo dari draf', () async {
      final id = await save(
        credit(contactId: sari, dueAt: DateTime(2026, 10, 20)),
      );
      final record = (await transactions.findById(id))!;

      final replaced = await transactions.replace(
        id,
        confirmDraftByUser(
          draft: TransactionDraft.fromRecord(record),
          editedFields: const {},
        )!,
        storeId: storeId,
      );

      expect(replaced.dueAt, DateTime(2026, 10, 20));
    });
  });

  group('telat bayar', () {
    test('belum telat pada hari jatuh tempo, telat sesudahnya', () async {
      final id = await save(
        credit(contactId: sari, dueAt: DateTime(2026, 10, 12)),
      );
      final record = (await transactions.findById(id))!;

      expect(record.isOverdue(DateTime(2026, 10, 12, 23)), isFalse);
      expect(record.daysOverdue(DateTime(2026, 10, 15, 8)), 3);
    });

    test('kasbon lunas tidak pernah telat', () async {
      final id = await save(
        credit(contactId: sari, dueAt: DateTime(2026, 10, 1)),
      );
      await debts.addPayment(
        storeId: storeId,
        transactionId: id,
        amount: 20000,
      );

      expect((await transactions.findById(id))!.isOverdue(today), isFalse);
    });

    test('ringkasan memisahkan bagian yang telat', () async {
      await save(credit(contactId: sari, dueAt: DateTime(2026, 10, 5)));
      await save(credit(contactId: sari, dueAt: DateTime(2026, 10, 30)));
      await save(credit(contactId: budi));

      final totals = await debts.totals(storeId, now: today);

      expect(totals.receivable, 60000);
      expect(totals.overdueReceivable, 20000);
    });

    test(
      'kontak yang telat tampil paling atas walau sisanya lebih kecil',
      () async {
        await save(credit(contactId: budi, price: 90000));
        await save(credit(contactId: sari, dueAt: DateTime(2026, 10, 5)));

        final balances = await debts.balances(storeId, now: today);

        expect(balances.map((b) => b.name), ['Bu Sari', 'Pak Budi']);
        expect(balances.first.isOverdue, isTrue);
        expect(balances.first.overdue, 20000);
        expect(balances.first.nextDue, DateTime(2026, 10, 5));
        expect(balances.last.isOverdue, isFalse);
        expect(balances.last.nextDue, isNull);
      },
    );
  });

  group('mengubah jatuh tempo', () {
    test('bisa diubah dan dihapus', () async {
      final id = await save(credit(contactId: sari));

      await debts.setDueDate(id, DateTime(2026, 11, 1, 9));
      expect((await transactions.findById(id))!.dueAt, DateTime(2026, 11, 1));

      await debts.setDueDate(id, null);
      expect((await transactions.findById(id))!.dueAt, isNull);
    });

    test('ditolak untuk transaksi tunai', () async {
      final id = await save(credit(contactId: sari, onCredit: false));

      await expectLater(
        debts.setDueDate(id, DateTime(2026, 11, 1)),
        throwsA(isA<DebtException>()),
      );
    });
  });

  test('dueBetween hanya memuat kasbon belum lunas pada rentangnya', () async {
    await save(credit(contactId: sari, dueAt: DateTime(2026, 10, 13)));
    final paid = await save(
      credit(contactId: budi, dueAt: DateTime(2026, 10, 13)),
    );
    await debts.addPayment(
      storeId: storeId,
      transactionId: paid,
      amount: 20000,
    );
    await save(credit(contactId: budi, dueAt: DateTime(2026, 10, 25)));

    final due = await debts.dueBetween(
      storeId,
      from: DateTime(2026, 10, 12),
      to: DateTime(2026, 10, 15),
    );

    expect(due.map((d) => d.contactName), ['Bu Sari']);
    expect(due.single.outstanding, 20000);
  });

  test('rekam jejak bayar menghitung yang lunas terlambat', () async {
    // Lunas tepat waktu.
    final onTime = await save(
      credit(
        contactId: sari,
        occurredAt: DateTime(2026, 9, 1),
        dueAt: DateTime(2026, 9, 10),
      ),
    );
    await debts.addPayment(
      storeId: storeId,
      transactionId: onTime,
      amount: 20000,
      paidAt: DateTime(2026, 9, 9),
    );
    // Lunas terlambat (dicicil, pembayaran terakhir sesudah jatuh tempo).
    final lateOne = await save(
      credit(
        contactId: sari,
        occurredAt: DateTime(2026, 9, 1),
        dueAt: DateTime(2026, 9, 5),
      ),
    );
    await debts.addPayment(
      storeId: storeId,
      transactionId: lateOne,
      amount: 10000,
      paidAt: DateTime(2026, 9, 4),
    );
    await debts.addPayment(
      storeId: storeId,
      transactionId: lateOne,
      amount: 10000,
      paidAt: DateTime(2026, 9, 21),
    );
    // Belum lunas: tidak dihitung.
    await save(credit(contactId: sari, dueAt: DateTime(2026, 9, 1)));

    final record = await debts.paymentRecord(storeId, sari);

    expect(record.settled, 2);
    expect(record.withDueDate, 2);
    expect(record.late, 1);
    expect(record.averageDaysToSettle, (8 + 20) / 2);
  });

  group('ucapan', () {
    const parser = RuleBasedParser();

    test('"bayar besok" = kasbon jatuh tempo besok', () {
      final result = parser.parse(
        'jual nasi goreng dua lima belas ribu bayar besok',
      );

      expect(result.onCredit, isTrue);
      expect(result.dueInDays, 1);
      expect(result.items.single.name.value, 'nasi goreng');
    });

    test('"ngutang ... minggu depan" = jatuh tempo 7 hari', () {
      final result = parser.parse(
        'jual nasi goreng dua lima belas ribu ngutang bayar minggu depan',
      );

      expect(result.dueInDays, 7);
      expect(result.unmatchedTokens, isEmpty);
      final draft = TransactionDraft.fromParseResult(
        result,
        occurredAt: DateTime(2026, 10, 12, 10),
      );
      expect(draft.dueAt, DateTime(2026, 10, 19));
    });

    test('tanpa kata kasbon, "besok" tidak jadi jatuh tempo', () {
      final result = parser.parse('beli roti dua lima ribu besok');

      expect(result.onCredit, isFalse);
      expect(result.dueInDays, isNull);
    });
  });
}
