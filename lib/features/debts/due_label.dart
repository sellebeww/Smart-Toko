/// Label jatuh tempo yang dipakai di daftar, detail, dan pengingat.
library;

import '../../core/format.dart';

/// "telat 3 hari", "jatuh tempo hari ini", "jatuh tempo besok",
/// "jatuh tempo 20 Okt 2026".
String dueLabel(DateTime due, DateTime now) {
  final days = startOfDay(due).difference(startOfDay(now)).inDays;
  if (days < 0) return 'telat ${-days} hari';
  if (days == 0) return 'jatuh tempo hari ini';
  if (days == 1) return 'jatuh tempo besok';
  return 'jatuh tempo ${formatShortDate(due)}';
}

/// Pilihan cepat jatuh tempo di layar konfirmasi (dalam hari).
const List<(String, int)> dueQuickOptions = [
  ('1 minggu', 7),
  ('2 minggu', 14),
  ('1 bulan', 30),
];
