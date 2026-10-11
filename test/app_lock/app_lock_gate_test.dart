/// Gerbang kunci: layar kunci menutupi isi aplikasi, dan kunci aktif lagi
/// setelah aplikasi ditinggalkan cukup lama.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/features/app_lock/app_lock_controller.dart';
import 'package:smart_toko/features/app_lock/ui/app_lock_gate.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late DateTime now;
  late ProviderContainer container;

  Future<void> settle(WidgetTester tester) async {
    // sqflite dan PBKDF2 berjalan di luar jam palsu widget test.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> launch(WidgetTester tester, {String? pin}) async {
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        appLockClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await container.read(appLockControllerProvider.future);
      if (pin != null) {
        await container.read(appLockControllerProvider.notifier).enable(pin);
        // Seperti aplikasi dibuka ulang: terkunci dari awal.
        container.invalidate(appLockControllerProvider);
        await container.read(appLockControllerProvider.future);
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AppLockGate(child: Scaffold(body: Text('ISI RAHASIA'))),
        ),
      ),
    );
    await settle(tester);
  }

  /// Menunggu sampai [done] benar. Hashing PIN berjalan di luar jam palsu
  /// dan lamanya bergantung beban mesin, jadi tidak bisa dengan tunggu tetap.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'kondisi tidak tercapai tepat waktu');
  }

  /// Memasukkan [pin] lalu menunggu pemeriksaannya selesai (kolom dikosongkan
  /// bila PIN salah, layar kunci hilang bila benar).
  Future<void> enterPin(WidgetTester tester, String pin) async {
    await tester.enterText(find.byType(TextField), pin);
    await tester.pump();
    await tester.tap(find.text('Buka'));
    await pumpUntil(tester, () {
      if (find.text('SmartToko terkunci').evaluate().isEmpty) return true;
      return tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text
          .isEmpty;
    });
  }

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    now = DateTime(2026, 10, 12, 9);
  });

  tearDown(() async => database.close());

  testWidgets('tanpa PIN, isi aplikasi langsung terbuka', (tester) async {
    await launch(tester);

    expect(find.text('ISI RAHASIA'), findsOneWidget);
    expect(find.text('SmartToko terkunci'), findsNothing);
  });

  testWidgets('dengan PIN, layar kunci tampil saat aplikasi dibuka', (
    tester,
  ) async {
    await launch(tester, pin: '2580');

    expect(find.text('SmartToko terkunci'), findsOneWidget);
  });

  testWidgets('PIN salah menampilkan pesan dan tetap terkunci', (tester) async {
    await launch(tester, pin: '2580');

    await enterPin(tester, '1111');

    expect(find.text('PIN salah.'), findsOneWidget);
    expect(find.text('SmartToko terkunci'), findsOneWidget);
  });

  testWidgets('PIN benar membuka kunci', (tester) async {
    await launch(tester, pin: '2580');

    await enterPin(tester, '2580');

    expect(find.text('SmartToko terkunci'), findsNothing);
    expect(find.text('ISI RAHASIA'), findsOneWidget);
  });

  testWidgets('ditinggalkan sebentar: tidak terkunci lagi', (tester) async {
    await launch(tester, pin: '2580');
    await enterPin(tester, '2580');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(find.text('SmartToko terkunci'), findsNothing);
  });

  testWidgets('ditinggalkan lebih dari masa tenggang: terkunci lagi', (
    tester,
  ) async {
    await launch(tester, pin: '2580');
    await enterPin(tester, '2580');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(lockGracePeriod + const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(find.text('SmartToko terkunci'), findsOneWidget);
  });

  testWidgets('isi aplikasi tertutup di pratinjau saat di latar', (
    tester,
  ) async {
    await launch(tester, pin: '2580');
    await enterPin(tester, '2580');
    expect(find.text('ISI RAHASIA').hitTestable(), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.text('ISI RAHASIA').hitTestable(), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.text('ISI RAHASIA').hitTestable(), findsOneWidget);
  });

  testWidgets('isi aplikasi tertutup selama status kunci belum terbaca', (
    tester,
  ) async {
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        appLockClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AppLockGate(child: Scaffold(body: Text('ISI RAHASIA'))),
        ),
      ),
    );

    // Frame pertama: basis data belum menjawab.
    expect(find.text('ISI RAHASIA').hitTestable(), findsNothing);

    await settle(tester);
    expect(find.text('ISI RAHASIA').hitTestable(), findsOneWidget);
  });
}
