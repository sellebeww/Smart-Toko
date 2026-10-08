/// Penghapusan akun beserta seluruh datanya.
///
/// Urutannya penting: berkas di Storage dihapus lebih dulu selagi sesi masih
/// berlaku (policy Storage memeriksa uid pemilik), baru akun dihapus di
/// server, lalu data di HP ini dibersihkan.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/providers.dart';
import '../../core/db/dao/settings_dao.dart';
import '../backup/backup_providers.dart';
import '../backup/backup_service.dart';
import '../stores/data/store_cache.dart';
import '../verification/data/verification_repository.dart';

class AccountDeletionService {
  final SupabaseClient client;
  final BackupStorage backups;
  final StoreCache cache;
  final SettingsDao settings;

  AccountDeletionService({
    required this.client,
    required this.backups,
    required this.cache,
    required this.settings,
  });

  Future<void> deleteAccount(String uid) async {
    final rows = await client.from('stores').select('id').eq('owner_uid', uid);
    final storeIds = [for (final row in rows) row['id'] as String];

    final files = client.storage.from(verificationBucket);
    for (final storeId in storeIds) {
      final objects = await files.list(path: '$uid/$storeId');
      final paths = [
        for (final object in objects)
          if (object.id != null) '$uid/$storeId/${object.name}',
      ];
      if (paths.isNotEmpty) await files.remove(paths);
    }
    await backups.deleteAll(uid);

    await client.rpc('delete_my_account');

    // Toko lokal ikut menghapus transaksi, barang, stok, dan kontaknya
    // lewat ON DELETE CASCADE.
    await cache.deleteForOwner(uid);
    for (final storeId in storeIds) {
      await cache.db.delete('stores', where: 'id = ?', whereArgs: [storeId]);
      await settings.remove(SettingsKeys.lastBackupAt(storeId));
      await settings.remove(SettingsKeys.lastBackupFingerprint(storeId));
      await settings.remove(restoreOfferDismissedKey(storeId));
    }
    await settings.remove('${SettingsKeys.activeStoreId}:$uid');

    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Akunnya sudah tidak ada; sesi lokal tetap dibersihkan oleh SDK.
    }
  }
}

final accountDeletionServiceProvider = Provider<AccountDeletionService>(
  (ref) => AccountDeletionService(
    client: ref.watch(supabaseClientProvider),
    backups: ref.watch(backupStorageProvider),
    cache: ref.watch(storeCacheProvider),
    settings: ref.watch(settingsDaoProvider),
  ),
);
