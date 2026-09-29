/// Provider baca pelanggan & supplier toko aktif.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/dao/contact_dao.dart';

final contactsProvider = FutureProvider.autoDispose
    .family<List<ContactRecord>, ContactKind?>((ref, kind) async {
      ref.watch(dataRevisionProvider);
      final storeId = ref.watch(activeStoreIdProvider);
      if (storeId == null) return const [];
      return ref.watch(contactDaoProvider).list(storeId: storeId, kind: kind);
    });

final contactStatsProvider =
    FutureProvider.autoDispose<Map<String, ContactStats>>((ref) async {
      ref.watch(dataRevisionProvider);
      final storeId = ref.watch(activeStoreIdProvider);
      if (storeId == null) return const {};
      return ref.watch(contactDaoProvider).stats(storeId);
    });

/// Nama setiap kontak toko ini, untuk menampilkan "· Bu Ani" di baris
/// transaksi tanpa query per baris.
final contactNamesProvider = FutureProvider.autoDispose<Map<String, String>>((
  ref,
) async {
  final contacts = await ref.watch(contactsProvider(null).future);
  return {for (final c in contacts) c.id: c.name};
});
