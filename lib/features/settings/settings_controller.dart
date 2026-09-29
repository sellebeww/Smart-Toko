/// Keadaan setelan privasi.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/dao/settings_dao.dart';

class SettingsState {
  final bool syncEnabled;
  final bool llmEnabled;
  final bool qrisEnabled;
  final bool hasApiKey;

  const SettingsState({
    required this.syncEnabled,
    required this.llmEnabled,
    required this.qrisEnabled,
    required this.hasApiKey,
  });
}

class SettingsController extends AsyncNotifier<SettingsState> {
  @override
  Future<SettingsState> build() async => _load();

  Future<SettingsState> _load() async {
    final settings = ref.read(settingsDaoProvider);
    final keyStore = ref.read(keyStoreProvider);
    return SettingsState(
      syncEnabled: await settings.syncEnabled(),
      llmEnabled: await settings.llmEnabled(),
      qrisEnabled: await settings.qrisEnabled(),
      hasApiKey: await keyStore.hasLlmApiKey(),
    );
  }

  Future<void> _update(Future<void> Function() action) async {
    await action();
    state = AsyncData(await _load());
  }

  Future<void> setSyncEnabled({required bool value}) => _update(
    () => ref
        .read(settingsDaoProvider)
        .setFlag(SettingsKeys.syncEnabled, value: value),
  );

  Future<void> setLlmEnabled({required bool value}) => _update(
    () => ref
        .read(settingsDaoProvider)
        .setFlag(SettingsKeys.llmEnabled, value: value),
  );

  Future<void> saveApiKey(String key) =>
      _update(() => ref.read(keyStoreProvider).writeLlmApiKey(key.trim()));

  /// Menghapus kunci sekaligus mematikan fiturnya.
  ///
  /// Membiarkan sakelar menyala tanpa kunci akan membuat aplikasi terus
  /// mencoba memanggil API dan gagal diam-diam pada tiap ucapan yang sulit.
  Future<void> clearApiKey() => _update(() async {
    await ref.read(keyStoreProvider).deleteLlmApiKey();
    await ref
        .read(settingsDaoProvider)
        .setFlag(SettingsKeys.llmEnabled, value: false);
  });
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsState>(
      SettingsController.new,
    );
