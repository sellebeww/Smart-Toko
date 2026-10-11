/// Filter riwayat transaksi: rentang tanggal, kategori, dan sumber.
library;

import '../../../core/format.dart';
import '../../../core/transaction_kind.dart';
import 'transaction_record.dart';

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

  /// Kata kunci: dicocokkan dengan nama barang, catatan, kategori, dan nama
  /// pelanggan/supplier. Kosong = tidak menyaring.
  final String query;

  /// Hanya transaksi kasbon yang belum lunas.
  final bool onlyUnpaid;

  const HistoryFilter({
    this.range = HistoryRange.mingguIni,
    this.customFrom,
    this.customTo,
    this.categories = const {},
    this.source,
    this.query = '',
    this.onlyUnpaid = false,
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

  bool get isNarrowed =>
      categories.isNotEmpty ||
      source != null ||
      query.trim().isNotEmpty ||
      onlyUnpaid;

  HistoryFilter copyWith({
    HistoryRange? range,
    DateTime? customFrom,
    DateTime? customTo,
    Set<TxCategory>? categories,
    Object? source = _keep,
    String? query,
    bool? onlyUnpaid,
  }) => HistoryFilter(
    range: range ?? this.range,
    customFrom: customFrom ?? this.customFrom,
    customTo: customTo ?? this.customTo,
    categories: categories ?? this.categories,
    source: identical(source, _keep) ? this.source : source as TxSource?,
    query: query ?? this.query,
    onlyUnpaid: onlyUnpaid ?? this.onlyUnpaid,
  );

  /// Menerapkan [query] dan [onlyUnpaid] pada [records]. Rentang tanggal,
  /// kategori, dan sumber sudah disaring di basis data.
  List<TxRecord> applyLocal(
    List<TxRecord> records, {
    Map<String, String> contactNames = const {},
  }) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty && !onlyUnpaid) return records;
    return [
      for (final r in records)
        if ((!onlyUnpaid || r.isUnpaid) &&
            (needle.isEmpty ||
                recordMatchesQuery(r, needle, contactNames[r.contactId])))
          r,
    ];
  }
}

/// [needle] sudah huruf kecil dan tidak kosong.
bool recordMatchesQuery(TxRecord record, String needle, String? contactName) {
  bool has(String? text) => text != null && text.toLowerCase().contains(needle);
  return has(contactName) ||
      has(record.note) ||
      has(record.category.label) ||
      record.items.any((item) => has(item.name));
}

const Object _keep = Object();
