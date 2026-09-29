/// Kalimat ringkasan otomatis untuk dasbor dan umpan balik harian.
///
/// Sengaja berupa templat sederhana tanpa AI: angkanya dapat ditelusuri
/// langsung ke transaksi, dan tetap jalan tanpa internet.
library;

import '../../../core/format.dart';
import '../data/report_repository.dart';

enum ReportPeriod {
  hariIni('Hari ini', 'kemarin'),
  mingguIni('Minggu ini', 'minggu lalu'),
  bulanIni('Bulan ini', 'bulan lalu');

  final String label;

  /// Nama periode pembanding dalam kalimat ("dibanding kemarin").
  final String previousLabel;

  const ReportPeriod(this.label, this.previousLabel);

  /// Rentang periode berjalan dan periode pembanding dengan panjang yang
  /// sama. "Minggu ini" (Senin s.d. hari ini) dibandingkan dengan Senin s.d.
  /// hari yang sama minggu lalu, supaya adil.
  ({DateTime from, DateTime to, DateTime prevFrom, DateTime prevTo}) ranges(
    DateTime now,
  ) {
    final today = startOfDay(now);
    final tomorrow = today.add(const Duration(days: 1));
    switch (this) {
      case ReportPeriod.hariIni:
        final yesterday = today.subtract(const Duration(days: 1));
        return (from: today, to: tomorrow, prevFrom: yesterday, prevTo: today);
      case ReportPeriod.mingguIni:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        const week = Duration(days: 7);
        return (
          from: monday,
          to: tomorrow,
          prevFrom: monday.subtract(week),
          prevTo: tomorrow.subtract(week),
        );
      case ReportPeriod.bulanIni:
        final first = DateTime(now.year, now.month);
        final prevFirst = DateTime(now.year, now.month - 1);
        // Hari ke-31 bulan ini dibandingkan dengan akhir bulan lalu bila
        // bulan lalu lebih pendek.
        final prevMonthLength = first.difference(prevFirst).inDays;
        final dayOfMonth = now.day > prevMonthLength
            ? prevMonthLength
            : now.day;
        return (
          from: first,
          to: tomorrow,
          prevFrom: prevFirst,
          prevTo: DateTime(prevFirst.year, prevFirst.month, dayOfMonth + 1),
        );
    }
  }
}

/// Persentase perubahan dibulatkan; null bila pembandingnya nol (tidak
/// bermakna: "naik tak hingga persen").
int? percentChange(int current, int previous) {
  if (previous == 0) return null;
  return (((current - previous) / previous) * 100).round();
}

String _trend(String what, int current, int previous, String vs) {
  final pct = percentChange(current, previous);
  if (pct == null) return '';
  if (pct == 0) return '$what sama dengan $vs.';
  final dir = pct > 0 ? 'naik' : 'turun';
  return '$what $dir ${pct.abs()}% dibanding $vs '
      '(${formatRupiah(previous)} → ${formatRupiah(current)}).';
}

class LowStock {
  final String name;
  final int qty;
  final String? unit;

  const LowStock({required this.name, required this.qty, this.unit});
}

/// Kalimat wawasan untuk dasbor, paling penting dulu. Kosong bila belum ada
/// data sama sekali.
List<String> buildInsights({
  required ReportPeriod period,
  required CategoryTotals current,
  required CategoryTotals previous,
  required List<ItemAggregate> topMenu,
  required List<ItemAggregate> topSpending,
  required List<LowStock> lowStock,
}) {
  final vs = period.previousLabel;
  final insights = <String>[];

  if (topMenu.isNotEmpty) {
    final best = topMenu.first;
    insights.add(
      'Menu terlaris ${period.label.toLowerCase()}: ${best.name} '
      '(${formatQty(best.qty, best.unit)} terjual, ${formatRupiah(best.amount)}).',
    );
  }

  final omzetTrend = _trend('Omzet', current.omzet, previous.omzet, vs);
  if (omzetTrend.isNotEmpty) insights.add(omzetTrend);

  final spendTrend = _trend(
    'Pengeluaran',
    current.pengeluaran,
    previous.pengeluaran,
    vs,
  );
  if (spendTrend.isNotEmpty) insights.add(spendTrend);

  if (topSpending.isNotEmpty && current.pengeluaran > 0) {
    final top = topSpending.first;
    final share = ((top.amount / current.pengeluaran) * 100).round();
    insights.add(
      'Pengeluaran terbesar: ${top.name} ${formatRupiah(top.amount)} '
      '($share% dari total pengeluaran).',
    );
  }

  if (current.count > 0 && current.keuntungan < 0) {
    insights.add(
      'Uang keluar lebih besar dari uang masuk sebesar '
      '${formatRupiah(-current.keuntungan)}. Wajar bila baru belanja stok '
      'besar; perhatikan bila berlanjut.',
    );
  }

  if (lowStock.isNotEmpty) {
    final names = lowStock
        .take(3)
        .map((s) => '${s.name} (${formatQty(s.qty, s.unit)})')
        .join(', ');
    insights.add('Stok menipis: $names. Saatnya belanja lagi.');
  }

  return insights;
}

/// Satu kalimat penyemangat di layar utama, berdasar catatan hari ini
/// dibanding kemarin. [hour] dipakai untuk sapaan yang pas.
String dailyMotivation({
  required CategoryTotals today,
  required CategoryTotals yesterday,
  required int hour,
}) {
  if (today.count == 0) {
    if (hour < 11) {
      return 'Selamat pagi! Yuk catat penjualan pertama hari ini.';
    }
    if (hour < 15) {
      return 'Belum ada catatan hari ini. Tekan Rekam saat ada pembeli.';
    }
    return 'Belum ada catatan hari ini. Masih sempat mencatat, kok!';
  }
  if (today.omzet == 0) {
    return 'Catatan belanja sudah masuk. Semoga penjualan hari ini lancar!';
  }
  final pct = percentChange(today.omzet, yesterday.omzet);
  if (pct == null) {
    return 'Mantap! Omzet hari ini sudah ${formatRupiah(today.omzet)}. '
        'Terus catat, ya!';
  }
  if (pct >= 10) {
    return 'Mantap! Omzet hari ini ${formatRupiah(today.omzet)}, '
        'naik $pct% dari kemarin. Pertahankan!';
  }
  if (pct >= 0) {
    return 'Omzet hari ini ${formatRupiah(today.omzet)}, '
        'setara kemarin. Konsisten itu kunci!';
  }
  return 'Omzet hari ini ${formatRupiah(today.omzet)}. Masih ada waktu '
      'mengejar kemarin (${formatRupiah(yesterday.omzet)}). Semangat!';
}
