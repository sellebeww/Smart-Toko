/// Jembatan ke tabel `stores` di Supabase (Postgres).
///
/// Realtime lewat `.stream()` butuh tabel `stores` didaftarkan ke publication
/// `supabase_realtime` — sudah termasuk di skrip SQL setup.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../verification/domain/verification_status.dart';
import '../domain/store_profile.dart';

class StoreRepository {
  final SupabaseClient _client;

  StoreRepository(this._client);

  SupabaseQueryBuilder get _stores => _client.from('stores');

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
        .timeout(const Duration(seconds: 8));
  }

  Stream<StoreProfile> watchStore(String id) {
    return _stores
        .stream(primaryKey: ['id'])
        .eq('id', id)
        // Toko baru dijadikan aktif sedikit sebelum barisnya ditulis (lihat
        // AddStoreScreen), jadi snapshot pertama bisa saja masih kosong.
        .where((rows) => rows.isNotEmpty)
        .map((rows) => StoreProfile.fromRow(rows.first));
  }

  /// Dipanggil admin (lihat AdminVerificationScreen) lewat fungsi Postgres
  /// `review_store_verification` — bukan UPDATE langsung ke tabel, supaya
  /// user lain hanya bisa mengubah status verifikasi dan tidak bisa menyentuh
  /// kolom lain milik toko orang. Ini SIMULASI untuk demo, tidak ada
  /// pemeriksaan role admin sungguhan; lihat catatan di skrip SQL setup.
  Future<void> setVerificationStatus(
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

  /// [consentVersion] dicatat bersama waktunya supaya jelas teks persetujuan
  /// mana yang disetujui pemilik saat menyerahkan KTP/selfie.
  Future<void> submitForVerification(
    String id, {
    required String consentVersion,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _stores
        .update({
          'verification_status': StoreVerificationStatus.pending.name,
          'rejection_reason': null,
          'verification_submitted_at': now,
          'identity_consent_version': consentVersion,
          'identity_consent_at': now,
        })
        .eq('id', id);
  }

  /// Dipakai AdminVerificationScreen: semua toko (lintas akun) yang sedang
  /// menunggu ditinjau.
  Stream<List<StoreProfile>> watchPendingStores() {
    return _stores
        .stream(primaryKey: ['id'])
        .eq('verification_status', StoreVerificationStatus.pending.name)
        .map((rows) => rows.map(StoreProfile.fromRow).toList());
  }
}
