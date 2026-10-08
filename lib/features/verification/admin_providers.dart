/// Provider untuk peran admin peninjau verifikasi.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../auth/auth_providers.dart';
import 'domain/pending_verification.dart';

/// Apakah akun yang login terdaftar di tabel `admins`. Hanya menentukan
/// tampil-tidaknya menu admin; izin sesungguhnya diperiksa server di setiap
/// fungsi admin. Gagal memeriksa (mis. luring) dianggap bukan admin.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return false;
  try {
    return await ref.watch(storeRepositoryProvider).isCurrentUserAdmin();
  } catch (_) {
    return false;
  }
});

final pendingVerificationsProvider =
    FutureProvider.autoDispose<List<PendingVerification>>(
      (ref) => ref.watch(storeRepositoryProvider).pendingVerifications(),
    );
