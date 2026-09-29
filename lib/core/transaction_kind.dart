/// Kosakata bersama untuk jenis transaksi.
///
/// Diletakkan di core karena dipakai parser maupun lapisan transaksi; kalau
/// ditaruh di salah satunya, yang lain jadi bergantung ke fitur tetangga.
library;

enum TxDirection {
  masuk,
  keluar;

  static TxDirection? fromName(String? value) => switch (value) {
    'masuk' => TxDirection.masuk,
    'keluar' => TxDirection.keluar,
    _ => null,
  };
}

/// Kategori operasional, satu tingkat di bawah arah.
///
/// Arah (masuk/keluar) tetap disimpan terpisah karena seluruh total harian
/// dihitung dari situ; kategori membedakan hal yang arahnya sama tapi artinya
/// beda untuk laporan — belanja bahan (menambah stok) bukan pengeluaran
/// operasional seperti listrik dan gas.
enum TxCategory {
  penjualan(TxDirection.masuk, 'Penjualan', 'penjualan'),
  pemasukanLain(TxDirection.masuk, 'Pemasukan lain', 'pemasukan_lain'),
  pembelian(TxDirection.keluar, 'Pembelian bahan', 'pembelian'),
  pengeluaran(TxDirection.keluar, 'Pengeluaran operasional', 'pengeluaran');

  final TxDirection direction;
  final String label;
  final String dbName;

  const TxCategory(this.direction, this.label, this.dbName);

  /// Tebakan awal saat arah sudah diketahui tapi kategorinya tidak disebut.
  /// Tetap bisa diganti di layar konfirmasi.
  static TxCategory defaultFor(TxDirection direction) =>
      direction == TxDirection.masuk ? penjualan : pembelian;

  static List<TxCategory> forDirection(TxDirection direction) => [
    for (final c in values)
      if (c.direction == direction) c,
  ];

  static TxCategory? fromDbName(String? value) {
    for (final c in values) {
      if (c.dbName == value) return c;
    }
    return null;
  }
}

/// Cara membaca harga yang diucapkan untuk barang berjumlah lebih dari satu.
///
/// "Beli ayam 5 kg 200 ribu" hampir selalu berarti total, sedangkan "gorengan
/// sepuluh biji seribu" berarti per biji. Tidak ada cara aman menebak dari
/// kalimat saja, jadi pilihannya disimpan eksplisit dan bisa diganti pengguna.
enum PriceMode { perUnit, total }

/// Dari mana sebuah transaksi berasal. Dicatat apa adanya supaya kualitas tiap
/// jalur masukan bisa dibandingkan nanti.
enum TxSource {
  voice,
  manual,
  qris;

  String get label => switch (this) {
    TxSource.voice => 'Suara',
    TxSource.qris => 'QRIS',
    TxSource.manual => 'Manual',
  };

  static TxSource fromName(String value) => switch (value) {
    'voice' => TxSource.voice,
    'qris' => TxSource.qris,
    _ => TxSource.manual,
  };
}
