/// Migrasi skema bernomor.
///
/// Setiap perubahan skema WAJIB jadi entri baru di [migrations] dengan nomor
/// versi naik, dan [schemaVersion] ikut dinaikkan. Migrasi lama tidak pernah
/// diubah isinya — perangkat pengguna sudah terlanjur menjalankannya.
library;

import 'package:sqflite/sqflite.dart';

const int schemaVersion = 9;

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
  // Jatuh tempo kasbon: awal hari jatuh tempo (milidetik epoch), opsional.
  Migration(6, [
    'ALTER TABLE transactions ADD COLUMN due_at INTEGER',
    'CREATE INDEX idx_transactions_due ON transactions(store_id, due_at)',
  ]),
  // Modal (HPP) per menu, dan salinannya pada tiap penjualan supaya laba
  // masa lalu tidak ikut berubah saat modal diperbarui.
  Migration(7, [
    'ALTER TABLE products ADD COLUMN cost_price INTEGER',
    'ALTER TABLE transaction_items ADD COLUMN unit_cost INTEGER',
  ]),
  // Sinkronisasi antar-HP. Trigger mencatat setiap perubahan (termasuk
  // penghapusan berantai) ke sync_changes, hanya untuk toko yang
  // sinkronisasinya menyala di HP ini. Saat menerapkan data dari server,
  // sync_meta.applying = 1 supaya perubahan itu tidak dikirim balik.
  // Barang transaksi tidak punya store_id: tokonya dibaca dari induknya.
  // Bila induknya sudah terhapus (hapus berantai), server sendiri yang
  // menghapus barangnya.
  Migration(8, [
    'ALTER TABLE stores ADD COLUMN member_uid TEXT',
    'ALTER TABLE stores ADD COLUMN sync_enabled INTEGER NOT NULL DEFAULT 0',
    'CREATE INDEX idx_stores_member ON stores(member_uid)',
    '''
    CREATE TABLE sync_meta (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      applying INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'INSERT INTO sync_meta (id, applying) VALUES (1, 0)',
    '''
    CREATE TABLE sync_stores (
      store_id TEXT PRIMARY KEY,
      cursor INTEGER NOT NULL DEFAULT 0,
      last_synced_at INTEGER
    )
    ''',
    '''
    CREATE TABLE sync_changes (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      store_id TEXT NOT NULL,
      table_name TEXT NOT NULL,
      row_id TEXT NOT NULL,
      op TEXT NOT NULL CHECK (op IN ('upsert', 'delete'))
    )
    ''',
    'CREATE INDEX idx_sync_changes_store ON sync_changes(store_id, seq)',
    '''
    CREATE TRIGGER sync_products_insert AFTER INSERT ON products
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = NEW.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (NEW.store_id, 'products', NEW.id, 'upsert');
    END
    ''',
    '''
    CREATE TRIGGER sync_products_update AFTER UPDATE ON products
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = NEW.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (NEW.store_id, 'products', NEW.id, 'upsert');
    END
    ''',
    '''
    CREATE TRIGGER sync_products_delete AFTER DELETE ON products
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = OLD.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (OLD.store_id, 'products', OLD.id, 'delete');
    END
    ''',
    '''
    CREATE TRIGGER sync_contacts_insert AFTER INSERT ON contacts
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = NEW.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (NEW.store_id, 'contacts', NEW.id, 'upsert');
    END
    ''',
    '''
    CREATE TRIGGER sync_contacts_update AFTER UPDATE ON contacts
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = NEW.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (NEW.store_id, 'contacts', NEW.id, 'upsert');
    END
    ''',
    '''
    CREATE TRIGGER sync_contacts_delete AFTER DELETE ON contacts
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = OLD.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (OLD.store_id, 'contacts', OLD.id, 'delete');
    END
    ''',
    '''
    CREATE TRIGGER sync_transactions_insert AFTER INSERT ON transactions
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = NEW.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (NEW.store_id, 'transactions', NEW.id, 'upsert');
    END
    ''',
    '''
    CREATE TRIGGER sync_transactions_update AFTER UPDATE ON transactions
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = NEW.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (NEW.store_id, 'transactions', NEW.id, 'upsert');
    END
    ''',
    '''
    CREATE TRIGGER sync_transactions_delete AFTER DELETE ON transactions
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = OLD.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (OLD.store_id, 'transactions', OLD.id, 'delete');
    END
    ''',
    '''
    CREATE TRIGGER sync_stock_movements_insert AFTER INSERT ON stock_movements
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = NEW.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (NEW.store_id, 'stock_movements', NEW.id, 'upsert');
    END
    ''',
    '''
    CREATE TRIGGER sync_stock_movements_update AFTER UPDATE ON stock_movements
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = NEW.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (NEW.store_id, 'stock_movements', NEW.id, 'upsert');
    END
    ''',
    '''
    CREATE TRIGGER sync_stock_movements_delete AFTER DELETE ON stock_movements
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = OLD.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (OLD.store_id, 'stock_movements', OLD.id, 'delete');
    END
    ''',
    '''
    CREATE TRIGGER sync_debt_payments_insert AFTER INSERT ON debt_payments
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = NEW.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (NEW.store_id, 'debt_payments', NEW.id, 'upsert');
    END
    ''',
    '''
    CREATE TRIGGER sync_debt_payments_update AFTER UPDATE ON debt_payments
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = NEW.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (NEW.store_id, 'debt_payments', NEW.id, 'upsert');
    END
    ''',
    '''
    CREATE TRIGGER sync_debt_payments_delete AFTER DELETE ON debt_payments
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
      AND EXISTS (SELECT 1 FROM sync_stores WHERE store_id = OLD.store_id)
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      VALUES (OLD.store_id, 'debt_payments', OLD.id, 'delete');
    END
    ''',
    '''
    CREATE TRIGGER sync_transaction_items_insert AFTER INSERT ON transaction_items
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      SELECT t.store_id, 'transaction_items', NEW.id, 'upsert' FROM transactions t
      WHERE t.id = NEW.transaction_id
        AND EXISTS (SELECT 1 FROM sync_stores s WHERE s.store_id = t.store_id);
    END
    ''',
    '''
    CREATE TRIGGER sync_transaction_items_update AFTER UPDATE ON transaction_items
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      SELECT t.store_id, 'transaction_items', NEW.id, 'upsert' FROM transactions t
      WHERE t.id = NEW.transaction_id
        AND EXISTS (SELECT 1 FROM sync_stores s WHERE s.store_id = t.store_id);
    END
    ''',
    '''
    CREATE TRIGGER sync_transaction_items_delete AFTER DELETE ON transaction_items
    WHEN (SELECT applying FROM sync_meta WHERE id = 1) = 0
    BEGIN
      INSERT INTO sync_changes (store_id, table_name, row_id, op)
      SELECT t.store_id, 'transaction_items', OLD.id, 'delete' FROM transactions t
      WHERE t.id = OLD.transaction_id
        AND EXISTS (SELECT 1 FROM sync_stores s WHERE s.store_id = t.store_id);
    END
    ''',
  ]),
  // Foto barang: berkas di penyimpanan aplikasi HP ini saja. Tidak ikut
  // sinkronisasi maupun cadangan (lihat localOnlyColumns).
  Migration(9, ['ALTER TABLE products ADD COLUMN photo_path TEXT']),
];
