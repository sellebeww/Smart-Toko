/// Utang dan piutang (kasbon).
///
/// Transaksi yang dicatat belum dibayar tetap terhitung sebagai omzet atau
/// biaya pada tanggalnya; pembayarannya dicatat terpisah di sini. Sisa
/// = total transaksi − jumlah pembayaran, dihitung SQLite, tidak disimpan di
/// satu kolom yang bisa menyimpang dari riwayat pembayarannya.
library;

import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/transaction_kind.dart';

class DebtPayment {
  final String id;
  final String transactionId;
  final int amount;
  final DateTime paidAt;
  final String? note;

  const DebtPayment({
    required this.id,
    required this.transactionId,
    required this.amount,
    required this.paidAt,
    this.note,
  });

  factory DebtPayment.fromRow(Map<String, Object?> row) => DebtPayment(
    id: row['id']! as String,
    transactionId: row['transaction_id']! as String,
    amount: (row['amount']! as num).toInt(),
    paidAt: DateTime.fromMillisecondsSinceEpoch(
      (row['paid_at']! as num).toInt(),
    ),
    note: row['note'] as String?,
  );
}

/// Ringkasan sisa utang/piutang satu kontak.
class ContactBalance {
  final String contactId;
  final String name;

  /// Pemasukan belum dibayar = piutang (pelanggan berutang ke toko);
  /// pengeluaran belum dibayar = utang (toko berutang ke supplier).
  final TxDirection direction;
  final int outstanding;
  final int openCount;

  /// Tanggal transaksi belum lunas yang paling lama.
  final DateTime oldest;

  const ContactBalance({
    required this.contactId,
    required this.name,
    required this.direction,
    required this.outstanding,
    required this.openCount,
    required this.oldest,
  });
}

class DebtTotals {
  /// Uang yang masih harus diterima dari pelanggan.
  final int receivable;

  /// Uang yang masih harus dibayar ke supplier.
  final int payable;

  const DebtTotals({this.receivable = 0, this.payable = 0});

  bool get isEmpty => receivable == 0 && payable == 0;
}

class DebtException implements Exception {
  final String message;
  const DebtException(this.message);

  @override
  String toString() => message;
}

class DebtRepository {
  final AppDatabase database;
  final Uuid uuid;

  DebtRepository({required this.database, Uuid? uuid})
    : uuid = uuid ?? const Uuid();

  static const String _outstandingSql =
      'MAX(t.total_amount - COALESCE('
      '(SELECT SUM(p.amount) FROM debt_payments p '
      'WHERE p.transaction_id = t.id), 0), 0)';

  Future<List<DebtPayment>> paymentsFor(String transactionId) async {
    final rows = await database.db.query(
      'debt_payments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'paid_at DESC, created_at DESC',
    );
    return [for (final row in rows) DebtPayment.fromRow(row)];
  }

