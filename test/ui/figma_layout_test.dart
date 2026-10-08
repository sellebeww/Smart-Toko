import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/app/main_shell.dart';
import 'package:smart_toko/app/theme.dart';
import 'package:smart_toko/core/db/dao/product_dao.dart';
import 'package:smart_toko/core/transaction_kind.dart';
import 'package:smart_toko/features/auth/ui/login_screen.dart';
import 'package:smart_toko/features/backup/backup_providers.dart';
import 'package:smart_toko/features/catalog/catalog_providers.dart';
import 'package:smart_toko/features/catalog/ui/catalog_screen.dart';
import 'package:smart_toko/features/contacts/contacts_providers.dart';
import 'package:smart_toko/features/onboarding/ui/onboarding_screen.dart';
import 'package:smart_toko/features/reports/data/report_repository.dart';
import 'package:smart_toko/features/reports/domain/insights.dart';
import 'package:smart_toko/features/reports/recording_progress.dart';
import 'package:smart_toko/features/reports/reports_providers.dart';
import 'package:smart_toko/features/reports/ui/report_screen.dart';
import 'package:smart_toko/features/stores/domain/store_profile.dart';
import 'package:smart_toko/features/stores/stores_providers.dart';
import 'package:smart_toko/features/transactions/domain/transaction_draft.dart';
import 'package:smart_toko/features/transactions/domain/transaction_record.dart';
import 'package:smart_toko/features/transactions/transactions_providers.dart';
import 'package:smart_toko/features/transactions/ui/home_screen.dart';
import 'package:smart_toko/features/transactions/ui/text_entry_sheet.dart';
import 'package:smart_toko/features/voice_capture/capture_controller.dart';
import 'package:smart_toko/features/voice_parser/llm/llm_parser.dart';
import 'package:smart_toko/features/voice_parser/logging/parse_failure_logger.dart';
import 'package:smart_toko/features/voice_parser/parser_pipeline.dart';

class IdleCapture extends CaptureController {
  @override
  CaptureState build() => const CaptureIdle();
  @override
  Future<void> cancel() async {}
}

