/// Tujuan sinkronisasi di sisi server.
///
/// Sengaja berupa antarmuka: Firestore belum dipasang, dan seluruh antrean
/// sudah bisa diuji tanpa akun cloud mana pun. Menambahkan Firestore nanti
/// cukup dengan satu implementasi baru, tanpa menyentuh antrean.
library;

import '../db/dao/pending_sync_dao.dart';

sealed class SyncOutcome {
  const SyncOutcome();
}

class SyncSucceeded extends SyncOutcome {
  const SyncSucceeded();
}

/// Gagal sementara — layak dicoba lagi (jaringan putus, server sibuk).
class SyncRetryable extends SyncOutcome {
  final String message;
  const SyncRetryable(this.message);
}

/// Gagal permanen — mencoba lagi tidak akan menolong (payload ditolak).
class SyncRejected extends SyncOutcome {
  final String message;
  const SyncRejected(this.message);
}

abstract class RemoteSyncTarget {
  Future<SyncOutcome> push(PendingSyncEntry entry);
}

/// Jangan menandai antrean sebagai terkirim sebelum ada backend sungguhan.
class UnconfiguredRemoteSyncTarget implements RemoteSyncTarget {
  const UnconfiguredRemoteSyncTarget();

  @override
  Future<SyncOutcome> push(PendingSyncEntry entry) async => const SyncRetryable(
    'Pencadangan cloud belum tersedia. Catatan tetap tersimpan di perangkat.',
  );
}

/// Implementasi bawaan selama cloud belum dipasang.
///
/// Mencatat apa yang "terkirim" supaya alur antrean tetap bisa ditelusuri dan
/// diuji dari ujung ke ujung.
class FakeRemoteSyncTarget implements RemoteSyncTarget {
  final List<PendingSyncEntry> pushed = [];
  final Duration latency;

  /// Diisi pengujian untuk mensimulasikan kegagalan.
  SyncOutcome Function(PendingSyncEntry entry)? responder;

  FakeRemoteSyncTarget({this.latency = Duration.zero});

  @override
  Future<SyncOutcome> push(PendingSyncEntry entry) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final outcome = responder?.call(entry) ?? const SyncSucceeded();
    if (outcome is SyncSucceeded) pushed.add(entry);
    return outcome;
  }
}
