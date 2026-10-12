/// Sisi server sinkronisasi (fungsi sync_push / sync_pull di setup.sql).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Satu baris dari server.
class RemoteRow {
  final String table;
  final String id;
  final Map<String, Object?>? data;
  final bool deleted;
  final int version;

  const RemoteRow({
    required this.table,
    required this.id,
    required this.data,
    required this.deleted,
    required this.version,
  });
}

/// Satu perubahan yang dikirim ke server.
class OutgoingRow {
  final String table;
  final String id;
  final Map<String, Object?>? data;

  const OutgoingRow.upsert(this.table, this.id, Map<String, Object?> this.data);
  const OutgoingRow.delete(this.table, this.id) : data = null;

  bool get deleted => data == null;

  Map<String, Object?> toJson() => {
    'table': table,
    'id': id,
    'deleted': deleted,
    if (data != null) 'data': data,
  };
}

/// Pengguna bukan (lagi) anggota toko: dikeluarkan, atau sinkronisasi toko
/// dimatikan pemiliknya.
class SyncAccessLost implements Exception {
  const SyncAccessLost();
}

abstract class SyncRemote {
  Future<void> push(String storeId, List<OutgoingRow> rows);

  Future<List<RemoteRow>> pull(String storeId, {required int after, int limit});
}

class SupabaseSyncRemote implements SyncRemote {
  final SupabaseClient client;
  const SupabaseSyncRemote(this.client);

  Never _rethrow(PostgrestException e) {
    // 42501 = bukan anggota; 22023 'sync disabled' = sinkronisasi dimatikan.
    if (e.code == '42501' || e.message.contains('sync disabled')) {
      throw const SyncAccessLost();
    }
    throw e;
  }

  @override
  Future<void> push(String storeId, List<OutgoingRow> rows) async {
    try {
      await client.rpc(
        'sync_push',
        params: {
          'p_store': storeId,
          'p_rows': [for (final r in rows) r.toJson()],
        },
      );
    } on PostgrestException catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<List<RemoteRow>> pull(
    String storeId, {
    required int after,
    int limit = 500,
  }) async {
    try {
      final rows = await client.rpc(
        'sync_pull',
        params: {'p_store': storeId, 'p_after': after, 'p_limit': limit},
      ) as List;
      return [
        for (final raw in rows.cast<Map<String, dynamic>>())
          RemoteRow(
            table: raw['table_name'] as String,
            id: raw['row_id'] as String,
            data: (raw['data'] as Map?)?.cast<String, Object?>(),
            deleted: raw['deleted'] as bool? ?? false,
            version: (raw['version'] as num).toInt(),
          ),
      ];
    } on PostgrestException catch (e) {
      _rethrow(e);
    }
  }
}
