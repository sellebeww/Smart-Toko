/// Memecah transkrip menjadi token yang siap dianalisis parser.
library;

import 'indonesian_number.dart';

const String separatorToken = ',';

/// Urutan langkah di sini penting: normalisasi angka harus berjalan SEBELUM
/// tanda baca dibuang, karena "25.000" dan "2,5" masih membutuhkan titik dan
/// komanya. Koma yang tersisa setelah itu berarti pemisah antarbarang.
List<String> tokenize(String transcript) {
  var text = normalizeNumericText(transcript);

  text = text.replaceAll(',', ' $separatorToken ');
  text = text.replaceAll(RegExp(r'[^\w\s,.]'), ' ');
  // Titik yang tersisa (akhir kalimat) tidak lagi membawa makna angka.
  text = text.replaceAll(RegExp(r'\.(?!\d)'), ' ');
  text = text.replaceAll('_', ' ');

  return text
      .split(RegExp(r'\s+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList(growable: false);
}
