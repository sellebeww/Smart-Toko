/// Sidik jari/wajah sebagai cara cepat membuka kunci. PIN tetap wajib ada
/// sebagai cadangan (sensor kotor, wajah bermasker, perangkat diganti).
library;

import 'package:local_auth/local_auth.dart';

abstract class BiometricAuth {
  /// Perangkat punya sensor dan pemiliknya sudah mendaftarkan biometrik.
  Future<bool> isAvailable();

  /// True bila berhasil. Batal, gagal, atau sensor terkunci = false.
  Future<bool> authenticate(String reason);
}

class LocalBiometricAuth implements BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Tanpa jatuh ke PIN layar HP: PIN aplikasi sendiri yang jadi
        // cadangan, supaya orang yang tahu PIN HP tidak otomatis masuk.
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
