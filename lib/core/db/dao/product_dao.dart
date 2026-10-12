/// Akses katalog produk (menu & bahan) dan pergerakan stok.
///
/// Katalog tidak wajib diisi di depan: [findOrCreate] dipanggil setiap
/// transaksi disimpan, jadi daftar menu dan bahan tumbuh sendiri dari
/// pencatatan sehari-hari. Pengguna cukup merapikan (ganti nama, atur batas
/// stok) bila perlu.
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

enum ProductKind {
  /// Yang dijual ke pembeli (nasi ayam, es teh).
  menu('Menu', 'menu'),

  /// Yang dibeli untuk dimasak/dijual lagi; stoknya dilacak.
  bahan('Bahan', 'bahan');

  final String label;
  final String dbName;

  const ProductKind(this.label, this.dbName);

  static ProductKind fromDbName(String value) =>
      value == 'bahan' ? ProductKind.bahan : ProductKind.menu;
}

class ProductRecord {
  final String id;
  final String storeId;
  final ProductKind kind;
  final String name;
  final String? unit;

  /// Harga terakhir yang tercatat (jual untuk menu, beli untuk bahan).
  final int? defaultPrice;

  /// Stok di bawah angka ini ditandai menipis. Null = tidak dipantau.
  final int? lowStockThreshold;

  /// Modal per satuan (HPP) untuk menu. Null = belum diisi.
  final int? costPrice;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductRecord({
    required this.id,
    required this.storeId,
    required this.kind,
    required this.name,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    this.unit,
    this.defaultPrice,
    this.lowStockThreshold,
    this.costPrice,
  });

  /// Untung per satuan bila harga jual dan modal sama-sama diketahui.
  int? get unitProfit {
    final price = defaultPrice;
    final cost = costPrice;
    if (price == null || cost == null) return null;
    return price - cost;
  }

  /// Margin dalam persen dari harga jual, dibulatkan.
  int? get marginPercent {
    final profit = unitProfit;
    final price = defaultPrice;
    if (profit == null || price == null || price <= 0) return null;
    return (profit * 100 / price).round();
  }

  factory ProductRecord.fromRow(Map<String, Object?> row) => ProductRecord(
    id: row['id']! as String,
    storeId: row['store_id']! as String,
    kind: ProductKind.fromDbName(row['kind']! as String),
    name: row['name']! as String,
    unit: row['unit'] as String?,
    defaultPrice: (row['default_price'] as num?)?.toInt(),
    lowStockThreshold: (row['low_stock_threshold'] as num?)?.toInt(),
    costPrice: (row['cost_price'] as num?)?.toInt(),
    archived: (row['archived']! as num) != 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (row['created_at']! as num).toInt(),
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (row['updated_at']! as num).toInt(),
    ),
  );
}

enum StockReason {
  pembelian('Pembelian'),
  pemakaian('Pemakaian'),
  penyesuaian('Penyesuaian');

  final String label;

  const StockReason(this.label);

  static StockReason fromName(String value) => StockReason.values.firstWhere(
    (r) => r.name == value,
    orElse: () => StockReason.penyesuaian,
  );
}

class StockMovementRecord {
  final String id;
  final String productId;
  final int qtyDelta;
  final StockReason reason;
  final String? transactionItemId;
  final String? note;
  final DateTime occurredAt;

  const StockMovementRecord({
    required this.id,
    required this.productId,
    required this.qtyDelta,
    required this.reason,
    required this.occurredAt,
    this.transactionItemId,
    this.note,
  });

  factory StockMovementRecord.fromRow(Map<String, Object?> row) =>
      StockMovementRecord(
        id: row['id']! as String,
        productId: row['product_id']! as String,
        qtyDelta: (row['qty_delta']! as num).toInt(),
        reason: StockReason.fromName(row['reason']! as String),
        transactionItemId: row['transaction_item_id'] as String?,
        note: row['note'] as String?,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          (row['occurred_at']! as num).toInt(),
        ),
      );
}

/// Dilempar saat nama produk bentrok dengan produk lain sejenis di toko yang
/// sama.
class DuplicateProductNameException implements Exception {
  final String name;

  const DuplicateProductNameException(this.name);

  @override
  String toString() => 'Produk "$name" sudah ada';
}

const Object _keepCost = Object();

class ProductDao {
  /// Id barang baru ditentukan dari toko, jenis, dan namanya. Dua HP yang
  /// sama-sama mencatat "ayam" saat luring menghasilkan barang yang sama,
  /// sehingga sinkronisasi menggabungkannya alih-alih membuat dua "ayam".
  static String idFor(String storeId, ProductKind kind, String nameKey) =>
      const Uuid().v5(
        Namespace.url.value,
        'smarttoko:$storeId:${kind.dbName}:$nameKey',
      );

  final DatabaseExecutor db;
  final Uuid uuid;

  ProductDao(this.db, {Uuid? uuid}) : uuid = uuid ?? const Uuid();

