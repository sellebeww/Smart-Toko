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

  Future<List<StoreProfile>> forOwner(String ownerUid) async {
    final rows = await db.query(
      'stores',
      where: 'owner_uid = ?',
      whereArgs: [ownerUid],
      orderBy: 'created_at ASC',
    );
    return [for (final row in rows) _fromRow(row)];
  }

  Future<void> saveAll(List<StoreProfile> stores) async {
    final batch = db.batch();
    for (final store in stores) {
      batch.insert(
        'stores',
        _toRow(store),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      // Baris yang sudah ada diperbarui tanpa REPLACE: REPLACE di SQLite
      // menghapus baris lama dulu, dan ON DELETE CASCADE akan ikut menghapus
      // seluruh transaksi toko itu.
      batch.update(
        'stores',
        _toRow(store)..remove('id'),
        where: 'id = ?',
        whereArgs: [store.id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Menghapus toko beserta seluruh datanya di HP ini (lewat CASCADE).
  Future<void> deleteForOwner(String ownerUid) async {
    await db.delete('stores', where: 'owner_uid = ?', whereArgs: [ownerUid]);
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
  );
}
