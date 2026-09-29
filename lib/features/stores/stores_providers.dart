/// Provider daftar toko milik user yang sedang login.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/dao/settings_dao.dart';
import '../auth/auth_providers.dart';
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

final userStoresProvider = StreamProvider<List<StoreProfile>>((ref) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(storeRepositoryProvider).watchStoresForUser(user.uid);
});

/// Toko yang sedang dipakai (lihat activeStoreIdProvider): nama & status
/// verifikasinya untuk layar utama dan Pengaturan.
///
/// Ikut bergantung pada user yang login: saat keluar, listener Firestore
/// lama ditolak izinnya dan berakhir error. Kalau user yang sama login lagi,
/// id toko aktifnya tidak berubah — tanpa ketergantungan ini provider akan
/// terjebak di error lama itu.
final activeStoreProvider = StreamProvider<StoreProfile>((ref) {
  final user = ref.watch(authStateChangesProvider).value;
  final storeId = ref.watch(activeStoreIdProvider);
  if (user == null || storeId == null) return const Stream.empty();
  return ref.watch(storeRepositoryProvider).watchStore(storeId);
});