  /// "Ayam  Geprek " dan "ayam geprek" adalah produk yang sama.
  static String nameKey(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Dipakai saat menyimpan transaksi. Produk yang sudah ada diperbarui harga
  /// terakhirnya (dan satuannya bila sebelumnya kosong), serta dimunculkan
  /// lagi bila sempat diarsipkan.
  Future<ProductRecord> findOrCreate({
    required String storeId,
    required ProductKind kind,
    required String name,
    required DateTime now,
    String? unit,
    int? price,
  }) async {
    final key = nameKey(name);
    final rows = await db.query(
      'products',
      where: 'store_id = ? AND kind = ? AND name_key = ?',
      whereArgs: [storeId, kind.dbName, key],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final existing = ProductRecord.fromRow(rows.first);
      await db.update(
        'products',
        {
          'default_price': ?price,
          if (existing.unit == null && unit != null) 'unit': unit,
          'archived': 0,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return existing;
    }

    final record = ProductRecord(
      id: idFor(storeId, kind, key),
      storeId: storeId,
      kind: kind,
      name: name.trim(),
      unit: unit,
      defaultPrice: price,
      archived: false,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('products', {
      'id': record.id,
      'store_id': storeId,
      'kind': kind.dbName,
      'name': record.name,
      'name_key': key,
      'unit': unit,
      'default_price': price,
      'archived': 0,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return record;
  }

  Future<List<ProductRecord>> list({
    required String storeId,
    ProductKind? kind,
    bool includeArchived = false,
  }) async {
    final where = <String>['store_id = ?'];
    final args = <Object?>[storeId];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.dbName);
    }
    if (!includeArchived) where.add('archived = 0');
    final rows = await db.query(
      'products',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'name_key ASC',
    );
    return [for (final row in rows) ProductRecord.fromRow(row)];
  }

  Future<ProductRecord?> findById(String id) async {
    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ProductRecord.fromRow(rows.first);
  }

  /// [lowStockThreshold] null berarti "jangan pantau". Karena itu nilainya
  /// selalu ditulis, tidak seperti field lain yang hanya ditulis bila diisi.
  Future<void> update(
    ProductRecord product, {
    required String name,
    required String? unit,
    required int? defaultPrice,
    required int? lowStockThreshold,
    required DateTime now,
    Object? costPrice = _keepCost,
  }) async {
    final key = nameKey(name);
    if (key != nameKey(product.name)) {
      final clash = await db.query(
        'products',
        columns: ['id'],
        where: 'store_id = ? AND kind = ? AND name_key = ? AND id != ?',
        whereArgs: [product.storeId, product.kind.dbName, key, product.id],
        limit: 1,
      );
      if (clash.isNotEmpty) throw DuplicateProductNameException(name.trim());
    }
    await db.update(
      'products',
      {
        'name': name.trim(),
        'name_key': key,
        'unit': (unit?.trim().isEmpty ?? true) ? null : unit!.trim(),
        'default_price': defaultPrice,
        'low_stock_threshold': lowStockThreshold,
        if (!identical(costPrice, _keepCost)) 'cost_price': costPrice as int?,
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [product.id],
    );
    if (costPrice is int) await _backfillCost(product.id, costPrice);
  }

  /// Penjualan lama yang belum punya modal ikut memakai modal baru, supaya
  /// laporan laba langsung berguna setelah modal pertama kali diisi.
  /// Penjualan yang sudah punya salinan modal tidak disentuh.
  Future<int> _backfillCost(String productId, int cost) => db.rawUpdate(
    'UPDATE transaction_items SET unit_cost = ? '
    'WHERE product_id = ? AND unit_cost IS NULL '
    'AND transaction_id IN '
    "(SELECT id FROM transactions WHERE category = 'penjualan')",
    [cost, productId],
  );

  Future<void> setArchived(String id, {required bool archived}) async {
    await db.update(
      'products',
      {'archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Stok tiap bahan = jumlah semua pergerakannya. Bahan tanpa pergerakan
  /// tidak muncul di peta ini (stoknya 0).
  Future<Map<String, int>> stockLevels(String storeId) async {
    final rows = await db.rawQuery(
      'SELECT product_id, COALESCE(SUM(qty_delta), 0) AS qty '
      'FROM stock_movements WHERE store_id = ? GROUP BY product_id',
      [storeId],
    );
    return {
      for (final row in rows)
        row['product_id']! as String: (row['qty']! as num).toInt(),
    };
  }

  Future<void> addMovement({
    required String storeId,
    required String productId,
    required int qtyDelta,
    required StockReason reason,
    required DateTime occurredAt,
    required DateTime now,
    String? transactionItemId,
    String? note,
  }) async {
    await db.insert('stock_movements', {
      'id': uuid.v4(),
      'store_id': storeId,
      'product_id': productId,
      'qty_delta': qtyDelta,
      'reason': reason.name,
      'transaction_item_id': transactionItemId,
      'note': note,
      'occurred_at': occurredAt.millisecondsSinceEpoch,
      'created_at': now.millisecondsSinceEpoch,
    });
  }

  Future<List<StockMovementRecord>> movements(
    String productId, {
    int limit = 50,
  }) async {
    final rows = await db.query(
      'stock_movements',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'occurred_at DESC, created_at DESC',
      limit: limit,
    );
    return [for (final row in rows) StockMovementRecord.fromRow(row)];
  }
}