  /// Mencatat pembayaran. Ditolak bila melebihi sisa, supaya salah ketik
  /// tidak membuat saldo negatif yang diam-diam menutupi utang lain.
  Future<DebtPayment> addPayment({
    required String storeId,
    required String transactionId,
    required int amount,
    DateTime? paidAt,
    String? note,
  }) async {
    if (amount <= 0) {
      throw const DebtException('Jumlah pembayaran harus lebih dari nol.');
    }
    return database.db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT t.on_credit AS on_credit, '
        '$_outstandingSql AS outstanding '
        'FROM transactions t WHERE t.id = ? AND t.store_id = ?',
        [transactionId, storeId],
      );
      if (rows.isEmpty) {
        throw const DebtException('Transaksi tidak ditemukan.');
      }
      if (((rows.first['on_credit']! as num).toInt()) == 0) {
        throw const DebtException('Transaksi ini bukan kasbon.');
      }
      final outstanding = (rows.first['outstanding']! as num).toInt();
      if (outstanding == 0) {
        throw const DebtException('Transaksi ini sudah lunas.');
      }
      if (amount > outstanding) {
        throw DebtException('Melebihi sisa yang harus dibayar.');
      }
      final now = DateTime.now();
      final payment = DebtPayment(
        id: uuid.v4(),
        transactionId: transactionId,
        amount: amount,
        paidAt: paidAt ?? now,
        note: note == null || note.trim().isEmpty ? null : note.trim(),
      );
      await txn.insert('debt_payments', {
        'id': payment.id,
        'store_id': storeId,
        'transaction_id': payment.transactionId,
        'amount': payment.amount,
        'paid_at': payment.paidAt.millisecondsSinceEpoch,
        'note': payment.note,
        'created_at': now.millisecondsSinceEpoch,
      });
      // Menyentuh updated_at supaya cadangan otomatis ikut mengunggah.
      await txn.update(
        'transactions',
        {'updated_at': now.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [transactionId],
      );
      return payment;
    });
  }

  Future<void> deletePayment(String paymentId) async {
    await database.db.transaction((txn) async {
      final rows = await txn.query(
        'debt_payments',
        columns: ['transaction_id'],
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      if (rows.isEmpty) return;
      await txn.delete(
        'debt_payments',
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      await txn.update(
        'transactions',
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [rows.first['transaction_id']],
      );
    });
  }

  Future<DebtTotals> totals(String storeId) async {
    final rows = await database.db.rawQuery(
      'SELECT t.direction AS direction, '
      'COALESCE(SUM($_outstandingSql), 0) AS outstanding '
      'FROM transactions t WHERE t.store_id = ? AND t.on_credit = 1 '
      'GROUP BY t.direction',
      [storeId],
    );
    var receivable = 0;
    var payable = 0;
    for (final row in rows) {
      final amount = (row['outstanding']! as num).toInt();
      if (row['direction'] == TxDirection.masuk.name) {
        receivable = amount;
      } else {
        payable = amount;
      }
    }
    return DebtTotals(receivable: receivable, payable: payable);
  }

  /// Sisa per kontak, terbesar dulu. Kontak tanpa sisa tidak muncul.
  Future<List<ContactBalance>> balances(String storeId) async {
    final rows = await database.db.rawQuery(
      'SELECT t.contact_id AS contact_id, c.name AS name, '
      't.direction AS direction, '
      'SUM($_outstandingSql) AS outstanding, '
      'SUM(CASE WHEN $_outstandingSql > 0 THEN 1 ELSE 0 END) AS open_count, '
      'MIN(CASE WHEN $_outstandingSql > 0 THEN t.occurred_at END) AS oldest '
      'FROM transactions t JOIN contacts c ON c.id = t.contact_id '
      'WHERE t.store_id = ? AND t.on_credit = 1 '
      'GROUP BY t.contact_id, t.direction '
      'HAVING outstanding > 0 '
      'ORDER BY outstanding DESC',
      [storeId],
    );
    return [
      for (final row in rows)
        ContactBalance(
          contactId: row['contact_id']! as String,
          name: row['name']! as String,
          direction: TxDirection.fromName(row['direction']! as String)!,
          outstanding: (row['outstanding']! as num).toInt(),
          openCount: (row['open_count']! as num).toInt(),
          oldest: DateTime.fromMillisecondsSinceEpoch(
            (row['oldest']! as num).toInt(),
          ),
        ),
    ];
  }

  /// Sisa satu kontak, dipakai di detail kontak.
  Future<int> outstandingFor(String storeId, String contactId) async {
    final rows = await database.db.rawQuery(
      'SELECT COALESCE(SUM($_outstandingSql), 0) AS outstanding '
      'FROM transactions t '
      'WHERE t.store_id = ? AND t.contact_id = ? AND t.on_credit = 1',
      [storeId, contactId],
    );
    return (rows.first['outstanding']! as num).toInt();
  }
}
