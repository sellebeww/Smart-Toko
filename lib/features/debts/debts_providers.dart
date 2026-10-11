/// Provider baca utang/piutang toko aktif.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'data/debt_repository.dart';

final debtRepositoryProvider = Provider<DebtRepository>(
  (ref) => DebtRepository(database: ref.watch(appDatabaseProvider)),
);

final debtTotalsProvider = FutureProvider.autoDispose<DebtTotals>((ref) async {
  ref.watch(dataRevisionProvider);
  final storeId = ref.watch(activeStoreIdProvider);
  if (storeId == null) return const DebtTotals();
  return ref.watch(debtRepositoryProvider).totals(storeId);
});

final debtBalancesProvider = FutureProvider.autoDispose<List<ContactBalance>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final storeId = ref.watch(activeStoreIdProvider);
  if (storeId == null) return const [];
  return ref.watch(debtRepositoryProvider).balances(storeId);
});

final debtPaymentsProvider = FutureProvider.autoDispose
    .family<List<DebtPayment>, String>((ref, transactionId) {
      ref.watch(dataRevisionProvider);
      return ref.watch(debtRepositoryProvider).paymentsFor(transactionId);
    });
