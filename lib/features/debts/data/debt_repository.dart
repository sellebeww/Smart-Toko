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

  /// Bagian sisa yang sudah lewat jatuh tempo.
  final int overdue;

  /// Jatuh tempo terdekat di antara yang belum lunas, bila ada.
  final DateTime? nextDue;

  const ContactBalance({
    required this.contactId,
    required this.name,
    required this.direction,
    required this.outstanding,
    required this.openCount,
    required this.oldest,
    this.overdue = 0,
    this.nextDue,
  });

  bool get isOverdue => overdue > 0;
}

/// Kasbon yang jatuh tempo pada rentang tertentu (untuk pengingat).
class DueDebt {
  final String transactionId;
  final String contactName;
  final TxDirection direction;
  final int outstanding;
  final DateTime dueAt;

  const DueDebt({
    required this.transactionId,
    required this.contactName,
    required this.direction,
    required this.outstanding,
    required this.dueAt,
  });
}

/// Rekam jejak bayar satu kontak: bahan pertimbangan sebelum memberi kasbon
/// lagi. Hanya menghitung kasbon yang sudah lunas.
class PaymentRecord {
  final int settled;

  /// Yang lunas dan memang punya jatuh tempo — dasar penilaian tepat waktu.
  final int withDueDate;

  /// Lunas setelah hari jatuh temponya lewat.
  final int late;

  /// Rata-rata hari dari transaksi sampai lunas; null bila belum ada.
  final double? averageDaysToSettle;

  const PaymentRecord({
    this.settled = 0,
    this.withDueDate = 0,
    this.late = 0,
    this.averageDaysToSettle,
  });
}

class DebtTotals {
  /// Uang yang masih harus diterima dari pelanggan.
  final int receivable;

  /// Uang yang masih harus dibayar ke supplier.
  final int payable;

  /// Bagian [receivable] dan [payable] yang sudah lewat jatuh tempo.
  final int overdueReceivable;
  final int overduePayable;

  const DebtTotals({
    this.receivable = 0,
    this.payable = 0,
    this.overdueReceivable = 0,
    this.overduePayable = 0,
  });

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

