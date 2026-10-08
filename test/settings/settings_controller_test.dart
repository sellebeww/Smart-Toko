/// Tes sakelar privasi: semuanya mati saat baru, dan pilihan tersimpan.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/core/db/app_database.dart';
import 'package:smart_toko/features/settings/settings_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase();
    await database.open(overridePath: inMemoryDatabasePath);
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('semua sakelar pengiriman data mati pada pemakaian pertama', () async {
    final state = await container.read(settingsControllerProvider.future);

    expect(state.backupEnabled, isFalse);
    expect(state.llmEnabled, isFalse);
    expect(state.errorReportsEnabled, isFalse);
  });

  test('menyalakan satu sakelar tidak menyalakan yang lain', () async {
    final controller = container.read(settingsControllerProvider.notifier);
    await container.read(settingsControllerProvider.future);

    await controller.setErrorReportsEnabled(value: true);

    final state = container.read(settingsControllerProvider).requireValue;
    expect(state.errorReportsEnabled, isTrue);
    expect(state.backupEnabled, isFalse);
    expect(state.llmEnabled, isFalse);
  });

  test('pilihan tersimpan di basis data dan bisa dimatikan lagi', () async {
    final controller = container.read(settingsControllerProvider.notifier);
    await container.read(settingsControllerProvider.future);

    await controller.setBackupEnabled(value: true);
    expect(await container.read(settingsDaoProvider).backupEnabled(), isTrue);

    await controller.setBackupEnabled(value: false);
    expect(await container.read(settingsDaoProvider).backupEnabled(), isFalse);
  });
}
