/// Migrasi skema bernomor.
///
/// Setiap perubahan skema WAJIB jadi entri baru di [migrations] dengan nomor
/// versi naik, dan [schemaVersion] ikut dinaikkan. Migrasi lama tidak pernah
/// diubah isinya — perangkat pengguna sudah terlanjur menjalankannya.
library;

import 'package:sqflite/sqflite.dart';

const int schemaVersion = 5;

class Migration {
  final int version;
  final List<String> statements;

  const Migration(this.version, this.statements);

  Future<void> apply(Database db) async {
    for (final statement in statements) {
      await db.execute(statement);
    }
  }
}

const List<Migration> migrations = [
  Migration(1, [
    '''
    CREATE TABLE stores (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      verification_status TEXT NOT NULL DEFAULT 'unverified',
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      store_id TEXT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      direction TEXT NOT NULL CHECK (direction IN ('masuk','keluar')),
      occurred_at INTEGER NOT NULL,
      note TEXT,
      source TEXT NOT NULL CHECK (source IN ('voice','manual','qris')),
      total_amount INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_transactions_occurred_at ON transactions(occurred_at)',
    'CREATE INDEX idx_transactions_store ON transactions(store_id)',
    '''
    CREATE TABLE transaction_items (
      id TEXT PRIMARY KEY,
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      qty INTEGER NOT NULL,
      unit_price INTEGER NOT NULL,
      line_total INTEGER NOT NULL,
      field_confidence_json TEXT
    )
    ''',
    'CREATE INDEX idx_items_transaction ON transaction_items(transaction_id)',
    '''
    CREATE TABLE pending_sync (
      id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      op TEXT NOT NULL CHECK (op IN ('create','update','delete')),
      payload_json TEXT NOT NULL,
      attempt_count INTEGER NOT NULL DEFAULT 0,
      next_attempt_at INTEGER NOT NULL,
      last_error TEXT,
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','failed_permanent','done')),
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_pending_sync_due ON pending_sync(status, next_attempt_at)',
    '''
    CREATE TABLE parse_failures (
      id TEXT PRIMARY KEY,
      transcript TEXT NOT NULL,
      stt_confidence REAL,
      parser_version TEXT NOT NULL,
      reason TEXT NOT NULL,
      unmatched_tokens TEXT,
      created_at INTEGER NOT NULL,
      shared INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_parse_failures_created ON parse_failures(created_at)',
    '''
    CREATE TABLE consents (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      granted INTEGER NOT NULL,
      consent_text_version TEXT NOT NULL,
      granted_at INTEGER,
      revoked_at INTEGER
    )
    ''',
    'CREATE INDEX idx_consents_kind ON consents(kind)',
    '''
    CREATE TABLE app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ]),
  // Katalog produk, pelanggan/supplier, stok bahan, dan kategori transaksi.
  Migration(2, [
    // Katalog tumbuh sendiri dari transaksi (lihat TransactionRepository);
    // name_key = nama yang dinormalisasi supaya "Ayam Geprek" dan
    // "ayam geprek " dianggap produk yang sama.
    '''
    CREATE TABLE products (
      id TEXT PRIMARY KEY,
      store_id TEXT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('menu','bahan')),
      name TEXT NOT NULL,
      name_key TEXT NOT NULL,
      unit TEXT,
      default_price INTEGER,
      low_stock_threshold INTEGER,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE UNIQUE INDEX idx_products_key ON products(store_id, kind, name_key)',
    '''
    CREATE TABLE contacts (
      id TEXT PRIMARY KEY,
      store_id TEXT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('pelanggan','supplier')),
      name TEXT NOT NULL,
      location TEXT,
      phone TEXT,
      note TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_contacts_store ON contacts(store_id, kind)',
    // Stok = jumlah seluruh pergerakan, bukan satu angka yang ditimpa. Dengan
    // begitu riwayatnya bisa ditelusuri, dan menghapus transaksi pembelian
    // otomatis membatalkan penambahan stoknya (lewat CASCADE).
    '''
    CREATE TABLE stock_movements (
      id TEXT PRIMARY KEY,
      store_id TEXT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
      qty_delta INTEGER NOT NULL,
      reason TEXT NOT NULL
        CHECK (reason IN ('pembelian','pemakaian','penyesuaian')),
      transaction_item_id TEXT
        REFERENCES transaction_items(id) ON DELETE CASCADE,
      note TEXT,
      occurred_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_stock_product ON stock_movements(product_id)',
    '''
    ALTER TABLE transactions ADD COLUMN category TEXT NOT NULL
      DEFAULT 'penjualan'
      CHECK (category IN ('penjualan','pemasukan_lain','pembelian','pengeluaran'))
    ''',
    // Data lama hanya kenal arah. Pemasukan lama paling mungkin penjualan;
    // pengeluaran lama tidak bisa dipastikan belanja bahan, jadi dianggap
    // pengeluaran biasa agar tidak menambah stok yang tidak pernah ada.
    '''
    UPDATE transactions SET category =
      CASE direction WHEN 'masuk' THEN 'penjualan' ELSE 'pengeluaran' END
    ''',
    '''
    ALTER TABLE transactions ADD COLUMN contact_id TEXT
      REFERENCES contacts(id) ON DELETE SET NULL
    ''',
    '''
    CREATE INDEX idx_transactions_category
      ON transactions(store_id, category, occurred_at)
    ''',
    'ALTER TABLE transaction_items ADD COLUMN unit TEXT',
    '''
    ALTER TABLE transaction_items ADD COLUMN product_id TEXT
      REFERENCES products(id) ON DELETE SET NULL
    ''',
    'CREATE INDEX idx_items_product ON transaction_items(product_id)',
  ]),
  // Siapa yang mencatat (email akun). Baris lama dibiarkan kosong: tidak
  // bisa dipastikan siapa yang dulu mencatatnya.
  Migration(3, ['ALTER TABLE transactions ADD COLUMN recorded_by TEXT']),
  // Salinan profil toko dari server supaya aplikasi tetap bisa dibuka saat
  // luring. Antrean sinkron per transaksi diganti cadangan utuh per toko,
  // jadi tabelnya dibuang.
  Migration(4, [
    'ALTER TABLE stores ADD COLUMN owner_uid TEXT',
    'ALTER TABLE stores ADD COLUMN category TEXT',
    'ALTER TABLE stores ADD COLUMN address TEXT',
    'ALTER TABLE stores ADD COLUMN rejection_reason TEXT',
    'CREATE INDEX idx_stores_owner ON stores(owner_uid)',
    'DROP TABLE IF EXISTS pending_sync',
  ]),
  // Utang/piutang: transaksi bisa dicatat belum dibayar (on_credit), lalu
  // dilunasi bertahap lewat debt_payments. Sisa = total - jumlah pembayaran.
  // Baris lama tetap on_credit = 0 (tunai), jadi tidak ada yang berubah.
  Migration(5, [
    'ALTER TABLE transactions ADD COLUMN on_credit INTEGER NOT NULL DEFAULT 0',
    '''
    CREATE TABLE debt_payments (
      id TEXT PRIMARY KEY,
      store_id TEXT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      amount INTEGER NOT NULL CHECK (amount > 0),
      paid_at INTEGER NOT NULL,
      note TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_debt_payments_tx ON debt_payments(transaction_id)',
    'CREATE INDEX idx_transactions_credit ON transactions(store_id, on_credit)',
  ]),
];
