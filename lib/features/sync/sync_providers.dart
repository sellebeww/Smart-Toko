/// Provider sinkronisasi, tim, dan peran pengguna di toko aktif.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../auth/auth_providers.dart';
import '../stores/stores_providers.dart';
import 'sync_engine.dart';
import 'sync_remote.dart';
import 'team_repository.dart';

final syncRemoteProvider = Provider<SyncRemote>(
  (ref) => SupabaseSyncRemote(ref.watch(supabaseClientProvider)),
);

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    database: ref.watch(appDatabaseProvider),
    remote: ref.watch(syncRemoteProvider),
  ),
);

final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepository(ref.watch(supabaseClientProvider)),
);

enum StoreRole { owner, staff }

/// Peran di toko aktif. Bila belum diketahui, dianggap pemilik: satu-satunya
/// cara menjadi karyawan adalah lewat undangan, yang selalu tercatat di
/// profil toko dari server.
final activeStoreRoleProvider = Provider<StoreRole>((ref) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  final store = ref.watch(activeStoreProvider).value;
  if (store == null || uid == null) return StoreRole.owner;
  return store.isOwnedBy(uid) ? StoreRole.owner : StoreRole.staff;
});

/// Karyawan hanya boleh mengoreksi/menghapus catatan yang ia catat sendiri
/// (server juga menolak selain itu). Pemilik boleh semuanya.
bool canEditRecord({
  required bool staff,
  required String? email,
  required String? recordedBy,
}) => !staff || (email != null && email.isNotEmpty && recordedBy == email);

final isStaffProvider = Provider<bool>(
  (ref) => ref.watch(activeStoreRoleProvider) == StoreRole.staff,
);

class SyncStatus {
  final bool enabledHere;
  final int pending;
  final DateTime? lastSyncedAt;
  final String? error;

  const SyncStatus({
    this.enabledHere = false,
    this.pending = 0,
    this.lastSyncedAt,
    this.error,
  });
}

/// Galat sinkron terakhir (mis. luring), diisi pemicu sinkron.
class SyncError extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? message) => state = message;
}

final syncErrorProvider = NotifierProvider<SyncError, String?>(SyncError.new);

final syncStatusProvider = FutureProvider.autoDispose<SyncStatus>((ref) async {
  ref.watch(dataRevisionProvider);
  final storeId = ref.watch(activeStoreIdProvider);
  final error = ref.watch(syncErrorProvider);
  if (storeId == null) return const SyncStatus();
  final engine = ref.watch(syncEngineProvider);
  return SyncStatus(
    enabledHere: await engine.isEnabled(storeId),
    pending: await engine.pendingCount(storeId),
    lastSyncedAt: await engine.lastSyncedAt(storeId),
    error: error,
  );
});

final teamMembersProvider = FutureProvider.autoDispose
    .family<List<TeamMember>, String>(
      (ref, storeId) => ref.watch(teamRepositoryProvider).members(storeId),
    );
