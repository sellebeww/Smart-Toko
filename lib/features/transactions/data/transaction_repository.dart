/// Satu-satunya pintu penulisan transaksi.
///
/// Perhatikan tanda tangan [save] dan [replace]: keduanya hanya menerima
/// [ConfirmedDraft]. Tidak ada versi lain yang menerima hasil parser mentah,
/// jadi tidak ada cara menyimpan transaksi tanpa melewati layar konfirmasi.
///
/// Menyimpan transaksi juga merawat katalog dan stok: barang penjualan
/// tercatat sebagai menu, barang pembelian sebagai bahan (dan menambah
/// stoknya). Semuanya dalam satu transaksi basis data — tidak mungkin ada
/// transaksi tersimpan tanpa stoknya, atau sebaliknya.
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/dao/product_dao.dart';
import '../../../core/transaction_kind.dart';
import '../domain/confirmed_draft.dart';
import '../domain/transaction_record.dart';

class TransactionRepository {
  final AppDatabase database;
  final Uuid uuid;

  TransactionRepository({required this.database, Uuid? uuid})
    : uuid = uuid ?? const Uuid();

  Future<TxRecord> save(
    ConfirmedDraft confirmed, {
    required String storeId,
    String? recordedBy,
  }) {
    return database.db.transaction(
      (txn) =>
          _insert(txn, confirmed, storeId: storeId, recordedBy: recordedBy),
    );
  }

  /// Koreksi transaksi lama: yang lama dihapus dan versi terkoreksi disimpan
  /// dalam satu transaksi basis data, jadi stok dari pembelian lama ikut
  /// dibatalkan dan tidak pernah terhitung dua kali.
  Future<TxRecord> replace(
    String oldId,
    ConfirmedDraft confirmed, {
    required String storeId,
    String? recordedBy,
  }) {
    return database.db.transaction((txn) async {
      // Pembayaran utang menempel ke id transaksi, dan koreksi membuat id
      // baru; tanpa dipindahkan, CASCADE akan menghapus riwayat pembayaran.
      final payments = await txn.query(
        'debt_payments',
        where: 'transaction_id = ?',
        whereArgs: [oldId],
      );
      await txn.delete('transactions', where: 'id = ?', whereArgs: [oldId]);
      final record = await _insert(
        txn,
        confirmed,
        storeId: storeId,
        recordedBy: recordedBy,
      );
      if (record.onCredit) {
        for (final payment in payments) {
          await txn.insert('debt_payments', {
            ...payment,
            'transaction_id': record.id,
          });
        }
      }
      return record.onCredit ? _withPaid(txn, record) : record;
    });
  }

  Future<TxRecord> _insert(
    Transaction txn,
    ConfirmedDraft confirmed, {
    required String storeId,
    required String? recordedBy,
  }) async {
    final draft = confirmed.draft;
    final now = DateTime.now();
    final txId = uuid.v4();
    final category = draft.effectiveCategory!;
    final products = ProductDao(txn, uuid: uuid);

    final productKind = switch (category) {
      TxCategory.penjualan => ProductKind.menu,
      TxCategory.pembelian => ProductKind.bahan,
      // Pemasukan lain dan pengeluaran operasional (listrik, gas) bukan
      // barang dagangan, jadi tidak masuk katalog.
      TxCategory.pemasukanLain || TxCategory.pengeluaran => null,
    };

    final items = <TxItemRecord>[];
    for (final item in draft.items) {
      final name = item.name.value!.trim();
      final unitPrice = item.effectiveUnitPrice!;
      String? productId;
      if (productKind != null) {
        final product = await products.findOrCreate(
          storeId: storeId,
          kind: productKind,
          name: name,
          unit: item.unit,
          price: unitPrice,
          now: now,
        );
        productId = product.id;
      }
      items.add(
        TxItemRecord(
          id: uuid.v4(),
          transactionId: txId,
          name: name,
          qty: item.qty.value!,
          unitPrice: unitPrice,
          lineTotal: item.lineTotal!,
          unit: item.unit,
          productId: productId,
        ),
      );
    }

    final record = TxRecord(
      id: txId,
      storeId: storeId,
      direction: draft.direction.value!,
      category: category,
      occurredAt: draft.occurredAt,
      note: draft.note,
      source: draft.source,
      totalAmount: draft.total,
      contactId: draft.contactId,
      onCredit: draft.isCredit,
      recordedBy: recordedBy,
      createdAt: now,
      updatedAt: now,
      items: items,
    );

    await txn.insert('transactions', record.toRow());
    for (final item in items) {
      await txn.insert('transaction_items', item.toRow());
      if (category == TxCategory.pembelian && item.productId != null) {
        await products.addMovement(
          storeId: storeId,
          productId: item.productId!,
          qtyDelta: item.qty,
          reason: StockReason.pembelian,
          transactionItemId: item.id,
          occurredAt: record.occurredAt,
          now: now,
        );
      }
    }

    return record;
  }

