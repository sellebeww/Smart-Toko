/// Salinan lokal profil toko dari Supabase.
///
/// Sumber kebenaran profil toko tetap tabel `stores` di server. Salinan ini
/// hanya supaya aplikasi bisa langsung dibuka — dan tetap dipakai mencatat —
/// saat HP luring. Barisnya sekaligus memenuhi FK `transactions.store_id`.
library;

import 'package:sqflite/sqflite.dart';

import '../../verification/domain/verification_status.dart';
import '../domain/store_profile.dart';

class StoreCache {
  final DatabaseExecutor db;

  const StoreCache(this.db);

  /// Toko milik [ownerUid] dan toko tempat ia menjadi karyawan.
  Future<List<StoreProfile>> forOwner(String ownerUid) async {
    final rows = await db.query(
      'stores',
      where: 'owner_uid = ? OR member_uid = ?',
      whereArgs: [ownerUid, ownerUid],
      orderBy: 'created_at ASC',
    );
    return [for (final row in rows) _fromRow(row)];
  }

  /// [viewerUid]: pengguna yang sedang login. Toko yang bukan miliknya
  /// ditandai sebagai toko tempat ia bekerja, dan toko kerja yang tidak lagi
  /// ada di [stores] (dikeluarkan, atau sinkronisasi dimatikan pemilik)
  /// dihapus dari HP ini — tanpa dikirim sebagai penghapusan ke server.
  Future<void> saveAll(List<StoreProfile> stores, {String? viewerUid}) async {
    final batch = db.batch();
    for (final store in stores) {
      final row = _toRow(store)
        ..['member_uid'] = viewerUid == null || store.isOwnedBy(viewerUid)
            ? null
            : viewerUid;
      batch.insert('stores', row, conflictAlgorithm: ConflictAlgorithm.ignore);
      // Baris yang sudah ada diperbarui tanpa REPLACE: REPLACE di SQLite
      // menghapus baris lama dulu, dan ON DELETE CASCADE akan ikut menghapus
      // seluruh transaksi toko itu.
      batch.update(
        'stores',
        Map.of(row)..remove('id'),
        where: 'id = ?',
        whereArgs: [store.id],
      );
    }
    await batch.commit(noResult: true);

    if (viewerUid != null) {
      final keep = {for (final s in stores) s.id};
      final members = await db.query(
        'stores',
        columns: ['id'],
        where: 'member_uid = ?',
        whereArgs: [viewerUid],
      );
      for (final row in members) {
        final id = row['id']! as String;
        if (!keep.contains(id)) await removeCompletely(id);
      }
    }
  }

  /// Menghapus toko dan seluruh datanya dari HP ini. Pendaftaran sinkronnya
  /// dicabut lebih dulu, supaya hapus berantai tidak masuk antrean kirim.
  Future<void> removeCompletely(String storeId) async {
    await db.delete('sync_stores', where: 'store_id = ?', whereArgs: [storeId]);
    await db.delete(
      'sync_changes',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    await db.delete('stores', where: 'id = ?', whereArgs: [storeId]);
  }

  /// Menghapus semua toko akun ini dari HP — miliknya maupun tempat ia
  /// bekerja — beserta seluruh datanya, tanpa mengirim penghapusan apa pun
  /// lewat sinkronisasi.
  Future<void> deleteForOwner(String ownerUid) async {
    final rows = await db.query(
      'stores',
      columns: ['id'],
      where: 'owner_uid = ? OR member_uid = ?',
      whereArgs: [ownerUid, ownerUid],
    );
    for (final row in rows) {
      await removeCompletely(row['id']! as String);
    }
  }

  static Map<String, Object?> _toRow(StoreProfile store) => {
    'id': store.id,
    'owner_uid': store.ownerUid,
    'name': store.name,
    'category': store.category.name,
    'address': store.address,
    'verification_status': store.verificationStatus.name,
    'rejection_reason': store.rejectionReason,
    'created_at': store.createdAt.millisecondsSinceEpoch,
    'sync_enabled': store.syncEnabled ? 1 : 0,
  };

  static StoreProfile _fromRow(Map<String, Object?> row) => StoreProfile(
    id: row['id']! as String,
    ownerUid: row['owner_uid']! as String,
    name: row['name']! as String,
    category: StoreCategory.fromName(row['category'] as String?),
    address: row['address'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (row['created_at']! as num).toInt(),
    ),
    verificationStatus: StoreVerificationStatus.fromName(
      row['verification_status'] as String?,
    ),
    rejectionReason: row['rejection_reason'] as String?,
    syncEnabled: ((row['sync_enabled'] as num?) ?? 0) != 0,
  );
}
