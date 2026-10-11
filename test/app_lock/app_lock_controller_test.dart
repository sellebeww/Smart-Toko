/// Kunci PIN: pasang, buka, batas percobaan, dan bertahan setelah restart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/features/app_lock/app_lock_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late DateTime now;

  /// Satu "sesi aplikasi". Membuat container baru = membuka ulang aplikasi
  /// dengan basis data yang sama.
  Future<ProviderContainer> launch() async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        appLockClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appLockControllerProvider.future);
    return container;
  }

  AppLockController controller(ProviderContainer c) =>
      c.read(appLockControllerProvider.notifier);
  AppLockState lockState(ProviderContainer c) =>
      c.read(appLockControllerProvider).requireValue;

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    now = DateTime(2026, 10, 12, 9);
  });

  tearDown(() async => database.close());

  test('awalnya tidak aktif dan tidak terkunci', () async {
    final c = await launch();

    expect(lockState(c).enabled, isFalse);
    expect(lockState(c).locked, isFalse);
  });

  test('memasang PIN: aktif, tidak langsung terkunci', () async {
    final c = await launch();

    await controller(c).enable('2580');

    expect(lockState(c).enabled, isTrue);
    expect(lockState(c).locked, isFalse);
  });

  test('PIN tidak valid ditolak', () async {
    final c = await launch();

    for (final pin in ['', '12', '1234567', 'abcd']) {
      await expectLater(controller(c).enable(pin), throwsArgumentError);
    }
    expect(lockState(c).enabled, isFalse);
  });

  test('PIN tidak tersimpan sebagai teks asli', () async {
    final c = await launch();
    await controller(c).enable('2580');

    final rows = await database.db.query('app_settings');
    for (final row in rows) {
      expect(row['value'], isNot(contains('2580')));
      expect(row['key'], isNot(contains('2580')));
    }
  });

  test('aplikasi dibuka ulang: terkunci sampai PIN dimasukkan', () async {
    await controller(await launch()).enable('2580');

    final c = await launch();

    expect(lockState(c).enabled, isTrue);
    expect(lockState(c).locked, isTrue);
  });

  test('PIN benar membuka, PIN salah tidak', () async {
    await controller(await launch()).enable('2580');
    final c = await launch();

    expect(await controller(c).unlock('1111'), UnlockResult.wrong);
    expect(lockState(c).locked, isTrue);

    expect(await controller(c).unlock('2580'), UnlockResult.success);
    expect(lockState(c).locked, isFalse);
  });

  test(
    'lima percobaan salah memblokir sementara, bahkan untuk PIN benar',
    () async {
      await controller(await launch()).enable('2580');
      final c = await launch();

      for (var i = 0; i < attemptsBeforeBlock - 1; i++) {
        expect(await controller(c).unlock('0001'), UnlockResult.wrong);
      }
      expect(await controller(c).unlock('0001'), UnlockResult.blocked);

      expect(await controller(c).unlock('2580'), UnlockResult.blocked);
      expect(lockState(c).locked, isTrue);
      expect(lockState(c).isBlocked(now), isTrue);

      now = now.add(baseBlock + const Duration(seconds: 1));
      expect(await controller(c).unlock('2580'), UnlockResult.success);
    },
  );

  test('blokir bertahan walau aplikasi ditutup dan dibuka lagi', () async {
    await controller(await launch()).enable('2580');
    var c = await launch();
    for (var i = 0; i < attemptsBeforeBlock; i++) {
      await controller(c).unlock('0001');
    }

    c = await launch();

    expect(lockState(c).isBlocked(now), isTrue);
    expect(await controller(c).unlock('2580'), UnlockResult.blocked);
  });

  test('blokir berikutnya lebih lama', () async {
    await controller(await launch()).enable('2580');
    final c = await launch();
    for (var i = 0; i < attemptsBeforeBlock; i++) {
      await controller(c).unlock('0001');
    }
    final first = lockState(c).blockedUntil!.difference(now);

    now = now.add(first + const Duration(seconds: 1));
    for (var i = 0; i < attemptsBeforeBlock; i++) {
      await controller(c).unlock('0001');
    }
    final second = lockState(c).blockedUntil!.difference(now);

    expect(first, baseBlock);
    expect(second, baseBlock * 2);
  });

  test('berhasil membuka mengulang hitungan percobaan salah', () async {
    await controller(await launch()).enable('2580');
    final c = await launch();
    for (var i = 0; i < attemptsBeforeBlock - 1; i++) {
      await controller(c).unlock('0001');
    }
    await controller(c).unlock('2580');
    controller(c).lock();

    for (var i = 0; i < attemptsBeforeBlock - 1; i++) {
      expect(await controller(c).unlock('0001'), UnlockResult.wrong);
    }
    expect(lockState(c).isBlocked(now), isFalse);
  });

  test('lock() mengunci lagi hanya bila kunci aktif', () async {
    final c = await launch();
    controller(c).lock();
    expect(lockState(c).locked, isFalse, reason: 'kunci belum dipasang');

    await controller(c).enable('2580');
    controller(c).lock();
    expect(lockState(c).locked, isTrue);
  });

  test('mematikan kunci butuh PIN yang benar', () async {
    final c = await launch();
    await controller(c).enable('2580');

    expect(await controller(c).disable('1111'), UnlockResult.wrong);
    expect(lockState(c).enabled, isTrue);

    expect(await controller(c).disable('2580'), UnlockResult.success);
    expect(lockState(c).enabled, isFalse);
    expect(lockState(await launch()).enabled, isFalse);
  });

  test('mengubah PIN: yang lama tidak berlaku lagi', () async {
    final c = await launch();
    await controller(c).enable('2580');

    expect(await controller(c).changePin('1111', '1357'), UnlockResult.wrong);
    expect(await controller(c).changePin('2580', '1357'), UnlockResult.success);

    final reopened = await launch();
    expect(await controller(reopened).unlock('2580'), UnlockResult.wrong);
    expect(await controller(reopened).unlock('1357'), UnlockResult.success);
  });

  test('clear() (lupa PIN, keluar akun) menghapus kunci tanpa PIN', () async {
    final c = await launch();
    await controller(c).enable('2580');

    await controller(c).clear();

    expect(lockState(c).enabled, isFalse);
    expect(lockState(await launch()).enabled, isFalse);
  });
}
