/// Buka kunci dengan sidik jari/wajah.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/features/app_lock/app_lock_controller.dart';
import 'package:smart_toko/features/app_lock/biometric_auth.dart';
import 'package:smart_toko/features/app_lock/ui/app_lock_gate.dart';

class FakeBiometric implements BiometricAuth {
  bool available = true;
  bool succeed = true;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeed;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late FakeBiometric sensor;
  late DateTime now;

  ProviderContainer launch() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        biometricAuthProvider.overrideWithValue(sensor),
        appLockClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<AppLockController> ready(ProviderContainer c) async {
    await c.read(appLockControllerProvider.future);
    return c.read(appLockControllerProvider.notifier);
  }

  AppLockState lockState(ProviderContainer c) =>
      c.read(appLockControllerProvider).requireValue;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('smarttoko_bio');
    addTearDown(() => dir.delete(recursive: true));
    database = AppDatabase();
    await database.open(overridePath: '${dir.path}/app.db');
    sensor = FakeBiometric();
    now = DateTime(2026, 10, 12, 9);
  });

  tearDown(() async => database.close());

  group('pengaturan', () {
    test('butuh PIN terpasang lebih dulu', () async {
      final c = launch();

      expect(await (await ready(c)).setBiometric(true), isFalse);
      expect(sensor.prompts, 0);
    });

    test(
      'menyalakan meminta satu pemindaian dan bertahan setelah restart',
      () async {
        final c = launch();
        final lock = await ready(c);
        await lock.enable('2580');

        expect(await lock.setBiometric(true), isTrue);
        expect(sensor.prompts, 1);

        final reopened = launch();
        await ready(reopened);
        expect(lockState(reopened).biometric, isTrue);
      },
    );

    test('pemindaian gagal: tidak dinyalakan', () async {
      final c = launch();
      final lock = await ready(c);
      await lock.enable('2580');
      sensor.succeed = false;

      expect(await lock.setBiometric(true), isFalse);
      expect(lockState(c).biometric, isFalse);
    });

    test('sensor tidak tersedia: tidak dinyalakan', () async {
      final c = launch();
      final lock = await ready(c);
      await lock.enable('2580');
      sensor.available = false;

      expect(await lock.setBiometric(true), isFalse);
    });

    test(
      'mengubah PIN mempertahankan biometrik; keluar akun menghapusnya',
      () async {
        final c = launch();
        final lock = await ready(c);
        await lock.enable('2580');
        await lock.setBiometric(true);

        await lock.changePin('2580', '1357');
        expect(lockState(c).biometric, isTrue);

        await lock.clear();
        final reopened = launch();
        await ready(reopened);
        expect(lockState(reopened).biometric, isFalse);
      },
    );
  });

  group('membuka kunci', () {
    Future<ProviderContainer> lockedWithBiometric() async {
      final setup = launch();
      final lock = await ready(setup);
      await lock.enable('2580');
      await lock.setBiometric(true);
      final c = launch();
      await ready(c);
      return c;
    }

    test('berhasil membuka', () async {
      final c = await lockedWithBiometric();
      expect(lockState(c).locked, isTrue);

      expect(
        await c.read(appLockControllerProvider.notifier).unlockWithBiometric(),
        isTrue,
      );
      expect(lockState(c).locked, isFalse);
    });

    test('gagal: tetap terkunci', () async {
      final c = await lockedWithBiometric();
      sensor.succeed = false;

      expect(
        await c.read(appLockControllerProvider.notifier).unlockWithBiometric(),
        isFalse,
      );
      expect(lockState(c).locked, isTrue);
    });

    test('berhasil juga mencabut blokir PIN salah', () async {
      final c = await lockedWithBiometric();
      final lock = c.read(appLockControllerProvider.notifier);
      for (var i = 0; i < attemptsBeforeBlock; i++) {
        await lock.unlock('0000');
      }
      expect(lockState(c).isBlocked(now), isTrue);

      await lock.unlockWithBiometric();
      lock.lock();

      expect(await lock.unlock('2580'), UnlockResult.success);
    });

    test('tidak dipakai bila belum dinyalakan', () async {
      final setup = launch();
      await (await ready(setup)).enable('2580');
      final c = launch();
      await ready(c);

      expect(
        await c.read(appLockControllerProvider.notifier).unlockWithBiometric(),
        isFalse,
      );
      expect(sensor.prompts, 0);
    });
  });

  group('layar kunci', () {
    Future<void> pumpLocked(
      WidgetTester tester, {
      required bool biometric,
      bool sensorFails = false,
    }) async {
      late ProviderContainer c;
      await tester.runAsync(() async {
        final setup = launch();
        final lock = await ready(setup);
        await lock.enable('2580');
        if (biometric) await lock.setBiometric(true);
        sensor.prompts = 0;
        sensor.succeed = !sensorFails;
        c = launch();
        await ready(c);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            home: AppLockGate(child: Scaffold(body: Text('ISI'))),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
    }

    testWidgets('menawarkan sidik jari otomatis dan membuka bila berhasil', (
      tester,
    ) async {
      await pumpLocked(tester, biometric: true);

      expect(sensor.prompts, 1);
      expect(find.text('SmartToko terkunci'), findsNothing);
    });

    testWidgets('dibatalkan: tombol tetap ada dan PIN masih bisa', (
      tester,
    ) async {
      await pumpLocked(tester, biometric: true, sensorFails: true);

      expect(sensor.prompts, 1, reason: 'tidak memaksa dialog berulang');
      expect(find.text('SmartToko terkunci'), findsOneWidget);
      expect(find.text('Pakai sidik jari / wajah'), findsOneWidget);
    });

    testWidgets('tanpa biometrik: tidak ada tombol dan tidak ada dialog', (
      tester,
    ) async {
      await pumpLocked(tester, biometric: false);

      expect(sensor.prompts, 0);
      expect(find.text('Pakai sidik jari / wajah'), findsNothing);
    });
  });
}
