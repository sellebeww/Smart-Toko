/// Provider status cadangan untuk Pengaturan dan layar utama.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../auth/auth_providers.dart';

/// Kunci setelan: tawaran memulihkan cadangan sudah ditutup untuk toko ini.
String restoreOfferDismissedKey(String storeId) =>
    'restore_offer_dismissed:$storeId';

/// Waktu cadangan terakhir yang berhasil dari HP ini untuk toko aktif.
final backupStatusProvider = FutureProvider.autoDispose<DateTime?>((ref) {
  ref.watch(dataRevisionProvider);
  final storeId = ref.watch(activeStoreIdProvider);
  if (storeId == null) return null;
  return ref.watch(backupServiceProvider).lastBackupAt(storeId);
});

/// Waktu cadangan di server yang layak ditawarkan untuk dipulihkan: hanya
/// bila data toko aktif di HP ini masih kosong (mis. HP baru atau aplikasi
/// baru dipasang ulang) dan tawarannya belum ditutup. null = tidak ada
/// tawaran. Kegagalan jaringan tidak pernah ditampilkan sebagai galat.
final restoreOfferProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  ref.watch(dataRevisionProvider);
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  final storeId = ref.watch(activeStoreIdProvider);
  if (uid == null || storeId == null) return null;

  final settings = ref.watch(settingsDaoProvider);
  if (await settings.getFlag(restoreOfferDismissedKey(storeId))) return null;

  final service = ref.watch(backupServiceProvider);
  if (await service.hasLocalData(storeId)) return null;
  try {
    return await ref.watch(backupStorageProvider).lastModified(uid, storeId);
  } catch (_) {
    return null;
  }
});
