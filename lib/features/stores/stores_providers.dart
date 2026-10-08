/// Provider daftar toko milik user yang sedang login.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/dao/settings_dao.dart';
import '../auth/auth_providers.dart';
import 'data/store_cache.dart';
import 'domain/store_profile.dart';

/// Toko terakhir yang dipilih di perangkat ini, dipakai StoreListScreen
/// untuk langsung memilihkan toko yang sama saat aplikasi dibuka lagi.
/// autoDispose supaya dibaca ulang setiap daftar toko tampil, bukan memakai
/// nilai basi dari awal sesi.
final savedActiveStoreIdProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return null;
  final settings = ref.watch(settingsDaoProvider);
  return await settings.getString('${SettingsKeys.activeStoreId}:$uid') ??
      await settings.getString(SettingsKeys.activeStoreId);
});

/// Daftar toko: salinan lokal tampil lebih dulu (aplikasi langsung terbuka,
/// juga saat luring), lalu digantikan data server begitu tersedia. Saat
/// koneksi pulih, langganan ke server dibuka ulang.
final userStoresProvider = StreamProvider<List<StoreProfile>>((ref) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return const Stream.empty();
  ref.watch(
    connectivityStatusProvider.select((status) => status.value ?? true),
  );
  return cachedStores(
    remote: ref.watch(storeRepositoryProvider).watchStoresForUser(user.uid),
    cache: ref.watch(storeCacheProvider),
    ownerUid: user.uid,
  );
});

/// Menggabungkan salinan lokal dengan aliran dari server. Galat server hanya
/// diteruskan bila tidak ada salinan lokal sama sekali.
Stream<List<StoreProfile>> cachedStores({
  required Stream<List<StoreProfile>> remote,
  required StoreCache cache,
  required String ownerUid,
}) async* {
  final cached = await cache.forOwner(ownerUid);
  if (cached.isNotEmpty) yield cached;
  var hasData = cached.isNotEmpty;
  try {
    await for (final stores in remote) {
      try {
        await cache.saveAll(stores);
      } catch (_) {
        // Salinan lokal hanya pelengkap; data server tetap ditampilkan.
      }
      hasData = true;
      yield stores;
    }
  } catch (_) {
    if (!hasData) rethrow;
  }
}

/// Toko yang sedang dipakai (lihat activeStoreIdProvider): nama & status
/// verifikasinya untuk layar utama dan Pengaturan. Diturunkan dari
/// [userStoresProvider], jadi ikut tersedia saat luring.
final activeStoreProvider = Provider<AsyncValue<StoreProfile>>((ref) {
  final storeId = ref.watch(activeStoreIdProvider);
  final stores = ref.watch(userStoresProvider);
  // Saat langganan dibuka ulang, nilai lama tetap dipakai supaya layar tidak
  // berkedip ke status memuat.
  final value = stores.value;
  if (value != null) {
    for (final store in value) {
      if (store.id == storeId) return AsyncData(store);
    }
    return AsyncError(
      StateError('Toko aktif tidak ditemukan'),
      StackTrace.current,
    );
  }
  if (stores.hasError) return AsyncError(stores.error!, stores.stackTrace!);
  return const AsyncLoading();
});
