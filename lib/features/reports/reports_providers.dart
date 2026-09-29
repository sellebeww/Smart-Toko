/// Provider dasbor laporan dan umpan balik harian.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/transaction_kind.dart';
import '../catalog/catalog_providers.dart';
import 'data/report_repository.dart';
import 'domain/insights.dart';

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(appDatabaseProvider).db),
);

class ReportData {
  final ReportPeriod period;
  final CategoryTotals current;
  final CategoryTotals previous;
  final List<ItemAggregate> topMenu;
  final List<ItemAggregate> topSpending;
  final List<ProductWithStock> lowStock;
  final Map<DateTime, ({int masuk, int keluar})> daily;
  final DateTime from;
  final DateTime to;
  final List<String> insights;

  const ReportData({
    required this.period,
    required this.current,
    required this.previous,
    required this.topMenu,
    required this.topSpending,
    required this.lowStock,
    required this.daily,
    required this.from,
    required this.to,
    required this.insights,
  });
}

final reportProvider = FutureProvider.autoDispose
    .family<ReportData, ReportPeriod>((ref, period) async {
      ref.watch(dataRevisionProvider);
      final storeId = ref.watch(activeStoreIdProvider)!;
      final repo = ref.watch(reportRepositoryProvider);
      final r = period.ranges(DateTime.now());

      final current = await repo.totals(
        storeId: storeId,
        from: r.from,
        to: r.to,
      );
      final previous = await repo.totals(
        storeId: storeId,
        from: r.prevFrom,
        to: r.prevTo,
      );
      final topMenu = await repo.topItems(
        storeId: storeId,
        from: r.from,
        to: r.to,
        categories: {TxCategory.penjualan},
      );
      final topSpending = await repo.topItems(
        storeId: storeId,
        from: r.from,
        to: r.to,
        categories: {TxCategory.pembelian, TxCategory.pengeluaran},
        byQty: false,
      );
      final daily = period == ReportPeriod.hariIni
          ? const <DateTime, ({int masuk, int keluar})>{}
          : await repo.daily(storeId: storeId, from: r.from, to: r.to);
      final lowStock = await ref.watch(lowStockProvider.future);

      return ReportData(
        period: period,
        current: current,
        previous: previous,
        topMenu: topMenu,
        topSpending: topSpending,
        lowStock: lowStock,
        daily: daily,
        from: r.from,
        to: r.to,
        insights: buildInsights(
          period: period,
          current: current,
          previous: previous,
          topMenu: topMenu,
          topSpending: topSpending,
          lowStock: [
            for (final s in lowStock)
              LowStock(
                name: s.product.name,
                qty: s.stock,
                unit: s.product.unit,
              ),
          ],
        ),
      );
    });

final dailyMotivationProvider = FutureProvider.autoDispose<String>((ref) async {
  ref.watch(dataRevisionProvider);
  final storeId = ref.watch(activeStoreIdProvider);
  if (storeId == null) return '';
  final repo = ref.watch(reportRepositoryProvider);
  final now = DateTime.now();
  final r = ReportPeriod.hariIni.ranges(now);
  return dailyMotivation(
    today: await repo.totals(storeId: storeId, from: r.from, to: r.to),
    yesterday: await repo.totals(
      storeId: storeId,
      from: r.prevFrom,
      to: r.prevTo,
    ),
    hour: now.hour,
  );
});
