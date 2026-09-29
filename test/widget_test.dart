/// Tes layar konfirmasi.
///
/// Yang dijaga di sini adalah janji inti produk: tidak ada yang bisa disimpan
/// sebelum manusia melengkapi dan menyetujuinya.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_toko/core/confidence.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/transactions/domain/confirmed_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';
import 'package:smart_toko/features/transactions/ui/confirmation_sheet.dart';

Future<void> pumpSheet(
  WidgetTester tester,
  TransactionDraft draft, {
  void Function(ConfirmedDraft)? onConfirm,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConfirmationSheet(
          draft: draft,
          onConfirm: (confirmed) async => onConfirm?.call(confirmed),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TransactionDraft voiceDraft({
  TxDirection? direction,
  ConfidenceBand priceBand = ConfidenceBand.good,
  String? priceSpan,
}) => TransactionDraft(
  direction: direction == null
      ? const DraftField<TxDirection>.empty()
      : DraftField<TxDirection>(value: direction),
  items: [
    DraftItem(
      name: const DraftField<String>(value: 'indomie'),
      qty: const DraftField<int>(value: 2),
      unitPrice: DraftField<int>(
        value: priceBand == ConfidenceBand.poor ? null : 5000,
        band: priceBand,
        rawSpan: priceSpan,
      ),
    ),
  ],
  occurredAt: DateTime(2026, 1, 15, 10),
  source: TxSource.voice,
  transcript: 'jual indomie dua bungkus lima ribu',
);

void main() {
  testWidgets('transkrip asli ditampilkan agar bisa dinilai pengguna', (
    tester,
  ) async {
    await pumpSheet(tester, voiceDraft(direction: TxDirection.masuk));

    expect(
      find.textContaining('jual indomie dua bungkus lima ribu'),
      findsOneWidget,
    );
  });

  testWidgets('tanpa arah transaksi, tombol simpan mati', (tester) async {
    await pumpSheet(tester, voiceDraft());

    expect(find.text('Lengkapi dulu yang disorot'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Lengkapi dulu yang disorot'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('arah transaksi tidak dipilihkan otomatis', (tester) async {
    await pumpSheet(tester, voiceDraft());

    final selector = tester.widget<SegmentedButton<TxDirection>>(
      find.byType(SegmentedButton<TxDirection>),
    );
    expect(selector.selected, isEmpty);
    expect(find.text('Tidak terdengar jelas — pilih sendiri'), findsOneWidget);
  });

  testWidgets('memilih arah mengaktifkan tombol simpan', (tester) async {
    await pumpSheet(tester, voiceDraft());

    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('Simpan'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Simpan'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('field berkeyakinan rendah dikosongkan dan diberi petunjuk', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      voiceDraft(
        direction: TxDirection.masuk,
        priceBand: ConfidenceBand.poor,
        priceSpan: 'lima ribu',
      ),
    );

    expect(
      find.textContaining('Kurang jelas, terdengar: "lima ribu"'),
      findsOneWidget,
    );
    expect(find.text('Lengkapi dulu yang disorot'), findsOneWidget);
  });

  testWidgets('field meragukan disorot tapi tetap bisa disimpan', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      voiceDraft(
        direction: TxDirection.masuk,
        priceBand: ConfidenceBand.check,
        priceSpan: 'lima ribu',
      ),
    );

    expect(find.textContaining('Terdengar: "lima ribu"'), findsOneWidget);
    expect(find.text('Simpan'), findsOneWidget);
  });

  testWidgets(
    'menyimpan memberikan ConfirmedDraft berisi field yang disunting',
    (tester) async {
      ConfirmedDraft? captured;
      await pumpSheet(
        tester,
        voiceDraft(),
        onConfirm: (confirmed) => captured = confirmed,
      );

      await tester.tap(find.text('Keluar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.draft.direction.value, TxDirection.keluar);
      expect(captured!.editedFields, contains('direction'));
    },
  );

  testWidgets('jalur manual memakai layar yang sama persis', (tester) async {
    await pumpSheet(tester, TransactionDraft.manual());

    expect(find.byType(ConfirmationSheet), findsOneWidget);
    expect(find.text('Nama barang'), findsOneWidget);
    expect(find.text('Harga satuan'), findsOneWidget);
    // Tidak ada transkrip pada masukan manual.
    expect(find.byIcon(Icons.hearing), findsNothing);
  });

  testWidgets('jumlah nol ditolak dengan pesan yang jelas', (tester) async {
    await pumpSheet(tester, voiceDraft(direction: TxDirection.masuk));
    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.pumpAndSettle();
    expect(find.text('Minimal 1'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Lengkapi dulu yang disorot'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('gagal simpan mempertahankan isian dan bisa dicoba lagi', (
    tester,
  ) async {
    var attempts = 0;
    await pumpSheet(
      tester,
      voiceDraft(direction: TxDirection.masuk),
      onConfirm: (_) {
        attempts++;
        if (attempts == 1) throw StateError('disk unavailable');
      },
    );
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Transaksi belum tersimpan'), findsOneWidget);
    expect(find.text('indomie'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.textContaining('Transaksi belum tersimpan'), findsNothing);
  });

  group('kalimat bantuan menyesuaikan jalur masukan', () {
    testWidgets('masukan manual tidak menyalahkan pendengaran', (tester) async {
      await pumpSheet(tester, TransactionDraft.manual());

      expect(find.textContaining('terdengar'), findsNothing);
      expect(find.text('Belum diisi'), findsWidgets);
      expect(find.text('Pilih dulu masuk atau keluar'), findsOneWidget);
    });

    testWidgets('masukan suara tetap menjelaskan bahwa audionya kurang jelas', (
      tester,
    ) async {
      await pumpSheet(tester, voiceDraft(priceBand: ConfidenceBand.poor));

      expect(
        find.text('Tidak terdengar jelas — pilih sendiri'),
        findsOneWidget,
      );
      expect(find.text('Belum diisi'), findsNothing);
    });
  });
}
