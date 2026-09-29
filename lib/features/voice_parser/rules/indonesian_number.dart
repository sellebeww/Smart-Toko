/// Mengubah sebutan angka Bahasa Indonesia menjadi nilai numerik.
///
/// Pure Dart — tidak boleh mengimpor Flutter.
library;

/// Hasil pembacaan satu angka beserta rentang token asalnya.
class NumberMatch {
  final double value;
  final int startToken;
  final int endToken; // eksklusif
  final bool fromDigits;

  const NumberMatch({
    required this.value,
    required this.startToken,
    required this.endToken,
    required this.fromDigits,
  });

  int get asRupiah => value.round();

  @override
  String toString() =>
      'NumberMatch($value, [$startToken,$endToken), digits=$fromDigits)';
}

const Map<String, double> _smallWords = {
  'nol': 0,
  'kosong': 0,
  'satu': 1,
  'se': 1,
  'dua': 2,
  'tiga': 3,
  'empat': 4,
  'lima': 5,
  'enam': 6,
  'tujuh': 7,
  'delapan': 8,
  'sembilan': 9,
  'sepuluh': 10,
  'sebelas': 11,
};

const Set<String> _scaleWords = {
  'belas',
  'puluh',
  'ratus',
  'seratus',
  'ribu',
  'seribu',
  'juta',
  'sejuta',
  'miliar',
  'milyar',
};

/// Token yang boleh muncul di tengah angka tanpa memutusnya.
const Set<String> _numberGlue = {'setengah'};

bool isNumericToken(String token) =>
    _smallWords.containsKey(token) ||
    _scaleWords.contains(token) ||
    _numberGlue.contains(token) ||
    _digitPattern.hasMatch(token);

final RegExp _digitPattern = RegExp(r'^\d+(?:\.\d+)?$');

/// Normalisasi ragam tulisan/ucapan informal sebelum tokenisasi.
///
/// Menangani: pemisah ribuan (`25.000`), koma desimal (`2,5`), dan sufiks
/// yang menempel pada digit (`25rb`, `25k`, `2,5jt`).
String normalizeNumericText(String input) {
  var s = input.toLowerCase();

  // Pemisah ribuan gaya Indonesia: 25.000 / 1.250.000 -> 25000 / 1250000.
  s = s.replaceAllMapped(
    RegExp(r'\b(\d{1,3})((?:\.\d{3})+)\b'),
    (m) => '${m[1]}${m[2]!.replaceAll('.', '')}',
  );

  // Koma desimal -> titik desimal: 2,5 -> 2.5
  // Tanpa \b di akhir: pada "2,5jt" huruf setelah digit bukan batas kata.
  s = s.replaceAllMapped(RegExp(r'\b(\d+),(\d+)'), (m) => '${m[1]}.${m[2]}');

  // Sufiks skala yang menempel: 25rb -> 25 ribu, 25k -> 25 ribu, 2.5jt -> 2.5 juta
  s = s.replaceAllMapped(
    RegExp(r'\b(\d+(?:\.\d+)?)\s*(rb|ribu|k|jt|juta|m|miliar|milyar)\b'),
    (m) => '${m[1]} ${_expandSuffix(m[2]!)}',
  );

  return s;
}

String _expandSuffix(String suffix) {
  switch (suffix) {
    case 'rb':
    case 'k':
    case 'ribu':
      return 'ribu';
    case 'jt':
    case 'juta':
      return 'juta';
    case 'm':
    case 'miliar':
    case 'milyar':
      return 'miliar';
    default:
      return suffix;
  }
}

/// Membaca satu angka mulai dari [start]. Mengembalikan null bila token di
/// posisi itu bukan bagian dari angka.
///
/// Algoritma akumulasi bertingkat: [pending] menampung angka kecil yang baru
/// dibaca, [section] menampung nilai di bawah seribu, dan [total] menampung
/// hasil yang sudah dilewati batas ribu/juta. Pemisahan ini yang membuat
/// "seratus lima puluh ribu" terbaca 150.000, bukan 1.050.000.
NumberMatch? readNumberAt(List<String> tokens, int start) {
  if (start >= tokens.length) return null;
  if (!isNumericToken(tokens[start])) return null;
  // "setengah" tidak boleh mengawali angka sendirian tanpa skala sesudahnya.
  if (_numberGlue.contains(tokens[start]) &&
      (start + 1 >= tokens.length ||
          !_scaleWords.contains(tokens[start + 1]))) {
    return null;
  }

  double total = 0;
  double section = 0;
  double pending = 0;
  bool sawAnything = false;
  bool sawDigits = false;
  int i = start;

  void flushScale(double multiplier) {
    final base = section + pending;
    total += (base == 0 ? 1 : base) * multiplier;
    section = 0;
    pending = 0;
  }

  while (i < tokens.length) {
    final token = tokens[i];

    if (_digitPattern.hasMatch(token)) {
      // Dua digit berurutan adalah dua angka terpisah ("2 3"), hentikan.
      if (pending != 0) break;
      pending = double.parse(token);
      sawAnything = true;
      sawDigits = true;
      i++;
      continue;
    }

    if (token == 'setengah') {
      pending += 0.5;
      sawAnything = true;
      i++;
      continue;
    }

    final small = _smallWords[token];
    if (small != null) {
      if (pending != 0) break; // angka kecil berurutan -> angka baru
      pending = small;
      sawAnything = true;
      i++;
      continue;
    }

    switch (token) {
      case 'belas':
        section += 10 + pending;
        pending = 0;
        sawAnything = true;
      case 'puluh':
        section += pending * 10;
        pending = 0;
        sawAnything = true;
      case 'ratus':
        section += (pending == 0 ? 1 : pending) * 100;
        pending = 0;
        sawAnything = true;
      case 'seratus':
        section += 100;
        pending = 0;
        sawAnything = true;
      case 'ribu':
        flushScale(1000);
        sawAnything = true;
      case 'seribu':
        total += 1000;
        section = 0;
        pending = 0;
        sawAnything = true;
      case 'juta':
        flushScale(1000000);
        sawAnything = true;
      case 'sejuta':
        total += 1000000;
        section = 0;
        pending = 0;
        sawAnything = true;
      case 'miliar':
      case 'milyar':
        flushScale(1000000000);
        sawAnything = true;
      default:
        // Bukan token angka -> selesai.
        final value = total + section + pending;
        if (!sawAnything) return null;
        return NumberMatch(
          value: value,
          startToken: start,
          endToken: i,
          fromDigits: sawDigits,
        );
    }
    i++;
  }

  if (!sawAnything) return null;
  return NumberMatch(
    value: total + section + pending,
    startToken: start,
    endToken: i,
    fromDigits: sawDigits,
  );
}

/// Membaca seluruh angka yang muncul dalam [tokens], kiri ke kanan.
List<NumberMatch> readAllNumbers(List<String> tokens) {
  final result = <NumberMatch>[];
  var i = 0;
  while (i < tokens.length) {
    final match = readNumberAt(tokens, i);
    if (match != null && match.endToken > match.startToken) {
      result.add(match);
      i = match.endToken;
    } else {
      i++;
    }
  }
  return result;
}
