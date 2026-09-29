/// Antrean sinkronisasi yang tertunda.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

enum SyncOp { create, update, delete }

enum SyncStatus { pending, failedPermanent, done }

class PendingSyncEntry {
  final String id;
  final String entityType;
  final String entityId;
  final SyncOp op;
  final Map<String, Object?> payload;
  final int attemptCount;
  final DateTime nextAttemptAt;
  final String? lastError;
  final SyncStatus status;
  final DateTime createdAt;

  const PendingSyncEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.op,
    required this.payload,
    required this.attemptCount,
    required this.nextAttemptAt,
    required this.status,
    required this.createdAt,
    this.lastError,
  });

  factory PendingSyncEntry.fromRow(Map<String, Object?> row) =>
      PendingSyncEntry(
        id: row['id']! as String,
        entityType: row['entity_type']! as String,
        entityId: row['entity_id']! as String,
        op: SyncOp.values.byName(row['op']! as String),
        payload:
            jsonDecode(row['payload_json']! as String) as Map<String, Object?>,
        attemptCount: (row['attempt_count']! as num).toInt(),
        nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
          (row['next_attempt_at']! as num).toInt(),
        ),
        lastError: row['last_error'] as String?,
        status: _statusFromDb(row['status']! as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (row['created_at']! as num).toInt(),
        ),
      );

  static SyncStatus _statusFromDb(String value) => switch (value) {
    'failed_permanent' => SyncStatus.failedPermanent,
    'done' => SyncStatus.done,
    _ => SyncStatus.pending,
  };

  static String statusToDb(SyncStatus status) => switch (status) {
    SyncStatus.failedPermanent => 'failed_permanent',
    SyncStatus.done => 'done',
    SyncStatus.pending => 'pending',
  };
}

class PendingSyncDao {
  final DatabaseExecutor db;

  const PendingSyncDao(this.db);

  /// Dipanggil di dalam transaksi basis data yang sama dengan penulisan
  /// entitasnya, supaya tidak mungkin ada entitas tersimpan tanpa antrean
  /// (atau sebaliknya) ketika aplikasi mati di tengah jalan.
  Future<void> enqueue({
    required String id,
    required String entityType,
    required String entityId,
    required SyncOp op,
    required Map<String, Object?> payload,
    required DateTime now,
  }) async {
    await db.insert('pending_sync', {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'op': op.name,
      'payload_json': jsonEncode(payload),
      'attempt_count': 0,
      'next_attempt_at': now.millisecondsSinceEpoch,
      'status': 'pending',
      'created_at': now.millisecondsSinceEpoch,
    });
  }

  Future<List<PendingSyncEntry>> due(DateTime now, {int limit = 20}) async {
    final rows = await db.query(
      'pending_sync',
      where: 'status = ? AND next_attempt_at <= ?',
      whereArgs: ['pending', now.millisecondsSinceEpoch],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return [for (final row in rows) PendingSyncEntry.fromRow(row)];
  }

  Future<void> markDone(String id) async {
    await db.update(
      'pending_sync',
      {'status': 'done', 'last_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reschedule({
    required String id,
    required int attemptCount,
    required DateTime nextAttemptAt,
    required String error,
  }) async {
    await db.update(
      'pending_sync',
      {
        'attempt_count': attemptCount,
        'next_attempt_at': nextAttemptAt.millisecondsSinceEpoch,
        'last_error': error,
        'status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markFailedPermanently({
    required String id,
    required int attemptCount,
    required String error,
  }) async {
    await db.update(
      'pending_sync',
      {
        'attempt_count': attemptCount,
        'last_error': error,
        'status': 'failed_permanent',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PendingSyncEntry>> failedPermanently() async {
    final rows = await db.query(
      'pending_sync',
      where: 'status = ?',
      whereArgs: ['failed_permanent'],
      orderBy: 'created_at ASC',
    );
    return [for (final row in rows) PendingSyncEntry.fromRow(row)];
  }

  /// Dipicu pengguna dari layar "gagal terkirim". Antrean yang sudah menyerah
  /// tidak pernah hilang sendiri; hanya perintah inilah yang membangunkannya.
  Future<int> retryFailed(DateTime now) => db.update(
    'pending_sync',
    {
      'status': 'pending',
      'attempt_count': 0,
      'next_attempt_at': now.millisecondsSinceEpoch,
    },
    where: 'status = ?',
    whereArgs: ['failed_permanent'],
  );

  Future<int> pendingCount() async {
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_sync WHERE status = 'pending'",
    );
    return (result.first['c']! as num).toInt();
  }

  /// Id entitas yang masih menunggu dikirim, untuk lencana "belum tersinkron".
  Future<Set<String>> pendingEntityIds(String entityType) async {
    final rows = await db.query(
      'pending_sync',
      columns: ['entity_id'],
      where: "entity_type = ? AND status = 'pending'",
      whereArgs: [entityType],
    );
    return {for (final row in rows) row['entity_id']! as String};
  }
}
