/// Kamus kata kunci Bahasa Indonesia untuk parser transaksi warung.
library;

import '../../../core/transaction_kind.dart';

const Map<String, TxDirection> directionWords = {
  'jual': TxDirection.masuk,
  'jualan': TxDirection.masuk,
  'terjual': TxDirection.masuk,
  'penjualan': TxDirection.masuk,
  'laku': TxDirection.masuk,
  'masuk': TxDirection.masuk,
  'pemasukan': TxDirection.masuk,
  'terima': TxDirection.masuk,
  'dapat': TxDirection.masuk,
  'beli': TxDirection.keluar,
  'membeli': TxDirection.keluar,
  'belanja': TxDirection.keluar,
  'kulakan': TxDirection.keluar,
  'kulak': TxDirection.keluar,
  'keluar': TxDirection.keluar,
  'pengeluaran': TxDirection.keluar,
  'bayar': TxDirection.keluar,
  'modal': TxDirection.keluar,
};

/// Kategori yang tersirat dari kata kerja arah. Kuncinya sama persis dengan
/// [directionWords], jadi kategori selalu searah dengan arahnya.
const Map<String, TxCategory> categoryWords = {
  'jual': TxCategory.penjualan,
  'jualan': TxCategory.penjualan,
  'terjual': TxCategory.penjualan,
  'penjualan': TxCategory.penjualan,
  'laku': TxCategory.penjualan,
  'masuk': TxCategory.pemasukanLain,
  'pemasukan': TxCategory.pemasukanLain,
  'terima': TxCategory.pemasukanLain,
  'dapat': TxCategory.pemasukanLain,
  'beli': TxCategory.pembelian,
  'membeli': TxCategory.pembelian,
  'belanja': TxCategory.pembelian,
  'kulakan': TxCategory.pembelian,
  'kulak': TxCategory.pembelian,
  'modal': TxCategory.pembelian,
  'keluar': TxCategory.pengeluaran,
  'pengeluaran': TxCategory.pengeluaran,
  'bayar': TxCategory.pengeluaran,
};

/// Hal yang dibeli/dibayar tapi bukan bahan dagangan: "beli gas" dan "bayar
/// listrik" masuk pengeluaran operasional dan tidak menambah stok. Sengaja
/// tidak memuat "air" — "air mineral" adalah barang dagangan.
const Set<String> operationalExpenseWords = {
  'listrik',
  'gas',
  'elpiji',
  'lpg',
  'sewa',
  'kontrakan',
  'gaji',
  'upah',
  'bensin',
  'solar',
  'parkir',
  'token',
  'pdam',
  'internet',
  'wifi',
  'iuran',
  'kebersihan',
  'sampah',
  'retribusi',
  'ongkir',
  'ongkos',
  'transport',
  'servis',
  'service',
  'pajak',
};

/// Satuan yang, bila mengikuti sebuah angka, menandai angka itu sebagai
/// kuantitas. Syarat "mengikuti angka" penting: tanpa itu, "teh botol" akan
/// salah dibaca sebagai kuantitas dalam botol.
const Set<String> unitWords = {
  'kilo',
  'kilogram',
  'kg',
  'gram',
  'gr',
  'ons',
  'liter',
  'ltr',
  'mililiter',
  'ml',
  'bungkus',
  'bks',
  'pcs',
  'pieces',
  'buah',
  'biji',
  'batang',
  'botol',
  'kaleng',
  'pack',
  'pak',
  'dus',
  'kardus',
  'renteng',
  'sachet',
  'saset',
  'lembar',
  'ekor',
  'porsi',
  'piring',
  'gelas',
  'cup',
  'potong',
  'ikat',
  'papan',
  'slop',
  'karung',
  'sak',
};

const Map<String, String> _unitAliases = {
  'kilo': 'kg',
  'kilogram': 'kg',
  'gr': 'gram',
  'ltr': 'liter',
  'mililiter': 'ml',
  'bks': 'bungkus',
  'pieces': 'pcs',
  'saset': 'sachet',
  'pak': 'pack',
  'kardus': 'dus',
};

/// Satuan dalam bentuk bakunya, supaya "3 kilo" dan "3 kg" jadi stok yang
/// sama.
String normalizeUnit(String token) => _unitAliases[token] ?? token;

/// Satuan timbang/takar (setelah dinormalisasi). Harga yang disebut sesudah
/// satuan seperti ini ("beras 10 kilo 150 ribu") hampir selalu total, bukan
/// harga per kilo.
const Set<String> bulkUnits = {
  'kg',
  'gram',
  'ons',
  'liter',
  'ml',
  'karung',
  'sak',
};

/// Penanda bahwa harga yang disebut adalah per satuan ("40 ribu per kilo").
const Set<String> perUnitPriceMarkers = {
  'per',
  'perkilo',
  'perbiji',
  'satunya',
  'tiap',
  'masing',
};

/// Penanda bahwa harga yang disebut adalah total ("semuanya 200 ribu").
const Set<String> totalPriceMarkers = {
  'total',
  'totalnya',
  'semua',
  'semuanya',
  'seluruhnya',
};

/// Penanda eksplisit bahwa angka berikutnya adalah harga.
const Set<String> priceMarkers = {'harga', 'seharga', 'hargane', 'senilai'};

/// Penanda eksplisit bahwa angka berikutnya adalah kuantitas.
const Set<String> qtyMarkers = {'sebanyak', 'jumlah', 'qty'};

/// Kata yang memisahkan satu barang dari barang berikutnya.
const Set<String> itemSeparators = {
  'dan',
  'sama',
  'terus',
  'lalu',
  'kemudian',
  'plus',
  'trus',
};

/// Kata yang menandakan transaksi dicatat belum dibayar (kasbon).
const Set<String> creditWords = {
  'utang',
  'utangnya',
  'ngutang',
  'berutang',
  'hutang',
  'hutangnya',
  'ngehutang',
  'berhutang',
  'kasbon',
  'ngebon',
  'kredit',
};

/// Dua kata berurutan yang juga berarti kasbon, mis. "belum bayar".
const Set<(String, String)> creditPhrases = {
  ('belum', 'bayar'),
  ('belum', 'lunas'),
  ('nanti', 'bayar'),
  ('bayar', 'nanti'),
  ('bayar', 'besok'),
};

/// Kata waktu pembayaran kasbon → jumlah hari sejak transaksi.
const Map<String, int> dueWords = {'besok': 1, 'lusa': 2};

/// Kata kerja janji bayar yang menempel pada kata waktu.
const Set<String> payVerbs = {'bayar', 'dibayar', 'lunas', 'dilunasi'};

/// Dua kata waktu pembayaran: "minggu depan", "bulan depan".
const Map<(String, String), int> duePhrases = {
  ('minggu', 'depan'): 7,
  ('pekan', 'depan'): 7,
  ('bulan', 'depan'): 30,
};

/// Kata sambung yang tidak membawa makna untuk parsing dan aman dibuang.
const Set<String> fillerWords = {
  'yang',
  'itu',
  'ini',
  'nya',
  'nih',
  'tuh',
  'ya',
  'sih',
  'deh',
  'ke',
  'di',
  'dari',
  'untuk',
  'buat',
  'dengan',
  'pakai',
  'per',
  'total',
  'sudah',
  'udah',
  'tadi',
  'barusan',
  'catat',
  'catatkan',
  'tolong',
  'aku',
  'saya',
  'gue',
  'punya',
};

bool isUnitWord(String token) => unitWords.contains(token);

bool isSeparator(String token) => itemSeparators.contains(token);

bool isFiller(String token) => fillerWords.contains(token);
