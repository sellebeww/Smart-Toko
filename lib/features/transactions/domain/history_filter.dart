/// Filter riwayat transaksi: rentang tanggal, kategori, dan sumber.
library;

import '../../../core/format.dart';
import '../../../core/transaction_kind.dart';

enum HistoryRange {
  hariIni('Hari ini'),
  mingguIni('Minggu ini'),
  bulanIni('Bulan ini'),
  pilihTanggal('Pilih tanggal');

  final String label;
  const HistoryRange(this.label);
}

class HistoryFilter {
  final HistoryRange range;

  /// Hanya dipakai untuk [HistoryRange.pilihTanggal]; [customTo] inklusif.
  final DateTime? customFrom;
  final DateTime? customTo;

  /// Kosong berarti semua kategori.
  final Set<TxCategory> categories;
  final TxSource? source;

  const HistoryFilter({
    this.range = HistoryRange.mingguIni,
    this.customFrom,
    this.customTo,
    this.categories = const {},
    this.source,
  });

  /// Rentang [from, to) di zona waktu perangkat. Minggu dimulai Senin.
  ({DateTime from, DateTime to}) resolve(DateTime now) {
    final today = startOfDay(now);
    return switch (range) {
      HistoryRange.hariIni => (
        from: today,
        to: today.add(const Duration(days: 1)),
      ),
      HistoryRange.mingguIni => (
        from: today.subtract(Duration(days: today.weekday - 1)),
        to: today.add(const Duration(days: 1)),
      ),
      HistoryRange.bulanIni => (
        from: DateTime(now.year, now.month),
        to: today.add(const Duration(days: 1)),
      ),
      HistoryRange.pilihTanggal => (
        from: startOfDay(customFrom ?? today),
        to: startOfDay(customTo ?? today).add(const Duration(days: 1)),
      ),
    };
  }

  bool get isNarrowed => categories.isNotEmpty || source != null;

  HistoryFilter copyWith({
    HistoryRange? range,
    DateTime? customFrom,
    DateTime? customTo,
    Set<TxCategory>? categories,
    Object? source = _keep,
  }) => HistoryFilter(
    range: range ?? this.range,
    customFrom: customFrom ?? this.customFrom,
    customTo: customTo ?? this.customTo,
    categories: categories ?? this.categories,
    source: identical(source, _keep) ? this.source : source as TxSource?,
  );
}

const Object _keep = Object();
