/// Pekerja antrean sinkronisasi.
///
/// Dijalankan saat aplikasi kembali ke depan dan saat koneksi pulih. TIDAK ada
/// layanan latar belakang di versi ini — itu keputusan sadar: aplikasi yang
/// diam-diam aktif saat tidak dibuka justru memperkuat kecurigaan bahwa ia
/// mengawasi, dan itu risiko terbesar produk ini.
library;

import '../db/app_database.dart';
import '../db/dao/pending_sync_dao.dart';
import '../db/dao/settings_dao.dart';
import 'backoff.dart';
import 'remote_target.dart';

class SyncRunReport {
  final int succeeded;
  final int rescheduled;
  final int givenUp;
  final bool skipped;

  const SyncRunReport({
    this.succeeded = 0,
    this.rescheduled = 0,
    this.givenUp = 0,
    this.skipped = false,
  });

  const SyncRunReport.skipped() : this(skipped: true);

  int get processed => succeeded + rescheduled + givenUp;

  @override
  String toString() => skipped
      ? 'SyncRunReport(dilewati)'
      : 'SyncRunReport(sukses=$succeeded, dijadwalkan ulang=$rescheduled, '
            'menyerah=$givenUp)';
}

class SyncQueue {
  final AppDatabase database;
  final RemoteSyncTarget target;
  final SyncBackoff backoff;

  SyncQueue({
    required this.database,
    required this.target,
    SyncBackoff? backoff,
  }) : backoff = backoff ?? SyncBackoff();

  /// Memproses antrean yang sudah jatuh tempo.
  ///
  /// Pemeriksaan sakelar dilakukan di sini, bukan hanya saat mengantre. Dengan
  /// begitu mematikan sinkronisasi langsung menghentikan pengiriman, termasuk
  /// untuk baris yang terlanjur mengantre sebelumnya.
  Future<SyncRunReport> drain({DateTime? now, int limit = 20}) async {
    final db = database.db;
    if (!await SettingsDao(db).syncEnabled()) {
      return const SyncRunReport.skipped();
    }

    final clock = now ?? DateTime.now();
    final dao = PendingSyncDao(db);
    final entries = await dao.due(clock, limit: limit);

    var succeeded = 0;
    var rescheduled = 0;
    var givenUp = 0;

    for (final entry in entries) {
      final outcome = await target.push(entry);
      switch (outcome) {
        case SyncSucceeded():
          await dao.markDone(entry.id);
          succeeded++;

        case SyncRejected(:final message):
          // Ditolak server: mengulang tidak akan mengubah hasilnya.
          await dao.markFailedPermanently(
            id: entry.id,
            attemptCount: entry.attemptCount + 1,
            error: message,
          );
          givenUp++;

        case SyncRetryable(:final message):
          final attempt = entry.attemptCount + 1;
          if (backoff.isExhausted(attempt)) {
            await dao.markFailedPermanently(
              id: entry.id,
              attemptCount: attempt,
              error: message,
            );
            givenUp++;
          } else {
            await dao.reschedule(
              id: entry.id,
              attemptCount: attempt,
              nextAttemptAt: backoff.nextAttemptAt(clock, attempt),
              error: message,
            );
            rescheduled++;
          }
      }
    }

    return SyncRunReport(
      succeeded: succeeded,
      rescheduled: rescheduled,
      givenUp: givenUp,
    );
  }

  Future<int> pendingCount() => PendingSyncDao(database.db).pendingCount();

  Future<List<PendingSyncEntry>> failedEntries() =>
      PendingSyncDao(database.db).failedPermanently();

  /// Dipicu pengguna dari layar "gagal terkirim".
  Future<int> retryFailed({DateTime? now}) =>
      PendingSyncDao(database.db).retryFailed(now ?? DateTime.now());
}
