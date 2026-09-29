/// Agregasi untuk dasbor laporan. Semua penjumlahan dikerjakan SQLite.
library;

import 'package:sqflite/sqflite.dart';

import '../../../core/transaction_kind.dart';

class CategoryTotals {
  final Map<TxCategory, int> amounts;
  final int count;

  const CategoryTotals({required this.amounts, required this.count});

  static const empty = CategoryTotals(amounts: {}, count: 0);

  int of(TxCategory c) => amounts[c] ?? 0;

  /// Penjualan saja — "omzet" pada deck.
  int get omzet => of(TxCategory.penjualan);

  int get pemasukan => omzet + of(TxCategory.pemasukanLain);

  int get pengeluaran => of(TxCategory.pembelian) + of(TxCategory.pengeluaran);

  /// Perkiraan kas: uang masuk − uang keluar. Bukan laba akuntansi, karena
  /// bahan yang dibeli hari ini bisa terpakai berhari-hari.
  int get keuntungan => pemasukan - pengeluaran;
}

class ItemAggregate {
  final String name;
  final String? unit;
  final int qty;
  final int amount;

  const ItemAggregate({
    required this.name,
    required this.qty,
    required this.amount,
    this.unit,
  });
}

class ReportRepository {
  final DatabaseExecutor db;

  const ReportRepository(this.db);

  Future<CategoryTotals> totals({
    required String storeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await db.rawQuery(
      'SELECT category, COALESCE(SUM(total_amount), 0) AS total, '
      'COUNT(*) AS n FROM transactions '
      'WHERE store_id = ? AND occurred_at >= ? AND occurred_at < ? '
      'GROUP BY category',
      [storeId, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );
    final amounts = <TxCategory, int>{};
    var count = 0;
    for (final row in rows) {
      final category = TxCategory.fromDbName(row['category'] as String?);
      if (category == null) continue;
      amounts[category] = (row['total']! as num).toInt();
      count += (row['n']! as num).toInt();
    }
    return CategoryTotals(amounts: amounts, count: count);
  }

  /// Barang per kategori, diurutkan dari yang paling banyak ([byQty]) atau
  /// paling besar nilainya. Barang yang sama digabung lewat katalog, atau
  /// lewat namanya bila tidak tercatat di katalog.
  Future<List<ItemAggregate>> topItems({
    required String storeId,
    required DateTime from,
    required DateTime to,
    required Set<TxCategory> categories,
    bool byQty = true,
    int limit = 5,
  }) async {
    final placeholders = List.filled(categories.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT MAX(i.name) AS name, MAX(i.unit) AS unit, '
      'SUM(i.qty) AS qty, SUM(i.line_total) AS amount '
      'FROM transaction_items i JOIN transactions t ON t.id = i.transaction_id '
      'WHERE t.store_id = ? AND t.occurred_at >= ? AND t.occurred_at < ? '
      'AND t.category IN ($placeholders) '
      'GROUP BY COALESCE(i.product_id, LOWER(TRIM(i.name))) '
      'ORDER BY ${byQty ? 'qty' : 'amount'} DESC, amount DESC '
      'LIMIT ?',
      [
        storeId,
        from.millisecondsSinceEpoch,
        to.millisecondsSinceEpoch,
        ...categories.map((c) => c.dbName),
        limit,
      ],
    );
    return [
      for (final row in rows)
        ItemAggregate(
          name: row['name']! as String,
          unit: row['unit'] as String?,
          qty: (row['qty']! as num).toInt(),
          amount: (row['amount']! as num).toInt(),
        ),
    ];
  }

  /// Pemasukan dan pengeluaran per hari (kunci: tengah malam waktu lokal),
  /// untuk grafik batang. Pengelompokan dilakukan di Dart karena SQLite
  /// tidak tahu zona waktu perangkat.
  Future<Map<DateTime, ({int masuk, int keluar})>> daily({
    required String storeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await db.rawQuery(
      'SELECT occurred_at, direction, total_amount FROM transactions '
      'WHERE store_id = ? AND occurred_at >= ? AND occurred_at < ?',
      [storeId, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );
    final result = <DateTime, ({int masuk, int keluar})>{};
    for (final row in rows) {
      final at = DateTime.fromMillisecondsSinceEpoch(
        (row['occurred_at']! as num).toInt(),
      );
      final day = DateTime(at.year, at.month, at.day);
      final amount = (row['total_amount']! as num).toInt();
      final prev = result[day] ?? (masuk: 0, keluar: 0);
      result[day] = row['direction'] == TxDirection.masuk.name
          ? (masuk: prev.masuk + amount, keluar: prev.keluar)
          : (masuk: prev.masuk, keluar: prev.keluar + amount);
    }
    return result;
  }
}
