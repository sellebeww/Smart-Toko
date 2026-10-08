/// Jembatan ke tabel `stores` di Supabase (Postgres).
///
/// Klien hanya boleh menulis nama, kategori, dan alamat toko (hak kolom di
/// supabase/setup.sql). Status verifikasi hanya berubah lewat fungsi
/// `submit_store_verification` (pemilik) dan `review_store_verification`
/// (admin), yang memeriksa pemanggilnya di sisi server.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../verification/domain/pending_verification.dart';
import '../../verification/domain/verification_status.dart';
import '../domain/store_profile.dart';

class StoreRepository {
  final SupabaseClient _client;

  StoreRepository(this._client);

  SupabaseQueryBuilder get _stores => _client.from('stores');

  /// Realtime lewat `.stream()` butuh tabel `stores` di publication
  /// `supabase_realtime` — sudah termasuk di skrip SQL setup.
  Stream<List<StoreProfile>> watchStoresForUser(String ownerUid) {
    return _stores.stream(primaryKey: ['id']).eq('owner_uid', ownerUid).map((
      rows,
    ) {
      final stores = rows.map(StoreProfile.fromRow).toList();
      stores.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return stores;
    });
  }

  Future<void> create({
    required String id,
    required String ownerUid,
    required String name,
    required StoreCategory category,
    required String address,
  }) {
    return _stores
        .insert({
          'id': id,
          'owner_uid': ownerUid,
          'name': name,
          'category': category.name,
          'address': address,
        })
        .timeout(const Duration(seconds: 10));
  }

  Future<void> updateProfile(
    String id, {
    required String name,
    required StoreCategory category,
    required String address,
  }) {
    return _stores
        .update({'name': name, 'category': category.name, 'address': address})
        .eq('id', id)
        .timeout(const Duration(seconds: 10));
  }

  /// Server memeriksa bahwa pemanggil pemilik toko, statusnya boleh
  /// diajukan, dan ketiga foto wajib sudah terunggah. [consentVersion]
  /// dicatat bersama waktunya supaya jelas teks persetujuan mana yang
  /// disetujui pemilik saat menyerahkan KTP/selfie.
  Future<void> submitForVerification(
    String id, {
    required String consentVersion,
  }) async {
    await _client.rpc(
      'submit_store_verification',
      params: {'p_store_id': id, 'p_consent_version': consentVersion},
    );
  }

  Future<bool> isCurrentUserAdmin() async {
    final result = await _client.rpc('is_admin');
    return result == true;
  }

  /// Hanya berhasil untuk admin; selain itu server menolak.
  Future<List<PendingVerification>> pendingVerifications() async {
    final rows = await _client.rpc('admin_pending_verifications') as List;
    return [
      for (final row in rows)
        PendingVerification.fromRow(row as Map<String, dynamic>),
    ];
  }

  /// Hanya berhasil untuk admin dan hanya untuk pengajuan yang masih
  /// menunggu; keputusan dicatat di `verification_reviews`.
  Future<void> reviewVerification(
    String id, {
    required StoreVerificationStatus status,
    String? rejectionReason,
  }) async {
    await _client.rpc(
      'review_store_verification',
      params: {
        'p_store_id': id,
        'p_status': status.name,
        'p_reason': rejectionReason,
      },
    );
  }
}
