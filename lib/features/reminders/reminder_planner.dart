/// Perencana pengingat: menentukan notifikasi apa saja yang dijadwalkan
/// untuk beberapa hari ke depan.
///
/// Notifikasi terjadwal tidak bisa menjalankan kode saat berbunyi, jadi
/// "lewati bila hari ini sudah mencatat" diwujudkan dengan menghitung ulang
/// seluruh rencana setiap kali data berubah atau aplikasi dibuka. Fungsi ini
/// murni (tanpa plugin, tanpa jam sistem) supaya mudah diuji.
library;

import '../../core/format.dart';
import '../../core/transaction_kind.dart';
import '../debts/data/debt_repository.dart';

/// Berapa hari ke depan yang dijadwalkan. Aplikasi yang tidak dibuka
/// seminggu tetap diingatkan tiap hari selama seminggu itu.
const int planDays = 7;

/// Jam pengingat kasbon (pagi, saat warung bersiap).
const int dueReminderHour = 8;

class ReminderSettings {
  final bool dailyEnabled;
  final int hour;
  final int minute;
  final bool dueEnabled;

  const ReminderSettings({
    this.dailyEnabled = false,
    this.hour = 20,
    this.minute = 0,
    this.dueEnabled = false,
  });

  bool get anyEnabled => dailyEnabled || dueEnabled;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ReminderSettings copyWith({
    bool? dailyEnabled,
    int? hour,
    int? minute,
    bool? dueEnabled,
  }) => ReminderSettings(
    dailyEnabled: dailyEnabled ?? this.dailyEnabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    dueEnabled: dueEnabled ?? this.dueEnabled,
  );
}

enum ReminderKind { daily, due }

class PlannedNotification {
  final int id;
  final ReminderKind kind;
  final DateTime at;
  final String title;
  final String body;

  const PlannedNotification({
    required this.id,
    required this.kind,
    required this.at,
    required this.title,
    required this.body,
  });

  /// Dibawa notifikasi; dipakai untuk membuka layar yang tepat saat diketuk.
  String get payload => kind == ReminderKind.due ? 'debts' : 'record';

  @override
  String toString() => 'PlannedNotification($id, $at, $title)';
}

/// Isi pengingat mencatat dirotasi supaya tidak terasa seperti spam.
const List<String> _dailyBodies = [
  'Catat penjualan dan pengeluaran hari ini selagi masih ingat. Cukup '
      'tekan rekam dan sebutkan.',
  'Satu menit sebelum tutup warung: catat transaksi hari ini supaya laporan '
      'tetap lengkap.',
  'Jangan sampai ada yang terlewat. Catat dulu transaksi hari ini, ya.',
];

List<PlannedNotification> planReminders({
  required ReminderSettings settings,
  required DateTime now,
  required String storeName,
  required bool recordedToday,
  List<DueDebt> upcomingDue = const [],
  int overdueCount = 0,
  int overdueAmount = 0,
}) {
  final today = startOfDay(now);
  final plan = <PlannedNotification>[];

  if (settings.dailyEnabled) {
    for (var d = 0; d < planDays; d++) {
      if (d == 0 && recordedToday) continue;
      final day = today.add(Duration(days: d));
      final at = DateTime(
        day.year,
        day.month,
        day.day,
        settings.hour,
        settings.minute,
      );
      if (!at.isAfter(now)) continue;
      plan.add(
        PlannedNotification(
          id: 1000 + d,
          kind: ReminderKind.daily,
          at: at,
          title: 'Sudah catat hari ini? · $storeName',
          body: _dailyBodies[day.day % _dailyBodies.length],
        ),
      );
    }
  }

  if (settings.dueEnabled) {
    final byDay = <DateTime, List<DueDebt>>{};
    for (final debt in upcomingDue) {
      final day = startOfDay(debt.dueAt);
      if (day.isBefore(today)) continue;
      byDay.putIfAbsent(day, () => []).add(debt);
    }
    var overdueAnnounced = false;
    for (var d = 0; d < planDays; d++) {
      final day = today.add(Duration(days: d));
      final at = DateTime(day.year, day.month, day.day, dueReminderHour);
      if (!at.isAfter(now)) continue;
      final dues = byDay[day] ?? const <DueDebt>[];
      // Ringkasan yang sudah telat ikut di pengingat pagi pertama saja,
      // supaya tidak menagih setiap hari dari HP pemilik sendiri.
      final mentionOverdue = !overdueAnnounced && overdueCount > 0;
      if (dues.isEmpty && !mentionOverdue) continue;
      overdueAnnounced = overdueAnnounced || mentionOverdue;
      plan.add(
        PlannedNotification(
          id: 2000 + d,
          kind: ReminderKind.due,
          at: at,
          title: dues.isEmpty
              ? 'Ada kasbon yang lewat jatuh tempo'
              : d == 0
              ? 'Jatuh tempo hari ini'
              : 'Jatuh tempo ${formatShortDate(day)}',
          body: _dueBody(
            dues,
            mentionOverdue ? overdueCount : 0,
            overdueAmount,
          ),
        ),
      );
    }
  }

  plan.sort((a, b) => a.at.compareTo(b.at));
  return plan;
}

String _dueBody(List<DueDebt> dues, int overdueCount, int overdueAmount) {
  String names(Iterable<DueDebt> list) {
    final items = list.toList();
    final shown = items
        .take(2)
        .map((d) => '${d.contactName} ${formatRupiah(d.outstanding)}')
        .join(', ');
    return items.length > 2 ? '$shown, dan ${items.length - 2} lainnya' : shown;
  }

  final collect = dues.where((d) => d.direction == TxDirection.masuk);
  final pay = dues.where((d) => d.direction == TxDirection.keluar);
  final parts = [
    if (collect.isNotEmpty) 'Tagih: ${names(collect)}',
    if (pay.isNotEmpty) 'Bayar: ${names(pay)}',
    if (overdueCount > 0)
      '$overdueCount kasbon sudah telat, total ${formatRupiah(overdueAmount)}',
  ];
  return '${parts.join('. ')}.';
}