  static int _todayMillis(DateTime? now) {
    final n = now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day).millisecondsSinceEpoch;
  }

  /// Sisa yang sudah lewat jatuh tempo, sebagai ekspresi SQL. Parameter
  /// pertama yang diikat adalah awal hari ini.
  static const String _overdueSql =
      'CASE WHEN t.due_at IS NOT NULL AND t.due_at < ?1 '
      'THEN $_outstandingSql ELSE 0 END';

  Future<DebtTotals> totals(String storeId, {DateTime? now}) async {
    final rows = await database.db.rawQuery(
      'SELECT t.direction AS direction, '
      'COALESCE(SUM($_outstandingSql), 0) AS outstanding, '
      'COALESCE(SUM($_overdueSql), 0) AS overdue '
      'FROM transactions t WHERE t.store_id = ?2 AND t.on_credit = 1 '
      'GROUP BY t.direction',
      [_todayMillis(now), storeId],
    );
    var receivable = 0, payable = 0, overdueIn = 0, overdueOut = 0;
    for (final row in rows) {
      final amount = (row['outstanding']! as num).toInt();
      final overdue = (row['overdue']! as num).toInt();
      if (row['direction'] == TxDirection.masuk.name) {
        receivable = amount;
        overdueIn = overdue;
      } else {
        payable = amount;
        overdueOut = overdue;
      }
    }
    return DebtTotals(
      receivable: receivable,
      payable: payable,
      overdueReceivable: overdueIn,
      overduePayable: overdueOut,
    );
  }

  /// Sisa per kontak: yang sudah telat dulu, lalu terbesar. Kontak tanpa
  /// sisa tidak muncul.
  Future<List<ContactBalance>> balances(String storeId, {DateTime? now}) async {
    final rows = await database.db.rawQuery(
      'SELECT t.contact_id AS contact_id, c.name AS name, '
      't.direction AS direction, '
      'SUM($_outstandingSql) AS outstanding, '
      'SUM($_overdueSql) AS overdue, '
      'SUM(CASE WHEN $_outstandingSql > 0 THEN 1 ELSE 0 END) AS open_count, '
      'MIN(CASE WHEN $_outstandingSql > 0 THEN t.occurred_at END) AS oldest, '
      'MIN(CASE WHEN $_outstandingSql > 0 THEN t.due_at END) AS next_due '
      'FROM transactions t JOIN contacts c ON c.id = t.contact_id '
      'WHERE t.store_id = ?2 AND t.on_credit = 1 '
      'GROUP BY t.contact_id, t.direction '
      'HAVING outstanding > 0 '
      'ORDER BY overdue > 0 DESC, outstanding DESC',
      [_todayMillis(now), storeId],
    );
    return [
      for (final row in rows)
        ContactBalance(
          contactId: row['contact_id']! as String,
          name: row['name']! as String,
          direction: TxDirection.fromName(row['direction']! as String)!,
          outstanding: (row['outstanding']! as num).toInt(),
          overdue: (row['overdue']! as num).toInt(),
          openCount: (row['open_count']! as num).toInt(),
          oldest: DateTime.fromMillisecondsSinceEpoch(
            (row['oldest']! as num).toInt(),
          ),
          nextDue: row['next_due'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (row['next_due']! as num).toInt(),
                ),
        ),
    ];
  }

  /// Mengubah atau menghapus ([dueAt] null) jatuh tempo satu kasbon.
  Future<void> setDueDate(String transactionId, DateTime? dueAt) async {
    final day = dueAt == null
        ? null
        : DateTime(dueAt.year, dueAt.month, dueAt.day);
    final updated = await database.db.update(
      'transactions',
      {
        'due_at': day?.millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ? AND on_credit = 1',
      whereArgs: [transactionId],
    );
    if (updated == 0) {
      throw const DebtException('Jatuh tempo hanya untuk transaksi kasbon.');
    }
  }

  /// Kasbon belum lunas yang jatuh tempo pada [from, to) — termasuk yang
  /// sudah lewat bila [from] di masa lalu. Terlama dulu.
  Future<List<DueDebt>> dueBetween(
    String storeId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await database.db.rawQuery(
      'SELECT t.id AS id, c.name AS name, t.direction AS direction, '
      't.due_at AS due_at, $_outstandingSql AS outstanding '
      'FROM transactions t JOIN contacts c ON c.id = t.contact_id '
      'WHERE t.store_id = ? AND t.on_credit = 1 AND t.due_at IS NOT NULL '
      'AND t.due_at >= ? AND t.due_at < ? AND $_outstandingSql > 0 '
      'ORDER BY t.due_at',
      [storeId, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );
    return [
      for (final row in rows)
        DueDebt(
          transactionId: row['id']! as String,
          contactName: row['name']! as String,
          direction: TxDirection.fromName(row['direction']! as String)!,
          outstanding: (row['outstanding']! as num).toInt(),
          dueAt: DateTime.fromMillisecondsSinceEpoch(
            (row['due_at']! as num).toInt(),
          ),
        ),
    ];
  }

  /// Rekam jejak bayar [contactId] dari kasbon yang sudah lunas.
  Future<PaymentRecord> paymentRecord(String storeId, String contactId) async {
    final rows = await database.db.rawQuery(
      'SELECT t.occurred_at AS occurred_at, t.due_at AS due_at, '
      't.total_amount AS total, '
      '(SELECT SUM(p.amount) FROM debt_payments p WHERE p.transaction_id = t.id) AS paid, '
      '(SELECT MAX(p.paid_at) FROM debt_payments p WHERE p.transaction_id = t.id) AS settled_at '
      'FROM transactions t '
      'WHERE t.store_id = ? AND t.contact_id = ? AND t.on_credit = 1',
      [storeId, contactId],
    );
    var settled = 0, late = 0, withDue = 0;
    var totalDays = 0;
    for (final row in rows) {
      final paid = (row['paid'] as num?)?.toInt() ?? 0;
      final total = (row['total']! as num).toInt();
      final settledAt = row['settled_at'] as num?;
      if (settledAt == null || paid < total) continue;
      settled++;
      final settledDay = _day(settledAt.toInt());
      totalDays += settledDay
          .difference(_day((row['occurred_at']! as num).toInt()))
          .inDays;
      final due = row['due_at'] as num?;
      if (due != null) {
        withDue++;
        if (settledDay.isAfter(_day(due.toInt()))) late++;
      }
    }
    return PaymentRecord(
      settled: settled,
      withDueDate: withDue,
      late: late,
      averageDaysToSettle: settled == 0 ? null : totalDays / settled,
    );
  }

  static DateTime _day(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime(d.year, d.month, d.day);
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