  Future<List<TxRecord>> listBetween({
    required String storeId,
    required DateTime from,
    required DateTime to,
    Set<TxCategory>? categories,
    TxSource? source,
    String? contactId,
  }) async {
    final db = database.db;
    final where = <String>[
      'store_id = ?',
      'occurred_at >= ?',
      'occurred_at < ?',
    ];
    final args = <Object?>[
      storeId,
      from.millisecondsSinceEpoch,
      to.millisecondsSinceEpoch,
    ];
    if (categories != null && categories.isNotEmpty) {
      where.add(
        'category IN (${List.filled(categories.length, '?').join(',')})',
      );
      args.addAll(categories.map((c) => c.dbName));
    }
    if (source != null) {
      where.add('source = ?');
      args.add(source.name);
    }
    if (contactId != null) {
      where.add('contact_id = ?');
      args.add(contactId);
    }

    final rows = await db.query(
      'transactions',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'occurred_at DESC',
    );
    return _withItems(rows);
  }

  Future<TxRecord?> findById(String id) async {
    final rows = await database.db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final records = await _withItems(rows);
    return records.isEmpty ? null : records.first;
  }

  Future<List<TxRecord>> _withItems(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return const [];
    final ids = [for (final row in rows) row['id']! as String];
    final itemsByTx = <String, List<TxItemRecord>>{};
    // Dipotong per 500 supaya tidak menabrak batas parameter SQLite saat
    // riwayat yang diminta panjang.
    for (var start = 0; start < ids.length; start += 500) {
      final chunk = ids.sublist(
        start,
        start + 500 > ids.length ? ids.length : start + 500,
      );
      final itemRows = await database.db.query(
        'transaction_items',
        where:
            'transaction_id IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: chunk,
      );
      for (final row in itemRows) {
        final item = TxItemRecord.fromRow(row);
        itemsByTx.putIfAbsent(item.transactionId, () => []).add(item);
      }
    }

    final paidByTx = await _paidAmounts(database.db, ids);
    return [
      for (final row in rows)
        TxRecord.fromRow(
          row,
          items: itemsByTx[row['id']] ?? const [],
          paidAmount: paidByTx[row['id']] ?? 0,
        ),
    ];
  }

  static Future<Map<String, int>> _paidAmounts(
    DatabaseExecutor db,
    List<String> ids,
  ) async {
    final paid = <String, int>{};
    for (var start = 0; start < ids.length; start += 500) {
      final chunk = ids.sublist(
        start,
        start + 500 > ids.length ? ids.length : start + 500,
      );
      final rows = await db.rawQuery(
        'SELECT transaction_id AS id, SUM(amount) AS paid FROM debt_payments '
        'WHERE transaction_id IN (${List.filled(chunk.length, '?').join(',')}) '
        'GROUP BY transaction_id',
        chunk,
      );
      for (final row in rows) {
        paid[row['id']! as String] = (row['paid']! as num).toInt();
      }
    }
    return paid;
  }

  static Future<TxRecord> _withPaid(
    DatabaseExecutor db,
    TxRecord record,
  ) async {
    final paid = (await _paidAmounts(db, [record.id]))[record.id] ?? 0;
    return TxRecord(
      id: record.id,
      storeId: record.storeId,
      direction: record.direction,
      category: record.category,
      occurredAt: record.occurredAt,
      source: record.source,
      totalAmount: record.totalAmount,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      items: record.items,
      note: record.note,
      contactId: record.contactId,
      onCredit: record.onCredit,
      paidAmount: paid,
      recordedBy: record.recordedBy,
    );
  }

  /// Agregasi dikerjakan SQLite, bukan di Dart. Inilah alasan utama memilih
  /// basis data relasional: total harian tetap murah walau baris menumpuk.
  Future<int> totalBetween({
    required String storeId,
    required TxDirection direction,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await database.db.rawQuery(
      'SELECT COALESCE(SUM(total_amount), 0) AS total FROM transactions '
      'WHERE store_id = ? AND direction = ? AND occurred_at >= ? AND occurred_at < ?',
      [
        storeId,
        direction.name,
        from.millisecondsSinceEpoch,
        to.millisecondsSinceEpoch,
      ],
    );
    return (rows.first['total']! as num).toInt();
  }

  Future<int> countBetween({
    required String storeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await database.db.rawQuery(
      'SELECT COUNT(*) AS n FROM transactions '
      'WHERE store_id = ? AND occurred_at >= ? AND occurred_at < ?',
      [storeId, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );
    return (rows.first['n']! as num).toInt();
  }

  /// Item ikut terhapus lewat ON DELETE CASCADE, dan stok dari pembelian ini
  /// ikut dibatalkan karena pergerakan stoknya menempel ke item tersebut.
  Future<void> delete(String id) async {
    await database.db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }
}
