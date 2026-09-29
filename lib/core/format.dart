/// Pemformat tampilan.
library;

import 'package:intl/intl.dart';

final NumberFormat _rupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp',
  decimalDigits: 0,
);

final NumberFormat _plain = NumberFormat.decimalPattern('id_ID');

String formatRupiah(int amount) => _rupiah.format(amount);

String formatNumber(int value) => _plain.format(value);

/// Membaca angka yang diketik pengguna, memaafkan titik/koma pemisah ribuan.
int? parseRupiahInput(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

String formatDayMonth(DateTime date) =>
    DateFormat('d MMMM y', 'id_ID').format(date);

String formatTime(DateTime date) => DateFormat('HH:mm').format(date);

/// "Senin, 29 Sep" — judul grup harian di riwayat.
String formatDayHeader(DateTime date) =>
    DateFormat('EEEE, d MMM', 'id_ID').format(date);

/// "29 Sep 2026".
String formatShortDate(DateTime date) =>
    DateFormat('d MMM y', 'id_ID').format(date);

/// "2026-09-29" — dipakai di nama berkas dan kolom tanggal Excel.
String formatIsoDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

/// "5 kg", "2 porsi", atau "3" bila satuannya tidak disebut.
String formatQty(int qty, String? unit) => unit == null || unit.isEmpty
    ? formatNumber(qty)
    : '${formatNumber(qty)} $unit';

/// Tanggal tanpa jam, di zona waktu perangkat.
DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);
