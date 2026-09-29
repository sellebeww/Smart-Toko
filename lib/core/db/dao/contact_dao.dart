/// Akses data pelanggan dan supplier.
///
/// Keduanya opsional di setiap transaksi. Menghapus kontak tidak menghapus
/// transaksinya — kolom contact_id di transaksi cukup menjadi kosong.
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

enum ContactKind {
  pelanggan('Pelanggan', 'pelanggan'),
  supplier('Supplier', 'supplier');

  final String label;
  final String dbName;

  const ContactKind(this.label, this.dbName);

  static ContactKind fromDbName(String value) =>
      value == 'supplier' ? ContactKind.supplier : ContactKind.pelanggan;
}

class ContactRecord {
  final String id;
  final String storeId;
  final ContactKind kind;
  final String name;
  final String? location;
  final String? phone;
  final String? note;
  final DateTime createdAt;

  const ContactRecord({
    required this.id,
    required this.storeId,
    required this.kind,
    required this.name,
    required this.createdAt,
    this.location,
    this.phone,
    this.note,
  });

  factory ContactRecord.fromRow(Map<String, Object?> row) => ContactRecord(
    id: row['id']! as String,
    storeId: row['store_id']! as String,
    kind: ContactKind.fromDbName(row['kind']! as String),
    name: row['name']! as String,
    location: row['location'] as String?,
    phone: row['phone'] as String?,
    note: row['note'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (row['created_at']! as num).toInt(),
    ),
  );
}

/// Ringkasan transaksi seorang kontak: dipakai daftar kontak untuk
/// menampilkan riwayat singkat tanpa query per baris.
class ContactStats {
  final int transactionCount;
  final int totalAmount;
  final DateTime? lastTransactionAt;

  const ContactStats({
    required this.transactionCount,
    required this.totalAmount,
    this.lastTransactionAt,
  });

  static const empty = ContactStats(transactionCount: 0, totalAmount: 0);
}

class ContactDao {
  final DatabaseExecutor db;
  final Uuid uuid;

  ContactDao(this.db, {Uuid? uuid}) : uuid = uuid ?? const Uuid();

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<List<ContactRecord>> list({
    required String storeId,
    ContactKind? kind,
  }) async {
    final rows = await db.query(
      'contacts',
      where: kind == null ? 'store_id = ?' : 'store_id = ? AND kind = ?',
      whereArgs: kind == null ? [storeId] : [storeId, kind.dbName],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return [for (final row in rows) ContactRecord.fromRow(row)];
  }

  Future<ContactRecord?> findById(String id) async {
    final rows = await db.query(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ContactRecord.fromRow(rows.first);
  }

  Future<ContactRecord> create({
    required String storeId,
    required ContactKind kind,
    required String name,
    required DateTime now,
    String? location,
    String? phone,
    String? note,
  }) async {
    final record = ContactRecord(
      id: uuid.v4(),
      storeId: storeId,
      kind: kind,
      name: name.trim(),
      location: _clean(location),
      phone: _clean(phone),
      note: _clean(note),
      createdAt: now,
    );
    await db.insert('contacts', {
      'id': record.id,
      'store_id': storeId,
      'kind': kind.dbName,
      'name': record.name,
      'location': record.location,
      'phone': record.phone,
      'note': record.note,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return record;
  }

  Future<void> update(
    String id, {
    required String name,
    required DateTime now,
    String? location,
    String? phone,
    String? note,
  }) async {
    await db.update(
      'contacts',
      {
        'name': name.trim(),
        'location': _clean(location),
        'phone': _clean(phone),
        'note': _clean(note),
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    await db.delete('contacts', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, ContactStats>> stats(String storeId) async {
    final rows = await db.rawQuery(
      'SELECT contact_id, COUNT(*) AS n, COALESCE(SUM(total_amount), 0) AS total, '
      'MAX(occurred_at) AS last_at FROM transactions '
      'WHERE store_id = ? AND contact_id IS NOT NULL GROUP BY contact_id',
      [storeId],
    );
    return {
      for (final row in rows)
        row['contact_id']! as String: ContactStats(
          transactionCount: (row['n']! as num).toInt(),
          totalAmount: (row['total']! as num).toInt(),
          lastTransactionAt: row['last_at'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (row['last_at']! as num).toInt(),
                ),
        ),
    };
  }
}
