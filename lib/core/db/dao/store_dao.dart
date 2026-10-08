/// Akses data toko.
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Status verifikasi TIDAK membatasi fungsi apa pun.
///
/// Toko yang belum diverifikasi tetap bisa dipakai penuh; verifikasi hanya
/// menambah lencana. Ini yang menjaga agar pengumpulan data KTP tetap benar-
/// benar opsional, bukan syarat terselubung untuk memakai aplikasi.
enum VerificationStatus {
  unverified,
  pending,
  verified;

  static VerificationStatus fromName(String? value) => switch (value) {
    'pending' => VerificationStatus.pending,
    'verified' => VerificationStatus.verified,
    _ => VerificationStatus.unverified,
  };
}

class StoreRecord {
  final String id;
  final String name;
  final VerificationStatus verificationStatus;
  final DateTime createdAt;

  const StoreRecord({
    required this.id,
    required this.name,
    required this.verificationStatus,
    required this.createdAt,
  });

  factory StoreRecord.fromRow(Map<String, Object?> row) => StoreRecord(
    id: row['id']! as String,
    name: row['name']! as String,
    verificationStatus: VerificationStatus.fromName(
      row['verification_status'] as String?,
    ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (row['created_at']! as num).toInt(),
    ),
  );
}

class StoreDao {
  final DatabaseExecutor db;
  final Uuid uuid;

  StoreDao(this.db, {Uuid? uuid}) : uuid = uuid ?? const Uuid();

  Future<StoreRecord?> findById(String id) async {
    final rows = await db.query(
      'stores',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StoreRecord.fromRow(rows.first);
  }

  Future<StoreRecord?> first() async {
    final rows = await db.query('stores', orderBy: 'created_at ASC', limit: 1);
    if (rows.isEmpty) return null;
    return StoreRecord.fromRow(rows.first);
  }

  Future<StoreRecord> create({
    required String name,
    DateTime? createdAt,
  }) async {
    final record = StoreRecord(
      id: uuid.v4(),
      name: name,
      verificationStatus: VerificationStatus.unverified,
      createdAt: createdAt ?? DateTime.now(),
    );
    await db.insert('stores', {
      'id': record.id,
      'name': record.name,
      'verification_status': record.verificationStatus.name,
      'created_at': record.createdAt.millisecondsSinceEpoch,
    });
    return record;
  }

  Future<void> rename(String id, String name) async {
    await db.update('stores', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// Memastikan ada baris lokal dengan [id] ini, tanpa menimpa baris yang
  /// sudah ada. Dipakai saat toko kanoniknya datang dari Supabase (multi-
  /// toko per akun) tapi `transactions.store_id` tetap butuh baris lokal yang
  /// valid karena FK-nya menunjuk ke tabel `stores` di sini.
  Future<void> ensureExists(String id, String name) async {
    await db.insert('stores', {
      'id': id,
      'name': name,
      'verification_status': VerificationStatus.unverified.name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
