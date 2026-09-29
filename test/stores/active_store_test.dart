import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/core/db/dao/settings_dao.dart';
import 'package:smart_toko/features/auth/auth_providers.dart';
import 'package:smart_toko/features/auth/domain/app_user.dart';
import 'package:smart_toko/features/stores/stores_providers.dart';

class UnusedDatabase extends Fake implements DatabaseExecutor {}

class MemorySettings extends SettingsDao {
  final values = <String, String>{};
  Completer<void>? pending;
  MemorySettings() : super(UnusedDatabase());

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    await pending?.future;
    values[key] = value;
  }
}

void main() {
  late StreamController<AppUser?> auth;
  late MemorySettings settings;
  late ProviderContainer container;

  setUp(() async {
    auth = StreamController<AppUser?>();
    settings = MemorySettings();
    container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => auth.stream),
        settingsDaoProvider.overrideWithValue(settings),
      ],
    );
    container.listen(activeStoreIdProvider, (_, _) {});
    auth.add(const AppUser(uid: 'owner-a', email: 'a@example.com'));
    await container.read(authStateChangesProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await auth.close();
  });

  Future<void> switchAccount(String uid) async {
    auth.add(AppUser(uid: uid, email: '$uid@example.com'));
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }

  test('selection is stored separately for each account', () async {
    await container.read(activeStoreIdProvider.notifier).set('store-a');
    await switchAccount('owner-b');
    expect(container.read(activeStoreIdProvider), isNull);
    await container.read(activeStoreIdProvider.notifier).set('store-b');
    expect(await container.read(savedActiveStoreIdProvider.future), 'store-b');
    await switchAccount('owner-a');
    expect(await container.read(savedActiveStoreIdProvider.future), 'store-a');
  });

  test('in-flight selection cannot become active in another account', () async {
    settings.pending = Completer<void>();
    final selection = container
        .read(activeStoreIdProvider.notifier)
        .set('store-a');
    await switchAccount('owner-b');
    settings.pending!.complete();
    await selection;
    expect(container.read(activeStoreIdProvider), isNull);
    expect(settings.values['active_store_id:owner-a'], 'store-a');
    expect(settings.values['active_store_id:owner-b'], isNull);
  });
}
