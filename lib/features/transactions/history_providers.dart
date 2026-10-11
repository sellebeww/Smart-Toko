/// Provider layar riwayat transaksi.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/transaction_kind.dart';
import '../contacts/contacts_providers.dart';
import 'domain/history_filter.dart';
import 'domain/transaction_record.dart';

class HistoryFilterNotifier extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() {
    // Filter kembali ke bawaan saat toko diganti.
    ref.watch(activeStoreIdProvider);
    return const HistoryFilter();
  }

  void set(HistoryFilter filter) => state = filter;
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilter>(
      HistoryFilterNotifier.new,
    );

final historyTransactionsProvider = FutureProvider.autoDispose<List<TxRecord>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final storeId = ref.watch(activeStoreIdProvider);
  if (storeId == null) return const [];
  final filter = ref.watch(historyFilterProvider);
  final range = filter.resolve(DateTime.now());
  final records = await ref
      .watch(transactionRepositoryProvider)
      .listBetween(
        storeId: storeId,
        from: range.from,
        to: range.to,
        categories: filter.categories,
        source: filter.source,
      );
  final contactNames = filter.query.trim().isEmpty
      ? const <String, String>{}
      : await ref.watch(contactNamesProvider.future);
  return filter.applyLocal(records, contactNames: contactNames);
});

class DayGroup {
  final DateTime day;
  final List<TxRecord> records;
  final int masuk;
  final int keluar;

  const DayGroup({
    required this.day,
    required this.records,
    required this.masuk,
    required this.keluar,
  });

  int get net => masuk - keluar;
}

/// Mengelompokkan transaksi (sudah terurut terbaru dulu) per hari.
List<DayGroup> groupByDay(List<TxRecord> records) {
  final groups = <DayGroup>[];
  DateTime? currentDay;
  var bucket = <TxRecord>[];
  var masuk = 0;
  var keluar = 0;

  void flush() {
    if (currentDay == null) return;
    groups.add(
      DayGroup(day: currentDay, records: bucket, masuk: masuk, keluar: keluar),
    );
  }

  for (final record in records) {
    final day = startOfDay(record.occurredAt);
    if (day != currentDay) {
      flush();
      currentDay = day;
      bucket = [];
      masuk = 0;
      keluar = 0;
    }
    bucket.add(record);
    if (record.direction == TxDirection.masuk) {
      masuk += record.totalAmount;
    } else {
      keluar += record.totalAmount;
    }
  }
  flush();
  return groups;
}
