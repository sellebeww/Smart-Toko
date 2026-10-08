/// Keadaan setelan privasi.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/dao/settings_dao.dart';

class SettingsState {
  final bool backupEnabled;
  final bool llmEnabled;
  final bool errorReportsEnabled;

  const SettingsState({
    required this.backupEnabled,
    required this.llmEnabled,
    required this.errorReportsEnabled,
  });
}

class SettingsController extends AsyncNotifier<SettingsState> {
  @override
  Future<SettingsState> build() async => _load();

  Future<SettingsState> _load() async {
    final settings = ref.read(settingsDaoProvider);
    return SettingsState(
      backupEnabled: await settings.backupEnabled(),
      llmEnabled: await settings.llmEnabled(),
      errorReportsEnabled: await settings.errorReportsEnabled(),
    );
  }

  Future<void> _update(Future<void> Function() action) async {
    await action();
    state = AsyncData(await _load());
  }

  Future<void> setBackupEnabled({required bool value}) => _update(
    () => ref
        .read(settingsDaoProvider)
        .setFlag(SettingsKeys.backupEnabled, value: value),
  );

  Future<void> setLlmEnabled({required bool value}) => _update(
    () => ref
        .read(settingsDaoProvider)
        .setFlag(SettingsKeys.llmEnabled, value: value),
  );

  Future<void> setErrorReportsEnabled({required bool value}) => _update(
    () => ref
        .read(settingsDaoProvider)
        .setFlag(SettingsKeys.errorReportsEnabled, value: value),
  );
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsState>(
      SettingsController.new,
    );