final now = DateTime.now();
final sampleStock = [
  ProductWithStock(
    ProductRecord(
      id: 'beras',
      storeId: 'store',
      kind: ProductKind.bahan,
      name: 'Beras',
      archived: false,
      createdAt: now,
      updatedAt: now,
      unit: 'kg',
      lowStockThreshold: 5,
    ),
    3,
  ),
  ProductWithStock(
    ProductRecord(
      id: 'ayam',
      storeId: 'store',
      kind: ProductKind.bahan,
      name: 'Ayam',
      archived: false,
      createdAt: now,
      updatedAt: now,
      unit: 'kg',
      lowStockThreshold: 3,
    ),
    6,
  ),
];
ReportData report(ReportPeriod period) => ReportData(
  period: period,
  current: const CategoryTotals(
    amounts: {
      TxCategory.penjualan: 1450000,
      TxCategory.pembelian: 630000,
      TxCategory.pengeluaran: 60000,
    },
    count: 8,
  ),
  previous: const CategoryTotals(
    amounts: {TxCategory.penjualan: 1200000, TxCategory.pembelian: 680000},
    count: 6,
  ),
  topMenu: const [
    ItemAggregate(name: 'Ayam Geprek', qty: 86, amount: 1892000, unit: 'porsi'),
  ],
  topSpending: const [],
  lowStock: sampleStock.take(1).toList(),
  daily: const {},
  from: DateTime(now.year, now.month, now.day),
  to: DateTime(now.year, now.month, now.day + 1),
  insights: const ['Ayam Geprek menjadi menu paling laku hari ini.'],
);

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  double width = 412,
  double height = 915,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        captureControllerProvider.overrideWith(IdleCapture.new),
        activeStoreProvider.overrideWithValue(
          AsyncData(
            StoreProfile(
              id: 'store',
              ownerUid: 'owner',
              name: 'Warteg Bu Sari',
              category: StoreCategory.warteg,
              address: '',
              createdAt: now,
            ),
          ),
        ),
        todayTransactionsProvider.overrideWith(
          (ref) async => [
            TxRecord(
              id: 'tx',
              storeId: 'store',
              direction: TxDirection.keluar,
              category: TxCategory.pembelian,
              occurredAt: now,
              source: TxSource.manual,
              totalAmount: 280000,
              createdAt: now,
              updatedAt: now,
              items: const [
                TxItemRecord(
                  id: 'item',
                  transactionId: 'tx',
                  name: 'Telur',
                  qty: 10,
                  unitPrice: 28000,
                  lineTotal: 280000,
                  unit: 'kg',
                ),
              ],
            ),
          ],
        ),
        reportProvider.overrideWith((ref, period) async => report(period)),
        dailyMotivationProvider.overrideWith(
          (ref) async =>
              'Mantap! Penjualan hari ini sudah Rp1.450.000. Terus catat, ya!',
        ),
        contactNamesProvider.overrideWith((ref) async => {}),
        restoreOfferProvider.overrideWith((ref) async => null),
        productsProvider.overrideWith(
          (ref, kind) async => kind == ProductKind.bahan ? sampleStock : [],
        ),
        recordingDaysProvider.overrideWith(
          (ref) async => {
            for (var i = 0; i < 7; i++)
              DateTime(now.year, now.month, now.day - i),
          },
        ),
        parserPipelineProvider.overrideWithValue(
          ParserPipeline(
            llmParser: const DisabledLlmParser(),
            failureLogger: const NoopParseFailureLogger(),
            isOnline: () async => false,
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SmartTokoTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(key: const ValueKey('preview'), child: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> preview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('WRITE_UI_PREVIEWS')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('preview')),
  );
  await tester.runAsync(() async {
    final rendered = await boundary.toImage(pixelRatio: 2);
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/ui-previews');
    await dir.create(recursive: true);
    await File('${dir.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    rendered.dispose();
  });
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final scale in [1.0, 1.8]) {
    testWidgets('beranda bisa digulir di 320px dengan skala teks $scale', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const HomeScreen(),
        width: 320,
        height: 640,
        scale: scale,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('form masuk, laporan, dan stok tetap terbaca dengan teks besar', (
    tester,
  ) async {
    for (final screen in <Widget>[
      const LoginScreen(),
      const ReportScreen(),
      const CatalogScreen(initialKind: ProductKind.bahan),
    ]) {
      await pumpScreen(tester, screen, width: 320, height: 640, scale: 1.8);
      expect(
        tester.takeException(),
        isNull,
        reason: screen.runtimeType.toString(),
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('onboarding layar kecil tetap bisa mencapai tombol Mulai', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      OnboardingScreen(onDone: () {}),
      width: 320,
      height: 568,
      scale: 1.8,
    );
    await tester.ensureVisible(find.text('Mulai'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ketik alami mengembalikan draf manual tanpa menyimpan', (
    tester,
  ) async {
    TransactionDraft? draft;
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                draft = await showTextEntry(context);
              },
              child: const Text('Buka'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Beli ayam 5 kg Rp200.000');
    await tester.tap(find.text('Periksa transaksi'));
    await tester.pumpAndSettle();
    expect(draft, isNotNull);
    expect(draft!.source, TxSource.manual);
    expect(draft!.direction.value, TxDirection.keluar);
    expect(draft!.items.single.qty.value, 5);
    expect(draft!.total, 200000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pratinjau layar utama, masuk, laporan, stok', (tester) async {
    for (final entry in <String, Widget>{
      'beranda': const HomeScreen(),
      'masuk': const LoginScreen(),
      'laporan': const ReportScreen(),
      'stok': const CatalogScreen(initialKind: ProductKind.bahan),
    }.entries) {
      final selected = {'beranda': 0, 'laporan': 3, 'stok': 2}[entry.key];
      final screen = selected == null
          ? entry.value
          : Scaffold(
              body: entry.value,
              bottomNavigationBar: SmartTokoNavigationBar(
                selectedIndex: selected,
                onSelected: (_) {},
              ),
            );
      await pumpScreen(tester, screen, height: 1120);
      expect(tester.takeException(), isNull, reason: entry.key);
      await preview(tester, entry.key);
      await tester.pumpWidget(const SizedBox());
    }
  });

  test(
    'streak menghitung hari berurutan dan memberi kesempatan mencatat hari ini',
    () {
      final days = {
        DateTime(2026, 9, 30),
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
      };
      expect(recordingStreak(days, DateTime(2026, 10, 2, 18)), 3);
      expect(recordingStreak(days, DateTime(2026, 10, 3, 9)), 3);
      expect(recordingStreak(days, DateTime(2026, 10, 4)), 0);
    },
  );
}
