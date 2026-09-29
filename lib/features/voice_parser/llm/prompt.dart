/// Prompt dan skema alat untuk parsing berbantuan LLM.
library;

const String llmToolName = 'catat_transaksi';

const String llmSystemPrompt = '''
Kamu membantu mengurai ucapan pemilik warung di Indonesia menjadi data transaksi.

Aturan:
- Hanya ekstrak yang benar-benar terdengar. JANGAN mengarang nama barang, jumlah, atau harga.
- Bila arah transaksi tidak jelas, isi "tidak_yakin". Jangan menebak.
- Bila jumlah tidak disebut, gunakan 1.
- Bila harga tidak disebut, isi null. Jangan memperkirakan harga pasar.
- Harga dalam rupiah penuh sebagai bilangan bulat: "lima ribu" -> 5000, "25rb" -> 25000.
- "keyakinan" adalah penilaian jujurmu 0..1 atas keseluruhan hasil. Turunkan nilainya bila ucapan ambigu atau terpotong.

Hasil akhirnya akan selalu ditampilkan ke pengguna untuk dikonfirmasi sebelum disimpan, jadi lebih baik mengaku tidak tahu daripada menebak.
''';

/// Skema argumen alat. `strict: true` mensyaratkan `additionalProperties:false`
/// dan seluruh properti terdaftar di `required`.
const Map<String, dynamic> llmToolInputSchema = {
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'arah': {
      'type': 'string',
      'enum': ['masuk', 'keluar', 'tidak_yakin'],
      'description':
          'masuk = penjualan/pemasukan, keluar = pembelian/pengeluaran',
    },
    'barang': {
      'type': 'array',
      'description': 'Daftar barang yang disebut. Boleh kosong.',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'nama': {
            'type': ['string', 'null'],
            'description': 'Nama barang apa adanya, null bila tidak disebut',
          },
          'jumlah': {
            'type': ['integer', 'null'],
            'description': 'Kuantitas, null bila tidak disebut',
          },
          'harga_satuan': {
            'type': ['integer', 'null'],
            'description':
                'Harga per unit dalam rupiah, null bila tidak disebut',
          },
        },
        'required': ['nama', 'jumlah', 'harga_satuan'],
      },
    },
    'keyakinan': {
      'type': 'number',
      'description': 'Keyakinan keseluruhan, 0 sampai 1',
    },
  },
  'required': ['arah', 'barang', 'keyakinan'],
};

const String llmToolDescription =
    'Catat hasil penguraian ucapan menjadi satu transaksi warung.';

String buildUserMessage(String transcript) =>
    'Ucapan pengguna (hasil speech-to-text, mungkin mengandung salah dengar):\n'
    '"$transcript"';
