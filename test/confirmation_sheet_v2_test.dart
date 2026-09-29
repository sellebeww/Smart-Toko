/// Layar konfirmasi: kategori, satuan, harga per-satuan vs total, dan kontak.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_toko/core/db/dao/contact_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';
import 'package:smart_toko/features/transactions/ui/confirmation_sheet.dart';
import 'package:smart_toko/features/voice_parser/rules/rule_parser.dart';

Future<void> pumpSheet(
  WidgetTester tester,
  TransactionDraft draft, {
  void Function(ConfirmedDraft)? onConfirm,
  Future<PickedContact?> Function(ContactKind)? pickContact,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConfirmationSheet(
          draft: draft,
          onConfirm: (confirmed) async => onConfirm?.call(confirmed),
          pickContact: pickContact,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TransactionDraft fromVoice(String transcript) =>
    TransactionDraft.fromParseResult(const RuleBasedParser().parse(transcript));

void main() {
  testWidgets(
    'contoh pitch deck tampil sebagai total Rp200.000 yang perlu dicek',
    (tester) async {
      await pumpSheet(tester, fromVoice('beli ayam 5 kg dua ratus ribu'));

      expect(find.text('Harga total'), findsOneWidget);
      expect(find.text('Cek: harga di atas untuk…'), findsOneWidget);
      expect(find.textContaining('Total Rp200.000'), findsOneWidget);
      expect(find.textContaining('Rp40.000/kg'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Pembelian bahan'),
            )
            .selected,
        isTrue,
      );
    },
  );

  testWidgets('mengganti ke "Per satuan" menghitung ulang total', (
    tester,
  ) async {
    await pumpSheet(tester, fromVoice('beli ayam 5 kg dua ratus ribu'));

    await tester.tap(find.text('Per satuan'));
    await tester.pumpAndSettle();

    expect(find.text('Harga satuan'), findsOneWidget);
    expect(find.textContaining('subtotal Rp1.000.000'), findsOneWidget);
  });

  testWidgets('saklar per satuan/total tidak muncul untuk satu barang', (
    tester,
  ) async {
    await pumpSheet(tester, fromVoice('bayar listrik seratus ribu'));

    expect(find.byType(SegmentedButton<PriceMode>), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, 'Pengeluaran operasional'),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('kategori baru muncul setelah arah dipilih, dengan tebakan', (
    tester,
  ) async {
    await pumpSheet(tester, TransactionDraft.manual());
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Penjualan'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Pemasukan lain'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Penjualan'))
          .selected,
      isTrue,
    );
  });

  testWidgets('kategori dan kontak ikut tersimpan', (tester) async {
    ConfirmedDraft? captured;
    await pumpSheet(
      tester,
      fromVoice('jual nasi ayam 2 porsi 30 ribu'),
      onConfirm: (c) => captured = c,
      pickContact: (kind) async => (id: 'c1', name: 'Bu Ani'),
    );

    await tester.tap(find.text('Pelanggan (opsional)'));
    await tester.pumpAndSettle();
    expect(find.text('Pelanggan: Bu Ani'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Pemasukan lain'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Penjualan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(captured!.draft.effectiveCategory, TxCategory.penjualan);
    expect(captured!.draft.contactId, 'c1');
    expect(captured!.draft.items.single.unit, 'porsi');
  });

  testWidgets('kontak dilepas bila kategori akhirnya tidak memakai kontak', (
    tester,
  ) async {
    ConfirmedDraft? captured;
    await pumpSheet(
      tester,
      fromVoice('jual nasi ayam 2 porsi 30 ribu'),
      onConfirm: (c) => captured = c,
      pickContact: (kind) async => (id: 'c1', name: 'Bu Ani'),
    );

    await tester.tap(find.text('Pelanggan (opsional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pemasukan lain'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(captured!.draft.contactId, isNull);
  });
}
