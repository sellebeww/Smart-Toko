/// Provider pembacaan transaksi untuk layar utama.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/dao/pending_sync_dao.dart';
import '../../core/transaction_kind.dart';
import 'domain/transaction_record.dart';

typedef DayTotals = ({int masuk, int keluar});

DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

final todayTransactionsProvider = FutureProvider<List<TxRecord>>((ref) async {
  ref.watch(dataRevisionProvider);
  final repository = ref.watch(transactionRepositoryProvider);
  final start = _startOfToday();
  // Non-null: provider ini hanya dipakai di HomeScreen, yang cuma dirender
  // setelah gerbang toko di app/app.dart memastikan ada toko aktif.
  return repository.listBetween(
    storeId: ref.watch(activeStoreIdProvider)!,
    from: start,
    to: start.add(const Duration(days: 1)),
  );
});

final todayTotalsProvider = FutureProvider<DayTotals>((ref) async {
  ref.watch(dataRevisionProvider);
  final repository = ref.watch(transactionRepositoryProvider);
  final storeId = ref.watch(activeStoreIdProvider)!;
  final start = _startOfToday();
  final end = start.add(const Duration(days: 1));

  final masuk = await repository.totalBetween(
    storeId: storeId,
    direction: TxDirection.masuk,
    from: start,
    to: end,
  );
  final keluar = await repository.totalBetween(
    storeId: storeId,
    direction: TxDirection.keluar,
    from: start,
    to: end,
  );

  return (masuk: masuk, keluar: keluar);
});

/// Id transaksi yang masih antre sinkron, untuk lencana di daftar.
final pendingTxIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final enabled = await ref.watch(settingsDaoProvider).syncEnabled();
  if (!enabled) return const {};
  return PendingSyncDao(ref.watch(appDatabaseProvider).db)
      .pendingEntityIds('transaction');
});

final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  final enabled = await ref.watch(settingsDaoProvider).syncEnabled();
  if (!enabled) return 0;
  return ref.watch(syncQueueProvider).pendingCount();
});
