/// Tampilan jatuh tempo: label, pilihan di layar konfirmasi, pengingat, dan
/// nota.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/debts/due_label.dart';
import 'package:smart_toko/features/debts/reminder.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/receipt.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_record.dart';
import 'package:smart_toko/features/transactions/ui/confirmation_sheet.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('dueLabel', () {
    final now = DateTime(2026, 10, 12, 20);

    test('telat, hari ini, besok, dan tanggal', () {
      expect(dueLabel(DateTime(2026, 10, 9), now), 'telat 3 hari');
      expect(dueLabel(DateTime(2026, 10, 12), now), 'jatuh tempo hari ini');
      expect(dueLabel(DateTime(2026, 10, 13), now), 'jatuh tempo besok');
      expect(dueLabel(DateTime(2026, 10, 20), now), 'jatuh tempo 20 Okt 2026');
    });
  });

  test('pengingat menyebut jatuh tempo bila ada', () {
    final message = buildReminderMessage(
      contactName: 'Bu Sari',
      storeName: 'Warung',
      outstanding: 20000,
      openCount: 1,
      since: DateTime(2026, 10, 1),
      dueAt: DateTime(2026, 10, 8),
    );

    expect(message, contains('jatuh tempo 8 Okt 2026'));
  });

  test('nota kasbon menyebut jatuh tempo', () {
    final record = TxRecord(
      id: 't1',
      storeId: 's1',
      direction: TxDirection.masuk,
      category: TxCategory.penjualan,
      occurredAt: DateTime(2026, 10, 1),
      source: TxSource.manual,
      totalAmount: 20000,
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
      onCredit: true,
      dueAt: DateTime(2026, 10, 8),
      items: const [],
    );

    expect(
      buildReceiptText(record, storeName: 'Warung'),
      contains('Jatuh tempo: 8 Okt 2026'),
    );
  });

  group('layar konfirmasi', () {
    Future<List<ConfirmedDraft>> pump(
      WidgetTester tester,
      TransactionDraft draft,
    ) async {
      final saved = <ConfirmedDraft>[];
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConfirmationSheet(
              draft: draft,
              onConfirm: (c) async => saved.add(c),
              pickContact: (kind) async => (id: 'sari', name: 'Bu Sari'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return saved;
    }

    TransactionDraft sale({bool onCredit = false}) => TransactionDraft(
      direction: const DraftField<TxDirection>.entered(TxDirection.masuk),
      items: const [
        DraftItem(
          name: DraftField<String>.entered('nasi'),
          qty: DraftField<int>.entered(1),
          unitPrice: DraftField<int>.entered(20000),
        ),
      ],
      occurredAt: DateTime(2026, 10, 12, 10),
      source: TxSource.manual,
      onCredit: onCredit,
      contactId: onCredit ? 'sari' : null,
    );

    testWidgets('transaksi tunai tidak menampilkan jatuh tempo', (
      tester,
    ) async {
      await pump(tester, sale());
      expect(find.text('Jatuh tempo (opsional)'), findsNothing);
    });

    testWidgets('kasbon menampilkan pilihan jatuh tempo', (tester) async {
      await pump(tester, sale(onCredit: true));
      expect(find.text('Jatuh tempo (opsional)'), findsOneWidget);
    });

    testWidgets('memilih "1 minggu" menyimpan jatuh tempo 7 hari', (
      tester,
    ) async {
      final saved = await pump(tester, sale(onCredit: true));

      await tester.tap(find.text('1 minggu'));
      await tester.pumpAndSettle();
      expect(find.text('Bayar paling lambat 19 Okt 2026'), findsOneWidget);

      await tester.tap(find.byWidgetPredicate((w) => w is FilledButton));
      await tester.pumpAndSettle();

      expect(saved.single.draft.dueAt, DateTime(2026, 10, 19));
      expect(saved.single.editedFields, contains('dueAt'));
    });

    testWidgets('"Tanpa" menghapus jatuh tempo dari suara', (tester) async {
      final saved = await pump(
        tester,
        sale(onCredit: true).copyWith(dueAt: DateTime(2026, 10, 13)),
      );

      await tester.tap(find.text('Tanpa'));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) => w is FilledButton));
      await tester.pumpAndSettle();

      expect(saved.single.draft.dueAt, isNull);
    });
  });
}
