/// Transaksi yang sudah tersimpan di basis data lokal.
library;

import '../../../core/transaction_kind.dart';

class TxItemRecord {
  final String id;
  final String transactionId;
  final String name;
  final int qty;

  /// Harga per satuan. Bila pengguna menyebut harga total ("5 kg 200 ribu"),
  /// ini hasil pembagian yang dibulatkan — [lineTotal] tetap angka yang
  /// benar-benar dibayar dan jadi sumber kebenaran untuk semua penjumlahan.
  final int unitPrice;
  final int lineTotal;
  final String? unit;
  final String? productId;

  const TxItemRecord({
    required this.id,
    required this.transactionId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
    this.unit,
    this.productId,
  });

  Map<String, Object?> toRow() => {
    'id': id,
    'transaction_id': transactionId,
    'name': name,
    'qty': qty,
    'unit_price': unitPrice,
    'line_total': lineTotal,
    'unit': unit,
    'product_id': productId,
  };

  factory TxItemRecord.fromRow(Map<String, Object?> row) => TxItemRecord(
    id: row['id']! as String,
    transactionId: row['transaction_id']! as String,
    name: row['name']! as String,
    qty: (row['qty']! as num).toInt(),
    unitPrice: (row['unit_price']! as num).toInt(),
    lineTotal: (row['line_total']! as num).toInt(),
    unit: row['unit'] as String?,
    productId: row['product_id'] as String?,
  );
}

class TxRecord {
  final String id;
  final String storeId;
  final TxDirection direction;
  final TxCategory category;
  final DateTime occurredAt;
  final String? note;
  final TxSource source;
  final int totalAmount;
  final String? contactId;

  /// Dicatat belum dibayar (kasbon). Pemasukan = piutang pelanggan,
  /// pengeluaran = utang ke supplier.
  final bool onCredit;

  /// Jumlah yang sudah dibayar sejauh ini. Hanya bermakna bila [onCredit];
  /// diisi dari tabel pembayaran saat dibaca, bukan disimpan di baris ini.
  final int paidAmount;

  /// Hari jatuh tempo kasbon (awal hari), bila disepakati.
  final DateTime? dueAt;

  /// Email akun yang mencatat; kosong untuk catatan sebelum kolom ini ada.
  final String? recordedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TxItemRecord> items;

  const TxRecord({
    required this.id,
    required this.storeId,
    required this.direction,
    required this.category,
    required this.occurredAt,
    required this.source,
    required this.totalAmount,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    this.note,
    this.contactId,
    this.onCredit = false,
    this.paidAmount = 0,
    this.dueAt,
    this.recordedBy,
  });

  /// Sisa yang belum dibayar; 0 untuk transaksi tunai atau yang sudah lunas.
  int get outstanding =>
      onCredit ? (totalAmount - paidAmount).clamp(0, totalAmount) : 0;

  bool get isUnpaid => outstanding > 0;

  /// Belum lunas dan hari jatuh temponya sudah lewat.
  bool isOverdue(DateTime now) => daysOverdue(now) > 0;

  /// Berapa hari lewat jatuh tempo; 0 bila belum lewat, lunas, atau tanpa
  /// jatuh tempo.
  int daysOverdue(DateTime now) {
    final due = dueAt;
    if (!isUnpaid || due == null) return 0;
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    final days = today.difference(dueDay).inDays;
    return days > 0 ? days : 0;
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'store_id': storeId,
    'direction': direction.name,
    'category': category.dbName,
    'occurred_at': occurredAt.millisecondsSinceEpoch,
    'note': note,
    'source': source.name,
    'total_amount': totalAmount,
    'contact_id': contactId,
    'on_credit': onCredit ? 1 : 0,
    'due_at': dueAt?.millisecondsSinceEpoch,
    'recorded_by': recordedBy,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory TxRecord.fromRow(
    Map<String, Object?> row, {
    List<TxItemRecord> items = const [],
    int paidAmount = 0,
  }) {
    final direction = TxDirection.fromName(row['direction'] as String?)!;
    return TxRecord(
      id: row['id']! as String,
      storeId: row['store_id']! as String,
      direction: direction,
      category:
          TxCategory.fromDbName(row['category'] as String?) ??
          TxCategory.defaultFor(direction),
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        (row['occurred_at']! as num).toInt(),
      ),
      note: row['note'] as String?,
      source: TxSource.fromName(row['source']! as String),
      totalAmount: (row['total_amount']! as num).toInt(),
      contactId: row['contact_id'] as String?,
      onCredit: ((row['on_credit'] as num?) ?? 0) != 0,
      paidAmount: paidAmount,
      dueAt: row['due_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (row['due_at']! as num).toInt(),
            ),
      recordedBy: row['recorded_by'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at']! as num).toInt(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at']! as num).toInt(),
      ),
      items: items,
    );
  }
}
