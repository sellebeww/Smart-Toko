/// Kunci aplikasi dengan PIN.
///
/// Ini mengunci TAMPILAN aplikasi bagi orang yang memegang HP yang sedang
/// menyala (mis. karyawan atau anak). Data di HP tidak dienkripsi oleh kunci
/// ini. Lupa PIN diselesaikan dengan keluar dari akun: tanpa kata sandi
/// akun, data toko tidak terbuka lagi.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/dao/settings_dao.dart';
import 'pin_hasher.dart';

/// Percobaan salah beruntun sebelum pengguna harus menunggu.
const int attemptsBeforeBlock = 5;

/// Tunggu awal; berlipat tiap [attemptsBeforeBlock] kegagalan berikutnya.
const Duration baseBlock = Duration(seconds: 30);
const Duration maxBlock = Duration(minutes: 15);

enum UnlockResult { success, wrong, blocked }

class AppLockState {
  final bool enabled;
  final bool locked;
  final DateTime? blockedUntil;

  const AppLockState({
    required this.enabled,
    required this.locked,
    this.blockedUntil,
  });

  bool isBlocked(DateTime now) =>
      blockedUntil != null && now.isBefore(blockedUntil!);
}

final appLockClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class AppLockController extends AsyncNotifier<AppLockState> {
  SettingsDao get _settings => ref.read(settingsDaoProvider);
  DateTime _now() => ref.read(appLockClockProvider)();

  @override
  Future<AppLockState> build() async {
    final settings = ref.read(settingsDaoProvider);
    final hash = await settings.getString(SettingsKeys.appLockHash);
    final salt = await settings.getString(SettingsKeys.appLockSalt);
    final enabled = hash != null && salt != null;
    return AppLockState(
      enabled: enabled,
      // Terkunci sejak aplikasi dibuka.
      locked: enabled,
      blockedUntil: enabled ? await _readBlockedUntil() : null,
    );
  }

  Future<DateTime?> _readBlockedUntil() async {
    final raw = await _settings.getString(SettingsKeys.appLockBlockedUntil);
    final millis = raw == null ? null : int.tryParse(raw);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<bool> _matches(String pin) async {
    final hash = await _settings.getString(SettingsKeys.appLockHash);
    final salt = await _settings.getString(SettingsKeys.appLockSalt);
    if (hash == null || salt == null) return false;
    return verifyPinAsync(pin, salt: salt, expected: hash);
  }

  /// Memeriksa PIN dengan pembatasan percobaan.
  Future<UnlockResult> _attempt(String pin) async {
    final blockedUntil = await _readBlockedUntil();
    if (blockedUntil != null && _now().isBefore(blockedUntil)) {
      state = AsyncData(_current.copyWithBlocked(blockedUntil));
      return UnlockResult.blocked;
    }
    if (await _matches(pin)) {
      await _settings.remove(SettingsKeys.appLockFailed);
      await _settings.remove(SettingsKeys.appLockBlockedUntil);
      return UnlockResult.success;
    }
    final failed =
        (int.tryParse(
              await _settings.getString(SettingsKeys.appLockFailed) ?? '',
            ) ??
            0) +
        1;
    await _settings.setString(SettingsKeys.appLockFailed, '$failed');
    if (failed % attemptsBeforeBlock == 0) {
      final doublings = failed ~/ attemptsBeforeBlock - 1;
      var wait = baseBlock * (1 << doublings.clamp(0, 10));
      if (wait > maxBlock) wait = maxBlock;
      final until = _now().add(wait);
      await _settings.setString(
        SettingsKeys.appLockBlockedUntil,
        '${until.millisecondsSinceEpoch}',
      );
      state = AsyncData(_current.copyWithBlocked(until));
      return UnlockResult.blocked;
    }
    return UnlockResult.wrong;
  }

  AppLockState get _current =>
      state.value ?? const AppLockState(enabled: false, locked: false);

  Future<UnlockResult> unlock(String pin) async {
    final result = await _attempt(pin);
    if (result == UnlockResult.success) {
      state = AsyncData(const AppLockState(enabled: true, locked: false));
    }
    return result;
  }

  /// Memasang PIN baru. [pin] harus sudah lolos [isValidPin].
  Future<void> enable(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError.value(pin, 'pin', 'tidak valid');
    final salt = newSalt();
    await _settings.setString(SettingsKeys.appLockSalt, salt);
    await _settings.setString(
      SettingsKeys.appLockHash,
      await hashPinAsync(pin, salt),
    );
    await _settings.remove(SettingsKeys.appLockFailed);
    await _settings.remove(SettingsKeys.appLockBlockedUntil);
    state = const AsyncData(AppLockState(enabled: true, locked: false));
  }

  /// Mematikan kunci; PIN saat ini harus benar.
  Future<UnlockResult> disable(String pin) async {
    final result = await _attempt(pin);
    if (result == UnlockResult.success) await clear();
    return result;
  }

  Future<UnlockResult> changePin(String oldPin, String newPin) async {
    final result = await _attempt(oldPin);
    if (result == UnlockResult.success) await enable(newPin);
    return result;
  }

  /// Mengunci sekarang (aplikasi ditinggalkan cukup lama).
  void lock() {
    final current = _current;
    if (current.enabled && !current.locked) {
      state = AsyncData(
        AppLockState(
          enabled: true,
          locked: true,
          blockedUntil: current.blockedUntil,
        ),
      );
    }
  }

  /// Menghapus kunci tanpa PIN. Hanya untuk keluar akun: tanpa kata sandi
  /// akun, data toko tetap tidak terbuka.
  Future<void> clear() async {
    for (final key in [
      SettingsKeys.appLockHash,
      SettingsKeys.appLockSalt,
      SettingsKeys.appLockFailed,
      SettingsKeys.appLockBlockedUntil,
    ]) {
      await _settings.remove(key);
    }
    state = const AsyncData(AppLockState(enabled: false, locked: false));
  }
}

extension on AppLockState {
  AppLockState copyWithBlocked(DateTime until) =>
      AppLockState(enabled: enabled, locked: locked, blockedUntil: until);
}

final appLockControllerProvider =
    AsyncNotifierProvider<AppLockController, AppLockState>(
      AppLockController.new,
    );
