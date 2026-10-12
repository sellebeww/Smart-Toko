/// Karyawan toko: undangan berkode, daftar anggota, dan keluar dari toko.
/// Semua aturan (hanya pemilik yang boleh mengundang, kode sekali pakai,
/// batas tebakan) ditegakkan server; lihat bagian 10 di setup.sql.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

class TeamMember {
  final String userId;
  final String email;
  final DateTime joinedAt;

  const TeamMember({
    required this.userId,
    required this.email,
    required this.joinedAt,
  });
}

class TeamException implements Exception {
  final String message;
  const TeamException(this.message);

  @override
  String toString() => message;
}

/// "abcde-12345" → "ABCDE12345"; tampilan: "ABCDE-12345".
String normalizeInviteCode(String raw) =>
    raw.replaceAll(RegExp('[^0-9A-Za-z]'), '').toUpperCase();

String formatInviteCode(String code) {
  final c = normalizeInviteCode(code);
  return c.length == 10 ? '${c.substring(0, 5)}-${c.substring(5)}' : c;
}

class TeamRepository {
  final SupabaseClient client;
  const TeamRepository(this.client);

  Future<void> setStoreSync(String storeId, {required bool enabled}) =>
      client.rpc(
        'set_store_sync',
        params: {'p_store': storeId, 'p_enabled': enabled},
      );

  Future<String> createInvite(String storeId) async {
    try {
      return await client.rpc(
        'create_store_invite',
        params: {'p_store': storeId},
      ) as String;
    } on PostgrestException catch (e) {
      if (e.message.contains('too many active invites')) {
        throw const TeamException(
          'Sudah ada 5 undangan yang belum dipakai. Tunggu kedaluwarsa '
          '(48 jam) atau minta karyawan memakainya dulu.',
        );
      }
      rethrow;
    }
  }

  /// Id toko yang diikuti. Null bila kodenya salah, kedaluwarsa, atau sudah
  /// dipakai.
  Future<String?> acceptInvite(String code) async {
    try {
      return await client.rpc(
        'accept_store_invite',
        params: {'p_code': normalizeInviteCode(code)},
      ) as String?;
    } on PostgrestException catch (e) {
      if (e.code == '54000') {
        throw const TeamException(
          'Terlalu banyak percobaan hari ini. Coba lagi besok.',
        );
      }
      if (e.message.contains('own store')) {
        throw const TeamException('Ini kode untuk tokomu sendiri.');
      }
      if (e.message.contains('sync disabled')) {
        throw const TeamException(
          'Pemilik toko belum menyalakan sinkronisasi.',
        );
      }
      rethrow;
    }
  }

  Future<List<TeamMember>> members(String storeId) async {
    final rows = await client.rpc(
      'store_member_list',
      params: {'p_store': storeId},
    ) as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        TeamMember(
          userId: row['user_id'] as String,
          email: row['email'] as String? ?? '',
          joinedAt: DateTime.parse(row['joined_at'] as String).toLocal(),
        ),
    ];
  }

  Future<void> removeMember(String storeId, String userId) => client.rpc(
    'remove_store_member',
    params: {'p_store': storeId, 'p_user': userId},
  );

  Future<void> leaveStore(String storeId) =>
      client.rpc('leave_store', params: {'p_store': storeId});
}
